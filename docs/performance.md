# Performance

`tools/bench.py` (`make bench`) times sh_jinja against Python Jinja2 on
generated workloads. Every engine must first produce the same output as
Python Jinja2; then each cell is run once to warm up and timed up to 10 times
(median shown).

| Engine | What is timed |
| --- | --- |
| `python` | a `python3` process: import `jinja2`, load the data, render (what a Python CLI does) |
| `sh_jinja/AWK` | a `bin/jinja -d DATA TEMPLATE` process with `JINJA_AWK=AWK` |
| `python-inproc` | render in a running Python, template already compiled: lower bound when one process renders many times |

| Workload | Content |
| --- | --- |
| `tiny` | `Hello {{ name }}!`: startup cost |
| `loop N` | `for` over N dicts with `if`, `loop.index`, `upper`, `format`, `join` |
| `json N` / `yaml N` | load an N-item data file, print a few values: loader cost |
| `inherit N` | `extends`, blocks, `import`, macro with `call`, `include` per item |
| `filters N` | `selectattr`, `rejectattr`, `map`, `sort`, `groupby`, `sum`, `unique`, `replace` |

```bash
tools/bench.py                      # every workload, sizes 100,1000,10000
tools/bench.py -a mawk -w loop -n 500,5000 -r 5
tools/bench.py --markdown           # report below
```

## Results

- CPU: Intel(R) Core(TM) Ultra 7 255HX
- OS: Linux 6.6.87.2-microsoft-standard-WSL2
- sh_jinja 0.1.1, /bin/sh = /usr/bin/dash
- Python 3.10.12, Jinja2 3.0.3
- gawk: GNU Awk 5.1.0, API: 3.0 (GNU MPFR 4.1.0, GNU MP 6.2.1)
- mawk: mawk 1.3.4 20200120
- busybox awk: BusyBox v1.30.1 (Ubuntu 1:1.30.1-7ubuntu3.1) multi-call binary.

Median wall time in ms (ratio to `python`).

| workload | `python` | `sh_jinja/gawk` | `sh_jinja/mawk` | `sh_jinja/busybox awk` | `python-inproc` |
| --- | ---: | ---: | ---: | ---: | ---: |
| tiny | 35.7 | 11.0 (×0.31) | 4.7 (×0.13) | 10.8 (×0.3) | 0.01 (×0.00037) |
| loop 100 | 36.1 | 17.2 (×0.48) | 8.5 (×0.24) | 28.5 (×0.79) | 0.26 (×0.0073) |
| loop 1000 | 39.1 | 69.9 (×1.8) | 46.0 (×1.2) | 191 (×4.9) | 2.4 (×0.061) |
| loop 10000 | 65.9 | 674 (×10) | 687 (×10) | 2096 (×32) | 26.2 (×0.4) |
| json 100 | 35.8 | 14.1 (×0.39) | 6.1 (×0.17) | 20.7 (×0.58) | 0.06 (×0.0016) |
| json 1000 | 35.6 | 36.7 (×1) | 21.0 (×0.59) | 115 (×3.2) | 0.49 (×0.014) |
| json 10000 | 43.2 | 275 (×6.4) | 213 (×4.9) | 1111 (×26) | 5.9 (×0.14) |
| yaml 100 | 64.1 | 15.1 (×0.23) | 6.8 (×0.11) | 21.1 (×0.33) | 21.1 (×0.33) |
| yaml 1000 | 266 | 47.6 (×0.18) | 30.1 (×0.11) | 106 (×0.4) | 216 (×0.81) |
| yaml 10000 | 2655 | 383 (×0.14) | 327 (×0.12) | 1017 (×0.38) | 2482 (×0.93) |
| inherit 100 | 38.0 | 18.3 (×0.48) | 9.1 (×0.24) | 30.7 (×0.81) | 0.91 (×0.024) |
| inherit 1000 | 45.7 | 73.5 (×1.6) | 49.6 (×1.1) | 205 (×4.5) | 7.5 (×0.16) |
| inherit 10000 | 117 | 667 (×5.7) | 648 (×5.5) | 2251 (×19) | 74.9 (×0.64) |
| filters 100 | 36.9 | 17.3 (×0.47) | 7.9 (×0.22) | 28.6 (×0.77) | 0.19 (×0.0052) |
| filters 1000 | 39.2 | 67.3 (×1.7) | 40.8 (×1) | 200 (×5.1) | 1.6 (×0.041) |
| filters 10000 | 57.4 | 737 (×13) | 621 (×11) | 3739 (×65) | 16.4 (×0.28) |

## Takeaways

- Startup: a `bin/jinja` run costs 5 ms (mawk) to 11 ms (gawk), a Python
  run 36 ms, mostly `import jinja2`. For the typical shell use, small
  templates and data, sh_jinja is 2 to 8 times faster.
- Python compiles templates to bytecode, so it wins on large renders: the
  break-even is around 1000 items with mawk, and at 10000 items sh_jinja is
  5 to 13 times slower with gawk or mawk.
- YAML: sh_jinja is faster at every size. `yaml.safe_load` uses the pure
  Python loader; PyYAML's C loader (`CSafeLoader`, needs libyaml) would
  narrow the gap.
- mawk is the fastest awk, gawk is close on large renders, busybox awk is 3
  to 6 times slower than mawk.
