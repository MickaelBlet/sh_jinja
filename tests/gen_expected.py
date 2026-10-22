#!/usr/bin/env python3
"""Generate golden files for tests/cases with the reference Python Jinja2.

Each case directory contains:
  template.j2          main template (other templates may sit next to it)
  data.json|data.yaml  optional context
  opts                 optional, one option per line: trim_blocks,
                       lstrip_blocks, keep_trailing_newline, autoescape,
                       strict, ext=loopcontrols, ext=do
Writes `expected` (rendered output) or `expected_error` (exception class).

Usage: tests/gen_expected.py [CASE...]
"""
import json
import os
import sys

import jinja2
import yaml

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases")


def read_opts(path):
    opts = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                key, _, val = line.partition("=")
                opts.setdefault(key, []).append(val)
    return opts


def render(case_dir):
    opts = read_opts(os.path.join(case_dir, "opts"))
    exts = ["jinja2.ext." + e.split(".")[-1] for e in opts.get("ext", [])]
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(case_dir),
        trim_blocks="trim_blocks" in opts,
        lstrip_blocks="lstrip_blocks" in opts,
        keep_trailing_newline="keep_trailing_newline" in opts,
        autoescape="autoescape" in opts,
        undefined=jinja2.StrictUndefined if "strict" in opts else jinja2.Undefined,
        extensions=exts,
    )
    ctx = {}
    for name in ("data.json", "data.yaml"):
        path = os.path.join(case_dir, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                data = json.load(f) if name.endswith(".json") else yaml.safe_load(f)
            ctx.update(data or {})
    return env.get_template("template.j2").render(ctx)


def main(argv):
    cases = argv or sorted(os.listdir(ROOT))
    for case in cases:
        case_dir = os.path.join(ROOT, case)
        if not os.path.isdir(case_dir):
            continue
        out_path = os.path.join(case_dir, "expected")
        err_path = os.path.join(case_dir, "expected_error")
        try:
            out = render(case_dir)
        except Exception as e:  # noqa: BLE001 - any template error is a result
            for p in (out_path,):
                if os.path.exists(p):
                    os.remove(p)
            with open(err_path, "w", encoding="utf-8") as f:
                f.write(type(e).__name__ + "\n")
            print(f"{case}: {type(e).__name__}: {e}")
            continue
        if os.path.exists(err_path):
            os.remove(err_path)
        with open(out_path, "w", encoding="utf-8", newline="") as f:
            f.write(out)


if __name__ == "__main__":
    main(sys.argv[1:])
