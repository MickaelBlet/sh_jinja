# main.awk - entry point: reads the context protocol written by jinja.sh on
# stdin, renders the main template and prints the result.
#
# Protocol (one record per line, tab separated, values escaped \\ \n \t):
#   O key value      option (trim_blocks, lstrip_blocks, keep_trailing_newline,
#                    autoescape, strict, ext, path, out)
#   X                environment variables -> context
#   S name value     string variable          I name value   integer variable
#   L name n         list, followed by n "E value" records
#   A name n         dict, followed by n "K key value" records
#   J name json      variable from a JSON document
#   V name value     -v NAME=VALUE: bash array literal or string (pd_inline)
#   F path           data file (.json, .yaml, .yml), merged into the context
#   T source         main template given as a string
#   M name           main template name, resolved through the search path

function pd_unesc(s,    out, k, c) {
	if (!index(s, "\\")) return s
	out = ""
	while ((k = index(s, "\\")) > 0) {
		out = out substr(s, 1, k - 1)
		c = substr(s, k + 1, 1)
		s = substr(s, k + 2)
		if (c == "n") out = out "\n"
		else if (c == "t") out = out "\t"
		else out = out c
	}
	return out s
}

# dict from PD_K[i] / PD_V[i] (i < PD_N, string keys and values), keys sorted
function pd_dict(    d, keys, i) {
	d = v_dict()
	keys = v_list()
	for (i = 0; i < PD_N; i++) {
		v_push(keys, v_str(PD_K[i]))
		PD_AV[PD_K[i]] = PD_V[i]
	}
	keys = f_sortby(keys, keys, 0)
	for (i = 0; i < PD_N; i++) v_dset(d, VE[keys, i], v_str(PD_AV[VV[VE[keys, i]]]))
	delete PD_K; delete PD_V; delete PD_AV
	return d
}

function pd_fail(msg,    pre, line) {
	pre = substr(PD_S, 1, PD_I)
	line = 1 + gsub(/\n/, "", pre)
	rt_fail_at("ValueError", msg, "-v " PD_NAME, line)
}

# read one word of PD_S from PD_I, up to an unquoted character of stop;
# removes quotes like bash ('..', "..", \x) but performs no expansion
function pd_word(stop,    w, c, n, q) {
	w = ""
	n = length(PD_S)
	while (PD_I <= n) {
		c = substr(PD_S, PD_I, 1)
		if (index(stop, c)) break
		if (c == "'") {
			q = index(substr(PD_S, PD_I + 1), "'")
			if (!q) pd_fail("unterminated quote")
			w = w substr(PD_S, PD_I + 1, q - 1)
			PD_I += q + 1
		} else if (c == "\"") {
			for (PD_I++; ; PD_I++) {
				if (PD_I > n) pd_fail("unterminated quote")
				c = substr(PD_S, PD_I, 1)
				if (c == "\"") break
				if (c == "\\" && PD_I < n && index("$`\"\\\n", substr(PD_S, PD_I + 1, 1))) {
					c = substr(PD_S, ++PD_I, 1)
					if (c == "\n") continue
				}
				w = w c
			}
			PD_I++
		} else if (c == "\\" && PD_I < n) {
			c = substr(PD_S, PD_I + 1, 1)
			if (c != "\n") w = w c
			PD_I += 2
		} else {
			w = w c
			PD_I++
		}
	}
	return w
}

# value of -v NAME=VALUE: '(a b)' list, '([k]=v ...)' dict, else string
function pd_inline(name, s,    dict, n, l, k, j) {
	if (s !~ /^\(/ || s !~ /\)$/ || length(s) < 2) return v_str(s)
	PD_NAME = name
	PD_S = substr(s, 2, length(s) - 2)
	PD_I = 1
	PD_N = 0
	n = length(PD_S)
	dict = PD_S ~ /^[ \t\n]*\[/
	l = v_list()
	for (;;) {
		while (PD_I <= n && index(" \t\n", substr(PD_S, PD_I, 1))) PD_I++
		if (PD_I > n) break
		if (!dict) {
			v_push(l, v_str(pd_word(" \t\n")))
			continue
		}
		if (substr(PD_S, PD_I, 1) != "[") pd_fail("expected [KEY]=VALUE")
		PD_I++
		k = pd_word("]")
		if (substr(PD_S, PD_I, 2) != "]=") pd_fail("expected [KEY]=VALUE")
		if (k == "") pd_fail("empty key")
		PD_I += 2
		# bash: a repeated key keeps its last value
		if (!(k in PD_SEEN)) { PD_SEEN[k] = PD_N; PD_K[PD_N++] = k }
		PD_V[PD_SEEN[k]] = pd_word(" \t\n")
	}
	delete PD_SEEN
	return dict ? pd_dict() : l
}

function main_data(path,    src, v, i, k, fmt) {
	src = io_read(path)
	if (!IO_OK) rt_fail_at("FileNotFoundError", "cannot read data file", path, 0)
	fmt = tolower(path)
	if (fmt ~ /\.json$/) fmt = "json"
	else if (fmt ~ /\.ya?ml$/) fmt = "yaml"
	else fmt = (src ~ /^[ \t\r\n]*[{[]/) ? "json" : "yaml"
	v = fmt == "json" ? json_parse(src, path) : yaml_parse(src, path)
	if (VT[v] == "none") return
	if (VT[v] != "dict") rt_fail_at("TypeError", "top-level data must be a mapping", path, 0)
	for (i = 0; i < VN[v]; i++) {
		k = VK[v, i]
		rt_fset(CTX, v_tostr(k), VD[v, v_hk(k)])
	}
}

BEGIN {
	CONVFMT = "%.17g"
	v_init()
	u8_init()
	f_init()
	t_init()
	b_init()
	srand()
	SP_N = 0
	CTX = rt_fnew(0)
	MAIN_NAME = ""
	MAIN_SRC = ""
	HAS_SRC = 0
	OUTFILE = ""
	while ((getline line) > 0) {
		n = split(line, fld, "\t")
		k = fld[1]
		if (k == "O") {
			o = fld[2]; val = pd_unesc(fld[3])
			if (o == "trim_blocks") TRIM_BLOCKS = val + 0
			else if (o == "lstrip_blocks") LSTRIP_BLOCKS = val + 0
			else if (o == "keep_trailing_newline") KEEP_TRAILING_NL = val + 0
			else if (o == "autoescape") AUTOESC = val + 0
			else if (o == "strict") STRICT = val + 0
			else if (o == "path") SP[++SP_N] = val
			else if (o == "out") OUTFILE = val
			else if (o == "math") HAS_MATH = val + 0
			else if (o == "ext") {
				if (val ~ /loopcontrols$/) EXT_LOOPCONTROLS = 1
				else if (val ~ /(^|\.)do$/) EXT_DO = 1
				else rt_fail_at("ValueError", "unknown extension '" val "'", "", 0)
			}
		} else if (k == "X") {
			for (e in ENVIRON) rt_fset(CTX, e, v_str(ENVIRON[e]))
		} else if (k == "S") {
			rt_fset(CTX, pd_unesc(fld[2]), v_str(pd_unesc(fld[3])))
		} else if (k == "I") {
			rt_fset(CTX, pd_unesc(fld[2]), v_int(fld[3] + 0))
		} else if (k == "L") {
			name = pd_unesc(fld[2]); cnt = fld[3] + 0
			l = v_list()
			for (i = 0; i < cnt; i++) {
				getline line
				split(line, fld, "\t")
				v_push(l, v_str(pd_unesc(fld[2])))
			}
			rt_fset(CTX, name, l)
		} else if (k == "A") {
			name = pd_unesc(fld[2]); cnt = fld[3] + 0
			# bash hash order is arbitrary: sort keys
			for (PD_N = 0; PD_N < cnt; PD_N++) {
				getline line
				split(line, fld, "\t")
				PD_K[PD_N] = pd_unesc(fld[2])
				PD_V[PD_N] = pd_unesc(fld[3])
			}
			rt_fset(CTX, name, pd_dict())
		} else if (k == "V") {
			name = pd_unesc(fld[2])
			rt_fset(CTX, name, pd_inline(name, pd_unesc(fld[3])))
		} else if (k == "J") {
			rt_fset(CTX, pd_unesc(fld[2]), json_parse(pd_unesc(fld[3]), "-J " pd_unesc(fld[2])))
		} else if (k == "F") {
			main_data(pd_unesc(fld[2]))
		} else if (k == "T") {
			MAIN_SRC = pd_unesc(fld[2])
			HAS_SRC = 1
		} else if (k == "M") {
			MAIN_NAME = pd_unesc(fld[2])
		}
	}
	if (!SP_N) SP[++SP_N] = "."
	if (HAS_SRC) {
		tpl = rt_compile("\001string", MAIN_SRC)
		TPL_NAME[tpl] = ""
	} else {
		tpl = rt_load(MAIN_NAME)
		if (!tpl) rt_fail_at("TemplateNotFound", MAIN_NAME, MAIN_NAME, 0)
	}
	RT_TPL = tpl
	out = rt_render_root(tpl, rt_newctx(CTX))
	if (OUTFILE != "") {
		printf "%s", out > OUTFILE
		close(OUTFILE)
	} else {
		printf "%s", out
	}
	exit 0
}
