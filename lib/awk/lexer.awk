# lexer.awk - template source -> token arrays, mirrors jinja2/lexer.py
#
# Tokens: TK_N count, TK_T[i] type, TK_V[i] value, TK_L[i] line.
# Types: data var_begin var_end block_begin block_end name string integer
# float eof, and operators use their own text as type ("(", "==", ...).

function lx_tokenize(src, tname,    pos, n, line, rest, i, kind, sign, text, tagend, lpos, j, c, m, raw, rawend, body, k, tail) {
	delete TK_T; delete TK_V; delete TK_L
	TK_N = 0
	LX_NAME = tname
	gsub(/\r\n/, "\n", src)
	gsub(/\r/, "\n", src)
	if (!KEEP_TRAILING_NL && substr(src, length(src)) == "\n") src = substr(src, 1, length(src) - 1)
	n = length(src)
	pos = 1
	line = 1
	LX_LINESTART = 1
	while (pos <= n) {
		# find next tag start
		i = lx_findtag(src, pos)
		if (!i) {
			text = substr(src, pos)
			lx_emit("data", text, line)
			break
		}
		kind = substr(src, i + 1, 1)
		sign = substr(src, i + 2, 1)
		if (sign != "-" && sign != "+") sign = ""
		tagend = i + 2 + length(sign)
		text = substr(src, pos, i - pos)
		raw = 0
		if (kind == "%") {
			tail = substr(src, i, 64)
			if (match(tail, /^\{%[-+]?[ \t\n\r\f\v]*raw[ \t\n\r\f\v]*(-%\}[ \t\n\r\f\v]*|%\})/)) {
				raw = 1
				rawend = i + RLENGTH
				# -%} may consume more whitespace than the 64 byte window
				if (substr(src, rawend - 1, 1) ~ /[ \t\n\r\f\v]/) rawend = lx_skipws(src, rawend)
			}
		}
		text = lx_strip(text, sign, kind)
		if (text != "") lx_emit("data", text, line)
		line += lx_nl(substr(src, pos, i - pos))
		if (raw) {
			# find matching endraw
			rest = substr(src, rawend)
			if (!match(rest, /\{%[-+]?[ \t\n\r\f\v]*endraw[ \t\n\r\f\v]*(\+%\}|-%\}|%\})/))
				lx_fail("Missing end of raw directive", line)
			body = substr(rest, 1, RSTART - 1)
			m = substr(rest, RSTART, RLENGTH)
			sign = substr(m, 3, 1)
			if (sign != "-" && sign != "+") sign = ""
			line += lx_nl(substr(src, i, rawend - i))
			LX_LINESTART = substr(src, rawend - 1, 1) == "\n"
			body = lx_strip(body, sign, "%")
			if (body != "") lx_emit("data", body, line)
			line += lx_nl(substr(rest, 1, RSTART + RLENGTH - 1))
			pos = rawend + RSTART + RLENGTH - 1
			pos = lx_tagtail(src, pos, substr(m, RLENGTH - 2, 1))
			continue
		}
		if (kind == "#") {
			j = lx_index(src, "#}", tagend)
			if (!j) lx_fail("Missing end of comment tag", line)
			c = (j > tagend) ? substr(src, j - 1, 1) : ""
			line += lx_nl(substr(src, i, j + 2 - i))
			pos = lx_tagtail(src, j + 2, c)
			continue
		}
		lx_emit(kind == "{" ? "var_begin" : "block_begin", "", line)
		line += lx_nl(substr(src, i, tagend - i))
		pos = lx_tag(src, tagend, kind == "{" ? "}}" : "%}", line)
		line = LX_LINE
	}
	lx_emit("eof", "", line)
}

# position of the earliest "{{", "{%" or "{#" at/after pos, 0 if none
function lx_findtag(src, pos,    off, k, c, rest) {
	rest = substr(src, pos)
	off = 0
	while ((k = index(rest, "{")) > 0) {
		c = substr(rest, k + 1, 1)
		if (c == "{" || c == "%" || c == "#") return pos + off + k - 1
		rest = substr(rest, k + 1)
		off += k
	}
	return 0
}

function lx_index(src, needle, from,    k) {
	k = index(substr(src, from), needle)
	return k ? from + k - 1 : 0
}

function lx_nl(s) { return gsub(/\n/, "", s) }

function lx_skipws(src, p) {
	while (substr(src, p, 1) ~ /^[ \t\n\r\f\v]$/) p++
	return p
}

# whitespace handling after a block/comment end: c is the modifier char
# placed before the closing delimiter ("-", "+" or other)
function lx_tagtail(src, p, c) {
	if (c == "-") p = lx_skipws(src, p)
	else if (c != "+" && TRIM_BLOCKS && substr(src, p, 1) == "\n") p++
	LX_LINESTART = substr(src, p - 1, 1) == "\n"
	return p
}

# apply "-" rstrip or lstrip_blocks to the data preceding a tag
function lx_strip(text, sign, kind,    lpos, k, after) {
	if (sign == "-") {
		sub(/[ \t\n\r\f\v]+$/, "", text)
		return text
	}
	if (sign != "+" && LSTRIP_BLOCKS && kind != "{") {
		lpos = 0
		k = text
		# last newline position
		while ((after = index(k, "\n")) > 0) {
			lpos += after
			k = substr(k, after + 1)
		}
		if (lpos > 0 || LX_LINESTART) {
			if (substr(text, lpos + 1) !~ /[^ \t]/) text = substr(text, 1, lpos)
		}
	}
	return text
}

function lx_emit(t, v, l) {
	TK_N++
	TK_T[TK_N] = t
	TK_V[TK_N] = v
	TK_L[TK_N] = l
	LX_LINESTART = 0
}

function lx_fail(msg, line) {
	rt_fail_at("TemplateSyntaxError", msg, LX_NAME, line)
}

# tokenize inside {{ }} / {% %}; returns position after the end delimiter
function lx_tag(src, p, endd, line,    n, bal, c, w, tok, q, j, s, op2, v) {
	n = length(src)
	bal = ""
	while (1) {
		if (p > n) { LX_LINE = line; return p }
		c = substr(src, p, 1)
		if (bal == "") {
			if (c == "-" && substr(src, p + 1, 2) == endd) {
				lx_emit(endd == "}}" ? "var_end" : "block_end", "", line)
				j = lx_skipws(src, p + 3)
				LX_LINE = line + lx_nl(substr(src, p + 3, j - p - 3))
				LX_LINESTART = substr(src, j - 1, 1) == "\n"
				return j
			}
			if (c == "+" && endd == "%}" && substr(src, p + 1, 2) == endd) {
				lx_emit("block_end", "", line)
				LX_LINE = line
				LX_LINESTART = 0
				return p + 3
			}
			if (substr(src, p, 2) == endd) {
				lx_emit(endd == "}}" ? "var_end" : "block_end", "", line)
				p += 2
				LX_LINESTART = 0
				if (endd == "%}" && TRIM_BLOCKS && substr(src, p, 1) == "\n") {
					p++
					line++
					LX_LINESTART = 1
				}
				LX_LINE = line
				return p
			}
		}
		if (c ~ /^[ \t\n\r\f\v]$/) {
			if (c == "\n") line++
			p++
			continue
		}
		w = substr(src, p, 256)
		# float (not preceded by ".")
		if (c ~ /^[0-9]$/ && substr(src, p - 1, 1) != "." &&
		    match(w, /^[0-9]+(_[0-9]+)*((\.[0-9]+(_[0-9]+)*)?[eE][-+]?[0-9]+(_[0-9]+)*|\.[0-9]+(_[0-9]+)*)/)) {
			tok = substr(w, 1, RLENGTH)
			gsub(/_/, "", tok)
			lx_emit("float", tok + 0, line)
			p += RLENGTH
			continue
		}
		if (c ~ /^[0-9]$/ &&
		    match(w, /^(0[bB](_?[01])+|0[oO](_?[0-7])+|0[xX](_?[0-9a-fA-F])+|[1-9](_?[0-9])*|0(_?0)*)/)) {
			tok = substr(w, 1, RLENGTH)
			gsub(/_/, "", tok)
			lx_emit("integer", lx_intval(tok), line)
			p += RLENGTH
			continue
		}
		if (match(w, /^[a-zA-Z_\200-\377][a-zA-Z0-9_\200-\377]*/)) {
			lx_emit("name", substr(w, 1, RLENGTH), line)
			p += RLENGTH
			continue
		}
		if (c == "'" || c == "\"") {
			j = p + 1
			while (j <= n) {
				s = substr(src, j, 1)
				if (s == "\\") { j += 2; continue }
				if (s == c) break
				j++
			}
			if (j > n) lx_fail("unexpected char " v_strrepr(c) " at " (p - 1), line)
			s = substr(src, p + 1, j - p - 1)
			lx_emit("string", lx_unescape(s, line), line)
			line += lx_nl(s)
			p = j + 1
			continue
		}
		op2 = substr(src, p, 2)
		if (op2 == "//" || op2 == "**" || op2 == "==" || op2 == "!=" || op2 == ">=" || op2 == "<=") {
			lx_emit(op2, op2, line)
			p += 2
			continue
		}
		if (index("+-/*%~[](){}><=.:|,;", c)) {
			if (c == "(" || c == "[" || c == "{") {
				bal = bal "" (c == "(" ? ")" : (c == "[" ? "]" : "}"))
			} else if (c == ")" || c == "]" || c == "}") {
				if (bal == "") lx_fail("unexpected '" c "'", line)
				v = substr(bal, length(bal))
				if (v != c) lx_fail("unexpected '" c "', expected '" v "'", line)
				bal = substr(bal, 1, length(bal) - 1)
			}
			lx_emit(c, c, line)
			p++
			continue
		}
		lx_fail("unexpected char " v_strrepr(c) " at " (p - 1), line)
	}
}

function lx_intval(tok,    p, base, n, i, d) {
	p = tolower(substr(tok, 1, 2))
	if (p == "0b") base = 2
	else if (p == "0o") base = 8
	else if (p == "0x") base = 16
	else {
		# keep the exact digits of big decimal literals
		sub(/^0+/, "", tok)
		return tok == "" ? "0" : tok
	}
	n = 0
	tok = tolower(substr(tok, 3))
	for (i = 1; i <= length(tok); i++) {
		d = index(HEXD, substr(tok, i, 1)) - 1
		n = n * base + d
	}
	return v_ifmt(n)
}

# Python "unicode-escape" decoding of a string literal body
function lx_unescape(s, line,    out, k, c, n, h, v) {
	if (!index(s, "\\")) return s
	out = ""
	while ((k = index(s, "\\")) > 0) {
		out = out substr(s, 1, k - 1)
		c = substr(s, k + 1, 1)
		s = substr(s, k + 2)
		if (c == "n") out = out "\n"
		else if (c == "t") out = out "\t"
		else if (c == "r") out = out "\r"
		else if (c == "\\") out = out "\\"
		else if (c == "'") out = out "'"
		else if (c == "\"") out = out "\""
		else if (c == "a") out = out "\007"
		else if (c == "b") out = out "\010"
		else if (c == "f") out = out "\014"
		else if (c == "v") out = out "\013"
		else if (c == "\n") out = out ""
		else if (c ~ /^[0-7]$/) {
			h = c
			while (length(h) < 3 && substr(s, 1, 1) ~ /^[0-7]$/) { h = h substr(s, 1, 1); s = substr(s, 2) }
			v = 0
			for (n = 1; n <= length(h); n++) v = v * 8 + substr(h, n, 1)
			out = out u8_enc(v)
		} else if (c == "x" || c == "u" || c == "U") {
			n = c == "x" ? 2 : (c == "u" ? 4 : 8)
			h = substr(s, 1, n)
			if (length(h) < n || h !~ /^[0-9a-fA-F]+$/)
				lx_fail("(unicode error) 'unicodeescape' codec can't decode bytes: truncated \\" c "XX escape", line)
			out = out u8_enc(u8_hexval(h))
			s = substr(s, n + 1)
		} else out = out "\\" c
	}
	return out s
}
