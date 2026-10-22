# Installation

## Requirements

- **bash 4.3** or newer (namerefs and associative arrays are used)
- a **POSIX awk**: gawk, mawk and busybox awk are tested

No other command is needed at render time.

gawk is used by default when it is installed, otherwise `awk`. Set
`JINJA_AWK` to choose another one:

```bash
JINJA_AWK=mawk jinja_render page.j2
JINJA_AWK="busybox awk" jinja_render page.j2
```

mawk, the default `awk` on Debian and Ubuntu, limits recursion depth (see
[differences](differences.md#awk-implementations)).

## From the repository

```bash
git clone https://github.com/MickaelBlet/bash_jinja.git
source bash_jinja/jinja.sh      # library
bash_jinja/bin/jinja --help     # command line
```

`jinja.sh` loads the awk engine from `lib/awk/`, next to itself. The library
and `bin/jinja` can be called from any directory. `bin/jinja` can also be
symlinked into your `PATH`.

## Single file

`tools/build.sh` writes `dist/jinja.sh`, which embeds the awk engine. Copy
this one file wherever you need it:

```bash
tools/build.sh                 # -> dist/jinja.sh
tools/build.sh /usr/local/lib/jinja.sh
```

`dist/jinja.sh` works like `jinja.sh`: source it as a library, or run it
directly as a command (`dist/jinja.sh -s '{{ 1 + 1 }}'`).
