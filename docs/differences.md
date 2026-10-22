# Differences from Python Jinja2

bash_jinja is tested against Jinja2 3.0 with golden files and differential
fuzzing. Its output is meant to be identical to Jinja2's. The known
differences are listed below.

## Values and numbers

- Numbers are awk doubles. Arithmetic on integers beyond 2^53 loses
  precision. Integer literals and data values are still printed exactly
  (`{{ 12345678901234567890 }}`).
- Case conversion (`upper`, `lower`, `title`, `capitalize`, `swapcase`, the
  `lower`/`upper` tests) handles ASCII, Latin-1, Latin Extended-A, Greek and
  Cyrillic. Other characters are left unchanged. Python's context rules
  (final sigma) are not applied.
- Word characters (`wordcount`, `isalpha`, ...) are ASCII letters, digits,
  `_` and all non-ASCII characters.
- `random` and `lipsum` are random, as in Jinja2, so their output differs
  from run to run.

## Objects

- Filters that return generators in Jinja2 (`map`, `select`, `reject`,
  `selectattr`, `rejectattr`, `unique`, `batch`, `slice`, `reverse` on
  lists) return lists here. Printing them directly shows a list rather than
  `<generator object ...>`. Output is the same when piped into `list`,
  `join`, a `for` loop, and so on.
- Objects without a stable text form print differently. For example,
  `{{ 'x'.upper }}` gives `<built-in function upper>` instead of
  `<built-in method upper of str object at 0x...>`.
- Only Jinja2's own builtin types exist. There are no custom Python
  objects, filters, tests or globals.

## Compiler quirks

Jinja2 evaluates constant expressions at compile time. In a few autoescape
corner cases this changes the result, for example
`{{ '<'|safe ~ '<' }}` with autoescape on. bash_jinja always evaluates at
render time, which gives the result Jinja2 gives for non-constant values.

## Not supported

- line statements and line comments (`line_statement_prefix`)
- custom delimiters (`block_start_string`, ...)
- the `i18n`, `debug` and `with_` extensions, other than `loopcontrols`
  and `do`
- sandboxing, async rendering, bytecode cache
- YAML tags, complex keys and multi-document files

## awk implementations

| | gawk | mawk | busybox awk |
| --- | --- | --- | --- |
| speed | fast | fast | slower (about 3x) |
| recursion depth | unlimited | about 30 levels of macro or `loop()` recursion, about 15 levels of nested parentheses | unlimited |
| `**` with fractional exponent | exact | exact | exact when built with math support, otherwise computed in software (last digit may differ) |

When mawk runs out of evaluation stack, the error is
`mawk: program limit exceeded: eval stack size=1024`. Use gawk for deeply
recursive templates. gawk is chosen by default when it is installed.

Other POSIX awks (BSD awk, the "one true awk" on macOS) are not tested.
