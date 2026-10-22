# Globals and methods

## Global functions

Available everywhere (template variables with the same name take precedence).

### `range([start,] stop[, step])`

Python `range`; prints as `range(0, 3)`, iterates as a list.

```jinja
{{ range(3)|list }} {{ range(1, 10, 4)|list }} {{ range(5, 0, -2)|list }}
```

Output: `[0, 1, 2] [1, 5, 9] [5, 3, 1]`

### `dict(**kwargs)`

Build a dict.

```jinja
{{ dict(a=1, b='x') }}
```

Output: `{'a': 1, 'b': 'x'}`

### `namespace(**kwargs)`

Mutable object whose attributes can be assigned with `{% set ns.attr = ... %}`, even from inside loops.

```jinja
{% set ns = namespace(total=0) %}{% for i in [1, 2, 3] %}{% set ns.total = ns.total + i %}{% endfor %}{{ ns.total }}
```

Output: `6`

### `cycler(*items)`

Cycle through values: `.next()`, `.current`, `.reset()`.

```jinja
{% set c = cycler('odd', 'even') %}{{ c.next() }} {{ c.next() }} {{ c.next() }} {{ c.current }}
```

Output: `odd even odd even`

### `joiner(sep=', ')`

Returns `''` on the first call, then `sep`.

```jinja
{% set j = joiner(' | ') %}{% for x in 'abc' %}{{ j() }}{{ x }}{% endfor %}
```

Output: `a | b | c`

### `lipsum(n=5, html=True, min=20, max=100)`

Random lorem ipsum paragraphs (not deterministic).

## `self`

`self.blockname()` renders a block of the current template again.

```jinja
{% block title %}Home{% endblock %} - {{ self.title() }}
```

Output: `Home - Home`

## `loop`

Available inside `for` loops, see [statements](statements.md#for).

## Methods

Values support the common Python methods. Calling a method that returns `None` prints `None`, so use `{% set _ = l.append(x) %}` (or the `do` extension) for in-place changes.

### str

`upper() lower() casefold() title() capitalize() swapcase()`

```jinja
{{ 'hello World'.title() }} {{ 'Ab'.swapcase() }}
```

Output: `Hello World aB`

`strip([chars]) lstrip([chars]) rstrip([chars])`

```jinja
[{{ '  x '.strip() }}] [{{ 'xxaxx'.lstrip('x') }}]
```

Output: `[x] [axx]`

`split(sep=None, maxsplit=-1) rsplit(...) splitlines(keepends=False)`

```jinja
{{ 'a,b,,c'.split(',') }} {{ ' a  b '.split() }} {{ 'a-b-c'.rsplit('-', 1) }}
```

Output: `['a', 'b', '', 'c'] ['a', 'b'] ['a-b', 'c']`

`startswith(prefix) endswith(suffix)`

```jinja
{{ 'abc'.startswith('ab') }} {{ 'abc'.endswith(('x', 'c')) }}
```

Output: `True True`

`find(sub) rfind(sub) index(sub) rindex(sub) count(sub)`

```jinja
{{ 'hello'.find('l') }} {{ 'hello'.rfind('l') }} {{ 'hello'.count('l') }}
```

Output: `2 3 2`

`replace(old, new[, count])`

```jinja
{{ 'hello'.replace('l', 'L', 1) }}
```

Output: `heLlo`

`join(iterable)`

```jinja
{{ '-'.join(['a', 'b', 'c']) }}
```

Output: `a-b-c`

`format(*args, **kwargs) format_map(mapping)`

```jinja
{{ '{} is {:>5.1f}'.format('pi', 3.14159) }} {{ '{name}!'.format(name='hi') }}
```

Output: `pi is   3.1 hi!`

`center(width[, fill]) ljust(...) rjust(...) zfill(width)`

```jinja
[{{ 'x'.center(5, '*') }}] [{{ '42'.zfill(5) }}]
```

Output: `[**x**] [00042]`

`partition(sep) rpartition(sep) removeprefix(p) removesuffix(s) expandtabs(n)`

```jinja
{{ 'a=b=c'.partition('=') }} {{ 'file.txt'.removesuffix('.txt') }}
```

Output: `('a', '=', 'b=c') file`

`isdigit() isalpha() isalnum() isspace() islower() isupper() istitle() isidentifier() ...`

```jinja
{{ '12'.isdigit() }} {{ 'ab1'.isalpha() }}
```

Output: `True False`

### list

`append(x) extend(it) insert(i, x)`

```jinja
{% set l = [1] %}{% set _ = l.append(2) %}{% set _ = l.extend([3, 4]) %}{{ l }}
```

Output: `[1, 2, 3, 4]`

`pop([i]) remove(x) clear()`

```jinja
{% set l = [1, 2, 3] %}{{ l.pop() }} {{ l.pop(0) }} {{ l }}
```

Output: `3 1 [2]`

`index(x) count(x) copy() reverse() sort(reverse=False)`

```jinja
{% set l = [3, 1, 2] %}{{ l.index(1) }} {% set _ = l.sort() %}{{ l }}
```

Output: `1 [1, 2, 3]`

### dict

`items() keys() values()`

```jinja
{% set d = {'a': 1, 'b': 2} %}{{ d.items()|list }} {{ d.keys()|list }} {{ d.values()|list }}
```

Output: `[('a', 1), ('b', 2)] ['a', 'b'] [1, 2]`

`get(key[, default])`

```jinja
{{ {'a': 1}.get('a') }} {{ {'a': 1}.get('z', 'dflt') }}
```

Output: `1 dflt`

`update(...) pop(key[, default]) popitem() setdefault(key[, default]) copy() clear()`

```jinja
{% set d = {'a': 1} %}{% set _ = d.update(b=2) %}{{ d }} {{ d.pop('a') }} {{ d }}
```

Output: `{'a': 1, 'b': 2} 1 {'b': 2}`
