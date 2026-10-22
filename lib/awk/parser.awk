# parser.awk - tokens -> AST, mirrors jinja2/parser.py
#
# Nodes: NT[n] type, NL[n] line, NA[n] scalar attribute,
#        NX[n,key] child, NC[n,key] list length, NX[n,key,i] list item.

function nd(t, line) {
	ND_N++
	NT[ND_N] = t
	NL[ND_N] = line
	return ND_N
}
function nset(n, k, v) { NX[n, k] = v }
function nget(n, k) { return ((n, k) in NX) ? NX[n, k] : 0 }
function npush(n, k, v) { NX[n, k, NC[n, k]++] = v }
function nlen(n, k) { return NC[n, k] + 0 }
function nat(n, k, i) { return NX[n, k, i] }

# ------------------------------------------------------------ stream ----

function ps_t() { return TK_T[PS_P] }
function ps_v() { return TK_V[PS_P] }
function ps_line() { return TK_L[PS_P] }
function ps_is(t) { return TK_T[PS_P] == t }
function ps_isname(v) { return TK_T[PS_P] == "name" && TK_V[PS_P] == v }
function ps_look_t() { return TK_T[PS_P + 1] }
function ps_look_isname(v) { return TK_T[PS_P + 1] == "name" && TK_V[PS_P + 1] == v }
function ps_next() { if (TK_T[PS_P] != "eof") PS_P++ }
function ps_skip_if(t) { if (TK_T[PS_P] == t) { ps_next(); return 1 } return 0 }
function ps_skip_name(v) { if (ps_isname(v)) { ps_next(); return 1 } return 0 }

# "name:endfor name:else" style test
function ps_test_any(toks,    arr, n, i, x) {
	n = split(toks, arr, " ")
	for (i = 1; i <= n; i++) {
		x = arr[i]
		if (substr(x, 1, 5) == "name:") { if (ps_isname(substr(x, 6))) return 1 }
		else if (ps_is(x)) return 1
	}
	return 0
}

function ps_describe(t, v) {
	if (t == "name") return v
	if (t == "eof") return "end of template"
	if (t == "block_end") return "end of statement block"
	if (t == "var_end") return "end of print statement"
	if (t == "block_begin") return "begin of statement block"
	if (t == "var_begin") return "begin of print statement"
	if (t == "string" || t == "integer" || t == "float") return t
	if (t == "data") return "template data / text"
	return t
}

function ps_fail(msg, line) {
	rt_fail_at("TemplateSyntaxError", msg, PS_NAME, line ? line : ps_line())
}

function ps_expect(t,    v, d) {
	if (substr(t, 1, 5) == "name:") {
		v = substr(t, 6)
		if (ps_isname(v)) { ps_next(); return PS_P - 1 }
		d = v
	} else {
		if (ps_is(t)) { ps_next(); return PS_P - 1 }
		d = ps_describe(t, "")
	}
	if (ps_is("eof")) ps_fail("unexpected end of template, expected '" d "'.")
	ps_fail("expected token '" d "', got '" ps_describe(ps_t(), ps_v()) "'")
}

# ------------------------------------------------------------- entry ----

# parse current token stream; returns template root node
function ps_parse(tname,    root) {
	PS_NAME = tname
	PS_P = 1
	PS_TAGS = 0
	PS_ENDS = 0
	PS_UNK_N = 0
	PS_SOFT = 0
	root = ps_subparse("")
	if (PS_UNK_N)
		rt_fail_at("TemplateAssertionError", "No " PS_UNK_KIND[1] " named '" PS_UNK_NAME[1] "'.", PS_NAME, PS_UNK_LINE[1])
	return root
}

function ps_subparse(endtoks,    body, line, e) {
	body = nd("body", ps_line())
	if (endtoks != "") PS_END[++PS_ENDS] = endtoks
	while (!ps_is("eof")) {
		if (ps_is("data")) {
			e = nd("data", ps_line())
			NA[e] = ps_v()
			npush(body, "c", e)
			ps_next()
		} else if (ps_is("var_begin")) {
			ps_next()
			e = nd("emit", ps_line())
			nset(e, "expr", ps_tuple(0, 1, "", 0))
			npush(body, "c", e)
			ps_expect("var_end")
		} else if (ps_is("block_begin")) {
			ps_next()
			if (endtoks != "" && ps_test_any(endtoks)) {
				PS_ENDS--
				return body
			}
			e = ps_statement()
			if (e) npush(body, "c", e)
			ps_expect("block_end")
		} else {
			ps_fail("internal parsing error")
		}
	}
	if (endtoks != "") PS_ENDS--
	return body
}

function ps_statements(endtoks, drop,    body) {
	ps_skip_if(":")
	ps_expect("block_end")
	body = ps_subparse(endtoks)
	if (ps_is("eof")) ps_fail_eof(endtoks)
	if (drop) ps_next()
	return body
}

function ps_fail_eof(endtoks,    msg, i, look) {
	look = ps_endtoks_desc(endtoks)
	msg = "Unexpected end of template."
	if (look != "") msg = msg " Jinja was looking for the following tags: " look "."
	if (PS_TAGS > 0) msg = msg " The innermost block that needs to be closed is '" PS_TAG[PS_TAGS] "'."
	ps_fail(msg)
}

function ps_endtoks_desc(toks,    arr, n, i, s) {
	n = split(toks, arr, " ")
	s = ""
	for (i = 1; i <= n; i++) {
		sub(/^name:/, "", arr[i])
		s = s "" (i > 1 ? " or " : "") "'" arr[i] "'"
	}
	return s
}

function ps_fail_unknown(name, line,    msg, look, i, arr, n, j, found) {
	msg = "Encountered unknown tag '" name "'."
	if (PS_ENDS > 0) {
		look = ps_endtoks_desc(PS_END[PS_ENDS])
		found = 0
		for (i = 1; i <= PS_ENDS; i++) {
			n = split(PS_END[i], arr, " ")
			for (j = 1; j <= n; j++) if (arr[j] == "name:" name) found = 1
		}
		if (found) msg = msg " You probably made a nesting mistake. Jinja is expecting this tag, but currently looking for " look "."
		else msg = msg " Jinja was looking for the following tags: " look "."
	}
	if (PS_TAGS > 0) msg = msg " The innermost block that needs to be closed is '" PS_TAG[PS_TAGS] "'."
	ps_fail(msg, line)
}

# unknown filters/tests fail at compile time unless inside if/condexpr
function ps_unknown(kind, name, line) {
	PS_UNK_N++
	PS_UNK_KIND[PS_UNK_N] = kind
	PS_UNK_NAME[PS_UNK_N] = name
	PS_UNK_LINE[PS_UNK_N] = line
}

# --------------------------------------------------------- statements ----

function ps_statement(    v, r, line, soft) {
	if (!ps_is("name")) ps_fail("tag name expected")
	v = ps_v()
	line = ps_line()
	PS_TAG[++PS_TAGS] = v
	soft = PS_SOFT
	if (v != "if" && v != "set" && v != "print" && v != "include" && v != "import" && v != "from" && v != "extends" && v != "do" && v != "autoescape") PS_SOFT = 0
	else if (v == "if") PS_SOFT++
	if (v == "for") r = ps_for()
	else if (v == "if") r = ps_if()
	else if (v == "block") r = ps_block()
	else if (v == "extends") r = ps_extends()
	else if (v == "print") r = ps_print()
	else if (v == "macro") r = ps_macro()
	else if (v == "include") r = ps_include()
	else if (v == "from") r = ps_from()
	else if (v == "import") r = ps_import()
	else if (v == "set") r = ps_set()
	else if (v == "with") r = ps_with()
	else if (v == "autoescape") r = ps_autoescape()
	else if (v == "call") r = ps_callblock()
	else if (v == "filter") r = ps_filterblock()
	else if ((v == "break" || v == "continue") && EXT_LOOPCONTROLS) {
		if (!PS_INLOOP) ps_fail("'" v "' tag outside of loop")
		ps_next()
		r = nd(v, line)
	} else if (v == "do" && EXT_DO) {
		ps_next()
		r = nd("do", line)
		nset(r, "expr", ps_tuple(0, 1, "", 0))
	} else {
		PS_TAGS--
		ps_fail_unknown(v, line)
	}
	PS_SOFT = soft
	PS_TAGS--
	return r
}

function ps_set(    n, line, target, f) {
	line = ps_line()
	ps_next()
	target = ps_assign_target(1, 0, "", 1)
	if (ps_skip_if("=")) {
		n = nd("set", line)
		nset(n, "target", target)
		nset(n, "expr", ps_tuple(0, 1, "", 0))
		return n
	}
	n = nd("setblock", line)
	nset(n, "target", target)
	nset(n, "filter", ps_filter(0, 0))
	nset(n, "body", ps_statements("name:endset", 1))
	return n
}

function ps_for(    n, line, saved) {
	line = ps_line()
	ps_expect("name:for")
	n = nd("for", line)
	nset(n, "target", ps_assign_target(1, 0, "name:in", 0))
	ps_expect("name:in")
	nset(n, "iter", ps_tuple(0, 0, "name:recursive", 0))
	if (ps_skip_name("if")) nset(n, "test", ps_expression(1))
	NA[n] = ps_skip_name("recursive")
	saved = PS_INLOOP
	PS_INLOOP = 1
	nset(n, "body", ps_statements("name:endfor name:else", 0))
	PS_INLOOP = saved
	if (ps_v() == "endfor") {
		ps_next()
	} else {
		ps_next()
		nset(n, "else", ps_statements("name:endfor", 1))
	}
	return n
}

function ps_if(    result, node, line, tok, n2) {
	line = ps_line()
	ps_expect("name:if")
	result = node = nd("if", line)
	while (1) {
		nset(node, "test", ps_tuple(0, 0, "", 0))
		nset(node, "body", ps_statements("name:elif name:else name:endif", 0))
		tok = ps_v()
		ps_next()
		if (tok == "elif") {
			line = ps_line()
			n2 = nd("if", line)
			nset(node, "elif", n2)
			node = n2
			continue
		} else if (tok == "else") {
			nset(node, "else", ps_statements("name:endif", 1))
		}
		break
	}
	return result
}

function ps_with(    n, t) {
	n = nd("with", ps_line())
	ps_next()
	while (!ps_is("block_end")) {
		if (nlen(n, "targets")) ps_expect(",")
		t = ps_assign_target(1, 0, "", 0)
		npush(n, "targets", t)
		ps_expect("=")
		npush(n, "values", ps_expression(1))
	}
	nset(n, "body", ps_statements("name:endwith", 1))
	return n
}

function ps_autoescape(    n) {
	n = nd("autoescape", ps_line())
	ps_next()
	nset(n, "expr", ps_expression(1))
	nset(n, "body", ps_statements("name:endautoescape", 1))
	return n
}

function ps_block(    n, name, i, c, ok, d) {
	n = nd("block", ps_line())
	ps_next()
	name = TK_V[ps_expect("name")]
	NA[n] = name
	nset(n, "scoped", ps_skip_name("scoped"))
	nset(n, "required", ps_skip_name("required"))
	if (ps_is("-"))
		ps_fail("Block names in Jinja have to be valid Python identifiers and may not contain hyphens, use an underscore instead.")
	nset(n, "body", ps_statements("name:endblock", 1))
	if (nget(n, "required")) {
		c = nget(n, "body")
		for (i = 0; i < nlen(c, "c"); i++) {
			d = nat(c, "c", i)
			if (NT[d] != "data" || NA[d] !~ /^[ \t\n\r\f\v]+$/)
				ps_fail("Required blocks can only contain comments or whitespace")
		}
	}
	ps_skip_name(name)
	if ((PS_TPL, name) in TPL_BLK)
		rt_fail_at("TemplateAssertionError", "block '" name "' defined twice", PS_NAME, NL[n])
	TPL_BLK[PS_TPL, name] = n
	return n
}

function ps_extends(    n) {
	n = nd("extends", ps_line())
	ps_next()
	nset(n, "template", ps_expression(1))
	return n
}

function ps_import_context(n, dflt) {
	if ((ps_isname("with") || ps_isname("without")) && ps_look_isname("context")) {
		nset(n, "with_context", ps_v() == "with")
		ps_next(); ps_next()
	} else {
		nset(n, "with_context", dflt)
	}
	return n
}

function ps_include(    n) {
	n = nd("include", ps_line())
	ps_next()
	nset(n, "template", ps_expression(1))
	if (ps_isname("ignore") && ps_look_isname("missing")) {
		nset(n, "ignore_missing", 1)
		ps_next(); ps_next()
	}
	return ps_import_context(n, 1)
}

function ps_import(    n) {
	n = nd("import", ps_line())
	ps_next()
	nset(n, "template", ps_expression(1))
	ps_expect("name:as")
	NA[n] = TK_V[ps_expect("name")]
	return ps_import_context(n, 0)
}

function ps_from(    n, name, k, done) {
	n = nd("fromimport", ps_line())
	ps_next()
	nset(n, "template", ps_expression(1))
	ps_expect("name:import")
	nset(n, "with_context", 0)
	while (1) {
		if (nlen(n, "names")) ps_expect(",")
		if (ps_is("name")) {
			if (ps_from_context(n)) break
			k = ps_line()
			name = TK_V[ps_expect("name")]
			if (substr(name, 1, 1) == "_")
				rt_fail_at("TemplateAssertionError", "names starting with an underline can not be imported", PS_NAME, k)
			npush(n, "names", name)
			if (ps_skip_name("as")) npush(n, "aliases", TK_V[ps_expect("name")])
			else npush(n, "aliases", name)
			if (ps_from_context(n) || !ps_is(",")) break
		} else {
			ps_expect("name")
		}
	}
	return n
}

function ps_from_context(n) {
	if ((ps_isname("with") || ps_isname("without")) && ps_look_isname("context")) {
		nset(n, "with_context", ps_v() == "with")
		ps_next(); ps_next()
		return 1
	}
	return 0
}

function ps_signature(n,    a, line) {
	ps_expect("(")
	while (!ps_is(")")) {
		if (nlen(n, "args")) ps_expect(",")
		line = ps_line()
		a = TK_V[ps_expect("name")]
		if (ps_skip_if("=")) npush(n, "defaults", ps_expression(1))
		else if (nlen(n, "defaults")) ps_fail("non-default argument follows default argument")
		npush(n, "args", a)
	}
	ps_expect(")")
}

# remember which special names a macro body references
function ps_scan_begin() {
	PS_SCAN_DEPTH++
	PS_SC_CALLER[PS_SCAN_DEPTH] = PS_SEEN["caller"] + 0
	PS_SC_VARARGS[PS_SCAN_DEPTH] = PS_SEEN["varargs"] + 0
	PS_SC_KWARGS[PS_SCAN_DEPTH] = PS_SEEN["kwargs"] + 0
}
function ps_scan_end(n) {
	nset(n, "uses_caller", PS_SEEN["caller"] + 0 > PS_SC_CALLER[PS_SCAN_DEPTH])
	nset(n, "uses_varargs", PS_SEEN["varargs"] + 0 > PS_SC_VARARGS[PS_SCAN_DEPTH])
	nset(n, "uses_kwargs", PS_SEEN["kwargs"] + 0 > PS_SC_KWARGS[PS_SCAN_DEPTH])
	PS_SCAN_DEPTH--
}

function ps_callblock(    n, saved) {
	n = nd("callblock", ps_line())
	ps_next()
	if (ps_is("(")) ps_signature(n)
	nset(n, "call", ps_expression(1))
	if (NT[nget(n, "call")] != "call") ps_fail("expected call", NL[n])
	saved = PS_INLOOP
	PS_INLOOP = 0
	ps_scan_begin()
	nset(n, "body", ps_statements("name:endcall", 1))
	ps_scan_end(n)
	PS_INLOOP = saved
	NA[n] = "caller"
	return n
}

function ps_filterblock(    n) {
	n = nd("filterblock", ps_line())
	ps_next()
	nset(n, "filter", ps_filter(0, 1))
	nset(n, "body", ps_statements("name:endfilter", 1))
	return n
}

function ps_macro(    n, saved) {
	n = nd("macro", ps_line())
	ps_next()
	NA[n] = TK_V[ps_expect("name")]
	ps_signature(n)
	saved = PS_INLOOP
	PS_INLOOP = 0
	ps_scan_begin()
	nset(n, "body", ps_statements("name:endmacro", 1))
	ps_scan_end(n)
	PS_INLOOP = saved
	return n
}

function ps_print(    n, e) {
	n = nd("print", ps_line())
	ps_next()
	while (!ps_is("block_end")) {
		if (nlen(n, "nodes")) ps_expect(",")
		npush(n, "nodes", ps_expression(1))
	}
	return n
}

# with_tuple, name_only, extra_end_rules, with_namespace
function ps_assign_target(with_tuple, name_only, extra, with_ns,    t, line, a) {
	line = ps_line()
	if (with_ns && ps_look_t() == ".") {
		t = nd("nsref", line)
		NA[t] = TK_V[ps_expect("name")]
		ps_next()
		nset(t, "attr", TK_V[ps_expect("name")])
		return t
	}
	if (name_only) {
		t = nd("name", line)
		NA[t] = TK_V[ps_expect("name")]
		return t
	}
	if (with_tuple) t = ps_tuple(1, 1, extra, 0)
	else t = ps_primary()
	if (!ps_can_assign(t)) ps_fail("can't assign to " ps_nodename(t), NL[t])
	return t
}

function ps_can_assign(t,    i) {
	if (NT[t] == "name") return NA[t] !~ /^(true|false|none|True|False|None)$/
	if (NT[t] == "nsref") return 1
	if (NT[t] == "tuple") {
		for (i = 0; i < nlen(t, "items"); i++) if (!ps_can_assign(nat(t, "items", i))) return 0
		return 1
	}
	return 0
}

function ps_nodename(t) {
	if (NT[t] == "const") return "'const'"
	if (NT[t] == "getattr") return "'getattr'"
	if (NT[t] == "getitem") return "'getitem'"
	return "'" NT[t] "'"
}

# --------------------------------------------------------- expressions ----

function ps_expression(with_condexpr) {
	if (with_condexpr) return ps_condexpr()
	return ps_or()
}

function ps_condexpr(    e1, e2, e3, n, line, u0) {
	line = ps_line()
	u0 = PS_UNK_N
	e1 = ps_or()
	while (ps_skip_name("if")) {
		e2 = ps_or()
		e3 = 0
		if (ps_skip_name("else")) e3 = ps_condexpr()
		n = nd("condexpr", line)
		nset(n, "test", e2)
		nset(n, "expr1", e1)
		nset(n, "expr2", e3)
		e1 = n
		line = ps_line()
		PS_UNK_N = u0
	}
	return e1
}

function ps_binop(t, l, r, line,    n) {
	n = nd(t, line)
	nset(n, "left", l)
	nset(n, "right", r)
	return n
}

function ps_or(    l, line) {
	line = ps_line()
	l = ps_and()
	while (ps_skip_name("or")) { l = ps_binop("or", l, ps_and(), line); line = ps_line() }
	return l
}

function ps_and(    l, line) {
	line = ps_line()
	l = ps_not()
	while (ps_skip_name("and")) { l = ps_binop("and", l, ps_not(), line); line = ps_line() }
	return l
}

function ps_not(    n, line) {
	if (ps_isname("not")) {
		line = ps_line()
		ps_next()
		n = nd("not", line)
		nset(n, "node", ps_not())
		return n
	}
	return ps_compare()
}

function ps_compare(    e, n, line, t, op) {
	line = ps_line()
	e = ps_math1()
	n = 0
	while (1) {
		t = ps_t()
		if (t == "==" || t == "!=" || t == "<" || t == "<=" || t == ">" || t == ">=") {
			ps_next(); op = t
		} else if (ps_skip_name("in")) {
			op = "in"
		} else if (ps_isname("not") && ps_look_isname("in")) {
			ps_next(); ps_next(); op = "notin"
		} else break
		if (!n) { n = nd("compare", line); nset(n, "expr", e) }
		npush(n, "ops", op)
		npush(n, "operands", ps_math1())
		line = ps_line()
	}
	if (!n) return e
	NL[n] = line
	return n
}

function ps_math1(    l, line, t) {
	line = ps_line()
	l = ps_concat()
	while (ps_is("+") || ps_is("-")) {
		t = ps_is("+") ? "add" : "sub"
		ps_next()
		l = ps_binop(t, l, ps_concat(), line)
		line = ps_line()
	}
	return l
}

function ps_concat(    first, n, line) {
	line = ps_line()
	first = ps_math2()
	if (!ps_is("~")) return first
	n = nd("concat", line)
	npush(n, "items", first)
	while (ps_is("~")) {
		ps_next()
		npush(n, "items", ps_math2())
	}
	return n
}

function ps_math2(    l, line, t) {
	line = ps_line()
	l = ps_pow()
	while (ps_is("*") || ps_is("/") || ps_is("//") || ps_is("%")) {
		t = ps_t()
		t = t == "*" ? "mul" : (t == "/" ? "div" : (t == "//" ? "floordiv" : "mod"))
		ps_next()
		l = ps_binop(t, l, ps_pow(), line)
		line = ps_line()
	}
	return l
}

function ps_pow(    l, line) {
	line = ps_line()
	l = ps_unary(1)
	while (ps_is("**")) {
		ps_next()
		l = ps_binop("pow", l, ps_unary(1), line)
		line = ps_line()
	}
	return l
}

function ps_unary(with_filter,    n, line) {
	line = ps_line()
	if (ps_is("-")) {
		ps_next()
		n = nd("neg", line)
		nset(n, "node", ps_unary(0))
	} else if (ps_is("+")) {
		ps_next()
		n = nd("pos", line)
		nset(n, "node", ps_unary(0))
	} else {
		n = ps_primary()
	}
	n = ps_postfix(n)
	if (with_filter) n = ps_filter_expr(n)
	return n
}

function ps_const(v, line,    n) {
	n = nd("const", line)
	NA[n] = v
	return n
}

function ps_primary(    t, v, line, n, buf) {
	t = ps_t(); v = ps_v(); line = ps_line()
	if (t == "name") {
		ps_next()
		if (v == "true" || v == "True") return ps_const(V_TRUE, line)
		if (v == "false" || v == "False") return ps_const(V_FALSE, line)
		if (v == "none" || v == "None") return ps_const(V_NONE, line)
		n = nd("name", line)
		NA[n] = v
		PS_SEEN[v]++
		return n
	}
	if (t == "string") {
		buf = v
		ps_next()
		while (ps_is("string")) { buf = buf ps_v(); ps_next() }
		return ps_const(v_str(buf), line)
	}
	if (t == "integer") { ps_next(); return ps_const(v_new("int", v), line) }
	if (t == "float") { ps_next(); return ps_const(v_float(v), line) }
	if (t == "(") {
		ps_next()
		n = ps_tuple(0, 1, "", 1)
		ps_expect(")")
		return n
	}
	if (t == "[") return ps_list()
	if (t == "{") return ps_dict()
	ps_fail("unexpected '" ps_describe(t, v) "'", line)
}

function ps_is_tuple_end(extra) {
	if (ps_is("var_end") || ps_is("block_end") || ps_is(")")) return 1
	if (extra != "") return ps_test_any(extra)
	return 0
}

# simplified: primaries only; with_condexpr; extra end rules; explicit parens
function ps_tuple(simplified, with_condexpr, extra, explicit,    n, line, is_tuple, first, cnt, e) {
	line = ps_line()
	n = nd("tuple", line)
	is_tuple = 0
	cnt = 0
	while (1) {
		if (cnt) ps_expect(",")
		if (ps_is_tuple_end(extra)) break
		if (simplified) e = ps_primary()
		else e = ps_expression(with_condexpr)
		npush(n, "items", e)
		cnt++
		if (ps_is(",")) is_tuple = 1
		else break
		line = ps_line()
	}
	if (!is_tuple) {
		if (cnt) return nat(n, "items", 0)
		if (!explicit) ps_fail("Expected an expression, got '" ps_describe(ps_t(), ps_v()) "'")
	}
	return n
}

function ps_list(    n) {
	n = nd("list", ps_line())
	ps_expect("[")
	while (!ps_is("]")) {
		if (nlen(n, "items")) ps_expect(",")
		if (ps_is("]")) break
		npush(n, "items", ps_expression(1))
	}
	ps_expect("]")
	return n
}

function ps_dict(    n) {
	n = nd("dict", ps_line())
	ps_expect("{")
	while (!ps_is("}")) {
		if (nlen(n, "keys")) ps_expect(",")
		if (ps_is("}")) break
		npush(n, "keys", ps_expression(1))
		ps_expect(":")
		npush(n, "values", ps_expression(1))
	}
	ps_expect("}")
	return n
}

function ps_postfix(n) {
	while (1) {
		if (ps_is(".") || ps_is("[")) n = ps_subscript(n)
		else if (ps_is("(")) n = ps_call(n)
		else break
	}
	return n
}

function ps_filter_expr(n) {
	while (1) {
		if (ps_is("|")) n = ps_filter(n, 0)
		else if (ps_isname("is")) n = ps_test(n)
		else if (ps_is("(")) n = ps_call(n)
		else break
	}
	return n
}

function ps_subscript(node,    line, t, v, n, args, cnt, a) {
	line = ps_line()
	if (ps_is(".")) {
		ps_next()
		t = ps_t(); v = ps_v()
		ps_next()
		if (t == "name") {
			n = nd("getattr", line)
			nset(n, "node", node)
			NA[n] = v
			return n
		}
		if (t != "integer") ps_fail("expected name or number", TK_L[PS_P - 1])
		n = nd("getitem", line)
		nset(n, "node", node)
		nset(n, "arg", ps_const(v_new("int", v), line))
		return n
	}
	if (ps_is("[")) {
		ps_next()
		a = nd("tuple", line)
		while (!ps_is("]")) {
			if (nlen(a, "items")) ps_expect(",")
			npush(a, "items", ps_subscribed())
		}
		ps_expect("]")
		n = nd("getitem", line)
		nset(n, "node", node)
		nset(n, "arg", nlen(a, "items") == 1 ? nat(a, "items", 0) : a)
		return n
	}
	ps_fail("expected subscript expression", line)
}

function ps_subscribed(    line, n, s) {
	line = ps_line()
	s = nd("slice", line)
	if (ps_is(":")) {
		ps_next()
	} else {
		n = ps_expression(1)
		if (!ps_is(":")) return n
		ps_next()
		nset(s, "start", n)
	}
	if (ps_is(":")) {
		# no stop
	} else if (!ps_is("]") && !ps_is(",")) {
		nset(s, "stop", ps_expression(1))
	}
	if (ps_is(":")) {
		ps_next()
		if (!ps_is("]") && !ps_is(",")) nset(s, "step", ps_expression(1))
	}
	return s
}

# parse "(...)" call arguments into node n
function ps_call_args(n,    line, req, key) {
	line = ps_line()
	ps_expect("(")
	req = 0
	while (!ps_is(")")) {
		if (req) {
			ps_expect(",")
			if (ps_is(")")) break
		}
		if (ps_is("*")) {
			if (nget(n, "dyn_args") || nget(n, "dyn_kwargs")) ps_fail("invalid syntax for function call expression", line)
			ps_next()
			nset(n, "dyn_args", ps_expression(1))
		} else if (ps_is("**")) {
			if (nget(n, "dyn_kwargs")) ps_fail("invalid syntax for function call expression", line)
			ps_next()
			nset(n, "dyn_kwargs", ps_expression(1))
		} else if (ps_is("name") && ps_look_t() == "=") {
			if (nget(n, "dyn_kwargs")) ps_fail("invalid syntax for function call expression", line)
			key = ps_v()
			ps_next(); ps_next()
			npush(n, "kwnames", key)
			npush(n, "kwvalues", ps_expression(1))
		} else {
			if (nget(n, "dyn_args") || nget(n, "dyn_kwargs") || nlen(n, "kwnames"))
				ps_fail("invalid syntax for function call expression", line)
			npush(n, "args", ps_expression(1))
		}
		req = 1
	}
	ps_expect(")")
}

function ps_call(node,    n) {
	n = nd("call", ps_line())
	nset(n, "node", node)
	ps_call_args(n)
	return n
}

function ps_filter(node, start_inline,    n, name, line) {
	while (ps_is("|") || start_inline) {
		if (!start_inline) ps_next()
		line = ps_line()
		name = TK_V[ps_expect("name")]
		while (ps_is(".")) { ps_next(); name = name "." TK_V[ps_expect("name")] }
		if (!(name in F_KNOWN) && !PS_SOFT) ps_unknown("filter", name, line)
		n = nd("filter", line)
		NA[n] = name
		nset(n, "node", node)
		if (ps_is("(")) ps_call_args(n)
		node = n
		start_inline = 0
	}
	return node
}

function ps_test(node,    n, line, neg, name, t, a) {
	line = ps_line()
	ps_next()
	neg = 0
	if (ps_isname("not")) { ps_next(); neg = 1 }
	name = TK_V[ps_expect("name")]
	while (ps_is(".")) { ps_next(); name = name "." TK_V[ps_expect("name")] }
	if (!(name in T_KNOWN) && !PS_SOFT) ps_unknown("test", name, line)
	n = nd("test", line)
	NA[n] = name
	nset(n, "node", node)
	t = ps_t()
	if (t == "(") {
		ps_call_args(n)
	} else if ((t == "name" || t == "string" || t == "integer" || t == "float" || t == "[" || t == "{") &&
	           !ps_isname("else") && !ps_isname("or") && !ps_isname("and")) {
		if (ps_isname("is")) ps_fail("You cannot chain multiple tests with is")
		a = ps_postfix(ps_primary())
		npush(n, "args", a)
	}
	if (neg) {
		a = nd("not", line)
		nset(a, "node", n)
		return a
	}
	return n
}
