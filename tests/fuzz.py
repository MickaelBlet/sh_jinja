#!/usr/bin/env python3
"""Differential fuzzing: random templates rendered by Python Jinja2 and by
bin/jinja must give the same output (or the same exception class).

Usage: tests/fuzz.py [expr|ws] [SEED] [COUNT]
  expr  random expressions (operators, filters, tests, subscripts)
  ws    random whitespace / tag modifier mixes under trim/lstrip options
Set JINJA_AWK to select the awk implementation.
"""
import json
import os
import random
import re
import subprocess
import sys
import tempfile

import jinja2

JINJA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "jinja")

CTX = {"i": 7, "f": 2.5, "s": "Hello World", "l": [3, 1, 2], "d": {"b": 2, "a": 1},
       "n": None, "t": True, "e": "", "u": "héllo wörld", "neg": -4, "big": 12345}
ATOMS = ["i", "f", "s", "l", "d", "n", "t", "e", "u", "neg", "big", "1", "0", "-3", "2.0",
         "0.1", "'abc'", "'A b'", "[1, 2]", "(1,)", "{'x': 1}", "none", "true", "false",
         "''", "'%s|%d'", "'{}-{}'", "range(4)", "3.75", "1e3", "'10'", "'3.5'"]
FILTERS = ["upper", "lower", "title", "capitalize", "length", "string", "list", "first",
           "last", "reverse|list", "sort", "join(',')", "join", "abs", "int", "float",
           "round", "round(1)", "default('D')", "d('D', true)", "trim", "center(9)",
           "truncate(5, true, '', 0)", "wordcount", "e", "tojson", "sum", "max", "min",
           "unique|list", "batch(2)|list", "slice(2)|list", "replace('l', 'L')",
           "indent(2)", "format(1, 2)", "pprint", "urlencode", "dictsort",
           "select('odd')|list", "reject('odd')|list", "map('string')|list", "count",
           "striptags", "filesizeformat", "xmlattr", "string|length"]
TESTS = ["defined", "none", "number", "string", "odd", "even", "integer", "float",
         "sequence", "mapping", "iterable", "lower", "upper", "true", "false", "boolean",
         "divisibleby 2", "in [1, 2, 3]", "eq 7", "gt 2"]
OPS = ["+", "-", "*", "/", "//", "%", "~", "==", "!=", "<", ">=", "and", "or", "in",
       "not in", "**"]
PIECES = ["a", " ", "  ", "\n", "\n\n", "\t", "x y", " \n "]
WS_OPTS = [[], ["trim_blocks"], ["lstrip_blocks"], ["trim_blocks", "lstrip_blocks"],
           ["keep_trailing_newline"]]


def expr(depth=0):
    r = random.random()
    if depth > 2 or r < 0.3:
        return random.choice(ATOMS)
    if r < 0.55:
        return f"{expr(depth + 1)}|{random.choice(FILTERS)}"
    if r < 0.75:
        return f"({expr(depth + 1)} {random.choice(OPS)} {expr(depth + 1)})"
    if r < 0.85:
        neg = random.choice(["", "not "])
        return f"({expr(depth + 1)} is {neg}{random.choice(TESTS)})"
    if r < 0.92:
        return f"({expr(depth + 1)} if {expr(depth + 1)} else {expr(depth + 1)})"
    obj = random.choice(["l", "s", "u", "d", "[5, 6, 7]", "'xyz'"])
    return obj + "[" + random.choice(["0", "-1", "1:", "::-1", "'a'", "5", ":2"]) + "]"


def mod():
    return random.choice(["", "", "-", "+"])


def tag():
    r = random.random()
    if r < 0.25:
        return "{{" + random.choice(["", "-"]) + " 'v' " + random.choice(["", "-"]) + "}}"
    if r < 0.45:
        return "{#" + mod() + " c " + mod() + "#}"
    if r < 0.6:
        return ("{%" + mod() + " if true " + mod() + "%}" + body(1)
                + "{%" + mod() + " endif " + mod() + "%}")
    if r < 0.75:
        return ("{%" + mod() + " for i in [1, 2] " + mod() + "%}" + body(1)
                + "{{ i }}{%" + mod() + " endfor " + mod() + "%}")
    if r < 0.85:
        return ("{%" + mod() + " raw " + random.choice(["", "-"]) + "%}"
                + random.choice(PIECES) + "{{ x }}" + random.choice(PIECES)
                + "{%" + mod() + " endraw " + mod() + "%}")
    return "{%" + mod() + " set z = 1 " + mod() + "%}"


def body(depth=0):
    out = ""
    for _ in range(random.randint(1, 5)):
        out += random.choice(PIECES) if random.random() < 0.55 or depth > 1 else tag()
    return out


def main(argv):
    mode = argv[0] if argv else "expr"
    random.seed(int(argv[1]) if len(argv) > 1 else 1)
    count = int(argv[2]) if len(argv) > 2 else 300
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(CTX, f, ensure_ascii=False)
        ctx_file = f.name
    fails = 0
    try:
        for _ in range(count):
            opts = random.choice(WS_OPTS) if mode == "ws" else []
            src = body() if mode == "ws" else "{{ " + expr() + " }}"
            env = jinja2.Environment(
                trim_blocks="trim_blocks" in opts,
                lstrip_blocks="lstrip_blocks" in opts,
                keep_trailing_newline="keep_trailing_newline" in opts,
            )
            try:
                want = ("OK", env.from_string(src).render(CTX))
            except Exception as e:  # noqa: BLE001 - any template error is a result
                want = ("ERR", type(e).__name__)
            if "<built-in method" in want[1] or "object at 0x" in want[1]:
                continue
            args = [JINJA, "-d", ctx_file] + ["--" + o.replace("_", "-") for o in opts]
            p = subprocess.run(args + ["-s", src], capture_output=True, text=True)
            if p.returncode == 0:
                got = ("OK", p.stdout)
            else:
                m = re.search(r": (\w+): ", p.stderr)
                got = ("ERR", m.group(1) if m else p.stderr)
            if want != got:
                fails += 1
                print(f"MISMATCH {opts} {src!r}\n   py : {want!r}\n   awk: {got!r}")
    finally:
        os.unlink(ctx_file)
    print(f"{fails} mismatches / {count}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
