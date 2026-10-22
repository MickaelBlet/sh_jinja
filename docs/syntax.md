# Template syntax

A template is text with three kinds of delimiters:

| Delimiter | Purpose |
| --- | --- |
| `{{ ... }}` | expression, its value is printed |
| `{% ... %}` | statement (`if`, `for`, `set`, ...) |
| `{# ... #}` | comment, removed from the output |

```json
{"name": "Ann", "admin": true}
```

```jinja
Hello {{ name }}!{# greeting #}{% if admin %} (admin){% endif %}
```

Output: `Hello Ann! (admin)`

## Printed values

Values are printed with Python's `str()`: `None`, `True`/`False`, lists and dicts in Python notation, floats in their shortest form. Undefined variables print as an empty string (see [strict mode](usage.md#strict-mode)).

```jinja
{{ none }} {{ true }} {{ [1, 'a', none] }} {{ {'k': 1.0} }} {{ 1 / 3 }} {{ 4 / 2 }} [{{ missing }}]
```

Output: `None True [1, 'a', None] {'k': 1.0} 0.3333333333333333 2.0 []`

## Whitespace control

By default whitespace is kept as is, except that **one trailing newline** at the end of the template is removed (use `--keep-trailing-newline` to keep it).

A `-` next to a delimiter strips all whitespace (including newlines) on that side:

```jinja
<ul>
  {%- for i in [1, 2] %}
  <li>{{ i }}</li>
  {%- endfor %}
</ul>
```

Output:

```text
<ul>
  <li>1</li>
  <li>2</li>
</ul>
```

```jinja
a  {{- ' b ' -}}  c
```

Output: `a b c`

### trim_blocks and lstrip_blocks

- `--trim-blocks`: the first newline after a `%}` (or `#}`) is removed.
- `--lstrip-blocks`: spaces and tabs before a `{%` (or `{#`) at the start of a line are removed.

Together they let block tags sit on their own lines:

```jinja
<ul>
    {% for i in [1, 2] %}
    <li>{{ i }}</li>
    {% endfor %}
</ul>
```

Output:

```text
<ul>
    <li>1</li>
    <li>2</li>
</ul>
```

A `+` disables these options for one tag: `{%+ if x %}` keeps the leading whitespace, `{% if x +%}` keeps the newline.

```jinja
    {%+ if true %}kept{% endif %}
    {% if true %}stripped{% endif %}
```

Output:

```text
    kept
stripped
```

## Raw blocks

Nothing inside `{% raw %}...{% endraw %}` is interpreted:

```jinja
{% raw %}{{ not a variable }} {% if %}{% endraw %}
```

Output: `{{ not a variable }} {% if %}`

Single delimiters can also be printed as strings: `{{ '{{' }}`.

## Line numbers and errors

Syntax errors are reported with the template name and line, using Jinja's messages:

```jinja
{% for x in items %}
  {{ x }}
{% endif %}
```

```text
jinja: string:3: TemplateSyntaxError: Encountered unknown tag 'endif'. Jinja was looking for the following tags: 'endfor' or 'else'. The innermost block that needs to be closed is 'for'.
```

Newlines `\r\n` and `\r` are normalized to `\n`.
