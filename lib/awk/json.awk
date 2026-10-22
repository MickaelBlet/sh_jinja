# json.awk - JSON parser (context data) and Python json.dumps (tojson)

# The parser works on a sliding window JS (position JP) over JTEXT: some
# awks (busybox) have O(n) substr on long strings.
function json_parse(text, name,    v) {
	JTEXT = text
	JTL = length(text)
	JBASE = 1
	JS = substr(text, 1, 32768)
	JL = length(JS)
	JP = 1
	JNAME = name
	json_ws()
	v = json_value()
	json_ws()
	if (JBASE + JP - 1 <= JTL) json_fail("Extra data")
	JTEXT = JS = ""
	return v
}

function json_fill() {
	if (JL - JP < 16384 && JBASE + JL <= JTL) {
		JBASE += JP - 1
		JS = substr(JTEXT, JBASE, 32768)
		JL = length(JS)
		JP = 1
	}
}

function json_fail(msg,    pre, line) {
	pre = substr(JTEXT, 1, JBASE + JP - 2)
	line = gsub(/\n/, "", pre) + 1
	rt_fail_at("JSONDecodeError", msg, JNAME, line)
}

function json_ws() {
	json_fill()
	while (JP <= JL && index(" \t\n\r", substr(JS, JP, 1))) {
		JP++
		if (JP > JL) json_fill()
	}
}

function json_value(    c, v, k, w) {
	json_fill()
	c = substr(JS, JP, 1)
	if (c == "{") {
		JP++
		v = v_dict()
		json_ws()
		if (substr(JS, JP, 1) == "}") { JP++; return v }
		while (1) {
			json_ws()
			if (substr(JS, JP, 1) != "\"") json_fail("Expecting property name enclosed in double quotes")
			k = json_string()
			json_ws()
			if (substr(JS, JP, 1) != ":") json_fail("Expecting ':' delimiter")
			JP++
			json_ws()
			v_dset(v, k, json_value())
			json_ws()
			c = substr(JS, JP, 1)
			JP++
			if (c == "}") return v
			if (c != ",") json_fail("Expecting ',' delimiter")
		}
	}
	if (c == "[") {
		JP++
		v = v_list()
		json_ws()
		if (substr(JS, JP, 1) == "]") { JP++; return v }
		while (1) {
			json_ws()
			v_push(v, json_value())
			json_ws()
			c = substr(JS, JP, 1)
			JP++
			if (c == "]") return v
			if (c != ",") json_fail("Expecting ',' delimiter")
		}
	}
	if (c == "\"") return json_string()
	w = substr(JS, JP, 64)
	if (match(w, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) {
		k = substr(w, 1, RLENGTH)
		JP += RLENGTH
		if (k ~ /[.eE]/) return v_float(k + 0)
		if (k == "-0") k = "0"
		return v_new("int", k)
	}
	if (substr(w, 1, 4) == "true") { JP += 4; return V_TRUE }
	if (substr(w, 1, 5) == "false") { JP += 5; return V_FALSE }
	if (substr(w, 1, 4) == "null") { JP += 4; return V_NONE }
	if (substr(w, 1, 3) == "NaN") { JP += 3; return v_float(m_nan()) }
	if (substr(w, 1, 8) == "Infinity") { JP += 8; return v_float(1e308 * 10) }
	if (substr(w, 1, 9) == "-Infinity") { JP += 9; return v_float(-1e308 * 10) }
	json_fail("Expecting value")
}

function json_string(    out, c, k, h, cp, lo, rest) {
	JP++
	out = ""
	while (1) {
		json_fill()
		rest = substr(JS, JP, 4096)
		if (match(rest, /^[^"\\]+/)) {
			out = out substr(rest, 1, RLENGTH)
			JP += RLENGTH
			continue
		}
		c = substr(JS, JP, 1)
		if (c == "") json_fail("Unterminated string starting at")
		JP++
		if (c == "\"") return v_str(out)
		c = substr(JS, JP, 1)
		JP++
		if (c == "n") out = out "\n"
		else if (c == "t") out = out "\t"
		else if (c == "r") out = out "\r"
		else if (c == "b") out = out "\010"
		else if (c == "f") out = out "\014"
		else if (c == "/" || c == "\\" || c == "\"") out = out c
		else if (c == "u") {
			h = substr(JS, JP, 4)
			cp = u8_hexval(h)
			if (length(h) < 4 || cp < 0) json_fail("Invalid \\uXXXX escape")
			JP += 4
			if (cp >= 55296 && cp < 56320 && substr(JS, JP, 2) == "\\u") {
				lo = u8_hexval(substr(JS, JP + 2, 4))
				if (lo >= 56320 && lo < 57344) {
					cp = 65536 + (cp - 55296) * 1024 + (lo - 56320)
					JP += 6
				}
			}
			out = out u8_enc(cp)
		} else json_fail("Invalid \\escape")
	}
}

# ------------------------------------------------------------- dumping ----

# Python json.dumps(v, sort_keys=sortk, indent=indent)
function json_dump(v, indent, sortk,    ind) {
	if (!indent || VT[indent] == "none") ind = ""
	else if (VT[indent] == "str") ind = VV[indent]
	else ind = v_rep(" ", VV[indent] + 0)
	JD_INDENTED = indent && VT[indent] != "none"
	return json_dump1(v, ind, "", sortk)
}

function json_dump1(v, ind, cur, sortk,    t, s, i, n, items, nl, sep, k, keys, x) {
	t = VT[v]
	if (t == "str") return json_str(VV[v])
	if (t == "int") return VV[v]
	if (t == "bool") return VV[v] ? "true" : "false"
	if (t == "none") return "null"
	if (t == "float") {
		x = m_special(VV[v] + 0)
		if (x == "nan") return "NaN"
		if (x == "inf") return "Infinity"
		if (x == "-inf") return "-Infinity"
		return v_fltrepr(VV[v] + 0)
	}
	nl = JD_INDENTED ? "\n" cur ind : ""
	sep = JD_INDENTED ? "," : ", "
	if (t == "list" || t == "tuple") {
		if (!VN[v]) return "[]"
		s = "["
		for (i = 0; i < VN[v]; i++) s = s "" (i ? sep : "") nl json_dump1(VE[v, i], ind, cur ind, sortk)
		return s "" (JD_INDENTED ? "\n" cur : "") "]"
	}
	if (t == "dict" || t == "ns") {
		if (!VN[v]) return "{}"
		keys = v_list()
		for (i = 0; i < VN[v]; i++) v_push(keys, VK[v, i])
		if (sortk) keys = f_sortby(keys, keys, 0)
		s = "{"
		for (i = 0; i < VN[keys]; i++) {
			k = VE[keys, i]
			s = s "" (i ? sep : "") nl json_key(k) ": " json_dump1(VD[v, v_hk(k)], ind, cur ind, sortk)
		}
		return s "" (JD_INDENTED ? "\n" cur : "") "}"
	}
	rt_fail("TypeError", "Object of type " v_pytype(v) " is not JSON serializable")
}

function json_key(k,    t) {
	t = VT[k]
	if (t == "str") return json_str(VV[k])
	if (t == "int") return "\"" VV[k] "\""
	if (t == "float") return "\"" v_fltrepr(VV[k] + 0) "\""
	if (t == "bool") return VV[k] ? "\"true\"" : "\"false\""
	if (t == "none") return "\"null\""
	rt_fail("TypeError", "keys must be str, int, float, bool or None, not " v_pytype(k))
}

# JSON string with ensure_ascii
function json_str(s,    out, n, i, c, o, arr, cp, hi, lo) {
	s = v_bsdouble(s)
	gsub(/"/, "\\\"", s)
	gsub(/\n/, "\\n", s)
	gsub(/\r/, "\\r", s)
	gsub(/\t/, "\\t", s)
	gsub(/\010/, "\\b", s)
	gsub(/\014/, "\\f", s)
	if (s ~ /[\001-\037\177-\377]/) {
		n = u8_chars(s, arr)
		out = ""
		for (i = 1; i <= n; i++) {
			c = arr[i]
			o = ORD[substr(c, 1, 1)]
			if (o < 32 || o == 127) out = out json_u4(o)
			else if (o < 128) out = out c
			else {
				cp = u8_ord(c)
				if (cp >= 65536) {
					cp -= 65536
					hi = 55296 + int(cp / 1024)
					lo = 56320 + cp % 1024
					out = out json_u4(hi) json_u4(lo)
				} else out = out json_u4(cp)
			}
		}
		s = out
	}
	return "\"" s "\""
}

function json_u4(cp) {
	return "\\u" substr(HEXD, int(cp / 4096) % 16 + 1, 1) substr(HEXD, int(cp / 256) % 16 + 1, 1) substr(HEXD, int(cp / 16) % 16 + 1, 1) substr(HEXD, cp % 16 + 1, 1)
}

function json_htmlsafe(s) {
	gsub(/</, "\\u003c", s)
	gsub(/>/, "\\u003e", s)
	gsub(/&/, "\\u0026", s)
	gsub(/'/, "\\u0027", s)
	return s
}
