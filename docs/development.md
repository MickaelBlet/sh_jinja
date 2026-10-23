# Development

## Layout

```text
jinja.sh               bash library and CLI entry point (options, context)
bin/jinja              command line wrapper
lib/awk/
  value.awk            value heap, Python str()/repr(), comparisons, math
  utf8.awk             code point aware string helpers, case mapping
  lexer.awk            template -> tokens (mirrors jinja2/lexer.py)
  parser.awk           tokens -> AST (mirrors jinja2/parser.py)
  runtime.awk          evaluator: scopes, statements, macros, inheritance
  filters.awk          builtin filters
  tests.awk            builtin tests
  builtins.awk         globals and Python str/list/dict methods
  json.awk             JSON parser and json.dumps (tojson)
  yaml.awk             YAML loader
  main.awk             protocol reader, render entry point
tools/build.sh         single-file build (dist/jinja.sh)
tools/lint_awk.sh      portability lint
tests/                 golden tests, CLI tests, fuzzer
```

## How rendering works

1. `jinja.sh` parses the options and writes a small text protocol, one
   record per line, tab separated, values escaped as `\\`, `\n`, `\t`:

   | Record | Meaning |
   | --- | --- |
   | `O key value` | option (`trim_blocks`, `strict`, `path`, `out`, `math`, ...) |
   | `X` | import environment variables |
   | `S name value` / `I name value` | string / integer variable |
   | `L name n` then n × `E value` | list |
   | `A name n` then n × `K key value` | dict |
   | `J name json` | JSON value |
   | `V name value` | `-v NAME=VALUE`: bash array literal or string, parsed by awk |
   | `F path` | data file |
   | `T source` / `M name` | main template (string / name) |

2. awk runs with `LC_ALL=C`, so strings are bytes. The program is the
   `lib/awk/*.awk` files, or the embedded source in `dist/jinja.sh`. awk
   reads the protocol on stdin and builds the context.
3. Templates are loaded through the search path, tokenized, parsed into an
   AST and cached.
4. The evaluator walks the AST. Values live in a typed heap: `VT[id]` is the
   type, `VV[id]` the scalar, and `VE`/`VK`/`VD` hold list and dict items.
   Scopes are frames chained by parent pointers. Output is built in buffers
   that join their chunks pairwise, so large outputs stay linear.
5. Output is printed only at the end. On error, a message goes to stderr
   and awk exits with status 1.

## Portability rules for the awk code

`tools/lint_awk.sh` checks most of these:

- Never write `name (expr)` for concatenation: busybox parses it as a
  function call. Write `name "" (expr)`.
- Do not use `^`, `**`, `sqrt`, `exp` or `log`: busybox may be built
  without math support. Use the `m_*` helpers in `value.awk`.
- Do not use `sprintf("%d")` for large numbers: mawk and busybox clamp it to
  32 bits. Use `v_ifmt`.
- Do not use `gsub` with `\\` in the replacement: mawk and gawk disagree.
  Use `v_bsdouble`.
- Coerce floats with `x * 1`, not `x + 0`, to keep `-0.0`.
- Keep few locals in recursive functions: mawk has a fixed stack of 1024
  slots. Save render state with `rt_push`/`rt_pop`.
- No gawk extensions: no arrays of arrays, `gensub`, `asort` or
  `strtonum`.

## Tests

```bash
make test        # golden tests on every available awk + CLI tests
make lint        # awk portability lint + shellcheck
make fuzz        # differential fuzzing against Python Jinja2
make dist        # build dist/jinja.sh
```

### Golden tests

`tests/cases/<name>/` contains:

| File | Content |
| --- | --- |
| `template.j2` | main template; other templates of the case sit next to it |
| `data.json` / `data.yaml` | optional context |
| `opts` | optional options, one per line: `trim_blocks`, `lstrip_blocks`, `keep_trailing_newline`, `autoescape`, `strict`, `ext=loopcontrols`, `ext=do` |
| `expected` | output produced by Python Jinja2 |
| `expected_error` | or: the exception class raised by Python Jinja2 |
| `requires` | optional awk features, space separated: `negzero` (`-0.0` kept), `denormal` (subnormal numbers kept); the case is skipped on an awk without them |

To add a case, create the directory, then generate its expected result with
the reference implementation (this needs `python3`, `jinja2` and `pyyaml`):

```bash
tests/gen_expected.py my_case
tests/run.sh my_case              # all awks
tests/run.sh -a mawk my_case      # one awk
```

Never edit `expected` by hand. It must come from Python Jinja2.

### CLI tests

`tests/cli.sh [-a AWK]` checks the bash side: variable export, options,
return codes and the CLI.

Both scripts test `jinja.sh` from the repository; set `JINJA_SH` to test
another copy, such as `JINJA_SH=$PWD/dist/jinja.sh`.

### CI

`.github/workflows/ci.yml` runs on every push and pull request:

| Job | Platform | awk |
| --- | --- | --- |
| `lint` | Ubuntu | `make lint` |
| `linux` | Ubuntu | gawk, mawk, busybox awk, `original-awk` (BWK), plus `dist/jinja.sh` |
| `macos` | macOS, Homebrew bash | `/usr/bin/awk` (BWK) |
| `alpine` | Alpine (musl) | busybox awk |

### Fuzzing

`tests/fuzz.py expr SEED COUNT` renders random expressions with Python
Jinja2 and with `bin/jinja`, and reports every difference in output or
exception class. `tests/fuzz.py ws SEED COUNT` does the same for
whitespace-control mixes under every `trim_blocks`/`lstrip_blocks`
combination. Turn every bug the fuzzer finds into a golden test.
