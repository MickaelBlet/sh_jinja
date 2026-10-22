# tests.awk - builtin tests (jinja2/tests.py)

function t_init(    arr, n, i) {
	n = split("odd even divisibleby defined undefined filter test none boolean false true integer float lower upper string mapping number sequence iterable callable sameas escaped in == eq equalto != ne > gt greaterthan ge >= < lt lessthan <= le", arr, " ")
	for (i = 1; i <= n; i++) T_KNOWN[arr[i]] = 1
}

function t_intarg(v, what) {
	if (VT[v] == "undef") rt_undef_fail(v)
	if (!v_isnum(v)) rt_fail("TypeError", "not all arguments converted during string formatting")
	return VV[v] + 0
}

function t_mod(v, d,    x, r) {
	# str % int is string formatting in Python
	if (VT[v] == "str") { rt_pyformat(v, v_int(d)); return -1 }
	x = t_intarg(v)
	if (d == 0) rt_fail("ZeroDivisionError", "integer division or modulo by zero")
	r = x % d
	if (r != 0 && ((r < 0) != (d < 0))) r += d
	return r
}

function t_call(name, v, p,    t, o) {
	t = VT[v]
	if (name == "defined") return t != "undef"
	if (name == "undefined") return t == "undef"
	if (name == "odd") return t_mod(v, 2) == 1
	if (name == "even") return t_mod(v, 2) == 0
	if (name == "divisibleby") return t_mod(v, t_intarg(ap_get(p, 0, "num", V_NONE))) == 0
	if (name == "none") return t == "none"
	if (name == "boolean") return t == "bool"
	if (name == "false") return t == "bool" && !VV[v]
	if (name == "true") return t == "bool" && VV[v]
	if (name == "integer") return t == "int"
	if (name == "float") return t == "float"
	if (name == "number") return t == "int" || t == "float" || t == "bool"
	if (name == "string") return t == "str"
	if (name == "mapping") return t == "dict"
	if (name == "sequence") return t == "str" || t == "list" || t == "tuple" || t == "dict" || t == "undef"
	if (name == "iterable") return t == "str" || t == "list" || t == "tuple" || t == "dict" || t == "undef" || t == "ns"
	if (name == "callable") return t == "macro" || t == "func" || t == "meth" || t == "joiner" || t == "loop"
	if (name == "escaped") return VM[v] ? 1 : 0
	if (name == "lower") return b_islower(v_tostr(v))
	if (name == "upper") return b_isupper(v_tostr(v))
	if (name == "filter") return (v_tostr(v) in F_KNOWN)
	if (name == "test") return (v_tostr(v) in T_KNOWN)
	if (name == "sameas") {
		o = ap_get(p, 0, "other", V_NONE)
		if (v == o) return 1
		if (t == "none" && VT[o] == "none") return 1
		if (t == "bool" && VT[o] == "bool") return VV[v] == VV[o]
		if (t == "int" && VT[o] == "int" && VV[v] == VV[o] && VV[v] + 0 >= -5 && VV[v] + 0 <= 256) return 1
		return 0
	}
	if (name == "in") return rt_contains(ap_get(p, 0, "seq", V_NONE), v)
	o = ap_get(p, 0, "b", V_NONE)
	if (name == "==" || name == "eq" || name == "equalto") return rt_compare("==", v, o)
	if (name == "!=" || name == "ne") return rt_compare("!=", v, o)
	if (name == ">" || name == "gt" || name == "greaterthan") return rt_compare(">", v, o)
	if (name == ">=" || name == "ge") return rt_compare(">=", v, o)
	if (name == "<" || name == "lt" || name == "lessthan") return rt_compare("<", v, o)
	if (name == "<=" || name == "le") return rt_compare("<=", v, o)
	rt_fail("TemplateRuntimeError", "No test named '" name "' found.")
}
