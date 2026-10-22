# Filters

Filters transform a value: `{{ value|filter }}`, `{{ value|filter(arg, key=value) }}`, and can be chained: `{{ name|trim|title }}`. Filter blocks apply a filter to a whole section:

```jinja
{% filter upper %}hello {{ 'you' }}{% endfilter %}
```

Output: `HELLO YOU`

Unknown filter names are a compile-time `TemplateAssertionError`, except inside an `{% if %}` (then the error happens only if the filter is actually used).

## Index

[`abs`](#abs) · [`attr`](#attr) · [`batch`](#batch) · [`capitalize`](#capitalize) · [`center`](#center) · [`default`](#default) · [`dictsort`](#dictsort) · [`escape`](#escape) · [`filesizeformat`](#filesizeformat) · [`first`](#first) · [`float`](#float) · [`forceescape`](#forceescape) · [`format`](#format) · [`groupby`](#groupby) · [`indent`](#indent) · [`int`](#int) · [`items`](#items) · [`join`](#join) · [`last`](#last) · [`length`](#length) · [`list`](#list) · [`lower`](#lower) · [`map`](#map) · [`max`](#max) · [`min`](#min) · [`pprint`](#pprint) · [`random`](#random) · [`reject`](#reject) · [`rejectattr`](#rejectattr) · [`replace`](#replace) · [`reverse`](#reverse) · [`round`](#round) · [`safe`](#safe) · [`select`](#select) · [`selectattr`](#selectattr) · [`slice`](#slice) · [`sort`](#sort) · [`string`](#string) · [`striptags`](#striptags) · [`sum`](#sum) · [`title`](#title) · [`tojson`](#tojson) · [`trim`](#trim) · [`truncate`](#truncate) · [`unique`](#unique) · [`upper`](#upper) · [`urlencode`](#urlencode) · [`urlize`](#urlize) · [`wordcount`](#wordcount) · [`wordwrap`](#wordwrap) · [`xmlattr`](#xmlattr)

## abs

`abs(number)`

Absolute value.

```jinja
{{ -3|abs }} {{ -2.5|abs }}
```

Output: `3 2.5`

## attr

`attr(obj, name)`

Attribute lookup that does not fall back to item lookup (dict keys are not attributes).

```jinja
{{ 'abc'|attr('upper')() }} [{{ {'x': 1}|attr('x') }}]
```

Output: `ABC []`

## batch

`batch(value, linecount, fill_with=None)`

Split a sequence into lists of `linecount` items; the last one is padded with `fill_with` if given.

```jinja
{{ [1, 2, 3, 4, 5]|batch(2)|list }} {{ [1, 2, 3]|batch(2, 'x')|list }}
```

Output: `[[1, 2], [3, 4], [5]] [[1, 2], [3, 'x']]`

## capitalize

`capitalize(s)`

First character uppercase, the rest lowercase.

```jinja
{{ 'hello WORLD'|capitalize }}
```

Output: `Hello world`

## center

`center(value, width=80)`

Center the string in a field of `width` characters.

```jinja
[{{ 'abc'|center(9) }}]
```

Output: `[   abc   ]`

## default

Alias: `d`

`default(value, default_value='', boolean=False)`

Replace an undefined value; with `boolean=true` also replace falsy values.

```jinja
{{ missing|default('none') }} {{ ''|d('empty', true) }} {{ 0|default(5) }}
```

Output: `none empty 0`

## dictsort

`dictsort(value, case_sensitive=False, by='key', reverse=False)`

Sort a dict and return a list of `(key, value)` pairs.

```jinja
{{ {'b': 1, 'A': 3, 'c': 2}|dictsort }} {{ {'b': 1, 'a': 2}|dictsort(by='value') }}
```

Output: `[('A', 3), ('b', 1), ('c', 2)] [('b', 1), ('a', 2)]`

## escape

Alias: `e`

`escape(s)`

HTML-escape `& < > " '` and mark the result safe.

```jinja
{{ '<a href="x">&</a>'|e }}
```

Output: `&lt;a href=&#34;x&#34;&gt;&amp;&lt;/a&gt;`

## filesizeformat

`filesizeformat(value, binary=False)`

Human readable file size (decimal kB/MB/... or binary KiB/MiB/...).

```jinja
{{ 1000|filesizeformat }} {{ 123456789|filesizeformat }} {{ 1536|filesizeformat(true) }}
```

Output: `1.0 kB 123.5 MB 1.5 KiB`

## first

`first(seq)`

First item (undefined if empty).

```jinja
{{ [3, 1, 2]|first }} {{ 'abc'|first }}
```

Output: `3 a`

## float

`float(value, default=0.0)`

Convert to float, `default` if impossible.

```jinja
{{ '3.5'|float }} {{ 'x'|float }} {{ 3|float }}
```

Output: `3.5 0.0 3.0`

## forceescape

`forceescape(value)`

HTML-escape even values already marked safe.

```jinja
{{ '<b>'|safe|forceescape }}
```

Output: `&lt;b&gt;`

## format

`format(value, *args, **kwargs)`

printf-style formatting (`value % args`).

```jinja
{{ '%s-%05.1f|%x'|format('a', 3.14159, 255) }} {{ '%(n)s!'|format(n='hi') }}
```

Output: `a-003.1|ff hi!`

## groupby

`groupby(value, attribute, default=None)`

Sort by `attribute` and group; yields `(grouper, list)` tuples (also usable as `.grouper` / `.list`).

```json
{"users": [{"name": "a", "city": "NY"}, {"name": "b", "city": "LA"}, {"name": "c", "city": "NY"}]}
```

```jinja
{% for city, items in users|groupby('city') %}{{ city }}: {{ items|map(attribute='name')|join(', ') }}; {% endfor %}
```

Output: `LA: b; NY: a, c; `

## indent

`indent(s, width=4, first=False, blank=False)`

Indent every line but the first (and blank lines) by `width` spaces or by the string `width`.

```jinja
{{ 'a\nb\n\nc'|indent(2) }}
```

Output:

```text
a
  b

  c
```

## int

`int(value, default=0, base=10)`

Convert to integer; strings may use base prefixes (`0x`, `0o`, `0b`).

```jinja
{{ '42'|int }} {{ '42.7'|int }} {{ 'x'|int(-1) }} {{ '0x1A'|int(0, 16) }} {{ 3.9|int }}
```

Output: `42 42 -1 26 3`

## items

`items(value)`

List of `(key, value)` pairs of a mapping (Jinja 3.1 filter).

```jinja
{% for k, v in {'a': 1, 'b': 2}|items %}{{ k }}={{ v }} {% endfor %}
```

Output: `a=1 b=2 `

## join

`join(value, d='', attribute=None)`

Concatenate items with separator `d`, optionally an attribute of each item.

```json
{"users": [{"name": "a"}, {"name": "b"}]}
```

```jinja
{{ [1, 2, 3]|join('|') }} {{ users|join(', ', attribute='name') }}
```

Output: `1|2|3 a, b`

## last

`last(seq)`

Last item (undefined if empty).

```jinja
{{ [3, 1, 2]|last }}
```

Output: `2`

## length

Alias: `count`

`length(obj)`

Number of items (characters for strings).

```jinja
{{ [1, 2]|length }} {{ 'héllo'|length }} {{ {'a': 1}|count }}
```

Output: `2 5 1`

## list

`list(value)`

Convert to a list (a string gives its characters).

```jinja
{{ 'abc'|list }} {{ {'a': 1}|list }}
```

Output: `['a', 'b', 'c'] ['a']`

## lower

`lower(s)`

Lowercase.

```jinja
{{ 'ÉCOLE Abc'|lower }}
```

Output: `école abc`

## map

`map(value, filter, *args) / map(attribute=..., default=...)`

Apply a filter to each item, or extract an attribute.

```json
{"users": [{"name": "x", "age": 3}, {"name": "y"}]}
```

```jinja
{{ ['a', 'b']|map('upper')|join }} {{ users|map(attribute='name')|join(',') }} {{ users|map(attribute='age', default='?')|list }}
```

Output: `AB x,y [3, '?']`

## max

`max(value, case_sensitive=False, attribute=None)`

Largest item.

```json
{"users": [{"age": 3}, {"age": 7}]}
```

```jinja
{{ [3, 1, 2]|max }} {{ ['b', 'A', 'c']|max }} {{ users|max(attribute='age') }}
```

Output: `3 c {'age': 7}`

## min

`min(value, case_sensitive=False, attribute=None)`

Smallest item.

```jinja
{{ [3, 1, 2]|min }} {{ ['b', 'A', 'c']|min(case_sensitive=true) }}
```

Output: `1 A`

## pprint

`pprint(value)`

Pretty print (Python `pprint.pformat`, sorted dict keys).

```jinja
{{ {'b': 1, 'a': [1, 2]}|pprint }}
```

Output: `{'a': [1, 2], 'b': 1}`

## random

`random(seq)`

Random item (not deterministic).

## reject

`reject(value, test, *args)`

Drop items for which the test succeeds (or that are truthy if no test).

```jinja
{{ [1, 2, 3, 4]|reject('odd')|list }} {{ [0, 1, '', 'x']|reject|list }}
```

Output: `[2, 4] [0, '']`

## rejectattr

`rejectattr(value, attribute, test, *args)`

Drop items whose attribute passes the test (or is truthy).

```json
{"users": [{"name": "a", "active": true}, {"name": "b", "active": false}]}
```

```jinja
{{ users|rejectattr('active')|map(attribute='name')|list }}
```

Output: `['b']`

## replace

`replace(s, old, new, count=None)`

Replace occurrences of `old` (at most `count`).

```jinja
{{ 'aaa'|replace('a', 'b', 2) }} {{ 'Hello World'|replace('Hello', 'Bye') }}
```

Output: `bba Bye World`

## reverse

`reverse(value)`

Reversed string or sequence.

```jinja
{{ 'abc'|reverse }} {{ [1, 2, 3]|reverse|list }}
```

Output: `cba [3, 2, 1]`

## round

`round(value, precision=0, method='common')`

Round to `precision` digits; `method` is `common` (half to even like Python), `ceil` or `floor`. Always returns a float for floats.

```jinja
{{ 42.55|round }} {{ 42.55|round(1, 'floor') }} {{ 2.5|round }} {{ 42.51|round(0, 'ceil') }}
```

Output: `43.0 42.5 2.0 43.0`

## safe

`safe(value)`

Mark as safe: not escaped when autoescaping.

```jinja
{{ '<b>'|safe }}
```

Output: `<b>`

## select

`select(value, test, *args)`

Keep items for which the test succeeds (or that are truthy).

```jinja
{{ [1, 2, 3, 4]|select('odd')|list }} {{ range(10)|select('divisibleby', 3)|list }}
```

Output: `[1, 3] [0, 3, 6, 9]`

## selectattr

`selectattr(value, attribute, test, *args)`

Keep items whose attribute passes the test (or is truthy).

```json
{"users": [{"name": "a", "age": 10}, {"name": "b", "age": 20}]}
```

```jinja
{{ users|selectattr('age', 'gt', 18)|map(attribute='name')|list }}
```

Output: `['b']`

## slice

`slice(value, slices, fill_with=None)`

Split into `slices` columns.

```jinja
{{ [1, 2, 3, 4, 5]|slice(3)|list }}
```

Output: `[[1, 2], [3, 4], [5]]`

## sort

`sort(value, reverse=False, case_sensitive=False, attribute=None)`

Stable sort; `attribute` may be dotted and comma separated (`'age,name'`).

```json
{"users": [{"name": "c", "age": 2}, {"name": "a", "age": 2}, {"name": "b", "age": 1}]}
```

```jinja
{{ [3, 1, 2]|sort }} {{ ['b', 'A', 'c']|sort }} {{ users|sort(attribute='age,name')|map(attribute='name')|join }}
```

Output: `[1, 2, 3] ['A', 'b', 'c'] bac`

## string

`string(value)`

Convert to string (keeps safe strings safe).

```jinja
{{ [1, 'a']|string }} {{ none|string }}
```

Output: `[1, 'a'] None`

## striptags

`striptags(value)`

Remove SGML/XML tags and comments, collapse whitespace, unescape entities.

```jinja
{{ '<p>Hello  <b>world</b></p> &amp; more'|striptags }}
```

Output: `Hello world & more`

## sum

`sum(iterable, attribute=None, start=0)`

Sum of the items (or of an attribute).

```json
{"items": [{"price": 1.5}, {"price": 2}]}
```

```jinja
{{ [1, 2, 3]|sum }} {{ items|sum(attribute='price') }}
```

Output: `6 3.5`

## title

`title(s)`

Titlecase each word.

```jinja
{{ 'hello wORLD-foo'|title }}
```

Output: `Hello World-Foo`

## tojson

`tojson(value, indent=None)`

Serialize to JSON with sorted keys, HTML-safe (`<`, `>`, `&`, `'` escaped).

```jinja
{{ {'b': [1, none], 'a': '<x>'}|tojson }}
```

Output: `{"a": "\u003cx\u003e", "b": [1, null]}`

## trim

`trim(value, chars=None)`

Strip leading/trailing whitespace or `chars`.

```jinja
[{{ '  x  '|trim }}] [{{ 'xxaxx'|trim('x') }}]
```

Output: `[x] [a]`

## truncate

`truncate(s, length=255, killwords=False, end='...', leeway=5)`

Truncate to `length` characters, at a word boundary unless `killwords`; strings exceeding by at most `leeway` are kept.

```jinja
{{ 'foo bar baz qux'|truncate(9) }} {{ 'foo bar baz qux'|truncate(9, true) }} {{ 'foo bar baz qux'|truncate(11) }}
```

Output: `foo... foo ba... foo bar baz qux`

## unique

`unique(value, case_sensitive=False, attribute=None)`

Remove duplicates, keeping the first occurrence.

```jinja
{{ ['a', 'B', 'b', 'A', 'c']|unique|list }}
```

Output: `['a', 'B', 'c']`

## upper

`upper(s)`

Uppercase.

```jinja
{{ 'élan vital'|upper }}
```

Output: `ÉLAN VITAL`

## urlencode

`urlencode(value)`

URL-quote a string (`/` kept) or build a query string from a dict / pairs.

```jinja
{{ 'a b/c?d'|urlencode }} {{ {'q': 'x y', 'n': 1}|urlencode }}
```

Output: `a%20b/c%3Fd q=x+y&n=1`

## urlize

`urlize(value, trim_url_limit=None, nofollow=False, target=None, rel=None, extra_schemes=None)`

Turn URLs and e-mail addresses into links (`rel="noopener"` by default).

```jinja
{{ 'see http://example.com and me@ex.com'|urlize }}
```

Output: `see <a href="http://example.com" rel="noopener">http://example.com</a> and <a href="mailto:me@ex.com">me@ex.com</a>`

## wordcount

`wordcount(s)`

Number of words.

```jinja
{{ 'one two  three'|wordcount }}
```

Output: `3`

## wordwrap

`wordwrap(s, width=79, break_long_words=True, wrapstring=None, break_on_hyphens=True)`

Wrap text (Python `textwrap`), paragraphs wrapped separately.

```jinja
{{ 'The quick brown fox jumps over the lazy dog'|wordwrap(15) }}
```

Output:

```text
The quick brown
fox jumps over
the lazy dog
```

## xmlattr

`xmlattr(d, autospace=True)`

Build an escaped SGML/XML attribute string; `none`/undefined values are skipped.

```jinja
<ul{{ {'class': 'nav', 'id': 'x<y', 'hidden': none}|xmlattr }}>
```

Output: `<ul class="nav" id="x&lt;y">`
