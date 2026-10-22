# runtime.awk - AST evaluator: scopes, statements, loops, macros,
# include/import, template inheritance.
#
# Frames: FP[f] parent frame (0 = none), FV[f,name] value id,
#         FK[f,i] / FKN[f] own names in assignment order.
# Render contexts (one per template render: main, include, import):
#         RC_FRAME[c] top-level frame, CB[c,name,i] / CB_N[c,name] block chain.

# ------------------------------------------------------------- errors ----

function rt_fail_at(cls, msg, tname, line) {
	if (tname == "") tname = "<template>"
	printf "jinja: %s:%s: %s: %s\n", tname, line + 0, cls, msg > "/dev/stderr"
	close("/dev/stderr")
	RT_FAILED = 1
	exit 1
}

function rt_fail(cls, msg) { rt_fail_at(cls, msg, TPL_NAME[RT_TPL], RT_LINE) }

function rt_undef_fail(u) { rt_fail("UndefinedError", VV[u]) }

# -------------------------------------------------------------- buffers ----
# Output accumulation without quadratic copying: small appends go to a
# chunk, full chunks are kept apart and joined pairwise at the end.

function bf_new() {
	BF_C++
	BFS[BF_C] = ""
	BFN[BF_C] = 0
	return BF_C
}

function bf_add(b, s) {
	BFS[b] = BFS[b] s
	if (length(BFS[b]) > 4096) {
		BFP[b, BFN[b]++] = BFS[b]
		BFS[b] = ""
	}
}

function bf_get(b,    n, i, j, r) {
	if (!BFN[b]) { r = BFS[b]; delete BFS[b]; return r }
	BFP[b, BFN[b]++] = BFS[b]
	n = BFN[b]
	while (n > 1) {
		j = 0
		for (i = 0; i < n; i += 2) {
			BFP[b, j++] = (i + 1 < n) ? BFP[b, i] BFP[b, i + 1] : BFP[b, i]
		}
		for (i = j; i < n; i++) delete BFP[b, i]
		n = j
	}
	r = BFP[b, 0]
	delete BFP[b, 0]
	delete BFS[b]
	delete BFN[b]
	return r
}

# ---------------------------------------------------------- state stack ----
# Saved render state lives in global arrays instead of locals: mawk has a
# fixed evaluation stack (1024 slots) shared by all call frames.

function rt_push() {
	SV_N++
	SV_EXT[SV_N] = RT_TOPEXT
	SV_BRK[SV_N] = RT_BRK
	SV_TPL[SV_N] = RT_TPL
	SV_CTX[SV_N] = RT_CTX
}

function rt_pop() {
	RT_TOPEXT = SV_EXT[SV_N]
	RT_BRK = SV_BRK[SV_N]
	RT_TPL = SV_TPL[SV_N]
	RT_CTX = SV_CTX[SV_N]
	SV_N--
}

# --------------------------------------------------------------- frames ----

function rt_fnew(parent) {
	FR_N++
	FP[FR_N] = parent
	FKN[FR_N] = 0
	return FR_N
}

function rt_fset(f, name, v) {
	if (!((f, name) in FV)) FK[f, FKN[f]++] = name
	FV[f, name] = v
}

function rt_lookup(f, name,    g) {
	g = f
	while (g) {
		if ((g, name) in FV) return FV[g, name]
		g = FP[g]
	}
	if (name == "range" || name == "dict" || name == "lipsum" || name == "cycler" || name == "joiner" || name == "namespace")
		return v_new("func", name)
	if (name == "self") return v_new("self", RT_CTX)
	return v_undef("'" name "' is undefined")
}

# ---------------------------------------------------------- arg packs ----

function ap_new() {
	AP_C++
	APN[AP_C] = 0
	AKC[AP_C] = 0
	return AP_C
}
function ap_add(p, v) { AP[p, APN[p]++] = v }
function ap_kw(p, name, v) {
	if (!((p, name) in AKV)) AKN[p, AKC[p]++] = name
	AKV[p, name] = v
}
# argument i (0-based) given positionally or by name, else dflt
function ap_get(p, i, name, dflt) {
	if (name != "" && (p, name) in AKV) return AKV[p, name]
	if (i >= 0 && i < APN[p]) return AP[p, i]
	return dflt
}
function ap_has(p, i, name) {
	return (name != "" && (p, name) in AKV) || (i >= 0 && i < APN[p])
}

function rt_args(n, f,    p, i, d, v, items, k) {
	p = ap_new()
	for (i = 0; i < nlen(n, "args"); i++) ap_add(p, ev(nat(n, "args", i), f))
	if ((d = nget(n, "dyn_args"))) {
		items = rt_iterlist(ev(d, f))
		for (i = 0; i < VN[items]; i++) ap_add(p, VE[items, i])
	}
	for (i = 0; i < nlen(n, "kwnames"); i++) ap_kw(p, nat(n, "kwnames", i), ev(nat(n, "kwvalues", i), f))
	if ((d = nget(n, "dyn_kwargs"))) {
		v = ev(d, f)
		if (VT[v] != "dict") rt_fail("TypeError", "argument after ** must be a mapping, not " v_pytype(v))
		for (i = 0; i < VN[v]; i++) {
			k = VK[v, i]
			ap_kw(p, v_tostr(k), VD[v, v_hk(k)])
		}
	}
	return p
}

# ----------------------------------------------------------- templates ----

function io_read(path,    rs, r, c, k, st, first) {
	rs = RS
	RS = "\001"
	c = ""
	k = 0
	first = 1
	IO_OK = 0
	while ((st = (getline r < path)) > 0) {
		c = c "" (k++ ? "\001" : "") r
		first = 0
	}
	if (st == 0) IO_OK = 1
	close(path)
	RS = rs
	return c
}

# load a template by name through the search path; 0 when not found
function rt_load(name,    t, i, path, src, parts, n, clean, j) {
	if (name in TPL_BYNAME) return TPL_BYNAME[name]
	n = split(name, parts, "/")
	clean = ""
	for (j = 1; j <= n; j++) {
		if (parts[j] == ".." ) return 0
		if (parts[j] == "" || parts[j] == ".") continue
		clean = clean "" (clean == "" ? "" : "/") parts[j]
	}
	if (clean == "") return 0
	for (i = 1; i <= SP_N; i++) {
		path = SP[i] "/" clean
		src = io_read(path)
		if (IO_OK) break
	}
	if (!IO_OK) return 0
	return rt_compile(name, src)
}

function rt_compile(name, src,    t) {
	t = ++TPL_N
	TPL_NAME[t] = name
	TPL_BYNAME[name] = t
	PS_TPL = t
	lx_tokenize(src, name)
	TPL_ROOT[t] = ps_parse(name)
	return t
}

# template value (name, list of names) -> template id, or 0 if ignore_missing
function rt_get_template(tv, ignore_missing,    t, items, i, names) {
	if (VT[tv] == "undef") rt_undef_fail(tv)
	if (VT[tv] == "list" || VT[tv] == "tuple") {
		names = ""
		for (i = 0; i < VN[tv]; i++) {
			t = rt_load(v_tostr(VE[tv, i]))
			if (t) return t
			names = names "" (i ? ", " : "") v_repr(VE[tv, i])
		}
		if (ignore_missing) return 0
		rt_fail("TemplatesNotFound", "none of the templates given were found: [" names "]")
	}
	t = rt_load(v_tostr(tv))
	if (!t && !ignore_missing) rt_fail("TemplateNotFound", v_tostr(tv))
	return t
}

function rt_newctx(frame) {
	RC_N++
	RC_FRAME[RC_N] = frame
	return RC_N
}

# register blocks of tpl in ctx (child first, parents appended)
function rt_regblocks(tpl, ctx,    k, parts, name) {
	for (k in TPL_BLK) {
		split(k, parts, SUBSEP)
		if (parts[1] != tpl) continue
		name = parts[2]
		CB[ctx, name, CB_N[ctx, name]++] = TPL_BLK[k]
	}
}

function rt_render_root(tpl, ctx,    body, buf, i, n) {
	rt_push()
	RT_TOPEXT = 0; RT_CTX = ctx; RT_TPL = tpl
	rt_regblocks(tpl, ctx)
	body = TPL_ROOT[tpl]
	buf = bf_new()
	n = nlen(body, "c")
	for (i = 0; i < n; i++) {
		RT_S = rt_stmt(nat(body, "c", i), RC_FRAME[ctx])
		if (!RT_TOPEXT) bf_add(buf, RT_S)
	}
	if (RT_TOPEXT) bf_add(buf, rt_render_root(RT_TOPEXT, ctx))
	rt_pop()
	return bf_get(buf)
}

# ---------------------------------------------------------- statements ----

function rt_body(b, f,    i, n, buf) {
	n = nlen(b, "c")
	if (n == 1) return rt_stmt(NX[b, "c", 0], f)
	buf = bf_new()
	for (i = 0; i < n; i++) {
		bf_add(buf, rt_stmt(NX[b, "c", i], f))
		if (RT_BRK) break
	}
	return bf_get(buf)
}

function rt_stmt(n, f,    t) {
	t = NT[n]
	RT_LINE = NL[n]
	if (t == "data") return NA[n]
	if (t == "emit") return rt_out(ev(NX[n, "expr"], f))
	if (t == "if") return rt_if(n, f)
	if (t == "for") return rt_for(n, f, rt_iterlist(ev(NX[n, "iter"], f)), 0)
	if (t == "set") {
		rt_assign(NX[n, "target"], ev(NX[n, "expr"], f), f)
		return ""
	}
	if (t == "setblock") return rt_setblock(n, f)
	if (t == "print") return rt_print(n, f)
	if (t == "with") return rt_with(n, f)
	if (t == "macro") {
		rt_fset(f, NA[n], rt_mkmacro(n, f))
		return ""
	}
	if (t == "callblock") return rt_callblock(n, f)
	if (t == "filterblock") return rt_filterblock(n, f)
	if (t == "block") return rt_block_stmt(n, f)
	if (t == "extends") {
		if (RT_TOPEXT) rt_fail("TemplateRuntimeError", "extended multiple times")
		RT_TOPEXT = rt_get_template(ev(NX[n, "template"], f), 0)
		return ""
	}
	if (t == "include") return rt_include(n, f)
	if (t == "import") {
		rt_fset(f, NA[n], rt_import(ev(NX[n, "template"], f), nget(n, "with_context"), f))
		return ""
	}
	if (t == "fromimport") return rt_fromimport(n, f)
	if (t == "autoescape") return rt_autoescape(n, f)
	if (t == "break") { RT_BRK = 1; return "" }
	if (t == "continue") { RT_BRK = 2; return "" }
	if (t == "do") { ev(NX[n, "expr"], f); return "" }
	rt_fail("RuntimeError", "unknown node " t)
}

function rt_if(n, f,    e) {
	while (n) {
		RT_LINE = NL[n]
		if (v_truth(ev(NX[n, "test"], f))) {
			e = NX[n, "body"]
			return NC[e, "c"] == 1 ? rt_stmt(NX[e, "c", 0], f) : rt_body(e, f)
		}
		if ((e = nget(n, "elif"))) { n = e; continue }
		if ((e = nget(n, "else"))) return NC[e, "c"] == 1 ? rt_stmt(NX[e, "c", 0], f) : rt_body(e, f)
		return ""
	}
	return ""
}

function rt_setblock(n, f,    nf, v) {
	nf = rt_fnew(f)
	v = rt_body(NX[n, "body"], nf)
	v = AUTOESC ? v_markup(v) : v_str(v)
	v = rt_applyfilters(nget(n, "filter"), v, f)
	rt_assign(NX[n, "target"], v, f)
	return ""
}

function rt_print(n, f,    s, i) {
	s = ""
	for (i = 0; i < nlen(n, "nodes"); i++) s = s rt_out(ev(nat(n, "nodes", i), f))
	return s
}

function rt_with(n, f,    nf, i) {
	nf = rt_fnew(f)
	for (i = 0; i < nlen(n, "targets"); i++)
		rt_assign(nat(n, "targets", i), ev(nat(n, "values", i), f), nf)
	return rt_body(NX[n, "body"], nf)
}

function rt_filterblock(n, f,    v) {
	v = rt_body(NX[n, "body"], rt_fnew(f))
	v = AUTOESC ? v_markup(v) : v_str(v)
	return rt_out(rt_applyfilters(NX[n, "filter"], v, f))
}

function rt_autoescape(n, f,    x, s) {
	x = AUTOESC
	AUTOESC = v_truth(ev(NX[n, "expr"], f))
	s = rt_body(NX[n, "body"], f)
	AUTOESC = x
	return s
}

function rt_out(v) {
	if (AUTOESC && !VM[v]) return f_escape_str(v_tostr(v))
	return v_tostr(v)
}

function rt_assign(t, v, f,    items, n, i, ns) {
	if (NT[t] == "name") { rt_fset(f, NA[t], v); return }
	if (NT[t] == "tuple") {
		items = rt_iterlist(v)
		n = nlen(t, "items")
		if (VN[items] < n) rt_fail("ValueError", "not enough values to unpack (expected " n ", got " VN[items] ")")
		if (VN[items] > n) rt_fail("ValueError", "too many values to unpack (expected " n ")")
		for (i = 0; i < n; i++) rt_assign(nat(t, "items", i), VE[items, i], f)
		return
	}
	if (NT[t] == "nsref") {
		ns = rt_lookup(f, NA[t])
		if (VT[ns] != "ns") rt_fail("TemplateRuntimeError", "cannot assign attribute on non-namespace object")
		v_dsets(ns, nget(t, "attr"), v)
		return
	}
	rt_fail("TemplateRuntimeError", "can't assign")
}

function rt_applyfilters(fn, v, f,    inner) {
	if (!fn) return v
	inner = nget(fn, "node")
	if (inner) v = rt_applyfilters(inner, v, f)
	RT_LINE = NL[fn]
	return f_call(NA[fn], v, rt_args(fn, f))
}

# -------------------------------------------------------------- loops ----

# value -> list id to iterate
function rt_iterlist(v,    t, r, i, n, arr) {
	t = VT[v]
	if (t == "list" || t == "tuple") return v
	if (t == "dict" || t == "ns") {
		r = v_list()
		for (i = 0; i < VN[v]; i++) VE[r, i] = VK[v, i]
		VN[r] = VN[v]
		return r
	}
	if (t == "str") {
		r = v_list()
		n = u8_chars(VV[v], arr)
		for (i = 1; i <= n; i++) v_push(r, v_str(arr[i]))
		return r
	}
	if (t == "undef") {
		if (STRICT) rt_undef_fail(v)
		return v_list()
	}
	if (t == "module") return v_list()
	rt_fail("TypeError", "'" v_pytype(v) "' object is not iterable")
}

function rt_for(n, f, items, depth,    lp, i, buf, fi) {
	if (nget(n, "test")) items = rt_for_filter(n, f, items)
	if (VN[items] == 0) {
		if (nget(n, "else")) return rt_body(NX[n, "else"], f)
		return ""
	}
	lp = ++LP_C
	LP_ITEMS[lp] = items
	LP_LEN[lp] = VN[items]
	LP_DEPTH[lp] = depth
	LP_NODE[lp] = n
	LP_FRAME[lp] = f
	LP_CHG[lp] = 0
	LP_VAL[lp] = v_new("loop", lp)
	LP_BODY[lp] = NX[n, "body"]
	buf = bf_new()
	for (i = 0; i < LP_LEN[lp]; i++) {
		LP_I[lp] = i
		fi = rt_fnew(f)
		rt_fset(fi, "loop", LP_VAL[lp])
		rt_assign(NX[n, "target"], VE[items, i], fi)
		bf_add(buf, NC[LP_BODY[lp], "c"] == 1 ? rt_stmt(NX[LP_BODY[lp], "c", 0], fi) : rt_body(LP_BODY[lp], fi))
		if (RT_BRK == 1) { RT_BRK = 0; break }
		RT_BRK = 0
	}
	return bf_get(buf)
}

function rt_for_filter(n, f, items,    fl, i, tf) {
	fl = v_list()
	for (i = 0; i < VN[items]; i++) {
		tf = rt_fnew(f)
		rt_assign(NX[n, "target"], VE[items, i], tf)
		if (v_truth(ev(NX[n, "test"], tf))) v_push(fl, VE[items, i])
	}
	return fl
}

function rt_loop_attr(lv, name,    lp, i) {
	lp = VV[lv]
	i = LP_I[lp]
	if (name == "index") return v_int(i + 1)
	if (name == "index0") return v_int(i)
	if (name == "revindex") return v_int(LP_LEN[lp] - i)
	if (name == "revindex0") return v_int(LP_LEN[lp] - i - 1)
	if (name == "first") return v_bool(i == 0)
	if (name == "last") return v_bool(i == LP_LEN[lp] - 1)
	if (name == "length") return v_int(LP_LEN[lp])
	if (name == "depth") return v_int(LP_DEPTH[lp] + 1)
	if (name == "depth0") return v_int(LP_DEPTH[lp])
	if (name == "previtem") return i > 0 ? VE[LP_ITEMS[lp], i - 1] : v_undef("there is no previous item")
	if (name == "nextitem") return i < LP_LEN[lp] - 1 ? VE[LP_ITEMS[lp], i + 1] : v_undef("there is no next item")
	if (name == "cycle" || name == "changed") return rt_meth(lv, name)
	return 0
}

function rt_loop_call(lv, p,    lp, r) {
	lp = VV[lv]
	if (!NA[LP_NODE[lp]]) rt_fail("TypeError", "The loop must have the 'recursive' marker to be called recursively.")
	r = rt_for(LP_NODE[lp], LP_FRAME[lp], rt_iterlist(ap_get(p, 0, "", V_NONE)), LP_DEPTH[lp] + 1)
	return AUTOESC ? v_markup(r) : v_str(r)
}

# -------------------------------------------------------------- macros ----

function rt_mkmacro(n, f,    m) {
	m = v_new("macro", n)
	MACRO_FRAME[m] = f
	MACRO_NAME[m] = NA[n]
	MACRO_TPL[m] = RT_TPL
	MACRO_CTX[m] = RT_CTX
	return m
}

function rt_call_macro(m, p,    mf, s) {
	mf = rt_macro_bind(m, p)
	rt_push()
	RT_TOPEXT = 0; RT_BRK = 0; RT_TPL = MACRO_TPL[m]; RT_CTX = MACRO_CTX[m]
	s = NX[VV[m], "body"]
	s = NC[s, "c"] == 1 ? rt_stmt(NX[s, "c", 0], mf) : rt_body(s, mf)
	rt_pop()
	return AUTOESC ? v_markup(s) : v_str(s)
}

function rt_macro_bind(m, p,    n, mf, nargs, ndef, i, an, v, va, kw, k, name, off, used) {
	n = VV[m]
	name = MACRO_NAME[m]
	mf = rt_fnew(MACRO_FRAME[m])
	nargs = nlen(n, "args")
	ndef = nlen(n, "defaults")
	off = APN[p] < nargs ? APN[p] : nargs
	for (i = 0; i < nargs; i++) {
		an = nat(n, "args", i)
		if (i < off) {
			v = AP[p, i]
		} else if ((p, an) in AKV) {
			v = AKV[p, an]
			used[an] = 1
		} else if (i >= nargs - ndef) {
			v = 0
		} else {
			v = v_undef("parameter '" an "' was not provided")
		}
		if (v) rt_fset(mf, an, v)
		else rt_fset(mf, an, ev(nat(n, "defaults", i - (nargs - ndef)), mf))
	}
	if (nget(n, "uses_caller")) {
		if ((p, "caller") in AKV) { rt_fset(mf, "caller", AKV[p, "caller"]); used["caller"] = 1 }
		else rt_fset(mf, "caller", v_undef("No caller defined"))
	}
	if (nget(n, "uses_kwargs")) {
		kw = v_dict()
		for (i = 0; i < AKC[p]; i++) {
			k = AKN[p, i]
			if (!(k in used)) v_dsets(kw, k, AKV[p, k])
		}
		rt_fset(mf, "kwargs", kw)
	} else {
		for (i = 0; i < AKC[p]; i++) {
			k = AKN[p, i]
			if (k in used) continue
			if (k == "caller") rt_fail("TypeError", "macro '" name "' was invoked with two values for the special caller argument. This is most likely a bug.")
			rt_fail("TypeError", "macro '" name "' takes no keyword argument '" k "'")
		}
	}
	if (nget(n, "uses_varargs")) {
		va = v_tuple()
		for (i = nargs; i < APN[p]; i++) v_push(va, AP[p, i])
		rt_fset(mf, "varargs", va)
	} else if (APN[p] > nargs) {
		rt_fail("TypeError", "macro '" name "' takes not more than " nargs " argument(s)")
	}
	return mf
}

function rt_macro_attr(m, name,    n, r, i) {
	n = VV[m]
	if (name == "name") return v_str(MACRO_NAME[m])
	if (name == "arguments") {
		r = v_tuple()
		for (i = 0; i < nlen(n, "args"); i++) v_push(r, v_str(nat(n, "args", i)))
		return r
	}
	if (name == "catch_kwargs") return v_bool(nget(n, "uses_kwargs"))
	if (name == "catch_varargs") return v_bool(nget(n, "uses_varargs"))
	if (name == "caller") return v_bool(nget(n, "uses_caller"))
	return 0
}

function rt_callblock(n, f,    caller, call, fn, p) {
	caller = rt_mkmacro(n, f)
	call = nget(n, "call")
	fn = ev(nget(call, "node"), f)
	p = rt_args(call, f)
	ap_kw(p, "caller", caller)
	RT_LINE = NL[n]
	return rt_out(rt_call(fn, p))
}

# ----------------------------------------------------------- blocks ----

function rt_block_stmt(n, f,    ctx) {
	if (RT_TOPEXT) return ""
	ctx = RT_CTX
	return rt_render_block(ctx, NA[n], 0, nget(n, "scoped") ? f : RC_FRAME[ctx])
}

function rt_render_block(ctx, name, lvl, pf,    node, bf, s, sup) {
	node = CB[ctx, name, lvl]
	if (nget(node, "required") && CB_N[ctx, name] <= 1)
		rt_fail("TemplateRuntimeError", "Required block '" name "' not found")
	bf = rt_fnew(pf)
	sup = v_new("func", "super")
	SUP_CTX[sup] = ctx; SUP_NAME[sup] = name; SUP_LVL[sup] = lvl + 1; SUP_FRAME[sup] = pf
	rt_fset(bf, "super", sup)
	rt_push()
	RT_TOPEXT = 0
	s = rt_body(NX[node, "body"], bf)
	rt_pop()
	return s
}

function rt_super(sup,    ctx, name, lvl, s) {
	ctx = SUP_CTX[sup]; name = SUP_NAME[sup]; lvl = SUP_LVL[sup]
	if (lvl >= CB_N[ctx, name]) rt_fail("UndefinedError", "there is no parent block called '" name "'.")
	s = rt_render_block(ctx, name, lvl, SUP_FRAME[sup])
	return AUTOESC ? v_markup(s) : v_str(s)
}

# -------------------------------------------------- include / import ----

function rt_include(n, f,    tpl, ctx) {
	tpl = rt_get_template(ev(nget(n, "template"), f), nget(n, "ignore_missing"))
	if (!tpl) return ""
	ctx = rt_newctx(rt_fnew(nget(n, "with_context") ? f : 0))
	return rt_render_root(tpl, ctx)
}

function rt_import(tv, with_ctx, f,    tpl, ctx, fr, m, key) {
	tpl = rt_get_template(tv, 0)
	key = tpl
	if (!with_ctx && (key in MOD_CACHE)) return MOD_CACHE[key]
	fr = rt_fnew(with_ctx ? f : 0)
	ctx = rt_newctx(fr)
	m = v_new("module", TPL_NAME[tpl])
	MOD_FRAME[m] = fr
	MOD_BODY[m] = rt_render_root(tpl, ctx)
	if (!with_ctx) MOD_CACHE[key] = m
	return m
}

function rt_module_attr(m, name,    fr) {
	fr = MOD_FRAME[m]
	if (substr(name, 1, 1) != "_" && (fr, name) in FV) return FV[fr, name]
	return 0
}

function rt_fromimport(n, f,    m, i, name, v) {
	m = rt_import(ev(nget(n, "template"), f), nget(n, "with_context"), f)
	for (i = 0; i < nlen(n, "names"); i++) {
		name = nat(n, "names", i)
		v = rt_module_attr(m, name)
		if (!v) v = v_undef("the template '" VV[m] "' (imported on line " NL[n] ") does not export the requested name '" name "'")
		rt_fset(f, nat(n, "aliases", i), v)
	}
	return ""
}

# --------------------------------------------------------- expressions ----

function ev(n, f,    t) {
	t = NT[n]
	RT_LINE = NL[n]
	if (t == "const") return NA[n]
	if (t == "name") return rt_lookup(f, NA[n])
	if (t == "getattr") return rt_getattr(ev(NX[n, "node"], f), NA[n])
	if (t == "getitem") return ev_getitem(n, f)
	if (t == "call") return ev_call(n, f)
	if (t == "filter") return ev_filter(n, f)
	if (t == "test") return v_bool(ev_test(n, f))
	if (t == "compare") return ev_compare(n, f)
	if (t == "or") return ev_or(n, f)
	if (t == "and") return ev_and(n, f)
	if (t == "not") return v_bool(!v_truth(ev(NX[n, "node"], f)))
	if (t == "condexpr") return ev_cond(n, f)
	if (t == "add" || t == "sub" || t == "mul" || t == "div" || t == "floordiv" || t == "mod" || t == "pow") return ev_arith(n, f, t)
	if (t == "concat") return ev_concat(n, f)
	if (t == "tuple" || t == "list") return ev_seq(n, f, t)
	if (t == "dict") return ev_dict(n, f)
	if (t == "neg" || t == "pos") return ev_unary(n, f, t)
	rt_fail("RuntimeError", "cannot evaluate node " t)
}

function ev_getitem(n, f,    v, a) {
	v = ev(NX[n, "node"], f)
	a = NX[n, "arg"]
	if (NT[a] == "slice") return rt_slice(v, a, f)
	return rt_getitem(v, ev(a, f))
}

function ev_call(n, f,    v, a) {
	v = ev(NX[n, "node"], f)
	a = rt_args(n, f)
	RT_LINE = NL[n]
	return rt_call(v, a)
}

function ev_filter(n, f,    v, a) {
	v = ev(NX[n, "node"], f)
	a = rt_args(n, f)
	RT_LINE = NL[n]
	return f_call(NA[n], v, a)
}

function ev_test(n, f,    v, a) {
	v = ev(NX[n, "node"], f)
	a = rt_args(n, f)
	RT_LINE = NL[n]
	return t_call(NA[n], v, a)
}

function ev_compare(n, f,    a, b, i) {
	a = ev(NX[n, "expr"], f)
	for (i = 0; i < NC[n, "ops"]; i++) {
		b = ev(NX[n, "operands", i], f)
		RT_LINE = NL[n]
		if (!rt_compare(NX[n, "ops", i], a, b)) return V_FALSE
		a = b
	}
	return V_TRUE
}

function ev_or(n, f,    l) {
	l = ev(NX[n, "left"], f)
	if (v_truth(l)) return l
	return ev(NX[n, "right"], f)
}

function ev_and(n, f,    l) {
	l = ev(NX[n, "left"], f)
	if (!v_truth(l)) return l
	return ev(NX[n, "right"], f)
}

function ev_cond(n, f) {
	if (v_truth(ev(NX[n, "test"], f))) return ev(NX[n, "expr1"], f)
	if (nget(n, "expr2")) return ev(NX[n, "expr2"], f)
	return v_undef("the inline if-expression on line " NL[n] " evaluated to false and no else section was defined.")
}

function ev_arith(n, f, t,    l, r) {
	l = ev(NX[n, "left"], f)
	r = ev(NX[n, "right"], f)
	RT_LINE = NL[n]
	return rt_arith(t, l, r)
}

function ev_concat(n, f,    l, i, s, mk, v) {
	l = v_list()
	mk = 0
	for (i = 0; i < NC[n, "items"]; i++) {
		v = ev(NX[n, "items", i], f)
		v_push(l, v)
		if (VM[v]) mk = 1
	}
	s = ""
	if (AUTOESC && mk) {
		for (i = 0; i < VN[l]; i++) s = s rt_out(VE[l, i])
		return v_markup(s)
	}
	for (i = 0; i < VN[l]; i++) s = s v_tostr(VE[l, i])
	return v_str(s)
}

function ev_seq(n, f, t,    r, i) {
	r = (t == "tuple") ? v_tuple() : v_list()
	for (i = 0; i < NC[n, "items"]; i++) v_push(r, ev(NX[n, "items", i], f))
	return r
}

function ev_dict(n, f,    r, i) {
	r = v_dict()
	for (i = 0; i < NC[n, "keys"]; i++) v_dset(r, ev(NX[n, "keys", i], f), ev(NX[n, "values", i], f))
	return r
}

function ev_unary(n, f, t,    v) {
	v = ev(NX[n, "node"], f)
	if (VT[v] == "undef") rt_undef_fail(v)
	if (!v_isnum(v)) rt_fail("TypeError", "bad operand type for unary " (t == "neg" ? "-" : "+") ": '" v_pytype(v) "'")
	if (t == "pos") return VT[v] == "bool" ? v_int(VV[v]) : v
	if (VT[v] == "float") return v_float(-VV[v])
	return v_int(-VV[v])
}

function rt_compare(op, a, b,    c) {
	if (op == "==") { rt_strict_chk(a, b); return v_eq(a, b) }
	if (op == "!=") { rt_strict_chk(a, b); return !v_eq(a, b) }
	if (op == "in") return rt_contains(b, a)
	if (op == "notin") return !rt_contains(b, a)
	if (VT[a] == "undef" || VT[b] == "undef") rt_undef_fail(VT[a] == "undef" ? a : b)
	c = v_cmp(a, b, op)
	if (op == "<") return c < 0
	if (op == "<=") return c <= 0
	if (op == ">") return c > 0
	if (op == ">=") return c >= 0
}

function rt_strict_chk(a, b) {
	if (!STRICT) return
	if (VT[a] == "undef") rt_undef_fail(a)
	if (VT[b] == "undef") rt_undef_fail(b)
}

function rt_contains(c, x,    t, i) {
	t = VT[c]
	if (t == "str") {
		if (VT[x] != "str") rt_fail("TypeError", "'in <string>' requires string as left operand, not " v_pytype(x))
		return VV[x] == "" || index(VV[c], VV[x]) > 0
	}
	if (t == "list" || t == "tuple") {
		for (i = 0; i < VN[c]; i++) if (v_eq(VE[c, i], x)) return 1
		return 0
	}
	if (t == "dict" || t == "ns") return v_dhas(c, x)
	if (t == "undef") { if (STRICT) rt_undef_fail(c); return 0 }
	rt_fail("TypeError", "argument of type '" v_pytype(c) "' is not iterable")
}

function rt_isint(v) { return VT[v] == "int" || VT[v] == "bool" }

function rt_arith(op, a, b,    ta, tb, x, y, r, sym, n, i, s) {
	ta = VT[a]; tb = VT[b]
	if (ta == "undef") rt_undef_fail(a)
	if (tb == "undef" && !(op == "mod" && ta == "str")) rt_undef_fail(b)
	sym = op == "add" ? "+" : op == "sub" ? "-" : op == "mul" ? "*" : op == "div" ? "/" : op == "floordiv" ? "//" : op == "mod" ? "%" : "** or pow()"
	if (v_isnum(a) && v_isnum(b)) {
		x = VV[a] * 1; y = VV[b] * 1
		if (op == "add") r = x + y
		else if (op == "sub") r = x - y
		else if (op == "mul") r = x * y
		else if (op == "div") {
			if (y == 0) rt_fail("ZeroDivisionError", "division by zero")
			return v_float(x / y)
		} else if (op == "floordiv") {
			if (y == 0) rt_fail("ZeroDivisionError", rt_isint(a) && rt_isint(b) ? "integer division or modulo by zero" : "float divmod()")
			r = m_floor(x / y)
		} else if (op == "mod") {
			if (y == 0) rt_fail("ZeroDivisionError", rt_isint(a) && rt_isint(b) ? "integer division or modulo by zero" : "float modulo")
			r = x % y
			if (r != 0 && ((r < 0) != (y < 0))) r += y
		} else {
			if (x == 0 && y < 0) rt_fail("ZeroDivisionError", "0.0 cannot be raised to a negative power")
			r = m_pow(x, y)
			if (rt_isint(a) && rt_isint(b) && y >= 0) return v_int(r)
			return v_float(r)
		}
		if (rt_isint(a) && rt_isint(b)) return v_int(r)
		return v_float(r)
	}
	if (op == "add") {
		if (ta == "str" && tb == "str") {
			if (VM[a] || VM[b]) return v_markup((VM[a] ? VV[a] : f_escape_str(VV[a])) (VM[b] ? VV[b] : f_escape_str(VV[b])))
			return v_str(VV[a] VV[b])
		}
		if ((ta == "list" && tb == "list") || (ta == "tuple" && tb == "tuple")) {
			r = v_lcopy(a, ta)
			for (i = 0; i < VN[b]; i++) v_push(r, VE[b, i])
			return r
		}
		if (ta == "str") rt_fail("TypeError", "can only concatenate str (not \"" v_pytype(b) "\") to str")
		if (ta == "list" || ta == "tuple") rt_fail("TypeError", "can only concatenate " ta " (not \"" v_pytype(b) "\") to " ta)
	}
	if (op == "mul") {
		if ((ta == "str" || ta == "list" || ta == "tuple") && rt_isint(b)) return rt_repeat(a, VV[b] + 0)
		if ((tb == "str" || tb == "list" || tb == "tuple") && rt_isint(a)) return rt_repeat(b, VV[a] + 0)
		if (ta == "str" || tb == "str" || ta == "list" || tb == "list" || ta == "tuple" || tb == "tuple")
			rt_fail("TypeError", "can't multiply sequence by non-int of type '" v_pytype(ta == "str" || ta == "list" || ta == "tuple" ? b : a) "'")
	}
	if (op == "mod" && ta == "str") return rt_pyformat(a, b)
	rt_fail("TypeError", "unsupported operand type(s) for " sym ": '" v_pytype(a) "' and '" v_pytype(b) "'")
}

function rt_repeat(v, n,    r, i, j) {
	if (VT[v] == "str") {
		r = v_str(v_rep(VV[v], n))
		if (VM[v]) VM[r] = 1
		return r
	}
	r = VT[v] == "tuple" ? v_tuple() : v_list()
	for (j = 0; j < n; j++) for (i = 0; i < VN[v]; i++) v_push(r, VE[v, i])
	return r
}

# ----------------------------------------------------- attribute access ----

function rt_meth(obj, name,    m) {
	m = v_new("meth", name)
	VO[m] = obj
	return m
}

function rt_objdesc(o,    t) {
	t = VT[o]
	if (t == "none") return "None"
	return v_pytype(o) " object"
}

function rt_getattr(o, name,    t, r) {
	t = VT[o]
	if (t == "undef") rt_undef_fail(o)
	if (t == "loop") { r = rt_loop_attr(o, name); if (r) return r }
	else if (t == "macro") { r = rt_macro_attr(o, name); if (r) return r }
	else if (t == "module") { r = rt_module_attr(o, name); if (r) return r }
	else if (t == "ns") { r = v_dgets(o, name); if (r) return r }
	else if (t == "self") return rt_meth(o, name)
	else {
		r = b_attr(o, name)
		if (r) return r
		if (t == "dict") { r = v_dgets(o, name); if (r) return r }
	}
	return v_undef("'" rt_objdesc(o) "' has no attribute '" name "'")
}

function rt_getitem(o, k,    t, r, i, n, arr) {
	t = VT[o]
	if (t == "undef") rt_undef_fail(o)
	if (t == "dict") {
		r = v_dget(o, k)
		if (r) return r
	} else if ((t == "list" || t == "tuple") && rt_isint(k)) {
		i = VV[k] + 0
		if (i < 0) i += VN[o]
		if (i >= 0 && i < VN[o]) return VE[o, i]
	} else if (t == "str" && rt_isint(k)) {
		i = VV[k] + 0
		n = u8_chars(VV[o], arr)
		if (i < 0) i += n
		if (i >= 0 && i < n) return v_str(arr[i + 1])
	} else if (t == "ns" || t == "module" || t == "loop") {
		if (VT[k] == "str") return rt_getattr(o, VV[k])
	}
	if (VT[k] == "str") {
		if (t == "dict") { r = b_attr(o, VV[k]); if (r) return r }
		else if (t != "ns" && t != "module" && t != "loop") return rt_getattr(o, VV[k])
		return v_undef("'" rt_objdesc(o) "' has no attribute '" VV[k] "'")
	}
	return v_undef(rt_objdesc(o) " has no element " v_repr(k))
}

# Python slice indices for length n -> SL_START, SL_STOP, SL_STEP
function rt_slice_idx(n, a, f,    s, e, st, x) {
	st = 1
	if ((x = nget(a, "step"))) {
		x = ev(x, f)
		if (VT[x] != "none") st = VV[x] + 0
	}
	if (st == 0) rt_fail("ValueError", "slice step cannot be zero")
	s = st > 0 ? 0 : n - 1
	e = st > 0 ? n : -1
	if ((x = nget(a, "start"))) {
		x = ev(x, f)
		if (VT[x] != "none") {
			s = VV[x] + 0
			if (s < 0) { s += n; if (s < 0) s = st > 0 ? 0 : -1 }
			else if (s >= n) s = st > 0 ? n : n - 1
		}
	}
	if ((x = nget(a, "stop"))) {
		x = ev(x, f)
		if (VT[x] != "none") {
			e = VV[x] + 0
			if (e < 0) { e += n; if (e < 0) e = st > 0 ? 0 : -1 }
			else if (e >= n) e = st > 0 ? n : n - 1
		}
	}
	SL_START = s; SL_STOP = e; SL_STEP = st
}

function rt_slice(o, a, f,    t, n, arr, r, i, s) {
	t = VT[o]
	if (t == "undef") rt_undef_fail(o)
	if (t == "str") {
		n = u8_chars(VV[o], arr)
		rt_slice_idx(n, a, f)
		s = ""
		if (SL_STEP > 0) for (i = SL_START; i < SL_STOP; i += SL_STEP) s = s arr[i + 1]
		else for (i = SL_START; i > SL_STOP; i += SL_STEP) s = s arr[i + 1]
		r = v_str(s)
		return r
	}
	if (t == "list" || t == "tuple") {
		rt_slice_idx(VN[o], a, f)
		r = t == "tuple" ? v_tuple() : v_list()
		if (SL_STEP > 0) for (i = SL_START; i < SL_STOP; i += SL_STEP) v_push(r, VE[o, i])
		else for (i = SL_START; i > SL_STOP; i += SL_STEP) v_push(r, VE[o, i])
		return r
	}
	# slices bypass environment.getitem: plain Python subscript errors
	if (t == "dict") rt_fail("TypeError", "unhashable type: 'slice'")
	rt_fail("TypeError", "'" v_pytype(o) "' object is not subscriptable")
}

# --------------------------------------------------------------- calls ----

function rt_call(fn, p,    t) {
	t = VT[fn]
	if (t == "macro") return rt_call_macro(fn, p)
	if (t == "func") {
		if (VV[fn] == "super") return rt_super(fn)
		return b_global(VV[fn], p)
	}
	if (t == "meth") {
		if (VT[VO[fn]] == "self") return rt_self_block(VO[fn], VV[fn])
		return b_callmeth(VO[fn], VV[fn], p)
	}
	if (t == "loop") return rt_loop_call(fn, p)
	if (t == "joiner") return b_joiner_call(fn)
	if (t == "undef") rt_undef_fail(fn)
	rt_fail("TypeError", "'" v_pytype(fn) "' object is not callable")
}

function rt_self_block(sv, name,    ctx, s) {
	ctx = VV[sv]
	if (!CB_N[ctx, name]) rt_fail("UndefinedError", "'TemplateReference object' has no attribute '" name "'")
	s = rt_render_block(ctx, name, 0, RC_FRAME[ctx])
	return AUTOESC ? v_markup(s) : v_str(s)
}

# Python printf-style formatting: fmt % args
function rt_pyformat(fv, args,    fmt, out, k, spec, conv, flags, width, prec, ai, v, s, m, name, isdict, argl, mapish, x) {
	fmt = VV[fv]
	isdict = VT[args] == "dict"
	# Python skips the "not all arguments converted" check for mapping-like
	# args (anything with __getitem__ but tuple/str) and for Markup formats
	mapish = isdict || VT[args] == "list" || VT[args] == "ns" || VT[args] == "undef" || (VM[fv] && VT[args] != "tuple")
	if (VT[args] == "tuple") argl = args
	else { argl = v_tuple(); v_push(argl, args) }
	if (VM[fv]) {
		x = argl
		argl = v_tuple()
		for (k = 0; k < VN[x]; k++) v_push(argl, VM[VE[x, k]] || !(VT[VE[x, k]] == "str" || VT[VE[x, k]] == "list" || VT[VE[x, k]] == "tuple" || VT[VE[x, k]] == "dict") ? VE[x, k] : f_escape(VE[x, k]))
	}
	ai = 0
	out = ""
	while ((k = index(fmt, "%")) > 0) {
		out = out substr(fmt, 1, k - 1)
		fmt = substr(fmt, k + 1)
		if (substr(fmt, 1, 1) == "%") { out = out "%"; fmt = substr(fmt, 2); continue }
		name = ""
		if (substr(fmt, 1, 1) == "(") {
			m = index(fmt, ")")
			name = substr(fmt, 2, m - 2)
			fmt = substr(fmt, m + 1)
		}
		if (!match(fmt, /^[-+ #0]*[0-9*]*(\.[0-9*]+)?[hlL]?[diouxXeEfFgGcrsa]/))
			rt_fail("ValueError", "unsupported format character")
		spec = substr(fmt, 1, RLENGTH)
		fmt = substr(fmt, RLENGTH + 1)
		conv = substr(spec, length(spec))
		spec = substr(spec, 1, length(spec) - 1)
		gsub(/[hlL]/, "", spec)
		if (name != "") {
			if (!isdict) rt_fail("TypeError", "format requires a mapping")
			v = v_dgets(args, name)
			if (!v) rt_fail("KeyError", v_strrepr(name))
		} else if (isdict) {
			v = args
		} else {
			if (ai >= VN[argl]) rt_fail("TypeError", "not enough arguments for format string")
			v = VE[argl, ai++]
		}
		out = out rt_fmt1(spec, conv, v)
	}
	if (!mapish && ai < VN[argl]) rt_fail("TypeError", "not all arguments converted during string formatting")
	return VM[fv] ? v_markup(out fmt) : v_str(out fmt)
}

function rt_fmt1(spec, conv, v,    s, x) {
	if (conv == "s" || conv == "r" || conv == "a") {
		s = conv == "s" ? v_tostr(v) : v_repr(v)
		return sprintf("%" spec "s", s)
	}
	if (conv == "c") {
		if (VT[v] == "str") s = VV[v]
		else s = u8_enc(VV[v] + 0)
		return sprintf("%" spec "s", s)
	}
	if (!v_isnum(v)) rt_fail("TypeError", "%" conv " format: a number is required, not " v_pytype(v))
	x = VV[v] * 1
	if (conv == "d" || conv == "i" || conv == "u") {
		x = x < 0 ? -int(-x) : int(x)
		s = sprintf("%.0f", x < 0 ? -x : x)
		return rt_padnum(spec, s, x < 0)
	}
	if (conv == "x" || conv == "X" || conv == "o") {
		s = rt_tobase(x < 0 ? -int(-x) : int(x), conv == "o" ? 8 : 16)
		if (conv == "X") s = toupper(s)
		if (index(spec, "#")) s = (conv == "o" ? "0o" : (conv == "X" ? "0X" : "0x")) s
		return rt_padnum(spec, s, x < 0)
	}
	if (!index(spec, ".") && (conv == "f" || conv == "F" || conv == "e" || conv == "E" || conv == "g" || conv == "G")) spec = spec ".6"
	return sprintf("%" spec conv, x)
}

function rt_tobase(n, b,    s, d) {
	if (n < 0) n = -n
	if (n == 0) return "0"
	s = ""
	while (n > 0) { d = n % b; s = substr(HEXD, d + 1, 1) s; n = int(n / b) }
	return s
}

# apply flags/width to an unsigned digit string
function rt_padnum(spec, digits, neg,    w, sign, prec, s, pad) {
	sign = neg ? "-" : (index(spec, "+") ? "+" : (index(spec, " ") ? " " : ""))
	prec = ""
	if (match(spec, /\.[0-9]+/)) {
		prec = substr(spec, RSTART + 1, RLENGTH - 1) + 0
		while (length(digits) < prec) digits = "0" digits
	}
	w = spec
	sub(/\.[0-9]*/, "", w)
	gsub(/[-+ #0]/, "", w)
	w = w + 0
	s = sign digits
	if (length(s) >= w) return s
	if (index(spec, "-")) return s v_rep(" ", w - length(s))
	if (match(spec, /^[-+ #]*0/) && prec == "") return sign v_rep("0", w - length(s)) digits
	return v_rep(" ", w - length(s)) s
}
