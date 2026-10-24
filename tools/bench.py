#!/usr/bin/env python3
"""Benchmark sh_jinja against the reference Python Jinja2.

Each workload is generated in a temporary directory, rendered once by every
engine (outputs must match Python Jinja2), then timed:
  python         python3 process: import jinja2, load data, render
  sh_jinja/AWK   bin/jinja process with JINJA_AWK=AWK
  python-inproc  render in an already running Python, template cached

Usage: tools/bench.py [-r REPS] [-a AWK]... [-w WORKLOAD]... [-n SIZES]
                      [-b SECONDS] [--markdown]
"""
import argparse
import json
import os
import platform
import re
import shlex
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
JINJA = os.path.join(ROOT, "bin", "jinja")
AWKS = ["gawk", "mawk", "busybox awk", "original-awk"]

LOOP = """\
{% for u in users %}
{{ loop.index }}. {{ u.name|upper }} <{{ u.email }}>{% if u.active %} active{% else %} inactive{% endif %} {{ "%05d"|format(u.id) }} {{ u.tags|join(",") }}
{% endfor %}
"""
LOAD = "{{ users|length }} {{ users[-1].name }} {{ users[-1].tags|join(',') }}\n"
BASE = """\
<html><head><title>{% block title %}{% endblock %}</title></head>
<body>{% block body %}{% endblock %}</body></html>
"""
MACROS = """\
{% macro row(u, i) -%}
<tr class="{{ 'odd' if i is odd else 'even' }}"><td>{{ i }}</td><td>{{ u.name|e }}</td>{{ caller() }}</tr>
{%- endmacro %}
"""
CELL = "<td>{{ u.dept }}</td>"
PAGE = """\
{% extends "base.j2" %}
{% block title %}Users ({{ users|length }}){% endblock %}
{% block body %}{% import "macros.j2" as m %}<table>
{% for u in users %}{% call m.row(u, loop.index) %}{% include "cell.j2" %}{% endcall %}
{% endfor %}</table>{% endblock %}
"""
FILTERS = """\
{{ users|selectattr("active")|map(attribute="name")|join(", ") }}
{{ users|sort(attribute="score", reverse=true)|map(attribute="email")|first }}
{% for g in users|groupby("dept") %}{{ g.grouper }}: {{ g.list|length }} {{ g.list|sum(attribute="score") }}
{% endfor %}
{{ users|map(attribute="name")|join(" ")|replace("user", "U")|length }}
{{ users|rejectattr("active")|map(attribute="id")|unique|list|length }}
"""

# name -> (templates, data format, sized)
WORKLOADS = {
    "tiny": ({"main.j2": "Hello {{ name }}!\n"}, "json", False),
    "loop": ({"main.j2": LOOP}, "json", True),
    "json": ({"main.j2": LOAD}, "json", True),
    "yaml": ({"main.j2": LOAD}, "yaml", True),
    "inherit": ({"main.j2": PAGE, "base.j2": BASE, "macros.j2": MACROS, "cell.j2": CELL},
                "json", True),
    "filters": ({"main.j2": FILTERS}, "json", True),
}


def users(n):
    return [{"id": i, "name": f"user{i}", "email": f"user{i}@example.com",
             "active": i % 3 != 0, "tags": [f"t{i % 5}", "x"],
             "score": (i * 37) % 101, "dept": f"d{i % 7}"} for i in range(n)]


def load_data(path):
    with open(path, encoding="utf-8") as f:
        if path.endswith(".json"):
            return json.load(f)
        import yaml
        return yaml.safe_load(f)


def render_cmd(tdir, data):
    """--render mode: what a Python CLI does for one template."""
    import jinja2
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(tdir))
    sys.stdout.write(env.get_template("main.j2").render(load_data(data)))


def setup(base, name, n):
    templates, fmt, sized = WORKLOADS[name]
    d = os.path.join(base, f"{name}-{n}")
    os.makedirs(d)
    for fname, src in templates.items():
        with open(os.path.join(d, fname), "w", encoding="utf-8") as f:
            f.write(src)
    ctx = {"users": users(n)} if sized else {"name": "World"}
    data = os.path.join(d, "data." + fmt)
    with open(data, "w", encoding="utf-8") as f:
        if fmt == "json":
            json.dump(ctx, f)
        else:
            import yaml
            yaml.safe_dump(ctx, f, default_flow_style=False)
    return d, data


def time_reps(fn, reps, budget):
    """1 warmup, then up to `reps` timed runs within `budget` seconds."""
    t = time.perf_counter()
    fn()
    first = time.perf_counter() - t
    reps = max(1, min(reps, int(budget / max(first, 1e-9))))
    times = []
    for _ in range(reps):
        t = time.perf_counter()
        fn()
        times.append(time.perf_counter() - t)
    return statistics.median(times), min(times)


def available_awks(wanted):
    out = []
    for a in wanted:
        try:
            r = subprocess.run(shlex.split(a) + ["BEGIN{}"], stdin=subprocess.DEVNULL,
                               capture_output=True)
        except OSError:
            continue
        if r.returncode == 0:
            out.append(a)
    return out


def first_line(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    except OSError:
        return "?"
    return ((r.stdout or r.stderr).strip().splitlines() or ["?"])[0]


def awk_version(a):
    exe = shlex.split(a)[0]
    if exe == "busybox":
        return first_line(["busybox"])
    if exe == "mawk":
        return first_line(["mawk", "-W", "version"])
    return first_line([exe, "--version"])


def environment(awks):
    import jinja2
    cpu = platform.processor() or "?"
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            m = re.search(r"^model name\s*:\s*(.*)$", f.read(), re.M)
            cpu = m.group(1) if m else cpu
    except OSError:
        pass
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as f:
        m = re.search(r"^## \[(\d[^\]]*)\]", f.read(), re.M)
    lines = [f"- CPU: {cpu}", f"- OS: {platform.system()} {platform.release()}",
             f"- sh_jinja {m.group(1) if m else '?'}, /bin/sh = {os.path.realpath('/bin/sh')}",
             f"- Python {platform.python_version()}, Jinja2 {jinja2.__version__}"]
    lines += [f"- {a}: {awk_version(a)}" for a in awks]
    return "\n".join(lines)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--render":
        render_cmd(sys.argv[2], sys.argv[3])
        return 0
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("-r", "--reps", type=int, default=10, help="timed runs per cell (10)")
    p.add_argument("-a", "--awk", action="append", help="awk to test (repeatable)")
    p.add_argument("-w", "--workload", action="append", choices=list(WORKLOADS))
    p.add_argument("-n", "--sizes", default="100,1000,10000", help="item counts (100,1000,10000)")
    p.add_argument("-b", "--budget", type=float, default=20,
                   help="max seconds of timed runs per cell (20)")
    p.add_argument("--markdown", action="store_true", help="print a Markdown report")
    args = p.parse_args()

    import jinja2
    awks = available_awks(args.awk or AWKS)
    sizes = [int(s) for s in args.sizes.split(",")]
    engines = ["python"] + [f"sh_jinja/{a}" for a in awks] + ["python-inproc"]
    rows = []
    with tempfile.TemporaryDirectory() as base:
        for name in args.workload or list(WORKLOADS):
            for n in sizes if WORKLOADS[name][2] else [0]:
                d, data = setup(base, name, n)
                cmds = {"python": ([sys.executable, os.path.abspath(__file__), "--render", d, data],
                                   None)}
                for a in awks:
                    cmds[f"sh_jinja/{a}"] = ([JINJA, "-I", d, "-d", data, os.path.join(d, "main.j2")],
                                             dict(os.environ, JINJA_AWK=a))
                env = jinja2.Environment(loader=jinja2.FileSystemLoader(d))
                tpl = env.get_template("main.j2")
                want = tpl.render(load_data(data))
                row = {}
                for eng in engines:
                    if eng == "python-inproc":
                        row[eng] = time_reps(lambda: tpl.render(load_data(data)),
                                             args.reps, args.budget)
                        continue
                    cmd, cenv = cmds[eng]
                    r = subprocess.run(cmd, env=cenv, capture_output=True, text=True)
                    if r.returncode != 0 or r.stdout != want:
                        print(f"{name} {n} {eng}: output differs from Python Jinja2"
                              f" (rc={r.returncode}) {r.stderr.strip()}", file=sys.stderr)
                        row[eng] = None
                        continue
                    row[eng] = time_reps(
                        lambda: subprocess.run(cmd, env=cenv, stdout=subprocess.DEVNULL,
                                               check=True), args.reps, args.budget)
                label = f"{name} {n}" if n else name
                rows.append((label, row))
                if not args.markdown:
                    print_row(label, row, engines)
    if args.markdown:
        print(environment(awks) + "\n")
        print("Median wall time in ms (ratio to `python`).\n")
        print("| workload | " + " | ".join(f"`{e}`" for e in engines) + " |")
        print("| --- |" + " ---: |" * len(engines))
        for label, row in rows:
            print(f"| {label} | " + " | ".join(cell(row, e) for e in engines) + " |")
    return 0


def fmt_ms(sec):
    ms = sec * 1000
    return f"{ms:.0f}" if ms >= 100 else f"{ms:.1f}" if ms >= 1 else f"{ms:.2f}"


def cell(row, eng):
    v = row.get(eng)
    if v is None:
        return "fail"
    s = fmt_ms(v[0])
    py = row.get("python")
    if eng != "python" and py:
        s += f" (×{v[0] / py[0]:.2g})"
    return s


def print_row(label, row, engines):
    parts = []
    for eng in engines:
        v = row.get(eng)
        parts.append(f"{eng}=" + ("fail" if v is None else
                                  f"{fmt_ms(v[0])}/{fmt_ms(v[1])}ms"))
    print(f"{label:14} " + "  ".join(parts), flush=True)


if __name__ == "__main__":
    sys.exit(main())
