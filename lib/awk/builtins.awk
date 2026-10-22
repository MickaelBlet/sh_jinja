# builtins.awk - Python methods of str/list/dict, template globals
# (range, dict, lipsum, cycler, joiner, namespace).

function b_init(    arr, n, i) {
	n = split("capitalize casefold center count endswith expandtabs find format format_map index isalnum isalpha isascii isdecimal isdigit isidentifier islower isnumeric isprintable isspace istitle isupper join ljust lower lstrip partition removeprefix removesuffix replace rfind rindex rjust rpartition rsplit rstrip split splitlines startswith strip swapcase title upper zfill", arr, " ")
	for (i = 1; i <= n; i++) B_STR[arr[i]] = 1
	n = split("append clear copy count extend index insert pop remove reverse sort", arr, " ")
	for (i = 1; i <= n; i++) B_LIST[arr[i]] = 1
	n = split("count index", arr, " ")
	for (i = 1; i <= n; i++) B_TUPLE[arr[i]] = 1
	n = split("clear copy get items keys pop popitem setdefault update values", arr, " ")
	for (i = 1; i <= n; i++) B_DICT[arr[i]] = 1
}

# attribute lookup on builtin values: method or attribute value, else 0
function b_attr(o, name,    t) {
	t = VT[o]
	if (t == "str") return (name in B_STR) ? rt_meth(o, name) : 0
	if (t == "list") return (name in B_LIST) ? rt_meth(o, name) : 0
	if (t == "tuple") {
		if (VG[o]) {
			if (name == "grouper") return VE[o, 0]
			if (name == "list") return VE[o, 1]
		}
		return (name in B_TUPLE) ? rt_meth(o, name) : 0
	}
	if (t == "dict") return (name in B_DICT) ? rt_meth(o, name) : 0
	if (t == "cycler") {
		if (name == "current") return VE[VV[o], CY_POS[o]]
		if (name == "next" || name == "reset") return rt_meth(o, name)
		return 0
	}
	if (t == "int" || t == "float" || t == "bool") {
		if (name == "real") return t == "float" ? o : v_int(VV[o])
		if (name == "imag") return t == "float" ? v_float(0) : v_int(0)
		return 0
	}
	return 0
}

function b_callmeth(o, name, p,    t) {
	t = VT[o]
	if (t == "str") return b_strmeth(o, name, p)
	if (t == "list" || t == "tuple") return b_listmeth(o, name, p)
	if (t == "dict") return b_dictmeth(o, name, p)
	if (t == "loop") return b_loopmeth(o, name, p)
	if (t == "cycler") {
		if (name == "reset") { CY_POS[o] = 0; return V_NONE }
		if (name == "next") return b_cycler_next(o)
	}
	rt_fail("TypeError", "'" name "' is not callable")
}

# ------------------------------------------------------------- strings ----

function b_isspace_c(c) { return c ~ /^[ \t\n\r\f\v\034\035\036\037]$/ }

# whitespace strip; mode 1=left 2=right 3=both
function b_wsstrip(s, mode) {
	if (mode == 1 || mode == 3) sub(/^[ \t\n\r\f\v\034\035\036\037]+/, "", s)
	if (mode == 2 || mode == 3) sub(/[ \t\n\r\f\v\034\035\036\037]+$/, "", s)
	return s
}

function b_cstrip(s, chars, mode,    arr, n, i, j, set, k) {
	n = u8_chars(chars, arr)
	for (k = 1; k <= n; k++) set[arr[k]] = 1
	n = u8_chars(s, arr)
	i = 1; j = n
	if (mode == 1 || mode == 3) while (i <= n && (arr[i] in set)) i++
	if (mode == 2 || mode == 3) while (j >= i && (arr[j] in set)) j--
	s = ""
	for (k = i; k <= j; k++) s = s arr[k]
	return s
}

function b_dostrip(s, chars, mode) {
	if (!chars || VT[chars] == "none") return b_wsstrip(s, mode)
	return b_cstrip(s, v_tostr(chars), mode)
}

function b_center(s, width, fill,    n, marg, left) {
	n = u8_len(s)
	if (width <= n) return s
	marg = width - n
	left = int(marg / 2) + ((marg % 2 == 1 && width % 2 == 1) ? 1 : 0)
	return v_rep(fill, left) s v_rep(fill, marg - left)
}

# str.replace(old, new, count)
function b_replace(s, old, new, cnt,    out, k, n, arr, i) {
	if (cnt == 0) return s
	if (old == "") {
		n = u8_chars(s, arr)
		out = ""
		for (i = 1; i <= n; i++) {
			if (cnt < 0 || i <= cnt) out = out new
			out = out arr[i]
		}
		if (cnt < 0 || n + 1 <= cnt) out = out new
		return out
	}
	out = ""
	while ((k = index(s, old)) > 0 && cnt != 0) {
		out = out substr(s, 1, k - 1) new
		s = substr(s, k + length(old))
		cnt--
	}
	return out s
}

function b_islower(s) { return u8_lower(s) == s && u8_upper(s) != s }
function b_isupper(s) { return u8_upper(s) == s && u8_lower(s) != s }

function b_istitle(s,    n, arr, i, c, prev, cased) {
	n = u8_chars(s, arr)
	prev = 0
	cased = 0
	for (i = 1; i <= n; i++) {
		c = arr[i]
		if (c ~ /^[A-Z]$/) { if (prev) return 0; prev = 1; cased = 1 }
		else if (c ~ /^[a-z]$/) { if (!prev) return 0; prev = 1; cased = 1 }
		else prev = 0
	}
	return cased
}

# python str.find (code point index), -1 if missing
function b_find(s, sub_, start, end,    n, arr, i, hay, k, base) {
	n = u8_len(s)
	if (start < 0) { start += n; if (start < 0) start = 0 }
	if (end == "" ) end = n
	if (end < 0) { end += n; if (end < 0) end = 0 }
	if (end > n) end = n
	if (start > end) return -1
	hay = u8_sub(s, start + 1, end - start)
	if (sub_ == "") return start
	k = index(hay, sub_)
	if (!k) return -1
	return start + u8_len(substr(hay, 1, k - 1))
}

function b_rfind(s, sub_, start, end,    n, hay, k, last, off) {
	n = u8_len(s)
	if (start < 0) { start += n; if (start < 0) start = 0 }
	if (end == "") end = n
	if (end < 0) { end += n; if (end < 0) end = 0 }
	if (end > n) end = n
	if (start > end) return -1
	hay = u8_sub(s, start + 1, end - start)
	if (sub_ == "") return end
	last = -1
	off = 0
	while ((k = index(hay, sub_)) > 0) {
		last = off + k
		off += k
		hay = substr(hay, k + 1)
	}
	if (last < 0) return -1
	return start + u8_len(substr(u8_sub(s, start + 1, end - start), 1, last - 1))
}

# python str.split; fills list
function b_split(s, sepv, maxs,    r, sep, k, n) {
	r = v_list()
	if (!sepv || VT[sepv] == "none") {
		s = b_wsstrip(s, 1)
		n = 0
		while (s != "") {
			if (maxs >= 0 && n >= maxs) { v_push(r, v_str(s)); return r }
			if (match(s, /[ \t\n\r\f\v\034\035\036\037]+/)) {
				v_push(r, v_str(substr(s, 1, RSTART - 1)))
				s = substr(s, RSTART + RLENGTH)
				n++
			} else {
				v_push(r, v_str(s))
				s = ""
			}
		}
		return r
	}
	sep = v_tostr(sepv)
	if (sep == "") rt_fail("ValueError", "empty separator")
	n = 0
	while ((k = index(s, sep)) > 0 && (maxs < 0 || n < maxs)) {
		v_push(r, v_str(substr(s, 1, k - 1)))
		s = substr(s, k + length(sep))
		n++
	}
	v_push(r, v_str(s))
	return r
}

function b_rsplit(s, sepv, maxs,    r, parts, i, n, sep, k, rev, tmp) {
	if (maxs < 0) return b_split(s, sepv, -1)
	# split from the right: reverse-scan
	tmp = v_list()
	if (!sepv || VT[sepv] == "none") {
		s = b_wsstrip(s, 2)
		n = 0
		while (s != "") {
			if (n >= maxs) { v_push(tmp, v_str(b_wsstrip(s, 2))); s = ""; break }
			if (match(s, /[ \t\n\r\f\v]+[^ \t\n\r\f\v]*$/)) {
				k = substr(s, RSTART)
				sub(/^[ \t\n\r\f\v]+/, "", k)
				v_push(tmp, v_str(k))
				s = substr(s, 1, RSTART - 1)
				n++
			} else { v_push(tmp, v_str(s)); s = "" }
		}
	} else {
		sep = v_tostr(sepv)
		n = 0
		while (n < maxs) {
			k = b_rfind_bytes(s, sep)
			if (!k) break
			v_push(tmp, v_str(substr(s, k + length(sep))))
			s = substr(s, 1, k - 1)
			n++
		}
		v_push(tmp, v_str(s))
	}
	r = v_list()
	for (i = VN[tmp] - 1; i >= 0; i--) v_push(r, VE[tmp, i])
	return r
}

# byte position of last occurrence, 0 if none
function b_rfind_bytes(s, sub_,    k, last, off) {
	last = 0; off = 0
	while ((k = index(s, sub_)) > 0) {
		last = off + k
		off += k
		s = substr(s, k + 1)
	}
	return last
}

function b_startswith(s, pv, ends,    items, i, x) {
	if (VT[pv] == "tuple" || VT[pv] == "list") {
		for (i = 0; i < VN[pv]; i++) if (b_startswith(s, VE[pv, i], ends)) return 1
		return 0
	}
	if (VT[pv] != "str") rt_fail("TypeError", (ends ? "endswith" : "startswith") " first arg must be str or a tuple of str, not " v_pytype(pv))
	x = VV[pv]
	if (ends) return length(x) <= length(s) && substr(s, length(s) - length(x) + 1) == x
	return substr(s, 1, length(x)) == x
}

function b_strmeth(o, name, p,    s, r, a, b, c, n, i, arr, x, k, sep) {
	s = VV[o]
	if (name == "upper") return f_sres(o, u8_upper(s))
	if (name == "lower" || name == "casefold") return f_sres(o, u8_lower(s))
	if (name == "title") return f_sres(o, b_pytitle(s))
	if (name == "capitalize") return f_sres(o, u8_upper(u8_sub(s, 1, 1)) u8_lower(u8_sub(s, 2, -1)))
	if (name == "swapcase") return f_sres(o, b_swapcase(s))
	if (name == "strip") return f_sres(o, b_dostrip(s, ap_get(p, 0, "", V_NONE), 3))
	if (name == "lstrip") return f_sres(o, b_dostrip(s, ap_get(p, 0, "", V_NONE), 1))
	if (name == "rstrip") return f_sres(o, b_dostrip(s, ap_get(p, 0, "", V_NONE), 2))
	if (name == "split" || name == "rsplit") {
		a = ap_get(p, 0, "sep", V_NONE)
		b = ap_get(p, 1, "maxsplit", 0)
		n = b ? VV[b] + 0 : -1
		return name == "split" ? b_split(s, a, n) : b_rsplit(s, a, n)
	}
	if (name == "splitlines") {
		r = v_list()
		a = ap_get(p, 0, "keepends", V_FALSE)
		n = b_splitlines_keep(s, arr, v_truth(a))
		for (i = 1; i <= n; i++) v_push(r, v_str(arr[i]))
		return r
	}
	if (name == "startswith") return v_bool(b_startswith(s, ap_get(p, 0, "", V_NONE), 0))
	if (name == "endswith") return v_bool(b_startswith(s, ap_get(p, 0, "", V_NONE), 1))
	if (name == "replace") {
		a = ap_get(p, 2, "count", 0)
		return f_sres(o, b_replace(s, v_tostr(ap_get(p, 0, "", V_EMPTY)), v_tostr(ap_get(p, 1, "", V_EMPTY)), a ? VV[a] + 0 : -1))
	}
	if (name == "find" || name == "index" || name == "rfind" || name == "rindex") {
		a = ap_get(p, 1, "", 0); b = ap_get(p, 2, "", 0)
		x = v_tostr(ap_get(p, 0, "", V_EMPTY))
		if (name == "find" || name == "index") k = b_find(s, x, a && VT[a] != "none" ? VV[a] + 0 : 0, b && VT[b] != "none" ? VV[b] + 0 : "")
		else k = b_rfind(s, x, a && VT[a] != "none" ? VV[a] + 0 : 0, b && VT[b] != "none" ? VV[b] + 0 : "")
		if (k < 0 && (name == "index" || name == "rindex")) rt_fail("ValueError", "substring not found")
		return v_int(k)
	}
	if (name == "count") return v_int(f_count(s, v_tostr(ap_get(p, 0, "", V_EMPTY))))
	if (name == "join") {
		a = rt_iterlist(ap_get(p, 0, "", V_NONE))
		r = ""
		for (i = 0; i < VN[a]; i++) {
			x = VE[a, i]
			if (VT[x] != "str") rt_fail("TypeError", "sequence item " i ": expected str instance, " v_pytype(x) " found")
			r = r "" (i ? s : "") VV[x]
		}
		return v_str(r)
	}
	if (name == "format") return v_str(b_strformat(s, p))
	if (name == "format_map") {
		a = ap_new()
		x = ap_get(p, 0, "", V_NONE)
		for (i = 0; i < VN[x]; i++) ap_kw(a, v_tostr(VK[x, i]), VD[x, v_hk(VK[x, i])])
		return v_str(b_strformat(s, a))
	}
	if (name == "center" || name == "ljust" || name == "rjust") {
		n = VV[ap_get(p, 0, "", v_int(0))] + 0
		c = v_tostr(ap_get(p, 1, "", v_str(" ")))
		if (name == "center") return v_str(b_center(s, n, c))
		k = n - u8_len(s)
		if (k <= 0) return o
		return v_str(name == "ljust" ? s v_rep(c, k) : v_rep(c, k) s)
	}
	if (name == "zfill") {
		n = VV[ap_get(p, 0, "", v_int(0))] + 0
		k = n - u8_len(s)
		if (k <= 0) return o
		if (substr(s, 1, 1) == "-" || substr(s, 1, 1) == "+") return v_str(substr(s, 1, 1) v_rep("0", k) substr(s, 2))
		return v_str(v_rep("0", k) s)
	}
	if (name == "isdigit" || name == "isdecimal" || name == "isnumeric") return v_bool(s ~ /^[0-9]+$/)
	if (name == "isalpha") return v_bool(s ~ /^[A-Za-z\200-\377]+$/)
	if (name == "isalnum") return v_bool(s ~ /^[A-Za-z0-9\200-\377]+$/)
	if (name == "isascii") return v_bool(u8_isascii(s))
	if (name == "isidentifier") return v_bool(s ~ /^[A-Za-z_\200-\377][A-Za-z0-9_\200-\377]*$/)
	if (name == "isprintable") return v_bool(s !~ /[\001-\037\177]/)
	if (name == "isspace") return v_bool(s ~ /^[ \t\n\r\f\v\034\035\036\037]+$/)
	if (name == "islower") return v_bool(b_islower(s))
	if (name == "isupper") return v_bool(b_isupper(s))
	if (name == "istitle") return v_bool(b_istitle(s))
	if (name == "partition" || name == "rpartition") {
		sep = v_tostr(ap_get(p, 0, "", V_EMPTY))
		if (sep == "") rt_fail("ValueError", "empty separator")
		k = name == "partition" ? index(s, sep) : b_rfind_bytes(s, sep)
		r = v_tuple()
		if (!k) {
			if (name == "partition") { v_push(r, o); v_push(r, V_EMPTY); v_push(r, V_EMPTY) }
			else { v_push(r, V_EMPTY); v_push(r, V_EMPTY); v_push(r, o) }
			return r
		}
		v_push(r, v_str(substr(s, 1, k - 1)))
		v_push(r, v_str(sep))
		v_push(r, v_str(substr(s, k + length(sep))))
		return r
	}
	if (name == "removeprefix") {
		x = v_tostr(ap_get(p, 0, "", V_EMPTY))
		if (x != "" && substr(s, 1, length(x)) == x) return v_str(substr(s, length(x) + 1))
		return o
	}
	if (name == "removesuffix") {
		x = v_tostr(ap_get(p, 0, "", V_EMPTY))
		if (x != "" && length(x) <= length(s) && substr(s, length(s) - length(x) + 1) == x) return v_str(substr(s, 1, length(s) - length(x)))
		return o
	}
	if (name == "expandtabs") {
		n = VV[ap_get(p, 0, "tabsize", v_int(8))] + 0
		return v_str(b_expandtabs(s, n))
	}
	rt_fail("AttributeError", "'str' object has no attribute '" name "'")
}

function b_expandtabs(s, n,    out, col, i, c, arr, cnt) {
	cnt = u8_chars(s, arr)
	out = ""; col = 0
	for (i = 1; i <= cnt; i++) {
		c = arr[i]
		if (c == "\t") { if (n > 0) { out = out v_rep(" ", n - col % n); col += n - col % n } }
		else if (c == "\n" || c == "\r") { out = out c; col = 0 }
		else { out = out c; col++ }
	}
	return out
}

# str.title(): uppercase after any uncased char
function b_pytitle(s,    out, n, arr, i, c, prev) {
	n = u8_chars(s, arr)
	out = ""
	prev = 0
	for (i = 1; i <= n; i++) {
		c = arr[i]
		if (u8_iscased(c)) {
			out = out "" (prev ? u8_lower(c) : u8_upper(c))
			prev = 1
		} else {
			out = out c
			prev = 0
		}
	}
	return out
}

function b_swapcase(s,    out, n, arr, i, c) {
	n = u8_chars(s, arr)
	out = ""
	for (i = 1; i <= n; i++) {
		c = arr[i]
		if (u8_lower(c) != c) c = u8_lower(c)
		else c = u8_upper(c)
		out = out c
	}
	return out
}

function b_splitlines_keep(s, arr, keep,    n, k, c, line, rest) {
	n = 0
	while (s != "") {
		if (match(s, /\r\n|[\n\r\013\014\034\035\036]/)) {
			line = substr(s, 1, RSTART - 1)
			if (keep) line = line substr(s, RSTART, RLENGTH)
			arr[++n] = line
			s = substr(s, RSTART + RLENGTH)
		} else {
			arr[++n] = s
			s = ""
		}
	}
	return n
}

# --------------------------------------------------------- str.format ----

function b_strformat(s, p,    out, k, c, field, auto, name, conv, spec, v, rest, depth, j, ch) {
	out = ""
	auto = 0
	while (s != "") {
		k = match(s, /[{}]/)
		if (!k) { out = out s; break }
		out = out substr(s, 1, RSTART - 1)
		c = substr(s, RSTART, 1)
		s = substr(s, RSTART + 1)
		if (c == "}") {
			if (substr(s, 1, 1) == "}") { out = out "}"; s = substr(s, 2); continue }
			rt_fail("ValueError", "Single '}' encountered in format string")
		}
		if (substr(s, 1, 1) == "{") { out = out "{"; s = substr(s, 2); continue }
		# find matching }
		depth = 1
		for (j = 1; j <= length(s); j++) {
			ch = substr(s, j, 1)
			if (ch == "{") depth++
			else if (ch == "}") { depth--; if (!depth) break }
		}
		if (depth) rt_fail("ValueError", "expected '}' before end of string")
		field = substr(s, 1, j - 1)
		s = substr(s, j + 1)
		conv = ""
		spec = ""
		if ((k = index(field, ":")) > 0) { spec = substr(field, k + 1); field = substr(field, 1, k - 1) }
		if ((k = index(field, "!")) > 0) { conv = substr(field, k + 1); field = substr(field, 1, k - 1) }
		if (index(spec, "{")) spec = b_strformat(spec, p)
		match(field, /^[^.[]*/)
		name = substr(field, 1, RLENGTH)
		rest = substr(field, RLENGTH + 1)
		if (name == "") {
			if (auto < 0) rt_fail("ValueError", "cannot switch from manual field specification to automatic field numbering")
			v = ap_get(p, auto, "", 0)
			if (!v) rt_fail("IndexError", "Replacement index " auto " out of range for positional args tuple")
			auto++
		} else if (name ~ /^[0-9]+$/) {
			if (auto > 0) rt_fail("ValueError", "cannot switch from automatic field numbering to manual field specification")
			auto = -1
			v = ap_get(p, name + 0, "", 0)
			if (!v) rt_fail("IndexError", "Replacement index " name " out of range for positional args tuple")
		} else {
			if (!((p, name) in AKV)) rt_fail("KeyError", v_strrepr(name))
			v = AKV[p, name]
		}
		while (rest != "") {
			if (match(rest, /^\.[^.[]+/)) {
				v = rt_getattr(v, substr(rest, 2, RLENGTH - 1))
				rest = substr(rest, RLENGTH + 1)
			} else if (match(rest, /^\[[^]]*\]/)) {
				k = substr(rest, 2, RLENGTH - 2)
				v = rt_getitem(v, k ~ /^[0-9]+$/ ? v_int(k + 0) : v_str(k))
				rest = substr(rest, RLENGTH + 1)
			} else rt_fail("ValueError", "Only '.' or '[' may follow ']' in format field specifier")
		}
		if (conv == "r" || conv == "a") v = v_str(v_repr(v))
		else if (conv == "s") v = v_str(v_tostr(v))
		out = out b_fmtspec(v, spec)
	}
	return out
}

# format(value, spec) mini-language
function b_fmtspec(v, spec,    fill, align, sign, alt, zero, width, comma, prec, type, s, x, neg, body, pad, t, n, i, intpart, frac) {
	t = VT[v]
	if (spec == "") return v_tostr(v)
	fill = " "; align = ""; sign = "-"; alt = 0; zero = 0; width = 0; comma = ""; prec = -1; type = ""
	if (length(spec) >= 2 && index("<>=^", substr(spec, 2, 1))) {
		fill = u8_sub(spec, 1, 1); align = substr(spec, 2, 1); spec = substr(spec, 3)
		if (U8W[fill] > 1) { }
	} else if (index("<>=^", substr(spec, 1, 1)) && substr(spec, 1, 1) != "") {
		align = substr(spec, 1, 1); spec = substr(spec, 2)
	}
	if (index("+- ", substr(spec, 1, 1)) && substr(spec, 1, 1) != "") { sign = substr(spec, 1, 1); spec = substr(spec, 2) }
	if (substr(spec, 1, 1) == "#") { alt = 1; spec = substr(spec, 2) }
	if (substr(spec, 1, 1) == "0") { zero = 1; spec = substr(spec, 2) }
	if (match(spec, /^[0-9]+/)) { width = substr(spec, 1, RLENGTH) + 0; spec = substr(spec, RLENGTH + 1) }
	if (substr(spec, 1, 1) == "," || substr(spec, 1, 1) == "_") { comma = substr(spec, 1, 1); spec = substr(spec, 2) }
	if (match(spec, /^\.[0-9]+/)) { prec = substr(spec, 2, RLENGTH - 1) + 0; spec = substr(spec, RLENGTH + 1) }
	type = spec
	if (zero && align == "") { fill = "0"; align = "=" }
	if (t == "str" || t == "none" || t == "undef" || t == "list" || t == "tuple" || t == "dict") {
		if (type != "" && type != "s") rt_fail("ValueError", "Unknown format code '" type "' for object of type '" v_pytype(v) "'")
		s = v_tostr(v)
		if (prec >= 0) s = u8_sub(s, 1, prec)
		if (align == "") align = "<"
		return b_align(s, "", fill, align, width)
	}
	x = VV[v] + 0
	neg = x < 0
	if (neg) x = -x
	if (type == "" && t == "float") type = "r"
	if (type == "" || type == "d" || type == "n") {
		if (t == "float" && (type == "d")) rt_fail("ValueError", "Unknown format code 'd' for object of type 'float'")
		body = sprintf("%.0f", int(x))
	} else if (type == "x" || type == "X" || type == "o" || type == "b") {
		body = rt_tobase(int(x), type == "o" ? 8 : (type == "b" ? 2 : 16))
		if (type == "b") body = b_tobin(int(x))
		if (type == "X") body = toupper(body)
		if (alt) body = "0" (type == "o" ? "o" : type == "b" ? "b" : type) body
	} else if (type == "c") {
		return b_align(u8_enc(int(x)), "", fill, align == "" ? "<" : align, width)
	} else if (type == "f" || type == "F") {
		body = sprintf("%." (prec < 0 ? 6 : prec) "f", x)
	} else if (type == "e" || type == "E") {
		body = sprintf("%." (prec < 0 ? 6 : prec) type, x)
	} else if (type == "g" || type == "G") {
		body = sprintf("%." (prec < 0 ? 6 : (prec == 0 ? 1 : prec)) type, x)
	} else if (type == "%") {
		body = sprintf("%." (prec < 0 ? 6 : prec) "f", x * 100) "%"
	} else if (type == "r") {
		if (prec >= 0) body = sprintf("%." (prec == 0 ? 1 : prec) "g", x)
		else body = v_fltrepr(x)
	} else rt_fail("ValueError", "Unknown format code '" type "' for object of type '" v_pytype(v) "'")
	if (comma != "") {
		intpart = body
		frac = ""
		if (match(body, /[.eE%]/)) { intpart = substr(body, 1, RSTART - 1); frac = substr(body, RSTART) }
		s = ""
		n = length(intpart)
		for (i = 1; i <= n; i++) {
			s = s substr(intpart, i, 1)
			if ((n - i) % 3 == 0 && i < n) s = s comma
		}
		body = s frac
	}
	s = neg ? "-" : (sign == "+" ? "+" : (sign == " " ? " " : ""))
	if (align == "") align = ">"
	return b_align(body, s, fill, align, width)
}

function b_tobin(n,    s) {
	if (n == 0) return "0"
	s = ""
	while (n > 0) { s = (n % 2) s; n = int(n / 2) }
	return s
}

function b_align(body, sign, fill, align, width,    n, pad, l) {
	n = u8_len(sign body)
	if (n >= width) return sign body
	pad = width - n
	if (align == "<") return sign body v_rep(fill, pad)
	if (align == ">") return v_rep(fill, pad) sign body
	if (align == "=") return sign v_rep(fill, pad) body
	l = int(pad / 2)
	return v_rep(fill, l) sign body v_rep(fill, pad - l)
}

# --------------------------------------------------------------- lists ----

function b_listmeth(o, name, p,    x, i, n, r, k, items, j) {
	if (name == "append") { v_push(o, ap_get(p, 0, "", V_NONE)); return V_NONE }
	if (name == "extend") {
		items = rt_iterlist(ap_get(p, 0, "", V_NONE))
		n = VN[items]
		for (i = 0; i < n; i++) v_push(o, VE[items, i])
		return V_NONE
	}
	if (name == "count") {
		x = ap_get(p, 0, "", V_NONE)
		k = 0
		for (i = 0; i < VN[o]; i++) if (v_eq(VE[o, i], x)) k++
		return v_int(k)
	}
	if (name == "index") {
		x = ap_get(p, 0, "", V_NONE)
		for (i = 0; i < VN[o]; i++) if (v_eq(VE[o, i], x)) return v_int(i)
		rt_fail("ValueError", v_repr(x) " is not in list")
	}
	if (name == "copy") return v_lcopy(o, "list")
	if (name == "clear") { VN[o] = 0; return V_NONE }
	if (name == "pop") {
		if (!VN[o]) rt_fail("IndexError", "pop from empty list")
		x = ap_get(p, 0, "", 0)
		i = x ? VV[x] + 0 : VN[o] - 1
		if (i < 0) i += VN[o]
		if (i < 0 || i >= VN[o]) rt_fail("IndexError", "pop index out of range")
		r = VE[o, i]
		for (j = i; j < VN[o] - 1; j++) VE[o, j] = VE[o, j + 1]
		VN[o]--
		return r
	}
	if (name == "insert") {
		i = VV[ap_get(p, 0, "", v_int(0))] + 0
		x = ap_get(p, 1, "", V_NONE)
		if (i < 0) { i += VN[o]; if (i < 0) i = 0 }
		if (i > VN[o]) i = VN[o]
		for (j = VN[o]; j > i; j--) VE[o, j] = VE[o, j - 1]
		VE[o, i] = x
		VN[o]++
		return V_NONE
	}
	if (name == "remove") {
		x = ap_get(p, 0, "", V_NONE)
		for (i = 0; i < VN[o]; i++) if (v_eq(VE[o, i], x)) break
		if (i >= VN[o]) rt_fail("ValueError", "list.remove(x): x not in list")
		for (j = i; j < VN[o] - 1; j++) VE[o, j] = VE[o, j + 1]
		VN[o]--
		return V_NONE
	}
	if (name == "reverse") {
		n = VN[o]
		for (i = 0; i < int(n / 2); i++) { x = VE[o, i]; VE[o, i] = VE[o, n - 1 - i]; VE[o, n - 1 - i] = x }
		return V_NONE
	}
	if (name == "sort") {
		r = v_list()
		for (i = 0; i < VN[o]; i++) v_push(r, VE[o, i])
		r = f_sortby(r, r, v_truth(ap_get(p, -1, "reverse", V_FALSE)))
		for (i = 0; i < VN[o]; i++) VE[o, i] = VE[r, i]
		return V_NONE
	}
	rt_fail("AttributeError", "'" VT[o] "' object has no attribute '" name "'")
}

# ---------------------------------------------------------------- dicts ----

function b_dict_items(d, wrap,    r, i, tp, k) {
	r = v_list()
	for (i = 0; i < VN[d]; i++) {
		k = VK[d, i]
		tp = v_tuple()
		v_push(tp, k)
		v_push(tp, VD[d, v_hk(k)])
		v_push(r, tp)
	}
	VW[r] = wrap
	return r
}

function b_dictmeth(o, name, p,    r, i, k, x, d, hk) {
	if (name == "items") return b_dict_items(o, "dict_items")
	if (name == "keys" || name == "values") {
		r = v_list()
		for (i = 0; i < VN[o]; i++) {
			k = VK[o, i]
			v_push(r, name == "keys" ? k : VD[o, v_hk(k)])
		}
		VW[r] = "dict_" name
		return r
	}
	if (name == "get") {
		x = v_dget(o, ap_get(p, 0, "", V_NONE))
		if (x) return x
		return ap_get(p, 1, "", V_NONE)
	}
	if (name == "pop") {
		k = ap_get(p, 0, "", V_NONE)
		x = v_dget(o, k)
		if (x) { v_ddel(o, k); return x }
		if (ap_has(p, 1, "")) return ap_get(p, 1, "", V_NONE)
		rt_fail("KeyError", v_repr(k))
	}
	if (name == "popitem") {
		if (!VN[o]) rt_fail("KeyError", "'popitem(): dictionary is empty'")
		k = VK[o, VN[o] - 1]
		r = v_tuple()
		v_push(r, k)
		v_push(r, v_dget(o, k))
		v_ddel(o, k)
		return r
	}
	if (name == "setdefault") {
		k = ap_get(p, 0, "", V_NONE)
		x = v_dget(o, k)
		if (x) return x
		x = ap_get(p, 1, "", V_NONE)
		v_dset(o, k, x)
		return x
	}
	if (name == "update") {
		if (APN[p]) {
			d = AP[p, 0]
			if (VT[d] == "dict") for (i = 0; i < VN[d]; i++) v_dset(o, VK[d, i], VD[d, v_hk(VK[d, i])])
			else {
				d = rt_iterlist(d)
				for (i = 0; i < VN[d]; i++) v_dset(o, VE[VE[d, i], 0], VE[VE[d, i], 1])
			}
		}
		for (i = 0; i < AKC[p]; i++) v_dsets(o, AKN[p, i], AKV[p, AKN[p, i]])
		return V_NONE
	}
	if (name == "copy") return v_dcopy(o)
	if (name == "clear") {
		for (i = 0; i < VN[o]; i++) delete VD[o, v_hk(VK[o, i])]
		VN[o] = 0
		return V_NONE
	}
	rt_fail("AttributeError", "'dict' object has no attribute '" name "'")
}

# ---------------------------------------------------------------- loop ----

function b_loopmeth(o, name, p,    lp, i, a, prev, n) {
	lp = VV[o]
	if (name == "cycle") {
		if (!APN[p]) rt_fail("TypeError", "no items for cycling given")
		return AP[p, LP_I[lp] % APN[p]]
	}
	if (name == "changed") {
		a = v_tuple()
		for (i = 0; i < APN[p]; i++) v_push(a, AP[p, i])
		if (LP_CHG[lp] && v_eq(LP_CHG[lp], a)) return V_FALSE
		LP_CHG[lp] = a
		return V_TRUE
	}
	rt_fail("AttributeError", "'LoopContext' object has no attribute '" name "'")
}

# -------------------------------------------------------------- globals ----

function b_global(name, p,    r, a, b, c, i, x, n, st, k) {
	if (name == "range") {
		if (APN[p] == 1) { a = 0; b = VV[AP[p, 0]] + 0; c = 1 }
		else { a = VV[AP[p, 0]] + 0; b = VV[AP[p, 1]] + 0; c = APN[p] > 2 ? VV[AP[p, 2]] + 0 : 1 }
		for (i = 0; i < APN[p]; i++) if (!rt_isint(AP[p, i])) rt_fail("TypeError", "'" v_pytype(AP[p, i]) "' object cannot be interpreted as an integer")
		if (!APN[p]) rt_fail("TypeError", "range expected at least 1 argument, got 0")
		if (c == 0) rt_fail("ValueError", "range() arg 3 must not be zero")
		r = v_list()
		if (c > 0) for (x = a; x < b; x += c) v_push(r, v_int(x))
		else for (x = a; x > b; x += c) v_push(r, v_int(x))
		VW[r] = "range"
		VV[r] = "range(" v_ifmt(a) ", " v_ifmt(b) (c != 1 ? ", " v_ifmt(c) : "") ")"
		return r
	}
	if (name == "dict") {
		r = v_dict()
		if (APN[p]) {
			x = AP[p, 0]
			if (VT[x] == "dict") r = v_dcopy(x)
			else {
				x = rt_iterlist(x)
				for (i = 0; i < VN[x]; i++) v_dset(r, VE[VE[x, i], 0], VE[VE[x, i], 1])
			}
		}
		for (i = 0; i < AKC[p]; i++) v_dsets(r, AKN[p, i], AKV[p, AKN[p, i]])
		return r
	}
	if (name == "namespace") {
		r = b_global("dict", p)
		VT[r] = "ns"
		return r
	}
	if (name == "cycler") {
		r = v_new("cycler", 0)
		a = v_list()
		for (i = 0; i < APN[p]; i++) v_push(a, AP[p, i])
		if (!VN[a]) rt_fail("RuntimeError", "at least one item has to be provided")
		VV[r] = a
		CY_POS[r] = 0
		return r
	}
	if (name == "joiner") {
		r = v_new("joiner", v_tostr(ap_get(p, 0, "sep", v_str(", "))))
		JN_USED[r] = 0
		return r
	}
	if (name == "lipsum") return b_lipsum(p)
	rt_fail("TypeError", "'" name "' is not callable")
}

function b_cycler_next(o,    r, items) {
	items = VV[o]
	r = VE[items, CY_POS[o]]
	CY_POS[o] = (CY_POS[o] + 1) % VN[items]
	return r
}

function b_joiner_call(o) {
	if (!JN_USED[o]) { JN_USED[o] = 1; return V_EMPTY }
	return v_str(VV[o])
}

function b_lipsum(p,    n, html, mn, mx, words, nw, out, i, j, cnt, w, last, lc, lf, nc, para, res) {
	n = VV[ap_get(p, 0, "n", v_int(5))] + 0
	html = v_truth(ap_get(p, 1, "html", V_TRUE))
	mn = VV[ap_get(p, 2, "min", v_int(20))] + 0
	mx = VV[ap_get(p, 3, "max", v_int(100))] + 0
	nw = split("a ac accumsan ad adipiscing aenean aliquam aliquet amet ante aptent arcu at auctor augue bibendum blandit class commodo condimentum congue consectetuer consequat conubia convallis cras cubilia cum curabitur curae cursus dapibus diam dictum dictumst dignissim dis dolor donec dui duis egestas eget eleifend elementum elit enim erat eros est et etiam eu euismod facilisi facilisis fames faucibus felis fermentum feugiat fringilla fusce gravida habitant habitasse hac hendrerit hymenaeos iaculis id imperdiet in inceptos integer interdum ipsum justo lacinia lacus laoreet lectus leo libero ligula litora lobortis lorem luctus maecenas magna magnis malesuada massa mattis mauris metus mi molestie mollis montes morbi mus nam nascetur natoque nec neque netus nibh nisi nisl non nonummy nostra nulla nullam nunc odio orci ornare parturient pede pellentesque penatibus per pharetra phasellus placerat platea porta porttitor posuere potenti praesent pretium primis proin pulvinar purus quam quis quisque rhoncus ridiculus risus rutrum sagittis sapien scelerisque sed sem semper senectus sit sociis sociosqu sodales sollicitudin suscipit suspendisse taciti tellus tempor tempus tincidunt torquent tortor tristique turpis ullamcorper ultrices ultricies urna ut varius vehicula vel velit venenatis vestibulum vitae vivamus viverra volutpat vulputate", words, " ")
	res = ""
	for (i = 0; i < n; i++) {
		nc = 1; lc = 0; lf = 0; last = ""
		para = ""
		cnt = mn + int(rand() * (mx - mn))
		for (j = 0; j < cnt; j++) {
			do { w = words[1 + int(rand() * nw)] } while (w == last)
			last = w
			if (nc) { w = toupper(substr(w, 1, 1)) substr(w, 2); nc = 0 }
			if (j - (3 + int(rand() * 5)) > lc) { lc = j; lf += 2; w = w "," }
			if (j - (10 + int(rand() * 10)) > lf) { lc = lf = j; w = w "."; nc = 1 }
			para = para "" (j ? " " : "") w
		}
		if (para ~ /,$/) para = substr(para, 1, length(para) - 1) "."
		else if (para !~ /\.$/) para = para "."
		if (html) res = res "" (i ? "\n" : "") "<p>" f_escape_str(para) "</p>"
		else res = res "" (i ? "\n\n" : "") para
	}
	return html ? v_markup(res) : v_str(res)
}
