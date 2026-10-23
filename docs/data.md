# Template data

Variables come from six sources. They are merged in command line order and
later sources win. Environment variables (`-e`) always have the lowest
priority. Like `dict.update`, merging replaces whole top-level values; it
does not merge nested dicts.

```bash
jinja_render -e -d defaults.yaml -d prod.yaml -D env=prod page.j2
# env vars < defaults.yaml < prod.yaml < env=prod
```

## Bash variables: `-v NAME`

| bash | template value |
| --- | --- |
| `x=hello` | `'hello'` (str) |
| `declare -i n=3` | `3` (int) |
| `arr=(a "b c")` | `['a', 'b c']` (list) |
| `declare -A m=([k]=v)` | `{'k': 'v'}` (dict, keys sorted) |
| `declare -n ref=x` | the value of `x`, exported as `ref` |
| `x=` | `''` |

```bash
server_name=example.com
declare -i workers=4
upstreams=(10.0.0.1 10.0.0.2)
declare -A headers=([X-Frame-Options]=DENY [X-Content-Type-Options]=nosniff)

jinja_render_string -v server_name -v workers -v upstreams -v headers \
'server {{ server_name }} ({{ workers * 2 }} conns)
{% for u in upstreams %}upstream {{ loop.index }}: {{ u }}
{% endfor %}{% for k, v in headers.items() %}add_header {{ k }} {{ v }};
{% endfor %}'
```

```text
server example.com (8 conns)
upstream 1: 10.0.0.1
upstream 2: 10.0.0.2
add_header X-Content-Type-Options nosniff;
add_header X-Frame-Options DENY;
```

Notes:

- Values keep every byte: spaces, tabs, newlines and backslashes.
- Only `declare -i` variables become numbers. Other values are strings, so
  use `|int` or `|float` to convert them: `{{ port|int + 1 }}`.
- Bash does not keep the insertion order of associative arrays, so their
  keys are sorted.
- Sparse indexed arrays are compacted: `a[0]=x a[5]=y` gives `['x', 'y']`.
- A glob exports every matching variable: `-v 'app_*'` exports `app_name`,
  `app_port`, ...
- `-v` fails (return code 2) if the variable is not set.
- Local variables of the calling function can be exported:

  ```bash
  render() {
      local title=$1
      jinja_render -v title page.j2
  }
  ```

## Inline values: `-v NAME=VALUE`, `-i NAME=INT`

With `=`, `-v` defines the variable directly, using the bash assignment
syntax, so nothing has to be declared first:

| option | template value |
| --- | --- |
| `-v x=hello` | `'hello'` (str) |
| `-v 'arr=(a "b c")'` | `['a', 'b c']` (list) |
| `-v 'm=([k]=v [x]="y z")'` | `{'k': 'v', 'x': 'y z'}` (dict, keys sorted) |
| `-v 'e=()'` | `[]` |
| `-i n=3` | `3` (int) |

```bash
jinja_render_string -v server_name=example.com -i workers=4 \
  -v 'upstreams=(10.0.0.1 10.0.0.2)' \
  -v 'headers=([X-Frame-Options]=DENY [X-Content-Type-Options]=nosniff)' \
  '{{ server_name }} {{ workers * 2 }} {{ upstreams|join(",") }} {{ headers|length }}'
# example.com 8 10.0.0.1,10.0.0.2 2
```

Notes:

- A value is a list when it starts with `(` and ends with `)`, a dict when
  it also starts with `([`. Anything else is a string.
- List and dict values are evaluated by bash like an assignment: quotes are
  removed and expansions (`$x`, `$(cmd)`) run. Do not pass untrusted input
  as a `(...)` value; use `-D` or `-J` for it.
- `NAME` must be a valid bash identifier.
- `-i` accepts a decimal integer (`-12`, `007` is `7`).

## Strings: `-D KEY=VALUE`

```bash
jinja_render_string -D 'name=World' -D 'greeting=Hi there' '{{ greeting }}, {{ name }}'
```

The value is everything after the first `=`.

## JSON values: `-J KEY=JSON`

```bash
jinja_render_string -J 'cfg={"a": [1, 2]}' -J 'n=3' '{{ cfg.a|sum + n }}'   # 6
```

## Data files: `-d FILE`

The file type comes from its extension: `.json` for JSON, `.yaml` or `.yml`
for YAML. For any other extension, the content is read as JSON if it starts
with `{` or `[`, and as YAML otherwise. The top level must be a mapping; its
keys become variables.

### JSON

Standard JSON, plus `NaN` and `Infinity`. Numbers without a fraction or
exponent are ints, others are floats (`1.0` is a float), as with Python's
`json`. Large integers are printed exactly. `\uXXXX` escapes, including
surrogate pairs, are decoded to UTF-8.

### YAML

The YAML loader follows PyYAML `safe_load` for the common subset:

- block mappings and sequences, including indentless sequences
  (`key:` followed by `- item` at the same indentation)
- flow collections: `[a, b]`, `{a: 1, b: [2, 3]}`
- plain, `'single'` and `"double"` quoted scalars, with escapes and
  multi-line folding
- block scalars `|` and `>` with chomping (`-`, `+`) and indentation
  indicators
- comments, `---` and `...` document markers
- anchors `&name`, aliases `*name` and merge keys `<<: *base`

Values are typed with the YAML 1.1 rules used by PyYAML:

| YAML | value |
| --- | --- |
| `yes`, `no`, `on`, `off`, `true`, `False`, ... | bool |
| `~`, `null`, empty | `none` |
| `42`, `0x1F`, `010` (octal), `0b11`, `1_000`, `1:30` (sexagesimal) | int |
| `1.5`, `.5`, `1.0e+3`, `.inf`, `.nan` | float |
| `1e5` (no dot, no exponent sign) | string |
| `2020-01-02` | string (PyYAML gives a date, which prints the same) |

```yaml
defaults: &defaults
  port: 80
  tags: [web]
services:
  - name: front
    <<: *defaults
  - name: api
    <<: *defaults
    port: 8080
```

```jinja
{% for s in services %}{{ s.name }}:{{ s.port }} {% endfor %}
```

Output: `front:80 api:8080 `

Not supported: tags (`!!str`, `!custom`) are ignored, complex keys (`? `),
multiple documents in one file.

## Environment: `-e`

Every environment variable becomes a string variable:

```bash
jinja_render_string -e '{{ HOME }} {{ USER|default("nobody") }}'
```

Exported bash variables are part of the environment. Non-exported ones need
`-v`.
