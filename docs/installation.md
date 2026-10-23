# Installation

## Requirements

- a **POSIX shell**: bash 3.2+, dash, busybox sh, ksh93, mksh, posh and zsh are tested. Exporting
  integers and arrays with `-v NAME` needs bash (associative arrays: bash 4,
  namerefs: bash 4.3); other shells export strings.
- a **POSIX awk**: gawk, mawk, busybox awk and BWK awk (macOS, BSD) are
  tested

Besides awk, only shell builtins are used at render time, plus `cat` for a
template read from stdin (`jinja -`) and `mktemp` for `dist/jinja.sh` on
systems without `/dev/fd` (FreeBSD without fdescfs).

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
git clone https://github.com/MickaelBlet/sh_jinja.git
. sh_jinja/jinja.sh           # library
sh_jinja/bin/jinja --help     # command line
```

`jinja.sh` loads the awk engine from `lib/awk/`, next to itself, and the bash
additions from `lib/bash.sh`. bash and zsh find this directory when they
source `jinja.sh`; other shells cannot know the path of a sourced file, so
set `JINJA_LIB` first (or use the single file below):

```sh
JINJA_LIB=/opt/sh_jinja/lib
. /opt/sh_jinja/jinja.sh
```

The library and `bin/jinja` can be called from any directory. `bin/jinja` can also be
symlinked into your `PATH`.

## Single file

`tools/build.sh` writes `dist/jinja.sh`, which embeds the awk engine. Copy
this one file wherever you need it:

```bash
tools/build.sh                 # -> dist/jinja.sh
tools/build.sh /usr/local/lib/jinja.sh
```

`dist/jinja.sh` works like `jinja.sh` in any shell, without `JINJA_LIB`:
source it as a library, or run it directly as a command
(`dist/jinja.sh -s '{{ 1 + 1 }}'`). Run by bash or zsh it acts as a command
under any name; run by another shell, the file must be named `jinja.sh` or
`jinja`, since it cannot otherwise tell being run from being sourced.
