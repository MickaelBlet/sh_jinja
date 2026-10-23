# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `-v NAME=VALUE` defines a variable without declaring it first, using the
  bash assignment syntax: `'(a b)'` gives a list, `'([k]=v)'` a dict,
  anything else a string.
- `-i, --int NAME=INT` defines an integer variable.

## [0.1.0] - 2026-10-22

### Added

- `jinja.sh` library: `jinja_render` (template file) and
  `jinja_render_string` (template string), output to stdout or `-o FILE`.
- `bin/jinja` command line front-end: template file, `-s SOURCE` or stdin.
- Context sources: bash variables (`-v`, scalars, integers, indexed and
  associative arrays, namerefs, glob patterns), `-D KEY=VALUE`,
  `-J KEY=JSON`, environment (`-e`), JSON and YAML data files (`-d`).
- Options: `--strict`, `--trim-blocks`, `--lstrip-blocks`,
  `--keep-trailing-newline`, `--autoescape`, `--ext loopcontrols|do`,
  template search path (`-I`).
- awk engine (gawk, mawk, busybox awk) reproducing Jinja2 3.x output:
  lexer and parser mirroring `jinja2/lexer.py` and `jinja2/parser.py`,
  whitespace control, `raw`, full expression grammar and precedence.
- Statements: `if`, `for` (loop object, `else`, filtering, `recursive`),
  `set`, `namespace`, `with`, `macro`, `call`, `filter`, `include`,
  `import`, `from ... import`, `extends`, `block` (`super()`, `scoped`,
  `required`), `autoescape`, `print`.
- All builtin filters, tests and globals; common Python `str`, `list`
  and `dict` methods, `%` formatting and `str.format()`.
- Python value semantics: `repr()`/`str()`, float formatting, integer
  and float arithmetic, `Markup`/autoescape, `Undefined` and Jinja2
  error classes.
- YAML loader covering the common PyYAML `safe_load` subset (block and
  flow collections, block scalars, anchors, merge keys, YAML 1.1 typing).
- `tools/build.sh` to build a single-file `dist/jinja.sh`.
- Golden tests generated with Python Jinja2 (`tests/run.sh`), CLI tests
  (`tests/cli.sh`), differential fuzzing (`tests/fuzz.py`), awk
  portability lint (`tools/lint_awk.sh`) and a `Makefile`.
- Documentation in `docs/`: installation, usage, template data, syntax,
  expressions, statements, filters, tests, globals and methods,
  differences from Python Jinja2, development guide.

[Unreleased]: https://github.com/MickaelBlet/bash_jinja/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MickaelBlet/bash_jinja/releases/tag/v0.1.0
