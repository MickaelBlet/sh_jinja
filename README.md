# bash_jinja

Render [Jinja2](https://jinja.palletsprojects.com/) templates from bash, with
the **same syntax and the same output** as Python Jinja2 (3.x) — without
Python. Only **bash ≥ 4.3** and a **POSIX awk** are needed (tested with gawk,
mawk and busybox awk).

```bash
source jinja.sh
name=World
jinja_render_string -v name 'Hello {{ name }}!'     # Hello World!
jinja_render -d config.yaml -o nginx.conf templates/nginx.conf.j2
```

Full documentation: [docs/](docs/README.md).

## Installation

Either use the repository as is (`jinja.sh` loads the engine from
`lib/awk/`), or build a single self-contained file:

```bash
tools/build.sh            # -> dist/jinja.sh (bash + embedded awk engine)
```

## Usage

### Library

```bash
source jinja.sh
jinja_render        [options] TEMPLATE   # render a template file
jinja_render_string [options] SOURCE     # render a template given as a string
```

The result goes to stdout (or `-o FILE`); the return code is non-zero on
error, with a message on stderr:

```
jinja: page.html:12: UndefinedError: 'user' is undefined
```

### Command line

```bash
bin/jinja [options] TEMPLATE
bin/jinja [options] -s 'SOURCE'
echo '{{ 6 * 7 }}' | bin/jinja -
```

### Options

| Option | Description |
| --- | --- |
| `-d, --data FILE` | load variables from a `.json`, `.yaml` or `.yml` file |
| `-v, --var NAME` | export a bash variable; `NAME` may be a glob (`'app_*'`) |
| `-v, --var NAME=VALUE` | define `NAME` without declaring it: `'(a b)'` list, `'([k]=v)'` dict, else string |
| `-i, --int NAME=INT` | define an integer variable |
| `-D, --define KEY=VALUE` | define a string variable |
| `-J, --json KEY=JSON` | define a variable from a JSON value |
| `-e, --env` | expose environment variables |
| `-I, --path DIR` | add `DIR` to the template search path |
| `-o, --output FILE` | write the result to `FILE` (only on success) |
| `--strict` | undefined variables raise an error (`StrictUndefined`) |
| `--trim-blocks` | remove the first newline after a block tag |
| `--lstrip-blocks` | strip spaces/tabs before a block tag on its line |
| `--keep-trailing-newline` | keep the final newline of the template |
| `--autoescape` | HTML-escape variable output |
| `--ext NAME` | enable an extension: `loopcontrols` (`break`/`continue`), `do` |

Sources are merged in command line order, later ones win; environment
variables (`-e`) have the lowest priority.

`JINJA_AWK` selects the awk implementation (default: `gawk` when installed,
else `awk`), e.g. `JINJA_AWK=mawk` or `JINJA_AWK="busybox awk"`.

### Bash variables

| bash | template value |
| --- | --- |
| `x=hello` | `'hello'` (str) |
| `declare -i n=3` | `3` (int) |
| `arr=(a b)` | `['a', 'b']` (list) |
| `declare -A m=([k]=v)` | `{'k': 'v'}` (dict, keys sorted) |
| `declare -n r=x` | value of `x` |

```bash
declare -A user=([name]=alice [role]=admin)
hosts=(web1 web2)
jinja_render_string -v user -v hosts \
  '{{ user.name|title }} ({{ user.role }}): {{ hosts|join(", ") }}'
# Alice (admin): web1, web2
```

Same without declaring anything:

```bash
jinja_render_string -v 'user=([name]=alice [role]=admin)' -v 'hosts=(web1 web2)' \
  -i port=8080 '{{ user.name|title }}: {{ hosts|join(", ") }}:{{ port + 1 }}'
# Alice: web1, web2:8081
```

### Template loading

`jinja_render dir/page.j2` behaves like
`Environment(loader=FileSystemLoader(["dir", <-I dirs>...]))`:
`include`, `import` and `extends` names are resolved from the template's
directory first, then from each `-I` directory.

## Supported Jinja2 features

Everything from the default `jinja2.Environment`:

- **Syntax**: `{{ }}`, `{% %}`, `{# #}`, whitespace control (`-`, `+`),
  `trim_blocks`, `lstrip_blocks`, `keep_trailing_newline`, `{% raw %}`.
- **Expressions**: literals (str with Python escapes, int incl. `0x`/`0o`/`0b`/`_`,
  float, list, tuple, dict, `true/false/none`), `+ - * / // % **`, `~`,
  comparisons (chained), `in`/`not in`, `and/or/not`, `is [not]` tests,
  inline `if/else`, attribute/item access, slicing, calls with
  `*args`/`**kwargs`, filters with arguments — with Jinja's precedence rules.
- **Statements**: `if/elif/else`, `for` (`else`, filtering `if`, unpacking,
  `recursive`, full `loop` object incl. `cycle`, `changed`, `previtem`,
  `nextitem`, `depth`), `set` (incl. block set with filters), `namespace`,
  `with`, `macro` (defaults, `varargs`, `kwargs`, `caller`), `call` blocks,
  `filter` blocks, `include` (`ignore missing`, lists, `with/without context`),
  `import` / `from ... import` (`with context`), `extends`, `block`
  (`super()`, `self.name()`, `scoped`, `required`), `autoescape`, `print`.
- **Filters**: abs, attr, batch, capitalize, center, count, d, default,
  dictsort, e, escape, filesizeformat, first, float, forceescape, format,
  groupby, indent, int, items, join, last, length, list, lower, map, max, min,
  pprint, random, reject, rejectattr, replace, reverse, round, safe, select,
  selectattr, slice, sort, string, striptags, sum, title, tojson, trim,
  truncate, unique, upper, urlencode, urlize, wordcount, wordwrap, xmlattr.
- **Tests**: all builtin tests (`defined`, `divisibleby`, `odd`, `sameas`,
  `in`, `eq`, `lt`, ...).
- **Globals**: `range`, `dict`, `namespace`, `cycler`, `joiner`, `lipsum`.
- **Python semantics**: `str()`/`repr()` of values (`[1, 'a']`, `True`,
  `None`, shortest float repr, `4/2 → 2.0`), floor division and modulo signs,
  `%` string formatting, `str.format()`, common `str`/`list`/`dict` methods
  (`split`, `startswith`, `items`, `get`, `append`, ...), `Markup` /
  autoescape rules, `Undefined` behaviour and error classes
  (`UndefinedError`, `TemplateSyntaxError`, `TemplateNotFound`, `TypeError`, ...).

YAML files support the common subset of PyYAML `safe_load`: block and flow
collections, quoted/plain/block scalars (`|`, `>`, chomping and indentation
indicators), comments, anchors/aliases, merge keys, YAML 1.1 typing
(`yes/no/on/off`, octal `010`, `1e5` is a string, ...).

## Known differences

- Numbers are awk doubles: integers beyond 2^53 lose precision in
  arithmetic (literals and data values are printed exactly).
- Case mapping (`upper`, `lower`, `title`, ...) covers ASCII, Latin-1,
  Latin Extended-A, Greek and Cyrillic.
- mawk has a fixed evaluation stack: recursion is limited to about 30
  levels of recursive macros / `loop()` calls and about 15 levels of nested
  parentheses ("program limit exceeded: eval stack size"). gawk and busybox
  awk have no such limit.
- Without math support in awk (some busybox builds), `**` with a
  fractional exponent is computed in software and may differ in the last
  digit.
- Values without a stable representation (`<built-in method ... at 0x...>`,
  generators returned by `map`/`select`/... when printed directly) differ.
  Filters returning generators in Jinja return lists here.
- Constant folding quirks of the Jinja compiler are not reproduced.
- Not supported: custom filters/tests/extensions written in Python, `i18n`,
  line statements, async, sandbox, YAML tags and complex keys.

## Development

```bash
tests/run.sh                 # golden tests x every available awk
tests/cli.sh [-a AWK]        # bash side: variables, options, CLI
tests/gen_expected.py [CASE] # regenerate golden files with Python Jinja2
tests/fuzz.py expr|ws [SEED] [COUNT]  # differential fuzzing vs Python Jinja2
tools/lint_awk.sh            # detect constructs that break mawk/busybox
tools/build.sh               # build dist/jinja.sh
```

Each `tests/cases/<name>/` holds `template.j2` (plus included templates),
optional `data.json`/`data.yaml` and `opts`, and the expected output
(`expected`) or exception class (`expected_error`) produced by Python
Jinja2.

## License

MIT
