# Expressions

## Literals

| Literal | Examples |
| --- | --- |
| string | `'single'`, `"double"`, escapes `\n \t \\ \' \x41 \u00e9`; adjacent strings are joined |
| integer | `42`, `1_000`, `0x1F`, `0o17`, `0b101` |
| float | `1.5`, `2.5e-3`, `1e3` |
| list | `[1, 2, 'three']` |
| tuple | `(1, 2)`, `(1,)`, `()` |
| dict | `{'key': 'value', 1: [2]}` |
| boolean / none | `true` `false` `none` (also `True` `False` `None`) |

```jinja
{{ 'a\tb' }}|{{ 'x' 'y' }}|{{ 0x1F }}|{{ 1_000 }}|{{ 2.5e-3 }}|{{ (1,) }}|{{ {'k': [1, 2]} }}
```

Output: `a	b|xy|31|1000|0.0025|(1,)|{'k': [1, 2]}`

## Variables, attributes and items

`foo.bar` looks up the attribute `bar`, then the item `'bar'`; `foo['bar']` does the opposite. Integer parts are items: `items.0` is `items[0]`. A missing attribute or item gives an undefined value; accessing an attribute *of* an undefined value is an error.

```json
{"user": {"name": "Ann"}, "tags": ["a", "b"]}
```

```jinja
{{ user.name }} {{ user['name'] }} {{ tags.0 }} {{ tags[-1] }} [{{ user.missing }}]
```

Output: `Ann Ann a b []`

Because attributes win, `d.items` is the dict method, while `d['items']` is the key:

```json
{"d": {"items": 3}}
```

```jinja
{{ d['items'] }} {{ d.items()|list }}
```

Output: `3 [('items', 3)]`

### Slicing

```json
{"s": "hello", "l": [1, 2, 3, 4, 5]}
```

```jinja
{{ s[1:3] }} {{ s[::-1] }} {{ l[1:] }} {{ l[::2] }} {{ l[-2:] }}
```

Output: `el olleh [2, 3, 4, 5] [1, 3, 5] [4, 5]`

## Operators

| Operators | Meaning |
| --- | --- |
| `+ - * / // % **` | arithmetic (Python semantics: `/` is true division, `//` and `%` floor towards minus infinity) |
| `~` | string concatenation (converts operands to strings) |
| `== != < <= > >=` | comparison, can be chained: `1 < x < 10` |
| `in`, `not in` | membership (substring, list item, dict key) |
| `and or not` | boolean logic, returns an operand like Python |
| `is`, `is not` | [tests](tests.md) |
| `\|` | [filters](filters.md) |
| `x if cond else y` | conditional expression (`else` optional: undefined) |

```jinja
{{ 7 / 2 }} {{ 7 // 2 }} {{ -7 // 2 }} {{ -7 % 3 }} {{ 2 ** 10 }} {{ 'a' ~ 1 ~ none }} {{ 'ab' * 2 }} {{ [1] + [2] }}
```

Output: `3.5 3 -4 2 1024 a1None abab [1, 2]`

```jinja
{{ 1 < 2 < 3 }} {{ 'b' in 'abc' }} {{ 'k' in {'k': 1} }} {{ 3 not in [1, 2] }} {{ 0 or 'default' }} {{ 'x' if false else 'y' }}
```

Output: `True True True True default y`

### Precedence

From lowest to highest (as in Jinja):

1. `x if c else y`
2. `or`
3. `and`
4. `not`
5. comparisons, `in`, `not in`
6. `+ -`
7. `~`
8. `* / // %`
9. `**` (left-associative in Jinja!)
10. unary `- +`, then filters `|`, tests `is`, attribute/item access and calls

Filters bind tighter than any binary operator, but apply after a unary minus; `**` is left-associative and its left operand includes the sign:

```jinja
{{ -3|abs }} {{ 1 ~ 2|string }} {{ 2 ** 3 ** 2 }} {{ -2 ** 2 }} {{ 1 + 2 * 3 }}
```

Output: `3 12 64 4 7`

Since `+` binds looser than `~`, `'a' ~ 1 + 2` is `('a' ~ 1) + 2`, a `TypeError`: write `'a' ~ (1 + 2)`.

## Calls

Macros, global functions and methods accept positional and keyword arguments, and `*args` / `**kwargs` unpacking:

```jinja
{% macro tag(name, cls='x') %}<{{ name }} class="{{ cls }}">{% endmacro %}{{ tag('p') }} {{ tag(*['b'], **{'cls': 'y'}) }} {{ '{}-{}'.format(1, 2) }}
```

Output: `<p class="x"> <b class="y"> 1-2`

## Undefined values

An undefined value prints as `''`, is false, iterates as an empty sequence and has length 0. Using it in arithmetic, comparing it with `<`, calling it or reading its attributes raises `UndefinedError`. `default` and `is defined` handle it:

```jinja
[{{ x }}] {{ x is defined }} {{ x|default('d') }} {{ x|length }} {% for i in x %}never{% else %}empty{% endfor %}
```

Output: `[] False d 0 empty`

```jinja
{{ user.name }}
```

```text
jinja: <template>:1: UndefinedError: 'user' is undefined
```

With `--strict` (`StrictUndefined`) printing, iterating, testing the truth of or comparing an undefined value is an error too; only `is defined`, `is undefined` and `default` work.

## HTML escaping

With `--autoescape` (or inside `{% autoescape true %}`), printed values are HTML-escaped unless marked safe (`|safe`, `|e`, macro results, `tojson`...):

```json
{"s": "<b>&</b>"}
```

```jinja
{% autoescape true %}{{ s }} {{ s|safe }} {{ s|e }}{% endautoescape %} {{ s }}
```

Output: `&lt;b&gt;&amp;&lt;/b&gt; <b>&</b> &lt;b&gt;&amp;&lt;/b&gt; <b>&</b>`
