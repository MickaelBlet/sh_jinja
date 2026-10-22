# filters.awk - builtin filters (jinja2/filters.py)

function f_init(    arr, n, i) {
	n = split("abs attr batch capitalize center count d default dictsort e escape filesizeformat first float forceescape format groupby indent int items join last length list lower map max min pprint random reject rejectattr replace reverse round safe select selectattr slice sort string striptags sum title tojson trim truncate unique upper urlencode urlize wordcount wordwrap xmlattr", arr, " ")
	for (i = 1; i <= n; i++) F_KNOWN[arr[i]] = 1
}

function f_escape_str(s) {
	if (s !~ /[&<>"']/) return s
	gsub(/&/, "\\&amp;", s)
	gsub(/</, "\\&lt;", s)
	gsub(/>/, "\\&gt;", s)
	gsub(/"/, "\\&#34;", s)
	gsub(/'/, "\\&#39;", s)
	return s
}

function f_escape(v) {
	if (VM[v]) return v
	return v_markup(f_escape_str(v_tostr(v)))
}

# filters calling value.items()
function f_needdict(v) {
	if (VT[v] == "undef") rt_undef_fail(v)
	if (VT[v] != "dict" && VT[v] != "ns") rt_fail("AttributeError", "'" v_pytype(v) "' object has no attribute 'items'")
}

# keep Markup-ness of the input for string results
function f_sres(v, s) { return VM[v] ? v_markup(s) : v_str(s) }

function f_bool(v) { return v ? v_truth(v) : 0 }

function f_argint(v, dflt) {
	if (!v) return dflt
	if (VT[v] == "str") return VV[v] + 0
	return VV[v] + 0
}

# Python len()
function f_len(v,    t) {
	t = VT[v]
	if (t == "str") return u8_len(VV[v])
	if (t == "list" || t == "tuple" || t == "dict" || t == "ns") return VN[v]
	if (t == "undef") { if (STRICT) rt_undef_fail(v); return 0 }
	if (t == "loop") return LP_LEN[VV[v]]
	rt_fail("TypeError", "object of type '" v_pytype(v) "' has no len()")
}

function f_call(name, v, p,    t, r, i, n, s, x, y, a, b, k, items, arr, d, cnt, w, pre) {
	t = VT[v]
	if (name == "default" || name == "d") {
		if (t == "undef" || (f_bool(ap_get(p, 1, "boolean", 0)) && !v_truth(v)))
			return ap_get(p, 0, "default_value", V_EMPTY)
		return v
	}
	if (name == "upper") return f_sres(v, u8_upper(v_tostr(v)))
	if (name == "lower") return f_sres(v, u8_lower(v_tostr(v)))
	if (name == "capitalize") {
		s = v_tostr(v)
		return f_sres(v, u8_upper(u8_sub(s, 1, 1)) u8_lower(u8_sub(s, 2, -1)))
	}
	if (name == "title") return f_sres(v, f_title(v_tostr(v)))
	if (name == "trim") return f_sres(v, b_dostrip(v_tostr(v), ap_get(p, 0, "chars", V_NONE), 3))
	if (name == "length" || name == "count") return v_int(f_len(v))
	if (name == "string") return VM[v] ? v : v_str(v_tostr(v))
	if (name == "safe") return VM[v] ? v : v_markup(v_tostr(v))
	if (name == "escape" || name == "e") return f_escape(v)
	if (name == "forceescape") return v_markup(f_escape_str(v_tostr(v)))
	if (name == "join") return f_join(v, p)
	if (name == "list") return v_lcopy(rt_iterlist(v), "list")
	if (name == "first") {
		items = rt_iterlist(v)
		return VN[items] ? VE[items, 0] : v_undef("No first item, sequence was empty.")
	}
	if (name == "last") {
		items = rt_iterlist(v)
		return VN[items] ? VE[items, VN[items] - 1] : v_undef("No last item, sequence was empty.")
	}
	if (name == "random") {
		items = rt_iterlist(v)
		if (!VN[items]) return v_undef("No random item, sequence was empty.")
		return VE[items, int(rand() * VN[items])]
	}
	if (name == "reverse") {
		if (t == "str") {
			n = u8_chars(VV[v], arr)
			s = ""
			for (i = n; i >= 1; i--) s = s arr[i]
			return f_sres(v, s)
		}
		if (t != "list" && t != "tuple" && t != "dict" && t != "undef" && t != "ns")
			rt_fail("FilterArgumentError", "argument must be iterable")
		items = rt_iterlist(v)
		r = v_list()
		for (i = VN[items] - 1; i >= 0; i--) v_push(r, VE[items, i])
		return r
	}
	if (name == "abs") {
		if (!v_isnum(v)) rt_fail("TypeError", "bad operand type for abs(): '" v_pytype(v) "'")
		x = VV[v] + 0
		if (x < 0) x = -x
		return t == "float" ? v_float(x) : v_int(x)
	}
	if (name == "int") return f_int(v, ap_get(p, 0, "default", 0), ap_get(p, 1, "base", 0))
	if (name == "float") return f_float(v, ap_get(p, 0, "default", 0))
	if (name == "round") return f_round(v, p)
	if (name == "center") {
		s = v_tostr(v)
		return f_sres(v, b_center(s, f_argint(ap_get(p, 0, "width", 0), 80), " "))
	}
	if (name == "replace") return f_replace(v, p)
	if (name == "truncate") return f_truncate(v, p)
	if (name == "wordcount") return v_int(f_wordcount(v_tostr(v)))
	if (name == "indent") return f_indent(v, p)
	if (name == "format") {
		if (AKC[p] && APN[p]) rt_fail("FilterArgumentError", "can't handle positional and keyword arguments at the same time")
		if (AKC[p]) {
			a = v_dict()
			for (i = 0; i < AKC[p]; i++) v_dsets(a, AKN[p, i], AKV[p, AKN[p, i]])
		} else {
			a = v_tuple()
			for (i = 0; i < APN[p]; i++) v_push(a, AP[p, i])
		}
		return f_sres(v, VV[rt_pyformat(v_str(v_tostr(v)), a)])
	}
	if (name == "batch") return f_batch(v, p)
	if (name == "slice") return f_slice(v, p)
	if (name == "sum") return f_sum(v, p)
	if (name == "sort") return f_sort(v, p)
	if (name == "dictsort") return f_dictsort(v, p)
	if (name == "unique") return f_unique(v, p)
	if (name == "min" || name == "max") return f_minmax(v, p, name == "max")
	if (name == "map") return f_map(v, p)
	if (name == "select" || name == "reject") return f_select(v, p, name == "reject", 0)
	if (name == "selectattr" || name == "rejectattr") return f_select(v, p, name == "rejectattr", 1)
	if (name == "groupby") return f_groupby(v, p)
	if (name == "attr") {
		k = v_tostr(ap_get(p, 0, "name", V_EMPTY))
		if (t == "undef") rt_undef_fail(v)
		if (t == "dict" || t == "list" || t == "tuple" || t == "str") {
			r = b_attr(v, k)
			if (r) return r
			return v_undef("'" rt_objdesc(v) "' has no attribute '" k "'")
		}
		return rt_getattr(v, k)
	}
	if (name == "items") {
		if (t == "undef") return v_list()
		if (t != "dict") rt_fail("TypeError", "Can only get item pairs from a mapping.")
		return b_dict_items(v, "")
	}
	if (name == "tojson") return v_markup(json_htmlsafe(json_dump(v, ap_get(p, 0, "indent", V_NONE), 1)))
	if (name == "filesizeformat") return v_str(f_filesize(v, f_bool(ap_get(p, 0, "binary", 0))))
	if (name == "striptags") return v_str(f_striptags(v_tostr(v)))
	if (name == "urlencode") return v_str(f_urlencode(v))
	if (name == "urlize") return f_urlize(v, p)
	if (name == "wordwrap") return v_str(f_wordwrap(v_tostr(v), p))
	if (name == "xmlattr") return f_xmlattr(v, p)
	if (name == "pprint") return v_str(f_pformat(v, 0, 0))
	rt_fail("TemplateRuntimeError", "No filter named '" name "' found.")
}

# --------------------------------------------------------------------------

function f_title(s,    out, n, arr, i, c, start) {
	# words start after [-\s({\[<]
	n = u8_chars(s, arr)
	out = ""
	start = 1
	for (i = 1; i <= n; i++) {
		c = arr[i]
		if (c ~ /^[- \t\n\r\f\v({[<]$/) { out = out c; start = 1; continue }
		if (start) { out = out u8_upper(c); start = 0 }
		else out = out u8_lower(c)
	}
	return out
}

function f_join(v, p,    items, sep, attr, i, s, x, mk, n, vals) {
	items = rt_iterlist(v)
	sep = ap_get(p, 0, "d", V_EMPTY)
	attr = ap_get(p, 1, "attribute", V_NONE)
	n = VN[items]
	vals = v_list()
	for (i = 0; i < n; i++) {
		x = VE[items, i]
		if (VT[attr] != "none") x = f_attrget(x, attr, 0)
		v_push(vals, x)
	}
	if (!AUTOESC) {
		s = ""
		for (i = 0; i < n; i++) s = s "" (i ? v_tostr(sep) : "") v_tostr(VE[vals, i])
		return v_str(s)
	}
	mk = VM[sep]
	if (!mk) for (i = 0; i < n; i++) if (VM[VE[vals, i]]) mk = 1
	s = ""
	for (i = 0; i < n; i++) {
		x = VE[vals, i]
		s = s "" (i ? (mk && !VM[sep] ? f_escape_str(v_tostr(sep)) : v_tostr(sep)) : "") (mk && !VM[x] ? f_escape_str(v_tostr(x)) : v_tostr(x))
	}
	return mk ? v_markup(s) : v_str(s)
}

# make_attrgetter: "a.b.0" path lookup through getitem
function f_attrget(item, attr, dflt,    parts, n, i, k, key) {
	if (VT[attr] == "int") return rt_getitem(item, attr)
	n = split(v_tostr(attr), parts, ".")
	for (i = 1; i <= n; i++) {
		if (parts[i] ~ /^[0-9]+$/) key = v_int(parts[i] + 0)
		else key = v_str(parts[i])
		item = rt_getitem(item, key)
		if (dflt && VT[item] == "undef") item = dflt
	}
	return item
}

function f_lowerkey(x) {
	if (VT[x] == "str") return v_str(u8_lower(VV[x]))
	return x
}

# key for sort/unique/minmax; attr may be comma separated (multi)
function f_key(item, attr, cs, multi,    parts, n, i, r, k) {
	if (!attr || VT[attr] == "none") return cs ? item : f_lowerkey(item)
	if (multi && VT[attr] == "str" && index(VV[attr], ",")) {
		n = split(VV[attr], parts, ",")
		r = v_list()
		for (i = 1; i <= n; i++) {
			k = f_attrget(item, v_str(parts[i]), 0)
			v_push(r, cs ? k : f_lowerkey(k))
		}
		return r
	}
	k = f_attrget(item, attr, 0)
	return cs ? k : f_lowerkey(k)
}

# stable merge sort of SRT_IDX[0..n-1] by SRT_KEY[], reverse flag
function f_msort(lo, hi, rev,    mid, i, j, k, tmp) {
	if (hi - lo < 1) return
	mid = int((lo + hi) / 2)
	f_msort(lo, mid, rev)
	f_msort(mid + 1, hi, rev)
	i = lo; j = mid + 1; k = 0
	while (i <= mid && j <= hi) {
		if (f_scmp(SRT_IDX[j], SRT_IDX[i], rev) < 0) tmp[k++] = SRT_IDX[j++]
		else tmp[k++] = SRT_IDX[i++]
	}
	while (i <= mid) tmp[k++] = SRT_IDX[i++]
	while (j <= hi) tmp[k++] = SRT_IDX[j++]
	for (i = 0; i < k; i++) SRT_IDX[lo + i] = tmp[i]
}

function f_scmp(a, b, rev,    c) {
	c = v_cmp(SRT_KEY[a], SRT_KEY[b], "<")
	return rev ? -c : c
}

# sort list items by keys (keys list parallel to items); returns new list
function f_sortby(items, keys, rev,    n, i, r) {
	n = VN[items]
	delete SRT_IDX; delete SRT_KEY
	for (i = 0; i < n; i++) { SRT_IDX[i] = i; SRT_KEY[i] = VE[keys, i] }
	f_msort(0, n - 1, rev)
	r = v_list()
	for (i = 0; i < n; i++) v_push(r, VE[items, SRT_IDX[i]])
	return r
}

function f_sort(v, p,    items, keys, i, rev, cs, attr) {
	rev = f_bool(ap_get(p, 0, "reverse", 0))
	cs = f_bool(ap_get(p, 1, "case_sensitive", 0))
	attr = ap_get(p, 2, "attribute", V_NONE)
	items = rt_iterlist(v)
	keys = v_list()
	for (i = 0; i < VN[items]; i++) v_push(keys, f_key(VE[items, i], attr, cs, 1))
	return f_sortby(items, keys, rev)
}

function f_dictsort(v, p,    cs, by, rev, pos, items, keys, i, k, x) {
	cs = f_bool(ap_get(p, 0, "case_sensitive", 0))
	by = v_tostr(ap_get(p, 1, "by", v_str("key")))
	rev = f_bool(ap_get(p, 2, "reverse", 0))
	if (by == "key") pos = 0
	else if (by == "value") pos = 1
	else rt_fail("FilterArgumentError", "You can only sort by either \"key\" or \"value\"")
	f_needdict(v)
	items = b_dict_items(v, "")
	VW[items] = ""
	keys = v_list()
	for (i = 0; i < VN[items]; i++) {
		x = VE[VE[items, i], pos]
		v_push(keys, cs ? x : f_lowerkey(x))
	}
	return f_sortby(items, keys, rev)
}

function f_unique(v, p,    cs, attr, items, r, i, k, seen, hk) {
	cs = f_bool(ap_get(p, 0, "case_sensitive", 0))
	attr = ap_get(p, 1, "attribute", V_NONE)
	items = rt_iterlist(v)
	r = v_list()
	for (i = 0; i < VN[items]; i++) {
		k = f_key(VE[items, i], attr, cs, 0)
		hk = v_hk(k)
		if (VT[k] == "list") hk = "l" v_repr(k)
		if (hk in seen) continue
		seen[hk] = 1
		v_push(r, VE[items, i])
	}
	return r
}

function f_minmax(v, p, ismax,    cs, attr, items, i, best, bk, k, c) {
	cs = f_bool(ap_get(p, 0, "case_sensitive", 0))
	attr = ap_get(p, 1, "attribute", V_NONE)
	items = rt_iterlist(v)
	if (!VN[items]) return v_undef("No aggregated item, sequence was empty.")
	best = VE[items, 0]
	bk = f_key(best, attr, cs, 0)
	for (i = 1; i < VN[items]; i++) {
		k = f_key(VE[items, i], attr, cs, 0)
		c = v_cmp(k, bk, ismax ? ">" : "<")
		if ((ismax && c > 0) || (!ismax && c < 0)) { best = VE[items, i]; bk = k }
	}
	return best
}

function f_sum(v, p,    attr, start, items, i, acc, x) {
	attr = ap_get(p, 0, "attribute", V_NONE)
	acc = ap_get(p, 1, "start", 0)
	if (!acc) acc = v_int(0)
	items = rt_iterlist(v)
	for (i = 0; i < VN[items]; i++) {
		x = VE[items, i]
		if (VT[attr] != "none") x = f_attrget(x, attr, 0)
		acc = rt_arith("add", acc, x)
	}
	return acc
}

function f_map(v, p,    items, r, i, attr, dflt, name, q, j, x) {
	r = v_list()
	if (!v_truth(v)) return r
	items = rt_iterlist(v)
	if (!APN[p] && (p, "attribute") in AKV) {
		attr = AKV[p, "attribute"]
		dflt = ((p, "default") in AKV) ? AKV[p, "default"] : 0
		if (dflt && VT[dflt] == "none") dflt = 0
		for (i = 0; i < VN[items]; i++) v_push(r, f_attrget(VE[items, i], attr, dflt))
		return r
	}
	if (!APN[p]) rt_fail("FilterArgumentError", "map requires a filter argument")
	name = v_tostr(AP[p, 0])
	q = f_shiftargs(p, 1)
	if (!(name in F_KNOWN)) rt_fail("TemplateRuntimeError", "No filter named '" name "' found.")
	for (i = 0; i < VN[items]; i++) v_push(r, f_call(name, VE[items, i], q))
	return r
}

# copy arg pack p without its first `off` positional args
function f_shiftargs(p, off,    q, j) {
	q = ap_new()
	for (j = off; j < APN[p]; j++) ap_add(q, AP[p, j])
	for (j = 0; j < AKC[p]; j++) ap_kw(q, AKN[p, j], AKV[p, AKN[p, j]])
	return q
}

function f_select(v, p, reject, lookup,    items, r, i, off, attr, name, q, x, ok, hastest) {
	r = v_list()
	if (!v_truth(v)) return r
	items = rt_iterlist(v)
	off = 0
	if (lookup) {
		if (!APN[p]) rt_fail("FilterArgumentError", "Missing parameter for attribute name")
		attr = AP[p, 0]
		off = 1
	}
	hastest = APN[p] > off
	if (hastest) {
		name = v_tostr(AP[p, off])
		q = f_shiftargs(p, off + 1)
		if (!(name in T_KNOWN)) rt_fail("TemplateRuntimeError", "No test named '" name "' found.")
	}
	for (i = 0; i < VN[items]; i++) {
		x = VE[items, i]
		if (lookup) x = f_attrget(x, attr, 0)
		ok = hastest ? t_call(name, x, q) : v_truth(x)
		if (reject) ok = !ok
		if (ok) v_push(r, VE[items, i])
	}
	return r
}

function f_groupby(v, p,    attr, dflt, items, keys, sorted, i, r, g, cur, k, lst, n) {
	attr = ap_get(p, 0, "attribute", V_NONE)
	dflt = ap_get(p, 1, "default", 0)
	if (dflt && VT[dflt] == "none") dflt = 0
	items = rt_iterlist(v)
	keys = v_list()
	for (i = 0; i < VN[items]; i++) v_push(keys, f_attrget(VE[items, i], attr, dflt))
	sorted = f_sortby(items, keys, 0)
	r = v_list()
	n = VN[sorted]
	cur = 0
	for (i = 0; i < n; i++) {
		k = f_attrget(VE[sorted, i], attr, dflt)
		if (!cur || !v_eq(k, cur)) {
			lst = v_list()
			g = v_tuple()
			v_push(g, k)
			v_push(g, lst)
			VG[g] = 1
			v_push(r, g)
			cur = k
		}
		v_push(lst, VE[sorted, i])
	}
	return r
}

function f_batch(v, p,    cnt, fill, items, r, tmp, i) {
	cnt = f_argint(ap_get(p, 0, "linecount", 0), 0)
	fill = ap_get(p, 1, "fill_with", V_NONE)
	items = rt_iterlist(v)
	r = v_list()
	tmp = v_list()
	for (i = 0; i < VN[items]; i++) {
		if (VN[tmp] == cnt) { v_push(r, tmp); tmp = v_list() }
		v_push(tmp, VE[items, i])
	}
	if (VN[tmp]) {
		if (VT[fill] != "none") while (VN[tmp] < cnt) v_push(tmp, fill)
		v_push(r, tmp)
	}
	return r
}

function f_slice(v, p,    slices, fill, items, len, per, extra, off, sn, start, end, r, tmp, i) {
	slices = f_argint(ap_get(p, 0, "slices", 0), 0)
	fill = ap_get(p, 1, "fill_with", V_NONE)
	items = rt_iterlist(v)
	len = VN[items]
	per = int(len / slices)
	extra = len % slices
	off = 0
	r = v_list()
	for (sn = 0; sn < slices; sn++) {
		start = off + sn * per
		if (sn < extra) off++
		end = off + (sn + 1) * per
		tmp = v_list()
		for (i = start; i < end && i < len; i++) v_push(tmp, VE[items, i])
		if (VT[fill] != "none" && sn >= extra) v_push(tmp, fill)
		v_push(r, tmp)
	}
	return r
}

# Python int() parsing of a string in base; returns "" if invalid
function f_parseint(s, base,    neg, d, i, n, c, digits) {
	gsub(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/, "", s)
	neg = 0
	if (substr(s, 1, 1) == "-" || substr(s, 1, 1) == "+") { neg = substr(s, 1, 1) == "-"; s = substr(s, 2) }
	c = tolower(substr(s, 1, 2))
	if (base == 0) {
		if (c == "0x") base = 16
		else if (c == "0o") base = 8
		else if (c == "0b") base = 2
		else base = 10
	}
	if ((base == 16 && c == "0x") || (base == 8 && c == "0o") || (base == 2 && c == "0b")) {
		s = substr(s, 3)
		if (substr(s, 1, 1) == "_") s = substr(s, 2)
	}
	if (s == "" || s ~ /^_|_$|__/) return ""
	gsub(/_/, "", s)
	s = tolower(s)
	digits = "0123456789abcdefghijklmnopqrstuvwxyz"
	n = 0
	for (i = 1; i <= length(s); i++) {
		d = index(digits, substr(s, i, 1)) - 1
		if (d < 0 || d >= base) return ""
		n = n * base + d
	}
	return neg ? -n : n
}

# Python float() parsing; returns "" if invalid
function f_parsefloat(s,    t) {
	gsub(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/, "", s)
	t = tolower(s)
	if (t ~ /^[-+]?(inf|infinity)$/) return substr(t, 1, 1) == "-" ? -m_inf() : m_inf()
	if (s ~ /^[-+]?([0-9](_?[0-9])*)?(\.([0-9](_?[0-9])*)?)?([eE][-+]?[0-9](_?[0-9])*)?$/ && s ~ /[0-9]/ && s !~ /^[-+]?[eE.]$/) {
		if (s ~ /^[-+]?\.?[eE]/) return ""
		gsub(/_/, "", s)
		return s + 0
	}
	return ""
}

function f_int(v, dflt, basev,    t, n, base, x) {
	t = VT[v]
	if (t == "undef") rt_undef_fail(v)
	base = basev ? VV[basev] + 0 : 10
	if (t == "int") return v
	if (t == "bool") return v_int(VV[v])
	if (t == "float") return v_int(VV[v] < 0 ? -int(-VV[v]) : int(VV[v]))
	if (t == "str") {
		n = f_parseint(VV[v], base)
		if (n != "") return v_int(n)
		x = f_parsefloat(VV[v])
		if (x != "" && x == x && x < 1e308 && x > -1e308) return v_int(x < 0 ? -int(-x) : int(x))
	}
	return dflt ? dflt : v_int(0)
}

function f_float(v, dflt,    t, x) {
	t = VT[v]
	if (t == "undef") rt_undef_fail(v)
	if (t == "float") return v
	if (t == "int" || t == "bool") return v_float(VV[v])
	if (t == "str") {
		x = f_parsefloat(VV[v])
		if (x != "") return v_float(x)
	}
	return dflt ? dflt : v_float(0)
}

function f_round(v, p,    prec, method, x, m, r) {
	prec = f_argint(ap_get(p, 0, "precision", 0), 0)
	method = v_tostr(ap_get(p, 1, "method", v_str("common")))
	if (method != "common" && method != "ceil" && method != "floor")
		rt_fail("FilterArgumentError", "method must be common, ceil or floor")
	if (!v_isnum(v)) rt_fail("TypeError", "type " v_pytype(v) " doesn't define __round__ method")
	x = VV[v] * 1
	if (method == "common") {
		if (VT[v] != "float") return v_int(prec >= 0 ? x : m_round(x / m_pow(10, -prec), 0) * m_pow(10, -prec))
		if (prec >= 0) return v_float(m_round(x, prec))
		m = m_pow(10, -prec)
		return v_float(m_round(x / m, 0) * m)
	}
	m = m_pow(10, prec)
	r = x * m
	if (method == "floor") r = m_floor(r)
	else { r = -m_floor(-r) }
	return v_float(r / m)
}

function f_replace(v, p,    s, old, new, cnt, out, k, n, arr, i, mk) {
	old = ap_get(p, 0, "old", V_EMPTY)
	new = ap_get(p, 1, "new", V_EMPTY)
	cnt = ap_get(p, 2, "count", V_NONE)
	cnt = VT[cnt] == "none" ? -1 : VV[cnt] + 0
	mk = 0
	if (AUTOESC) {
		if ((VM[old] || VM[new]) && !VM[v]) { s = f_escape_str(v_tostr(v)); mk = 1 }
		else { s = v_tostr(v); mk = VM[v] }
		old = VM[old] || !mk ? v_tostr(old) : f_escape_str(v_tostr(old))
		new = VM[new] || !mk ? v_tostr(new) : f_escape_str(v_tostr(new))
	} else {
		s = v_tostr(v)
		old = v_tostr(old)
		new = v_tostr(new)
	}
	out = b_replace(s, old, new, cnt)
	return mk ? v_markup(out) : v_str(out)
}

function f_truncate(v, p,    s, len, kill, end, lee, n, r, k, lp) {
	s = v_tostr(v)
	len = f_argint(ap_get(p, 0, "length", 0), 255)
	kill = f_bool(ap_get(p, 1, "killwords", 0))
	end = v_tostr(ap_get(p, 2, "end", v_str("...")))
	lee = ap_get(p, 3, "leeway", V_NONE)
	lee = VT[lee] == "none" ? 5 : VV[lee] + 0
	if (len < u8_len(end)) rt_fail("AssertionError", "expected length >= " u8_len(end) ", got " len)
	if (lee < 0) rt_fail("AssertionError", "expected leeway >= 0, got " lee)
	n = f_len(v)
	if (n <= len + lee) return v
	if (VT[v] != "str") rt_fail("TypeError", "can only concatenate " v_pytype(v) " (not \"str\") to " v_pytype(v))
	r = u8_sub(s, 1, len - u8_len(end))
	if (kill) return f_sres(v, r end)
	# rsplit(" ", 1)[0]
	lp = 0
	k = r
	while ((n = index(k, " ")) > 0) { lp += n; k = substr(k, n + 1) }
	if (lp) r = substr(r, 1, lp - 1)
	return f_sres(v, r end)
}

function f_wordcount(s,    n, t) {
	n = 0
	t = s
	while (match(t, /[A-Za-z0-9_\200-\377]+/)) {
		n++
		t = substr(t, RSTART + RLENGTH)
	}
	return n
}

# str.splitlines() on s; fills arr[1..n]
function f_splitlines(s, arr,    n, k) {
	n = 0
	gsub(/\r\n/, "\n", s)
	gsub(/[\r\013\014\034\035\036]/, "\n", s)
	while ((k = index(s, "\n")) > 0) {
		arr[++n] = substr(s, 1, k - 1)
		s = substr(s, k + 1)
	}
	if (s != "") arr[++n] = s
	return n
}

function f_indent(v, p,    s, w, first, blank, ind, n, arr, rv, i) {
	if (VT[v] == "undef") rt_undef_fail(v)
	if (VT[v] == "list") rt_fail("AttributeError", "'list' object has no attribute 'splitlines'")
	if (VT[v] != "str") rt_fail("TypeError", "unsupported operand type(s) for +=: '" v_pytype(v) "' and 'str'")
	s = v_tostr(v)
	w = ap_get(p, 0, "width", 0)
	if (!w) ind = "    "
	else if (VT[w] == "str") ind = VV[w]
	else ind = v_rep(" ", VV[w] + 0)
	first = f_bool(ap_get(p, 1, "first", 0))
	blank = f_bool(ap_get(p, 2, "blank", 0))
	s = s "\n"
	n = f_splitlines(s, arr)
	if (blank) {
		rv = ""
		for (i = 1; i <= n; i++) rv = rv "" (i > 1 ? "\n" ind : "") arr[i]
	} else {
		rv = arr[1]
		for (i = 2; i <= n; i++) rv = rv "\n" (arr[i] != "" ? ind arr[i] : "")
	}
	if (first) rv = ind rv
	return f_sres(v, rv)
}

function f_filesize(v, binary,    x, base, pre, i, unit, n) {
	if (VT[v] == "str") {
		x = f_parsefloat(VV[v])
		if (x == "") rt_fail("ValueError", "could not convert string to float: " v_strrepr(VV[v]))
	} else if (v_isnum(v)) x = VV[v] + 0
	else if (VT[v] == "undef") rt_undef_fail(v)
	else rt_fail("TypeError", "float() argument must be a string or a real number, not '" v_pytype(v) "'")
	base = binary ? 1024 : 1000
	n = split(binary ? "KiB MiB GiB TiB PiB EiB ZiB YiB" : "kB MB GB TB PB EB ZB YB", pre, " ")
	if (x == 1) return "1 Byte"
	if (x < base) return (x < 0 ? -int(-x) : int(x)) " Bytes"
	for (i = 1; i <= n; i++) {
		unit = m_pow(base, i + 1)
		if (x < unit) return sprintf("%.1f", base * x / unit) " " pre[i]
	}
	return sprintf("%.1f", base * x / unit) " " pre[n]
}

function f_html_unescape(s,    out, k, e, m, cp) {
	if (!index(s, "&")) return s
	out = ""
	while ((k = index(s, "&")) > 0) {
		out = out substr(s, 1, k - 1)
		s = substr(s, k)
		if (match(s, /^&#[xX][0-9a-fA-F]+;?/)) {
			e = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
			gsub(/[&#xX;]/, "", e)
			out = out u8_enc(u8_hexval(e))
		} else if (match(s, /^&#[0-9]+;?/)) {
			e = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
			gsub(/[&#;]/, "", e)
			out = out u8_enc(e + 0)
		} else if (match(s, /^&(amp|lt|gt|quot|apos|nbsp);/)) {
			e = substr(s, 2, RLENGTH - 2); s = substr(s, RLENGTH + 1)
			out = out "" (e == "amp" ? "&" : e == "lt" ? "<" : e == "gt" ? ">" : e == "quot" ? "\"" : e == "apos" ? "'" : u8_enc(160))
		} else {
			out = out "&"
			s = substr(s, 2)
		}
	}
	return out s
}

function f_striptags(s,    out, k, n, arr, i) {
	# remove comments and tags
	while (match(s, /<!--/)) {
		k = index(substr(s, RSTART + 4), "-->")
		if (!k) break
		s = substr(s, 1, RSTART - 1) substr(s, RSTART + 4 + k + 2)
	}
	gsub(/<[^>]*>/, "", s)
	n = split(s, arr, /[ \t\n\r\f\v]+/)
	out = ""
	for (i = 1; i <= n; i++) if (arr[i] != "") out = out "" (out == "" ? "" : " ") arr[i]
	return f_html_unescape(out)
}

function f_quote(s, safe,    out, i, n, c, o) {
	out = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c ~ /^[A-Za-z0-9_.~-]$/ || (safe != "" && index(safe, c))) out = out c
		else {
			o = ORD[c]
			out = out "%" toupper(substr(HEXD, int(o / 16) + 1, 1) substr(HEXD, o % 16 + 1, 1))
		}
	}
	return out
}

function f_qs(v,    s) {
	s = f_quote(v_tostr(v), "")
	gsub(/%20/, "+", s)
	return s
}

function f_urlencode(v,    t, items, i, s, pair) {
	t = VT[v]
	if (t == "str" || !(t == "list" || t == "tuple" || t == "dict")) return f_quote(v_tostr(v), "/")
	s = ""
	if (t == "dict") {
		for (i = 0; i < VN[v]; i++)
			s = s "" (i ? "&" : "") f_qs(VK[v, i]) "=" f_qs(VD[v, v_hk(VK[v, i])])
		return s
	}
	for (i = 0; i < VN[v]; i++) {
		pair = rt_iterlist(VE[v, i])
		s = s "" (i ? "&" : "") f_qs(VE[pair, 0]) "=" f_qs(VE[pair, 1])
	}
	return s
}

function f_xmlattr(v, p,    auto, i, k, x, s, items, ks) {
	f_needdict(v)
	auto = ap_get(p, 0, "autospace", V_TRUE)
	s = ""
	for (i = 0; i < VN[v]; i++) {
		k = VK[v, i]
		x = VD[v, v_hk(k)]
		if (VT[x] == "none" || VT[x] == "undef") continue
		ks = v_tostr(k)
		if (ks ~ /[ \t\n\r\f\v\/>=]/) rt_fail("ValueError", "Invalid character in attribute name: " v_repr(k))
		s = s "" (s == "" ? "" : " ") f_escape_str(ks) "=\"" (VM[x] ? v_tostr(x) : f_escape_str(v_tostr(x))) "\""
	}
	if (v_truth(auto) && s != "") s = " " s
	return AUTOESC ? v_markup(s) : v_str(s)
}

function f_ishttp(m,    rest, host) {
	if (m ~ /^(https?:\/\/|[wW][wW][wW]\.)(([A-Za-z0-9_%\200-\377-]+\.)+)?([A-Za-z][A-Za-z]+|[xX][nN]--[A-Za-z0-9_%\200-\377]+)(:[0-9]+)?([\/?#][^ \t\n\r\f\v]*)?$/) {
		host = m
		sub(/^(https?:\/\/|[wW][wW][wW]\.)/, "", host)
		sub(/[:\/?#].*$/, "", host)
		sub(/^.*\./, "", host)
		if (length(host) <= 63) return 1
	}
	if (m ~ /^([A-Za-z0-9_%\200-\377-]+\.)+([cC][oO][mM]|[nN][eE][tT]|[iI][nN][tT]|[eE][dD][uU]|[gG][oO][vV]|[oO][rR][gG]|[iI][nN][fF][oO]|[mM][iI][lL])(:[0-9]+)?([\/?#][^ \t\n\r\f\v]*)?$/) return 1
	if (m ~ /^https?:\/\/[0-9][0-9]?[0-9]?(\.[0-9][0-9]?[0-9]?)(\.[0-9][0-9]?[0-9]?)(\.[0-9][0-9]?[0-9]?)(:[0-9]+)?([\/?#][^ \t\n\r\f\v]*)?$/) return 1
	return 0
}

function f_isemail(m) { return m ~ /^[^ \t\n\r\f\v]+@[A-Za-z0-9_\200-\377][A-Za-z0-9_.\200-\377-]*\.[A-Za-z0-9_\200-\377]+$/ }

function f_urlize(v, p,    lim, nofollow, target, rel, words, n, i, w, head, mid, tail, ra, ta, out, sp, s, relp, k, sc, nsc, j) {
	lim = ap_get(p, 0, "trim_url_limit", V_NONE)
	nofollow = f_bool(ap_get(p, 1, "nofollow", 0))
	target = ap_get(p, 2, "target", V_NONE)
	rel = ap_get(p, 3, "rel", V_NONE)
	sc = ap_get(p, 4, "extra_schemes", V_NONE)
	relp = VT[rel] == "none" ? "" : v_tostr(rel)
	if (nofollow) relp = relp " nofollow"
	relp = relp " noopener"
	relp = f_sortwords(relp)
	ra = relp != "" ? " rel=\"" f_escape_str(relp) "\"" : ""
	ta = VT[target] != "none" && v_tostr(target) != "" ? " target=\"" f_escape_str(v_tostr(target)) "\"" : ""
	s = f_escape_str(v_tostr(v))
	out = ""
	while (s != "") {
		if (match(s, /^[ \t\n\r\f\v]+/)) {
			out = out substr(s, 1, RLENGTH)
			s = substr(s, RLENGTH + 1)
			continue
		}
		match(s, /^[^ \t\n\r\f\v]+/)
		w = substr(s, 1, RLENGTH)
		s = substr(s, RLENGTH + 1)
		head = ""; tail = ""; mid = w
		if (match(mid, /^([(<]|&lt;)+/)) { head = substr(mid, 1, RLENGTH); mid = substr(mid, RLENGTH + 1) }
		if (match(mid, /([).,>]|&gt;)+$/)) { tail = substr(mid, RSTART); mid = substr(mid, 1, RSTART - 1) }
		URLZ_TAIL = tail
		mid = f_urlize_balance(mid, "(", ")")
		mid = f_urlize_balance(mid, "<", ">")
		mid = f_urlize_balance(mid, "&lt;", "&gt;")
		tail = URLZ_TAIL
		if (f_ishttp(mid)) {
			if (mid ~ /^https?:\/\//) mid = "<a href=\"" mid "\"" ra ta ">" f_trimurl(mid, lim) "</a>"
			else mid = "<a href=\"https://" mid "\"" ra ta ">" f_trimurl(mid, lim) "</a>"
		} else if (substr(mid, 1, 7) == "mailto:" && f_isemail(substr(mid, 8))) {
			mid = "<a href=\"" mid "\">" substr(mid, 8) "</a>"
		} else if (index(mid, "@") && substr(mid, 1, 4) != "www." && !index(mid, ":") && f_isemail(mid)) {
			mid = "<a href=\"mailto:" mid "\">" mid "</a>"
		} else if (VT[sc] != "none") {
			nsc = rt_iterlist(sc)
			for (j = 0; j < VN[nsc]; j++) {
				k = v_tostr(VE[nsc, j])
				if (mid != k && substr(mid, 1, length(k)) == k) mid = "<a href=\"" mid "\"" ra ta ">" mid "</a>"
			}
		}
		out = out head mid tail
	}
	return AUTOESC ? v_markup(out) : v_str(out)
}

# move chars from the pending tail (URLZ_TAIL) into mid to balance sc/ec
function f_urlize_balance(mid, sc, ec,    sn, tn, k, i, tail) {
	tail = URLZ_TAIL
	sn = f_count(mid, sc)
	if (sn <= f_count(mid, ec)) return mid
	tn = f_count(tail, ec)
	if (tn > sn) tn = sn
	for (i = 0; i < tn; i++) {
		k = index(tail, ec) + length(ec) - 1
		mid = mid substr(tail, 1, k)
		tail = substr(tail, k + 1)
	}
	URLZ_TAIL = tail
	return mid
}

# non-overlapping occurrences of needle in s
function f_count(s, needle,    n, k) {
	n = 0
	if (needle == "") return u8_len(s) + 1
	while ((k = index(s, needle)) > 0) { n++; s = substr(s, k + length(needle)) }
	return n
}

function f_trimurl(x, lim) {
	if (VT[lim] == "none") return x
	if (length(x) > VV[lim] + 0) return substr(x, 1, VV[lim] + 0) "..."
	return x
}

function f_sortwords(s,    arr, n, i, j, t, out, seen) {
	n = split(s, arr, " ")
	for (i = 2; i <= n; i++) {
		t = arr[i]
		for (j = i - 1; j >= 1 && arr[j] > t; j--) arr[j + 1] = arr[j]
		arr[j + 1] = t
	}
	out = ""
	for (i = 1; i <= n; i++) {
		if (arr[i] == "" || (arr[i] in seen)) continue
		seen[arr[i]] = 1
		out = out "" (out == "" ? "" : " ") arr[i]
	}
	return out
}

# textwrap.wrap(expand_tabs=False, replace_whitespace=False) per paragraph
function f_wordwrap(s, p,    width, blw, ws, boh, n, lines, i, out) {
	width = f_argint(ap_get(p, 0, "width", 0), 79)
	blw = v_truth(ap_get(p, 1, "break_long_words", V_TRUE))
	ws = ap_get(p, 2, "wrapstring", V_NONE)
	ws = VT[ws] == "none" ? "\n" : v_tostr(ws)
	boh = v_truth(ap_get(p, 3, "break_on_hyphens", V_TRUE))
	n = f_splitlines(s, lines)
	out = ""
	for (i = 1; i <= n; i++) out = out "" (i > 1 ? ws : "") f_wrap(lines[i], width, blw, boh, ws)
	return out
}

# port of textwrap.TextWrapper._wrap_chunks
function f_wrap(text, width, blw, boh, ws,    chunks, nc, i, nl, cur, ncur, curlen, out, l, sl, end, ch, hy, j, line) {
	if (width <= 0) rt_fail("ValueError", "invalid width " width " (must be > 0)")
	nc = f_wrapchunks(text, chunks, boh)
	i = 1
	nl = 0
	out = ""
	while (i <= nc) {
		ncur = 0
		curlen = 0
		if (nl && chunks[i] ~ /^[ \t\n\r\f\v]*$/) i++
		while (i <= nc) {
			l = u8_len(chunks[i])
			if (curlen + l <= width) { cur[++ncur] = chunks[i]; curlen += l; i++ }
			else break
		}
		if (i <= nc && u8_len(chunks[i]) > width) {
			sl = width < 1 ? 1 : width - curlen
			if (blw) {
				end = sl
				ch = chunks[i]
				if (boh && u8_len(ch) > sl) {
					hy = 0
					for (j = sl - 1; j >= 1; j--) if (u8_sub(ch, j + 1, 1) == "-") { hy = j; break }
					if (hy > 0 && u8_sub(ch, 1, hy) ~ /[^-]/) end = hy + 1
				}
				cur[++ncur] = u8_sub(ch, 1, end)
				chunks[i] = u8_sub(ch, end + 1, -1)
			} else if (!ncur) {
				cur[++ncur] = chunks[i]
				i++
			}
		}
		if (ncur && cur[ncur] ~ /^[ \t\n\r\f\v]*$/) ncur--
		if (ncur) {
			line = ""
			for (j = 1; j <= ncur; j++) line = line cur[j]
			out = out "" (nl ? ws : "") line
			nl++
		}
	}
	return out
}

# textwrap wordsep_re: whitespace runs, words split after inner hyphens
function f_wrapchunks(text, chunks, boh,    n, w, j, L, c, start) {
	n = 0
	while (text != "") {
		if (match(text, /^[ \t\n\r\f\v]+/)) {
			chunks[++n] = substr(text, 1, RLENGTH)
			text = substr(text, RLENGTH + 1)
			continue
		}
		match(text, /^[^ \t\n\r\f\v]+/)
		w = substr(text, 1, RLENGTH)
		text = substr(text, RLENGTH + 1)
		if (boh && index(w, "-")) {
			L = length(w)
			start = 1
			for (j = 3; j < L; j++) {
				if (substr(w, j, 1) != "-") continue
				if (!(f_islt(substr(w, j - 2, 1)) && f_islt(substr(w, j - 1, 1))) &&
				    !(j >= 4 && f_islt(substr(w, j - 3, 1)) && substr(w, j - 2, 1) == "-" && f_islt(substr(w, j - 1, 1)))) continue
				c = substr(w, j + 1, 1)
				if (!f_islt(c)) continue
				if (!(f_islt(substr(w, j + 2, 1)) || (substr(w, j + 2, 1) == "-" && f_islt(substr(w, j + 3, 1))))) continue
				chunks[++n] = substr(w, start, j - start + 1)
				start = j + 1
			}
			w = substr(w, start)
		}
		chunks[++n] = w
	}
	return n
}

function f_islt(c) { return c ~ /^[A-Za-z\200-\377]$/ }

# ------------------------------------------------------------- pprint ----

# pprint.pformat with width 80, sort_dicts
function f_pformat(v, indent, level,    r, t, i, n, s, keys, items, k, sorted, key, ind) {
	r = f_srepr(v)
	if (length(r) + indent <= 80) return r
	t = VT[v]
	if (t == "dict" && VN[v]) {
		sorted = f_dsorted_keys(v)
		s = "{"
		for (i = 0; i < VN[sorted]; i++) {
			k = VE[sorted, i]
			key = v_repr(k) ": "
			s = s "" (i ? ",\n" v_rep(" ", indent + 1) : "") key f_pformat(VD[v, v_hk(k)], indent + 1 + length(key), level + 1)
		}
		return s "}"
	}
	if ((t == "list" || t == "tuple") && VN[v]) {
		s = t == "list" ? "[" : "("
		for (i = 0; i < VN[v]; i++)
			s = s "" (i ? ",\n" v_rep(" ", indent + 1) : "") f_pformat(VE[v, i], indent + 1, level + 1)
		if (t == "tuple" && VN[v] == 1) s = s ","
		return s "" (t == "list" ? "]" : ")")
	}
	return r
}

function f_dsorted_keys(v,    items, keys, i) {
	items = v_list()
	for (i = 0; i < VN[v]; i++) v_push(items, VK[v, i])
	return f_sortby(items, items, 0)
}

# repr with sorted dict keys (as pprint does)
function f_srepr(v,    t, s, i, sorted, k) {
	t = VT[v]
	if (VW[v] != "") return v_repr(v)
	if (t == "dict") {
		sorted = f_dsorted_keys(v)
		s = ""
		for (i = 0; i < VN[sorted]; i++) {
			k = VE[sorted, i]
			s = s "" (i ? ", " : "") v_repr(k) ": " f_srepr(VD[v, v_hk(k)])
		}
		return "{" s "}"
	}
	if (t == "list" || t == "tuple") {
		s = ""
		for (i = 0; i < VN[v]; i++) s = s "" (i ? ", " : "") f_srepr(VE[v, i])
		if (t == "tuple") return "(" s "" (VN[v] == 1 ? "," : "") ")"
		return "[" s "]"
	}
	return v_repr(v)
}
