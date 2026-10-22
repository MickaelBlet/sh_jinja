# Tests

Tests check a value with `is` and return a boolean: `{{ x is defined }}`, `{{ n is divisibleby(3) }}`, `{{ n is divisibleby 3 }}`, negated with `is not`. They are also used by `select`, `reject`, `selectattr` and `rejectattr`.

```jinja
{% for n in range(1, 7) %}{{ n }}{% if n is even %}e{% elif n is divisibleby 3 %}t{% endif %} {% endfor %}
```

Output: `1 2e 3t 4e 5 6e `

| Test | True when |
| --- | --- |
| `boolean` | value is `true` or `false` |
| `callable` | value can be called (macro, global function, method) |
| `defined` | variable is defined |
| `divisibleby` | value is divisible by `num` |
| `eq`, `equalto`, `==` | equal to |
| `escaped` | value is marked safe (Markup) |
| `even` | integer is even |
| `false` | value is `false` |
| `filter` | a filter with that name exists |
| `float` | value is a float |
| `ge`, `>=` | greater or equal |
| `gt`, `>`, `greaterthan` | greater than |
| `in` | value is contained in `seq` |
| `integer` | value is an int (not a bool) |
| `iterable` | value can be iterated |
| `le`, `<=` | less or equal |
| `lower` | string is lowercase |
| `lt`, `<`, `lessthan` | less than |
| `mapping` | value is a dict |
| `ne`, `!=` | not equal |
| `none` | value is `none` |
| `number` | value is a number (int, float, bool) |
| `odd` | integer is odd |
| `sameas` | same object (`is` in Python) |
| `sequence` | value has a length and supports indexing (str, list, tuple, dict) |
| `string` | value is a string |
| `test` | a test with that name exists |
| `true` | value is `true` |
| `undefined` | variable is undefined |
| `upper` | string is uppercase |

## Examples

### boolean

```jinja
{{ true is boolean }} {{ 1 is boolean }}
```

Output: `True False`

### callable

```jinja
{{ range is callable }} {{ 'x' is callable }}
```

Output: `True False`

### defined

```json
{"x": 1}
```

```jinja
{{ x is defined }} {{ missing is defined }}
```

Output: `True False`

### divisibleby

```jinja
{{ 9 is divisibleby 3 }} {{ 10 is divisibleby(3) }}
```

Output: `True False`

### eq

```jinja
{{ 1 is eq 1 }} {{ 'a' is equalto 'b' }}
```

Output: `True False`

### escaped

```jinja
{{ 'x'|e is escaped }} {{ 'x' is escaped }}
```

Output: `True False`

### even

```jinja
{{ 4 is even }}
```

Output: `True`

### false

```jinja
{{ false is false }} {{ 0 is false }}
```

Output: `True False`

### filter

```jinja
{{ 'upper' is filter }} {{ 'nope' is filter }}
```

Output: `True False`

### float

```jinja
{{ 1.0 is float }} {{ 1 is float }}
```

Output: `True False`

### ge

```jinja
{{ 2 is ge 2 }}
```

Output: `True`

### gt

```jinja
{{ 3 is gt 2 }} {{ 3 is greaterthan 5 }}
```

Output: `True False`

### in

```jinja
{{ 2 is in [1, 2] }} {{ 'b' is in 'abc' }}
```

Output: `True True`

### integer

```jinja
{{ 1 is integer }} {{ true is integer }}
```

Output: `True False`

### iterable

```jinja
{{ 'ab' is iterable }} {{ 5 is iterable }}
```

Output: `True False`

### le

```jinja
{{ 1 is le 1 }}
```

Output: `True`

### lower

```jinja
{{ 'abc' is lower }} {{ 'aBc' is lower }}
```

Output: `True False`

### lt

```jinja
{{ 1 is lt 2 }}
```

Output: `True`

### mapping

```jinja
{{ {} is mapping }} {{ [] is mapping }}
```

Output: `True False`

### ne

```jinja
{{ 1 is ne 2 }}
```

Output: `True`

### none

```jinja
{{ none is none }} {{ 0 is none }}
```

Output: `True False`

### number

```jinja
{{ 1.5 is number }} {{ '1' is number }}
```

Output: `True False`

### odd

```jinja
{{ 3 is odd }}
```

Output: `True`

### sameas

```json
{"x": false}
```

```jinja
{{ none is sameas none }} {{ x is sameas false }}
```

Output: `True True`

### sequence

```jinja
{{ 'ab' is sequence }} {{ 5 is sequence }}
```

Output: `True False`

### string

```jinja
{{ 'a' is string }} {{ 1 is string }}
```

Output: `True False`

### test

```jinja
{{ 'odd' is test }}
```

Output: `True`

### true

```jinja
{{ true is true }} {{ 1 is true }}
```

Output: `True False`

### undefined

```jinja
{{ missing is undefined }}
```

Output: `True`

### upper

```jinja
{{ 'ABC' is upper }}
```

Output: `True`
