# Usage

## Library

```bash
. jinja.sh

jinja_render        [options] TEMPLATE   # render a template file
jinja_render_string [options] SOURCE     # render a template given as a string
```

The rendered text goes to stdout, or to a file with `-o`. Capture it like
any other command:

```bash
config=$(jinja_render -d values.yaml templates/app.conf.j2) || exit 1
jinja_render -d values.yaml -o /etc/app.conf templates/app.conf.j2
```

`$(...)` removes trailing newlines from the output. To keep the output
byte-exact, use `-o FILE` or a redirection.

The library only defines functions and variables whose names start with
`jinja_`, `_jinja_`, `JINJA_` or `_JINJA_`. It does not change shell
options.

### Return codes

| Code | Meaning |
| --- | --- |
| `0` | success |
| `1` | template error (syntax, undefined variable in strict mode, missing template, ...) |
| `2` | invalid option or argument (unknown option, unset variable for `-v`, ...) |

With `-o`, the output file is written only when rendering succeeds.

## Command line

```text
jinja [options] TEMPLATE
jinja [options] -s SOURCE
jinja [options] -            (template read from stdin)
```

```bash
bin/jinja -d site.yaml templates/index.html > index.html
bin/jinja -D name=you -s 'Hello {{ name }}'
echo '{{ range(3)|list }}' | bin/jinja -
```

`bin/jinja --help` lists the options, `--version` prints the version.

## Options

| Option | Description |
| --- | --- |
| `-d, --data FILE` | load variables from a `.json`, `.yaml` or `.yml` file |
| `-v, --var NAME` | export a shell variable (in bash also integers and arrays); `NAME` may be a glob pattern such as `'app_*'` |
| `-v, --var NAME=VALUE` | define `NAME` without declaring it: `'(a b)'` list, `'([k]=v)'` dict, else string |
| `-i, --int NAME=INT` | define an integer variable |
| `-D, --define KEY=VALUE` | define a string variable |
| `-J, --json KEY=JSON` | define a variable from a JSON value |
| `-e, --env` | expose environment variables as variables |
| `-I, --path DIR` | add a directory to the template search path |
| `-o, --output FILE` | write the result to `FILE` |
| `--strict` | undefined variables raise an error |
| `--trim-blocks` | remove the first newline after a block tag |
| `--lstrip-blocks` | strip spaces and tabs before a block tag at the start of a line |
| `--keep-trailing-newline` | keep the final newline of the template |
| `--autoescape` | HTML-escape printed values |
| `--ext NAME` | enable an extension: `loopcontrols` (`break`, `continue`) or `do` |

Long options also accept `--option=value`. Use `--` to stop option parsing
when a template source starts with `-`:

```bash
jinja_render_string -- '-{{ 1 }}'
```

These options match the Python `jinja2.Environment` settings:

| sh_jinja | Python |
| --- | --- |
| `--trim-blocks` | `trim_blocks=True` |
| `--lstrip-blocks` | `lstrip_blocks=True` |
| `--keep-trailing-newline` | `keep_trailing_newline=True` |
| `--autoescape` | `autoescape=True` |
| `--strict` | `undefined=StrictUndefined` |
| `--ext loopcontrols` | `extensions=["jinja2.ext.loopcontrols"]` |
| `--ext do` | `extensions=["jinja2.ext.do"]` |

See [template data](data.md) for `-d`, `-v`, `-i`, `-D`, `-J` and `-e`.

## Template search path

`jinja_render dir/page.j2` loads `page.j2` from `dir`. Names used in
`include`, `import`, `from` and `extends` are looked up in `dir` first,
then in each `-I` directory, in order. This works like Jinja's
`FileSystemLoader(["dir", ...])`:

```text
templates/
├── page.j2          {% extends "layout/base.j2" %}
└── layout/
    └── base.j2      {% include "partials/nav.j2" %}
shared/
└── partials/
    └── nav.j2
```

```bash
jinja_render -I shared templates/page.j2
```

Template names always use `/` and are relative to a search path directory.
A name containing `..` is never loaded (`TemplateNotFound`).

For `jinja_render_string`, the search path is `-I` directories only, or the
current directory if there are none.

## Strict mode

By default an undefined variable prints as an empty string. With `--strict`,
printing, iterating, comparing or testing the truth of an undefined value is
an error. `is defined` and `default` still work:

```bash
jinja_render_string --strict '{{ port|default(80) }}'   # 80
jinja_render_string --strict '{{ port }}'
# jinja: <template>:1: UndefinedError: 'port' is undefined
```

## Errors

Errors are printed on stderr as `jinja: TEMPLATE:LINE: ErrorClass: message`.
Error classes and messages are the same as Jinja2's:

```text
jinja: page.html:3: TemplateSyntaxError: Encountered unknown tag 'endif'. ...
jinja: page.html:7: UndefinedError: 'dict object' has no attribute 'nmae'
jinja: page.html:1: TemplateNotFound: partials/nav.html
jinja: <template>:1: TypeError: unsupported operand type(s) for +: 'int' and 'str'
```

`<template>` is the name used for templates given as strings.
