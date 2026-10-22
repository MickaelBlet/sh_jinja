# yaml.awk - YAML subset loader with PyYAML safe_load scalar typing.
# Supports block mappings/sequences, flow collections, quoted and plain
# scalars, block scalars (| >, chomping, indent indicator), comments,
# anchors/aliases and merge keys (<<). No tags, no complex keys.

function yaml_parse(text, name,    n, i, line, v, arr) {
	YNAME = name
	gsub(/\r\n/, "\n", text)
	n = split(text, arr, "\n")
	YN = 0
	for (i = 1; i <= n; i++) {
		line = arr[i]
		YN++
		YR[YN] = line
		match(line, /^ */)
		YI[YN] = RLENGTH
		YT[YN] = substr(line, RLENGTH + 1)
		if (YT[YN] ~ /^#/ || YT[YN] ~ /^[ \t]*$/) YT[YN] = ""
		if (YI[YN] == 0 && (YT[YN] ~ /^---([ \t]|$)/ || YT[YN] ~ /^\.\.\.([ \t]|$)/)) {
			if (YT[YN] ~ /^--- *[^ #]/) { YT[YN] = substr(YT[YN], 4); sub(/^ +/, "", YT[YN]) }
			else YT[YN] = ""
		}
		if (YI[YN] == 0 && YT[YN] ~ /^%/) YT[YN] = ""
	}
	YP = 1
	yaml_skip()
	if (YP > YN) return v_dict()
	v = yaml_node(-1)
	yaml_skip()
	if (YP <= YN) yaml_fail("expected <document end>, but found another node")
	return v
}

function yaml_fail(msg) { rt_fail_at("YAMLError", msg, YNAME, YP) }

function yaml_skip() { while (YP <= YN && YT[YP] == "") YP++ }

function yaml_node(parent,    ind, t) {
	yaml_skip()
	if (YP > YN) return V_NONE
	ind = YI[YP]
	if (ind <= parent) return V_NONE
	t = YT[YP]
	if (t ~ /^-( |$)/) return yaml_seq(ind)
	if (yaml_keylen(t) > 0) return yaml_map(ind)
	YP++
	return yaml_value(t, parent)
}

# length of the key part (before ":"), 0 when the line is not "key: ..."
function yaml_keylen(t,    q, k, c, i, n) {
	c = substr(t, 1, 1)
	if (c == "\"" || c == "'") {
		n = length(t)
		for (i = 2; i <= n; i++) {
			if (c == "'" && substr(t, i, 2) == "''") { i++; continue }
			if (c == "\"" && substr(t, i, 1) == "\\") { i++; continue }
			if (substr(t, i, 1) == c) break
		}
		if (i > n) return 0
		if (substr(t, i + 1) ~ /^[ \t]*:([ \t]|$)/) return i
		return 0
	}
	if (c == "[" || c == "{" || c == "#" || c == "|" || c == ">" || c == "*" || c == "!" || c == "%" || c == "@" || c == "`") return 0
	if (t ~ /^-( |$)/) return 0
	k = index(t " ", ": ")
	if (!k) {
		if (substr(t, length(t)) == ":" && !index(t, " #")) return length(t) - 1
		return 0
	}
	if (index(substr(t, 1, k), " #")) return 0
	return k - 1
}

function yaml_keyval(s,    c) {
	sub(/[ \t]+$/, "", s)
	c = substr(s, 1, 1)
	if (c == "\"") return yaml_dq(substr(s, 2, length(s) - 2))
	if (c == "'") return yaml_sq(substr(s, 2, length(s) - 2))
	return yaml_resolve(s)
}

function yaml_map(ind,    d, t, kl, key, rest, val, i, src, k) {
	d = v_dict()
	while (1) {
		yaml_skip()
		if (YP > YN || YI[YP] < ind) break
		if (YI[YP] > ind) yaml_fail("mapping values are not allowed here")
		t = YT[YP]
		kl = yaml_keylen(t)
		if (!kl) {
			if (t ~ /^-( |$)/) break
			yaml_fail("could not find expected ':'")
		}
		key = yaml_keyval(substr(t, 1, kl))
		rest = substr(t, kl + 1)
		sub(/^[ \t]*:/, "", rest)
		sub(/^[ \t]+/, "", rest)
		YP++
		val = yaml_after(rest, ind, 1)
		if (VT[key] == "str" && VV[key] == "<<") {
			yaml_merge(d, val)
			continue
		}
		v_dset(d, key, val)
	}
	return d
}

function yaml_merge(d, src,    i, k, items) {
	if (VT[src] == "list") {
		for (i = 0; i < VN[src]; i++) yaml_merge(d, VE[src, i])
		return
	}
	if (VT[src] != "dict") yaml_fail("expected a mapping for merging")
	for (i = 0; i < VN[src]; i++) {
		k = VK[src, i]
		if (!v_dhas(d, k)) v_dset(d, k, VD[src, v_hk(k)])
	}
}

# value text after "key:" or "- " (current line already consumed)
function yaml_after(rest, ind, inmap,    anchor, val, a) {
	anchor = ""
	if (match(rest, /^&[^ \t]+/)) {
		anchor = substr(rest, 2, RLENGTH - 1)
		rest = substr(rest, RLENGTH + 1)
		sub(/^[ \t]+/, "", rest)
	}
	if (rest ~ /^!/) {
		sub(/^![^ \t]*[ \t]*/, "", rest)
	}
	if (rest == "" || rest ~ /^#/) {
		yaml_skip()
		if (YP <= YN && YI[YP] > ind) val = yaml_node(ind)
		else if (inmap && YP <= YN && YI[YP] == ind && YT[YP] ~ /^-( |$)/) val = yaml_seq(ind)
		else val = V_NONE
	} else if (rest ~ /^[|>]/) {
		val = yaml_block(rest, ind)
	} else if (rest ~ /^\*/) {
		a = rest
		sub(/^\*/, "", a)
		sub(/[ \t].*$/, "", a)
		if (!(a in YANCHOR)) yaml_fail("found undefined alias '" a "'")
		val = YANCHOR[a]
	} else {
		val = yaml_value(rest, ind)
	}
	if (anchor != "") YANCHOR[anchor] = val
	return val
}

function yaml_seq(ind,    l, t, rest, sp, col) {
	l = v_list()
	while (1) {
		yaml_skip()
		if (YP > YN || YI[YP] != ind || YT[YP] !~ /^-( |$)/) break
		t = YT[YP]
		rest = substr(t, 2)
		match(rest, /^ */)
		sp = RLENGTH
		rest = substr(rest, sp + 1)
		col = ind + 1 + sp
		if (rest != "" && rest !~ /^#/ && (yaml_keylen(rest) > 0 || rest ~ /^-( |$)/) && rest !~ /^[&*!]/) {
			YI[YP] = col
			YT[YP] = rest
			v_push(l, yaml_node(ind))
			continue
		}
		YP++
		v_push(l, yaml_after(rest, ind, 0))
	}
	return l
}

# scalar or flow starting with text t, continuation lines indented > ind
function yaml_value(t, ind,    c, s, q, done, nl, line, depth) {
	c = substr(t, 1, 1)
	if (c == "\"" || c == "'") {
		s = t
		while (!yaml_qclosed(s, c)) {
			if (YP > YN) yaml_fail("found unexpected end of stream")
			line = YR[YP++]
			sub(/^[ \t]+/, "", line)
			s = s "\n" line
		}
		return yaml_quoted(s, c)
	}
	if (c == "[" || c == "{") {
		s = t
		while (yaml_flowdepth(s) > 0) {
			if (YP > YN) yaml_fail("found unexpected end of stream")
			line = YR[YP++]
			s = s " " line
		}
		return yaml_flow(s)
	}
	# plain scalar, possibly multi-line
	s = yaml_nocomment(t)
	while (YP <= YN) {
		if (YT[YP] == "") {
			# blank line inside a multi-line plain scalar
			nl = YP
			while (nl <= YN && YT[nl] == "" && YR[nl] !~ /^[ \t]*#/) nl++
			if (nl <= YN && YI[nl] > ind && YT[nl] != "" && yaml_keylen(YT[nl]) == 0 && YT[nl] !~ /^-( |$)/ && YR[YP] !~ /^[ \t]*#/) {
				s = s v_rep("\n", nl - YP)
				YP = nl
				line = yaml_nocomment(YT[YP++])
				s = s line
				continue
			}
			break
		}
		if (YI[YP] <= ind || yaml_keylen(YT[YP]) > 0 || YT[YP] ~ /^-( |$)/ || YT[YP] ~ /^#/) break
		s = s " " yaml_nocomment(YT[YP++])
	}
	return yaml_resolve(s)
}

function yaml_nocomment(t,    k) {
	if (substr(t, 1, 1) == "#") return ""
	k = index(t, " #")
	if (!k) k = index(t, "\t#")
	if (k) t = substr(t, 1, k - 1)
	sub(/[ \t]+$/, "", t)
	return t
}

function yaml_qclosed(s, q,    i, n) {
	n = length(s)
	for (i = 2; i <= n; i++) {
		if (q == "'" && substr(s, i, 2) == "''") { i++; continue }
		if (q == "\"" && substr(s, i, 1) == "\\") { i++; continue }
		if (substr(s, i, 1) == q) return 1
	}
	return 0
}

function yaml_flowdepth(s,    i, n, c, d, q) {
	d = 0; q = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (q != "") {
			if (q == "\"" && c == "\\") { i++; continue }
			if (q == "'" && c == "'" && substr(s, i + 1, 1) == "'") { i++; continue }
			if (c == q) q = ""
			continue
		}
		if (c == "\"" || c == "'") q = c
		else if (c == "[" || c == "{") d++
		else if (c == "]" || c == "}") d--
		else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) break
	}
	return d
}

# quoted scalar s (starting with quote q) spanning lines; fold line breaks
function yaml_quoted(s, q,    i, n, body, c) {
	n = length(s)
	for (i = 2; i <= n; i++) {
		if (q == "'" && substr(s, i, 2) == "''") { i++; continue }
		if (q == "\"" && substr(s, i, 1) == "\\") { i++; continue }
		if (substr(s, i, 1) == q) break
	}
	body = substr(s, 2, i - 2)
	body = yaml_fold(body, q)
	return q == "'" ? yaml_sq(body) : yaml_dq(body)
}

# flow folding of line breaks inside quoted scalars
function yaml_fold(s, q,    out, parts, n, i, empties, line) {
	if (!index(s, "\n")) return s
	n = split(s, parts, "\n")
	out = parts[1]
	sub(/[ \t]+$/, "", out)
	empties = 0
	for (i = 2; i <= n; i++) {
		line = parts[i]
		sub(/^[ \t]+/, "", line)
		if (i < n) sub(/[ \t]+$/, "", line)
		if (line == "" && i < n) { empties++; continue }
		if (q == "\"" && substr(out, length(out)) == "\\" ) { out = substr(out, 1, length(out) - 1) line; empties = 0; continue }
		out = out "" (empties ? v_rep("\n", empties) : " ") line
		empties = 0
	}
	return out
}

function yaml_sq(s) {
	gsub(/''/, "'", s)
	return v_str(s)
}

function yaml_dq(s,    out, k, c, h, n) {
	if (!index(s, "\\")) return v_str(s)
	out = ""
	while ((k = index(s, "\\")) > 0) {
		out = out substr(s, 1, k - 1)
		c = substr(s, k + 1, 1)
		s = substr(s, k + 2)
		if (c == "n") out = out "\n"
		else if (c == "t" || c == "\t") out = out "\t"
		else if (c == "r") out = out "\r"
		else if (c == "\\") out = out "\\"
		else if (c == "\"") out = out "\""
		else if (c == "/") out = out "/"
		else if (c == " ") out = out " "
		else if (c == "0") out = out ""
		else if (c == "a") out = out "\007"
		else if (c == "b") out = out "\010"
		else if (c == "e") out = out "\033"
		else if (c == "f") out = out "\014"
		else if (c == "v") out = out "\013"
		else if (c == "N") out = out u8_enc(133)
		else if (c == "_") out = out u8_enc(160)
		else if (c == "L") out = out u8_enc(8232)
		else if (c == "P") out = out u8_enc(8233)
		else if (c == "x" || c == "u" || c == "U") {
			n = c == "x" ? 2 : (c == "u" ? 4 : 8)
			h = substr(s, 1, n)
			if (u8_hexval(h) < 0 || length(h) < n) yaml_fail("expected escape sequence of " n " hexadecimal numbers")
			out = out u8_enc(u8_hexval(h))
			s = substr(s, n + 1)
		} else yaml_fail("found unknown escape character '" c "'")
	}
	return v_str(out s)
}

# block scalar: header is "|..." or ">..."
function yaml_block(header, ind,    style, chomp, explicit, bind, lines, n, i, raw, out, k, trail, prevmore, line, more, first, empties) {
	style = substr(header, 1, 1)
	header = substr(header, 2)
	sub(/[ \t]+#.*$/, "", header)
	chomp = ""
	explicit = 0
	if (match(header, /[-+]/)) chomp = substr(header, RSTART, 1)
	if (match(header, /[1-9]/)) explicit = substr(header, RSTART, 1) + 0
	bind = explicit ? ind + explicit : 0
	if (bind < 0) bind = explicit
	n = 0
	while (YP <= YN) {
		raw = YR[YP]
		if (raw ~ /^[ \t]*$/) { lines[++n] = ""; YP++; continue }
		match(raw, /^ */)
		if (!bind) {
			if (RLENGTH <= ind) break
			bind = RLENGTH
		}
		if (RLENGTH < bind) break
		lines[++n] = substr(raw, bind + 1)
		YP++
	}
	# trailing blank lines
	trail = 0
	while (n > 0 && lines[n] == "") { n--; trail++ }
	out = ""
	if (style == "|") {
		for (i = 1; i <= n; i++) out = out lines[i] (i < n ? "\n" : "")
	} else {
		prevmore = 0
		first = 1
		empties = 0
		for (i = 1; i <= n; i++) {
			line = lines[i]
			if (line == "") { empties++; continue }
			more = line ~ /^[ \t]/
			if (!first) {
				if (!more && !prevmore) out = out "" (empties ? v_rep("\n", empties) : " ")
				else out = out "\n" v_rep("\n", empties)
			} else out = v_rep("\n", empties)
			out = out line
			first = 0
			prevmore = more
			empties = 0
		}
	}
	if (n == 0) {
		if (chomp == "+") return v_str(v_rep("\n", trail))
		return V_EMPTY
	}
	if (chomp == "-") return v_str(out)
	if (chomp == "+") return v_str(out "\n" v_rep("\n", trail))
	return v_str(out "\n")
}

# PyYAML (YAML 1.1) implicit resolvers
function yaml_resolve(s,    t, n, neg, parts, i, k, x) {
	if (s == "" || s == "~" || s == "null" || s == "Null" || s == "NULL") return V_NONE
	if (s ~ /^(yes|Yes|YES|true|True|TRUE|on|On|ON)$/) return V_TRUE
	if (s ~ /^(no|No|NO|false|False|FALSE|off|Off|OFF)$/) return V_FALSE
	if (s ~ /^[-+]?0b[01_]+$/) return yaml_intbase(s, 2)
	if (s ~ /^[-+]?0x[0-9a-fA-F_]+$/) return yaml_intbase(s, 16)
	if (s ~ /^[-+]?0[0-7_]+$/) return yaml_intbase(s, 8)
	if (s ~ /^[-+]?(0|[1-9][0-9_]*)$/) {
		t = s
		gsub(/_/, "", t)
		sub(/^\+/, "", t)
		if (t ~ /^-?0+$/) t = "0"
		return v_new("int", t)
	}
	if (s ~ /^[-+]?[1-9][0-9_]*(:[0-5]?[0-9])+$/) {
		neg = substr(s, 1, 1) == "-"
		t = s
		gsub(/[-+_]/, "", t)
		n = split(t, parts, ":")
		x = 0
		for (i = 1; i <= n; i++) x = x * 60 + parts[i]
		return v_int(neg ? -x : x)
	}
	if (s ~ /^[-+]?([0-9][0-9_]*)?\.[0-9_]*([eE][-+][0-9]+)?$/ && s ~ /[0-9]/ && s !~ /^[-+]?\.[eE_]/) {
		if (s ~ /^[-+]?\./ && s !~ /^\.[0-9]/) return v_str(s)
		t = s
		gsub(/_/, "", t)
		return v_float(t + 0)
	}
	if (s ~ /^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*$/) {
		neg = substr(s, 1, 1) == "-"
		t = s
		gsub(/[-+_]/, "", t)
		n = split(t, parts, ":")
		x = 0
		for (i = 1; i <= n; i++) x = x * 60 + parts[i]
		return v_float(neg ? -x : x)
	}
	if (s ~ /^[-+]?\.(inf|Inf|INF)$/) return v_float(substr(s, 1, 1) == "-" ? -m_inf() : m_inf())
	if (s ~ /^\.(nan|NaN|NAN)$/) return v_float(m_nan())
	return v_str(s)
}

function yaml_intbase(s, base,    neg, t, n, i, d) {
	neg = substr(s, 1, 1) == "-"
	t = s
	sub(/^[-+]/, "", t)
	if (base != 8) t = substr(t, 3)
	gsub(/_/, "", t)
	t = tolower(t)
	n = 0
	for (i = 1; i <= length(t); i++) {
		d = index(HEXD, substr(t, i, 1)) - 1
		n = n * base + d
	}
	return v_int(neg ? -n : n)
}

# ---------------------------------------------------------------- flow ----

function yaml_flow(s,    v) {
	YF = s
	YFP = 1
	v = yaml_fvalue(0)
	return v
}

function yaml_fws() {
	while (YFP <= length(YF)) {
		if (substr(YF, YFP, 1) ~ /[ \t\n]/) YFP++
		else if (substr(YF, YFP, 1) == "#" && (YFP == 1 || substr(YF, YFP - 1, 1) ~ /[ \t]/)) {
			while (YFP <= length(YF) && substr(YF, YFP, 1) != "\n") YFP++
		} else break
	}
}

function yaml_fvalue(inmap,    c, v, k, x, s, i, n, q) {
	yaml_fws()
	c = substr(YF, YFP, 1)
	if (c == "[") {
		YFP++
		v = v_list()
		while (1) {
			yaml_fws()
			c = substr(YF, YFP, 1)
			if (c == "]") { YFP++; return v }
			if (c == "") yaml_fail("expected ',' or ']'")
			k = yaml_fvalue(1)
			yaml_fws()
			if (substr(YF, YFP, 1) == ":") {
				YFP++
				x = v_dict()
				v_dset(x, k, yaml_fvalue(0))
				k = x
				yaml_fws()
			}
			v_push(v, k)
			c = substr(YF, YFP, 1)
			if (c == ",") { YFP++; continue }
			if (c == "]") { YFP++; return v }
			yaml_fail("did not find expected ',' or ']'")
		}
	}
	if (c == "{") {
		YFP++
		v = v_dict()
		while (1) {
			yaml_fws()
			c = substr(YF, YFP, 1)
			if (c == "}") { YFP++; return v }
			if (c == "") yaml_fail("expected ',' or '}'")
			k = yaml_fvalue(1)
			yaml_fws()
			if (substr(YF, YFP, 1) == ":") {
				YFP++
				x = yaml_fvalue(0)
			} else x = V_NONE
			v_dset(v, k, x)
			yaml_fws()
			c = substr(YF, YFP, 1)
			if (c == ",") { YFP++; continue }
			if (c == "}") { YFP++; return v }
			yaml_fail("did not find expected ',' or '}'")
		}
	}
	if (c == "\"" || c == "'") {
		n = length(YF)
		for (i = YFP + 1; i <= n; i++) {
			if (c == "'" && substr(YF, i, 2) == "''") { i++; continue }
			if (c == "\"" && substr(YF, i, 1) == "\\") { i++; continue }
			if (substr(YF, i, 1) == c) break
		}
		s = substr(YF, YFP, i - YFP + 1)
		YFP = i + 1
		return yaml_quoted(s, c)
	}
	if (c == "*") {
		match(substr(YF, YFP + 1), /^[^] \t,}]+/)
		s = substr(YF, YFP + 1, RLENGTH)
		YFP += RLENGTH + 1
		if (!(s in YANCHOR)) yaml_fail("found undefined alias '" s "'")
		return YANCHOR[s]
	}
	# plain scalar inside flow: stops at , ] } and ": "
	s = ""
	n = length(YF)
	while (YFP <= n) {
		c = substr(YF, YFP, 1)
		if (c == "," || c == "]" || c == "}" || c == "[" || c == "{") break
		if (c == ":" && (YFP == n || index(" \t,]}", substr(YF, YFP + 1, 1)))) break
		if (c == "#" && substr(YF, YFP - 1, 1) ~ /[ \t]/) break
		s = s c
		YFP++
	}
	gsub(/^[ \t\n]+|[ \t\n]+$/, "", s)
	gsub(/[ \t]*\n[ \t]*/, " ", s)
	return yaml_resolve(s)
}
