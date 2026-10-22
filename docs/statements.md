# Statements

- [if](#if) · [for](#for) · [set](#set) · [namespace](#namespace) · [with](#with) · [macro](#macro) · [call](#call) · [filter](#filter) · [include](#include) · [import](#import) · [extends / block](#extends-and-block) · [autoescape](#autoescape) · [print](#print) · [extensions](#extensions)

## if

```jinja
{% for n in [0, 1, 5] %}{% if n == 0 %}zero{% elif n < 3 %}small{% else %}big{% endif %} {% endfor %}
```

Output: `zero small big `

Variables set inside an `if` are visible after it (no new scope).

## for

```json
{"users": ["ann", "bob", "cy"]}
```

```jinja
{% for user in users %}{{ loop.index }}. {{ user }}{% if not loop.last %}, {% endif %}{% endfor %}
```

Output: `1. ann, 2. bob, 3. cy`

Iterating a dict gives its keys; use `.items()` or `|dictsort` for pairs. Tuples can be unpacked:

```json
{"d": {"b": 2, "a": 1}}
```

```jinja
{% for k, v in d|dictsort %}{{ k }}={{ v }} {% endfor %}{% for a, b in [(1, 2), (3, 4)] %}{{ a + b }} {% endfor %}
```

Output: `a=1 b=2 3 7 `

`else` is rendered when nothing was iterated; an inline `if` filters items (and `loop` counts only the kept ones):

```jinja
{% for x in [] %}{{ x }}{% else %}no items{% endfor %} | {% for x in range(10) if x is odd %}{{ x }}({{ loop.index }}/{{ loop.length }}) {% endfor %}
```

Output: `no items | 1(1/5) 3(2/5) 5(3/5) 7(4/5) 9(5/5) `

### The loop variable

| Attribute | Meaning |
| --- | --- |
| `loop.index` / `loop.index0` | iteration, from 1 / from 0 |
| `loop.revindex` / `loop.revindex0` | iterations left, to 1 / to 0 |
| `loop.first` / `loop.last` | first / last iteration |
| `loop.length` | number of items |
| `loop.depth` / `loop.depth0` | recursion level (recursive loops) |
| `loop.previtem` / `loop.nextitem` | neighbour items (undefined at the ends) |
| `loop.cycle(a, b, ...)` | cycle through the arguments |
| `loop.changed(value)` | true when value differs from the previous call |

```jinja
{% for x in [1, 1, 2] %}{{ loop.cycle('odd', 'even') }}:{{ x }}{% if loop.changed(x) %}*{% endif %}[{{ loop.previtem }}] {% endfor %}
```

Output: `odd:1*[] even:1[1] odd:2*[1] `

Inside nested loops, keep a reference to the outer loop with `{% set outer = loop %}`.

### Recursive loops

```json
{"tree": [{"name": "a", "children": [{"name": "b"}, {"name": "c", "children": [{"name": "d"}]}]}, {"name": "e"}]}
```

```jinja
{% for item in tree recursive %}{{ item.name }}{% if item.children %}({{ loop(item.children) }}){% endif %} {% endfor %}
```

Output: `a(b c(d ) ) e `

### Scoping

Each iteration has its own scope: a variable `set` in the loop body is not visible after the loop, nor in the next iteration. Use a [namespace](#namespace) to carry values out of a loop.

```jinja
{% set count = 0 %}{% for i in [1, 2, 3] %}{% set count = count + 1 %}{{ count }}{% endfor %} after: {{ count }}
```

Output: `111 after: 0`

## set

```jinja
{% set a = 1 %}{% set b, c = 2, 3 %}{% set items = [a, b, c] %}{{ items }}
```

Output: `[1, 2, 3]`

Block form, with optional filters:

```jinja
{% set greeting %}Hello {{ 'world' }}{% endset %}{% set loud | upper %}hey{% endset %}{{ greeting }} / {{ loud }}
```

Output: `Hello world / HEY`

Top-level variables of a child template are visible in the blocks of its parent template, and exported by [imported](#import) templates (unless their name starts with `_`).

## namespace

```jinja
{% set ns = namespace(found=false, total=0) %}{% for x in [3, 8, 2] %}{% set ns.total = ns.total + x %}{% if x > 5 %}{% set ns.found = true %}{% endif %}{% endfor %}{{ ns.found }} {{ ns.total }}
```

Output: `True 13`

## with

Creates an inner scope. Values are evaluated in the outer scope:

```jinja
{% set a = 5 %}{% with a = 1, b = a %}{{ a }} {{ b }}{% endwith %} {{ a }}
```

Output: `1 5 5`

## macro

Macros are reusable template functions. Arguments may have defaults (which can use earlier arguments). Extra positional arguments are in `varargs`, extra keyword arguments in `kwargs` (only if the macro body uses them):

```jinja
{% macro input(name, value='', type='text') -%}
<input type="{{ type }}" name="{{ name }}" value="{{ value }}"{% for k, v in kwargs|dictsort %} {{ k }}="{{ v }}"{% endfor %}>
{%- endmacro %}
{{ input('user') }}
{{ input('pass', type='password', required='required') }}
```

Output:

```text

<input type="text" name="user" value="">
<input type="password" name="pass" value="" required="required">
```

Macro objects expose `name`, `arguments`, `catch_kwargs`, `catch_varargs` and `caller`. Macros see the template's top-level variables and the variables of the scope where they are defined.

## call

Passes a block to a macro, which renders it with `caller()`:

```jinja
{% macro panel(title) %}<div><h2>{{ title }}</h2>{{ caller() }}</div>{% endmacro %}{% call panel('News') %}<p>Body</p>{% endcall %}
```

Output: `<div><h2>News</h2><p>Body</p></div>`

`caller` can take arguments:

```jinja
{% macro each(items) %}{% for i in items %}{{ caller(i, loop.index) }}{% endfor %}{% endmacro %}{% call(item, n) each(['a', 'b']) %}[{{ n }}:{{ item }}]{% endcall %}
```

Output: `[1:a][2:b]`

## filter

```jinja
{% filter upper|replace('O', '0') %}hello world{% endfilter %}
```

Output: `HELL0 W0RLD`

## include

Renders another template with the current context (including loop variables).

`page.html`:

```jinja
{% for item in ['a', 'b'] %}{% include 'item.html' %}{% endfor %}
{% include 'missing.html' ignore missing %}
{% include ['custom.html', 'default.html'] %}
```

`item.html`:

```jinja
<li>{{ item }}</li>
```

`default.html`:

```jinja
default
```

Rendering `page.html`:

```text
<li>a</li><li>b</li>

default
```

Add `without context` to render it without the current variables. A list of names renders the first existing template.

## import

Loads macros and top-level variables of another template:

`page.html`:

```jinja
{% import 'forms.html' as forms %}{{ forms.field('q') }} {{ forms.version }}
{% from 'forms.html' import field as f %}{{ f('x') }}
```

`forms.html`:

```jinja
{% set version = '1.0' %}{% macro field(name) %}<input name="{{ name }}">{% endmacro %}
```

Rendering `page.html`:

```text
<input name="q"> 1.0
<input name="x">
```

Imported templates do not see the importing template's variables unless `with context` is added.

## extends and block

A child template extends a parent and overrides its blocks; `super()` renders the parent block, `self.name()` renders a block again:

`base.html`:

```jinja
<title>{% block title %}Site{% endblock %}</title>
<main>{% block content %}{% endblock %}</main>
<footer>{% block footer %}(c) {{ self.title() }}{% endblock %}</footer>
```

`page.html`:

```jinja
{% extends 'base.html' %}
{% block title %}Page - {{ super() }}{% endblock %}
{% block content %}Hello {{ user }}{% endblock %}
```

Rendering `page.html`:

```text
<title>Page - Site</title>
<main>Hello Ann</main>
<footer>(c) Page - Site</footer>
```

- Text outside blocks in a child template is ignored; `{% set %}` there is still executed and visible to the parent.
- The parent name can be an expression: `{% extends layout %}`.
- Blocks can be nested and inherited over several levels.
- `{% block name scoped %}` gives the block access to enclosing loop variables.
- `{% block name required %}` must be overridden by a child template.

`base.html`:

```jinja
{% for item in [1, 2] %}{% block row scoped %}{{ item }}{% endblock %}{% endfor %}
```

`page.html`:

```jinja
{% extends 'base.html' %}{% block row %}<{{ item }}>{% endblock %}
```

Rendering `page.html`:

```text
<1><2>
```

## autoescape

```jinja
{% autoescape true %}{{ '<b>' }}{% endautoescape %} {{ '<b>' }}
```

Output: `&lt;b&gt; <b>`

## print

```jinja
{% print 'a', 1 + 1 %}
```

Output: `a2`

## Extensions

Enabled with `--ext`:

- `loopcontrols`: `{% break %}` and `{% continue %}` in loops.
- `do`: `{% do expression %}` evaluates an expression without printing it.

```jinja
{% for i in range(10) %}{% if i is odd %}{% continue %}{% endif %}{% if i > 6 %}{% break %}{% endif %}{{ i }}{% endfor %}
```

Output (with `--ext loopcontrols`): `0246`
