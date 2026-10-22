# value.awk - typed value heap, Python-compatible str()/repr(), equality,
# ordering and arithmetic helpers.
#
# Portability notes (POSIX awk: gawk, mawk, busybox):
#   - never write `ident (expr)` for concatenation (busybox parses a call)
#   - no `^`/`**`, sqrt, exp, log (busybox may lack math support)
#   - no sprintf("%d") for big numbers (mawk/busybox clamp to int32)
#
# Heap layout, one id per value:
#   VT[id]        type: undef none bool int float str list tuple dict
#                 macro func meth loop ns cycler joiner module self
#   VV[id]        scalar payload (str/int/float/bool, undef message, ...)
#   VM[id]        1 when the string is Markup (safe)
#   VN[id]        length of list/tuple/dict
#   VE[id,i]      list/tuple item (0-based)
#   VK[id,i]      dict key id (insertion order), VD[id,hk] dict value id
#   VW[id]        repr wrapper (range, dict_items, dict_keys, dict_values)
#   VO[id]        bound object of a method value

function v_init(    i) {
	V_N = 0
	V_NONE = v_new("none", "")
	V_TRUE = v_new("bool", 1)
	V_FALSE = v_new("bool", 0)
	V_EMPTY = v_new("str", "")
	for (i = 1; i < 256; i++) {
		CHR[i] = sprintf("%c", i)
		ORD[CHR[i]] = i
	}
	HEXD = "0123456789abcdef"
}

function v_new(t, v,    id) {
	id = ++V_N
	VT[id] = t
	VV[id] = v
	return id
}

function v_str(s) { return v_new("str", s) }
function v_markup(s,    id) { id = v_new("str", s); VM[id] = 1; return id }
function v_int(n) { return v_new("int", v_ifmt(n)) }
function v_float(f) { return v_new("float", f * 1) }
function v_bool(b) { return b ? V_TRUE : V_FALSE }
function v_undef(msg) { return v_new("undef", msg) }
function v_list() { VN[++V_N] = 0; VT[V_N] = "list"; return V_N }
function v_tuple() { VN[++V_N] = 0; VT[V_N] = "tuple"; return V_N }
function v_dict() { VN[++V_N] = 0; VT[V_N] = "dict"; return V_N }

function v_push(l, x) { VE[l, VN[l]++] = x; return l }

function v_num(id) { return VV[id] * 1 }

# Integer formatting that survives mawk/busybox (%d is int32 there).
function v_ifmt(n,    s) {
	n = n + 0
	if (n == 0) return "0"
	s = sprintf("%.0f", n)
	return s
}

function v_isnum(id,    t) {
	t = VT[id]
	return t == "int" || t == "float" || t == "bool"
}

function v_isseq(id,    t) {
	t = VT[id]
	return t == "list" || t == "tuple"
}

# ---------------------------------------------------------------- dict ----

# hash key used to index dict entries (Python: 1 == 1.0 == True)
function v_hk(id,    t, i, s, x) {
	t = VT[id]
	if (t == "str") return "s" VV[id]
	if (t == "int" || t == "bool") return "n" v_ifmt(VV[id])
	if (t == "float") {
		x = VV[id] + 0
		if (x == int(x) && x < 1e18 && x > -1e18) return "n" v_ifmt(x)
		return "n" sprintf("%.17g", x)
	}
	if (t == "none") return "N"
	if (t == "tuple") {
		s = "t"
		for (i = 0; i < VN[id]; i++) s = s "\035" v_hk(VE[id, i])
		return s
	}
	return "o" id
}

function v_dset(d, k, x,    hk) {
	hk = v_hk(k)
	if (!((d, hk) in VD)) {
		VK[d, VN[d]++] = k
	}
	VD[d, hk] = x
	return d
}

function v_dsets(d, ks, x) { return v_dset(d, v_str(ks), x) }

# value id or 0
function v_dget(d, k,    hk) {
	hk = v_hk(k)
	if ((d, hk) in VD) return VD[d, hk]
	return 0
}

function v_dgets(d, ks) {
	if ((d, "s" ks) in VD) return VD[d, "s" ks]
	return 0
}

function v_dhas(d, k) { return (d, v_hk(k)) in VD }

function v_ddel(d, k,    hk, i, j, n) {
	hk = v_hk(k)
	if (!((d, hk) in VD)) return 0
	delete VD[d, hk]
	n = VN[d]
	for (i = 0; i < n; i++) if (v_hk(VK[d, i]) == hk) break
	for (j = i; j < n - 1; j++) VK[d, j] = VK[d, j + 1]
	delete VK[d, n - 1]
	VN[d] = n - 1
	return 1
}

# shallow copies
function v_dcopy(d,    r, i) {
	r = v_dict()
	for (i = 0; i < VN[d]; i++) v_dset(r, VK[d, i], VD[d, v_hk(VK[d, i])])
	return r
}

function v_lcopy(l, t,    r, i) {
	r = (t == "tuple") ? v_tuple() : v_list()
	for (i = 0; i < VN[l]; i++) VE[r, i] = VE[l, i]
	VN[r] = VN[l]
	return r
}

# --------------------------------------------------------------- truth ----

function v_truth(id,    t) {
	t = VT[id]
	if (t == "undef") { if (STRICT) rt_undef_fail(id); return 0 }
	if (t == "none") return 0
	if (t == "bool" || t == "int" || t == "float") return VV[id] + 0 != 0
	if (t == "str") return VV[id] != ""
	if (t == "list" || t == "tuple" || t == "dict") return VN[id] > 0
	if (t == "ns") return 1
	return 1
}

# ----------------------------------------------------------------- str ----

function v_tostr(id,    t) {
	t = VT[id]
	if (t == "str") return VV[id]
	if (t == "int") return VV[id]
	if (t == "undef") { if (STRICT) rt_undef_fail(id); return "" }
	if (t == "float") return v_fltrepr(VV[id] * 1)
	if (t == "bool") return VV[id] ? "True" : "False"
	if (t == "none") return "None"
	return v_repr(id)
}

function v_repr(id,    t, s, i, n, sep) {
	t = VT[id]
	if (t == "str") {
		if (VM[id]) return "Markup(" v_strrepr(VV[id]) ")"
		return v_strrepr(VV[id])
	}
	if (t == "undef") return "Undefined"
	if (t == "int" || t == "float" || t == "bool" || t == "none") return v_tostr(id)
	if (VW[id] == "range") return VV[id]
	if (t == "list" || t == "tuple") {
		n = VN[id]
		s = ""
		for (i = 0; i < n; i++) s = s "" (i ? ", " : "") v_repr(VE[id, i])
		if (t == "tuple") {
			if (n == 1) s = s ","
			return "(" s ")"
		}
		s = "[" s "]"
		if (VW[id] != "") s = VW[id] "(" s ")"
		return s
	}
	if (t == "dict" || t == "ns") {
		n = VN[id]
		s = ""
		for (i = 0; i < n; i++)
			s = s "" (i ? ", " : "") v_repr(VK[id, i]) ": " v_repr(VD[id, v_hk(VK[id, i])])
		if (t == "ns") return "<Namespace " s ">"
		return "{" s "}"
	}
	if (t == "macro") return "<Macro '" MACRO_NAME[id] "'>"
	if (t == "loop") return "<LoopContext " (LP_I[VV[id]] + 1) "/" LP_LEN[VV[id]] ">"
	if (t == "module") return "<Module '" VV[id] "'>"
	if (t == "func" || t == "meth") return "<built-in function " VV[id] ">"
	if (t == "cycler") return "<Cycler>"
	if (t == "joiner") return "<Joiner>"
	if (t == "self") return "<TemplateReference>"
	return "<object>"
}

# double every backslash (gsub replacement escaping differs in mawk)
function v_bsdouble(s,    out, k) {
	if (!index(s, "\\")) return s
	out = ""
	while ((k = index(s, "\\")) > 0) {
		out = out substr(s, 1, k) "\\"
		s = substr(s, k + 1)
	}
	return out s
}

# Python repr() of a str
function v_strrepr(s,    q, out, i, n, c, o) {
	q = "'"
	if (index(s, "'") && !index(s, "\"")) q = "\""
	s = v_bsdouble(s)
	if (q == "'") gsub(/'/, "\\'", s)
	gsub(/\n/, "\\n", s)
	gsub(/\r/, "\\r", s)
	gsub(/\t/, "\\t", s)
	if (s ~ /[\001-\037\177]/) {
		out = ""
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			o = ORD[c]
			if (o < 32 || o == 127) c = "\\x" substr(HEXD, int(o / 16) + 1, 1) substr(HEXD, o % 16 + 1, 1)
			out = out c
		}
		s = out
	}
	return q s q
}

# Python float repr: shortest round-tripping representation.
function v_fltrepr(f,    p, s, i, m, e, digits, n, neg, out, ae) {
	if ((s = m_special(f)) != "") return s
	if (f == 0) return (sprintf("%.1f", f) ~ /^-/) ? "-0.0" : "0.0"
	for (p = 1; p <= 17; p++) {
		s = sprintf("%." (p - 1) "e", f)
		if (s + 0 == f) break
	}
	neg = substr(s, 1, 1) == "-"
	if (neg) s = substr(s, 2)
	i = index(s, "e")
	m = substr(s, 1, i - 1)
	e = substr(s, i + 1) + 0
	digits = m
	sub(/\./, "", digits)
	sub(/0+$/, "", digits)
	if (digits == "") digits = "0"
	n = length(digits)
	if (e >= -4 && e < 16) {
		if (e >= 0) {
			if (n <= e + 1) out = digits v_zeros(e + 1 - n) ".0"
			else out = substr(digits, 1, e + 1) "." substr(digits, e + 2)
		} else {
			out = "0." v_zeros(-e - 1) digits
		}
	} else {
		out = substr(digits, 1, 1)
		if (n > 1) out = out "." substr(digits, 2)
		ae = e < 0 ? -e : e
		out = out "e" (e < 0 ? "-" : "+") (ae < 10 ? "0" : "") ae
	}
	return (neg ? "-" : "") out
}

function v_zeros(n,    s) {
	s = ""
	while (n-- > 0) s = s "0"
	return s
}

function v_rep(s, n,    r) {
	r = ""
	while (n-- > 0) r = r s
	return r
}

# Python type name, for error messages
function v_pytype(id,    t) {
	t = VT[id]
	if (t == "none") return "NoneType"
	if (t == "undef") return "Undefined"
	if (t == "ns") return "Namespace"
	if (t == "macro") return "Macro"
	if (t == "loop") return "LoopContext"
	if (t == "func" || t == "meth") return "builtin_function_or_method"
	return t
}

# ----------------------------------------------------------- compare ----

function v_eq(a, b,    ta, tb, i, n, k) {
	if (a == b) return 1
	ta = VT[a]; tb = VT[b]
	if ((ta == "int" || ta == "float" || ta == "bool") && (tb == "int" || tb == "float" || tb == "bool"))
		return VV[a] + 0 == VV[b] + 0
	if (ta != tb) return 0
	if (ta == "str") return (VV[a] "") == (VV[b] "")
	if (ta == "none" || ta == "undef") return 1
	if (ta == "list" || ta == "tuple") {
		n = VN[a]
		if (n != VN[b]) return 0
		for (i = 0; i < n; i++) if (!v_eq(VE[a, i], VE[b, i])) return 0
		return 1
	}
	if (ta == "dict") {
		n = VN[a]
		if (n != VN[b]) return 0
		for (i = 0; i < n; i++) {
			k = v_hk(VK[a, i])
			if (!((b, k) in VD)) return 0
			if (!v_eq(VD[a, k], VD[b, k])) return 0
		}
		return 1
	}
	if (ta == "func" || ta == "meth") return VV[a] == VV[b] && VO[a] == VO[b]
	return 0
}

# returns -1, 0, 1; raises TypeError when not orderable
function v_cmp(a, b, op,    ta, tb, x, y, i, n, c) {
	ta = VT[a]; tb = VT[b]
	if ((ta == "int" || ta == "float" || ta == "bool") && (tb == "int" || tb == "float" || tb == "bool")) {
		x = VV[a] + 0; y = VV[b] + 0
		return x < y ? -1 : (x > y ? 1 : 0)
	}
	if (ta == "str" && tb == "str") {
		x = VV[a] ""; y = VV[b] ""
		return x < y ? -1 : (x > y ? 1 : 0)
	}
	if ((ta == "list" && tb == "list") || (ta == "tuple" && tb == "tuple")) {
		n = VN[a] < VN[b] ? VN[a] : VN[b]
		for (i = 0; i < n; i++) {
			if (v_eq(VE[a, i], VE[b, i])) continue
			return v_cmp(VE[a, i], VE[b, i], op)
		}
		return VN[a] < VN[b] ? -1 : (VN[a] > VN[b] ? 1 : 0)
	}
	if (ta == "undef" && STRICT) rt_undef_fail(a)
	if (tb == "undef" && STRICT) rt_undef_fail(b)
	if (op == "") op = "<"
	rt_fail("TypeError", "'" op "' not supported between instances of '" v_pytype(a) "' and '" v_pytype(b) "'")
}

# ------------------------------------------------------------- numbers ----

function m_floor(x,    i) {
	i = int(x)
	if (i > x) i--
	return i
}

function m_inf() { return 1e308 * 10 }

# "inf", "-inf", "nan" or "" (string based: busybox compares inf oddly)
function m_special(f,    s) {
	s = sprintf("%f", f)
	if (s ~ /nan/) return "nan"
	if (s ~ /inf/) return (s ~ /^-/) ? "-inf" : "inf"
	return ""
}
function m_nan(    x) { x = m_inf(); return x - x }

function m_abs(x) { return x < 0 ? -x : x }

# x ** y; integer exponent by squaring, otherwise exp(y*ln(x))
function m_pow(x, y,    r, n, neg) {
	if (y == int(y)) {
		n = y < 0 ? -y : y
		r = 1
		while (n > 0) {
			if (n % 2 == 1) r *= x
			x *= x
			n = int(n / 2)
		}
		return y < 0 ? 1 / r : r
	}
	if (x < 0) rt_fail("ValueError", "math domain error")
	if (x == 0) return 0
	if (HAS_MATH) return m_cpow(x, y)
	if (y == 0.5) return m_sqrt(x)
	return m_exp(y * m_ln(x))
}

# C pow(); only called when the awk has math support (busybox may not)
function m_cpow(x, y) { return x ^ y } # portable-math

function m_exp(x,    k, r, t, i, n) {
	# range reduction: x = k*ln2 + r
	k = int(x / 0.6931471805599453)
	if (x < 0) k--
	r = x - k * 0.6931471805599453
	t = 1; n = 1
	for (i = 1; i < 30; i++) { t = t * r / i; n += t }
	return n * m_pow(2, k)
}

function m_ln(x,    k, y, y2, s, t, i) {
	if (x <= 0) rt_fail("ValueError", "math domain error")
	k = 0
	while (x > 2) { x /= 2; k++ }
	while (x < 0.5) { x *= 2; k-- }
	y = (x - 1) / (x + 1)
	y2 = y * y
	s = 0; t = y
	for (i = 1; i < 200; i += 2) { s += t / i; t *= y2 }
	return 2 * s + k * 0.6931471805599453
}

function m_sqrt(x,    g, i, u, c, best, e, be) {
	if (x < 0) rt_fail("ValueError", "math domain error")
	if (x == 0) return 0
	g = x > 1 ? x / 2 : 1
	for (i = 0; i < 100; i++) g = (g + x / g) / 2
	# pick the neighbour with the smallest residual (Newton may be 1 ulp off)
	u = g * 2.220446049250313e-16
	best = g
	be = m_abs(m_sqres(g, x))
	for (i = -2; i <= 2; i++) {
		c = g + i * u / 2
		e = m_abs(m_sqres(c, x))
		if (e < be) { be = e; best = c }
	}
	return best
}

# c*c - x computed exactly (Dekker split)
function m_sqres(c, x,    t, hi, lo, p, e) {
	t = c * 134217729
	hi = t - (t - c)
	lo = c - hi
	p = c * c
	e = ((hi * hi - p) + 2 * hi * lo) + lo * lo
	return (p - x) + e
}

# Python round-half-even to ndigits (float in, float out)
function m_round(x, nd,    s) {
	s = sprintf("%." (nd < 0 ? 0 : nd) "f", x)
	return s * 1
}
