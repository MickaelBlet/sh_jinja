# sh_jinja documentation

sh_jinja renders [Jinja2](https://jinja.palletsprojects.com/) templates
with a POSIX shell and awk only. Templates use the same syntax as Jinja2 3.x and give
the same output as the Python implementation.

```bash
. jinja.sh
name=World
jinja_render_string -v name 'Hello {{ name }}!'   # Hello World!
```

## Contents

**Getting started**

- [Installation](installation.md): requirements, setup, single-file build
- [Usage](usage.md): library functions, command line, options, errors
- [Template data](data.md): shell variables, JSON, YAML, environment

**Template language**

- [Syntax](syntax.md): delimiters, whitespace control, raw blocks
- [Expressions](expressions.md): literals, operators, precedence, undefined values
- [Statements](statements.md): `if`, `for`, `set`, macros, include, import, inheritance
- [Filters](filters.md): every builtin filter, with examples
- [Tests](tests.md): every builtin test
- [Globals and methods](globals.md): `range`, `namespace`, `cycler`, Python methods

**Reference**

- [Differences from Python Jinja2](differences.md)
- [Development](development.md): architecture, tests, contributing

All template examples in this documentation are checked: their output is
identical with Python Jinja2 and with sh_jinja.
