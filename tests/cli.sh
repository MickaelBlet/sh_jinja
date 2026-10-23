#!/bin/sh
# shellcheck disable=SC2034  # variables below are exported through -v
# Tests for the shell side: variable export, options, CLI.
#
# Usage: tests/cli.sh [-s SHELL] [-a AWK]
#   -s SHELL   shell that runs the tests, bin/jinja and jinja.sh (default sh);
#              "busybox sh" is accepted
# Environment: JINJA_SH selects the library to test (e.g. dist/jinja.sh)
set -u
while getopts a:s: opt; do
	case $opt in
	a) JINJA_AWK=$OPTARG && export JINJA_AWK ;;
	s) shell=$OPTARG ;;
	*) exit 2 ;;
	esac
done
if [ -n "${shell:-}" ] && [ -z "${_JINJA_TEST_SHELL:-}" ]; then
	_JINJA_TEST_SHELL=$shell && export _JINJA_TEST_SHELL
	# shellcheck disable=SC2086
	exec $shell "$0"
fi
sh=${_JINJA_TEST_SHELL:-sh}

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=${here%/*}
# only bash and zsh can find lib/ next to a sourced jinja.sh
[ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] || JINJA_LIB=$root/lib
# shellcheck disable=SC1090,SC1091
. "${JINJA_SH:-$root/jinja.sh}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
nl='
'
tab=$(printf '\t')

# check NAME EXPECTED COMMAND...
check() {
	_t_name=$1 _t_want=$2
	shift 2
	_t_got=$("$@" 2>&1; printf x)
	_t_got=${_t_got%x}
	if [ "$_t_got" = "$_t_want" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n  want: [%s]\n  got:  [%s]\n' "$_t_name" "$_t_want" "$_t_got"
	fi
}

# check_rc NAME RC COMMAND...
check_rc() {
	_t_name=$1 _t_want=$2
	shift 2
	"$@" >/dev/null 2>&1
	_t_rc=$?
	if [ "$_t_rc" -eq "$_t_want" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL %s: rc=%d, want %d\n' "$_t_name" "$_t_rc" "$_t_want"
	fi
}

# --- shell variables (used through -v)
name="World"
app_host=localhost
app_port=8080
empty=
special="a\\b${tab}c${nl}d"

check scalar 'Hello World' jinja_render_string -v name 'Hello {{ name }}'
check scalar_special "a\\b${tab}c${nl}d" jinja_render_string -v special '{{ special }}'
big="x\\${tab}y${nl}${nl}"
while [ ${#big} -le 5000 ]; do big=$big$big; done
big=$big$nl
check scalar_big "$big|${#big}" jinja_render_string -v big -i n=${#big} '{{ big }}|{{ n }}'
check glob 'localhost:8080' jinja_render_string -v 'app_*' '{{ app_host }}:{{ app_port }}'
check glob_none "jinja: -v nope_*: no variable matches
" jinja_render_string -v 'nope_*' 'x'
check empty '[]' jinja_render_string -v empty '[{{ empty }}]'
check bad_name "jinja: -v a-b: invalid variable name
" jinja_render_string -v a-b 'x'
check unset_var 'jinja: -v nope_not_set: variable is not set
' jinja_render_string -v nope_not_set 'x'
if [ -n "${BASH_VERSION:-}" ]; then
	# shellcheck source=tests/cli_bash.sh
	. "$here/cli_bash.sh"
fi

# --- inline values
check inline_str 'World a=b []' jinja_render_string -v name=World -v 'eq=a=b' -v e= '{{ name }} {{ eq }} [{{ e }}]'
check inline_list "['web1', 'web 2'] []" jinja_render_string -v 'hosts=(web1 "web 2")' -v 'nil=()' '{{ hosts }} {{ nil }}'
check inline_dict "{'name': 'alice', 'role': 'x y'}" jinja_render_string -v 'user=([role]="x y" [name]=alice)' '{{ user }}'
check inline_long "['1', '2']" jinja_render_string --var='l=(1 2)' '{{ l }}'
check inline_bad 'jinja: -v 1x=a: invalid variable name
' jinja_render_string -v '1x=a' 'x'
check inline_quotes "['a b', 'c\"d', '\$x', 'e\\\\f', 'gh', '', 'i\\\\j']" jinja_render_string -v "l=('a b' \"c\\\"d\" \"\\\$x\" 'e\\f' g\\h '' \"i\\j\")" '{{ l }}'
# shellcheck disable=SC2016  # literal $ and backquotes on purpose
check inline_noexpand "['\$HOME', '\$(id)', '\`id\`']" jinja_render_string -v 'l=($HOME $(id) `id`)' '{{ l }}'
check inline_multiline "['a', 'b', 'c']" jinja_render_string -v "l=(${nl}  a${nl}  b${tab}c${nl})" '{{ l }}'
check inline_dict_keys "{'a b': '1', 'k': '3', 'z': ''}" jinja_render_string -v 'm=( [k]=1 ["a b"]=1 [z]= [k]=3 )' '{{ m }}'
check inline_not_array "(a b c" jinja_render_string -v 's=(a b c' '{{ s }}'
check inline_unterminated "jinja: -v l:2: ValueError: unterminated quote
" jinja_render_string -v "l=(a${nl}\"b)" 'x'
check inline_dict_bad "jinja: -v m:1: ValueError: expected [KEY]=VALUE
" jinja_render_string -v 'm=([a]=1 b)' 'x'
check inline_dict_empty_key "jinja: -v m:1: ValueError: empty key
" jinja_render_string -v 'm=([]=1)' 'x'
check int '8081 True -3' jinja_render_string -i port=8080 --int=neg=-3 '{{ port + 1 }} {{ port is integer }} {{ neg }}'
check int_bad "jinja: -i expects NAME=INTEGER, got 'n=1.5'
" jinja_render_string -i n=1.5 'x'
check int_no_name "jinja: -i expects NAME=INTEGER, got '=1'
" jinja_render_string -i '=1' 'x'
check special_chars "a\\b${tab}c${nl}d" jinja_render_string -D "v=a\\b${tab}c${nl}d" '{{ v }}'

# --- other sources and priority
JINJA_TEST_ENV=from-env && export JINJA_TEST_ENV
check env 'from-env' jinja_render_string -e '{{ JINJA_TEST_ENV }}'
check env_priority 'cli' jinja_render_string -D JINJA_TEST_ENV=cli -e '{{ JINJA_TEST_ENV }}'
check define_order 'b' jinja_render_string -D x=a -D x=b '{{ x }}'
check json_var "3 {'a': [1, None]}" jinja_render_string -J 'n=3' -J 'o={"a": [1, null]}' '{{ n }} {{ o }}'
printf '{"x": "file", "y": 1}\n' >"$tmp/d.json"
printf 'x: yaml\nz: [1, 2]\n' >"$tmp/d.yaml"
check data_merge 'yaml 1 [1, 2]' jinja_render_string -d "$tmp/d.json" -d "$tmp/d.yaml" '{{ x }} {{ y }} {{ z }}'
check data_then_define 'cli' jinja_render_string -d "$tmp/d.json" -D x=cli '{{ x }}'

# --- templates, search path, output
mkdir -p "$tmp/tpl/inc" "$tmp/other"
printf '{%% include "inc/part.j2" %%}|{%% include "shared.j2" %%}\n' >"$tmp/tpl/main.j2"
printf 'part' >"$tmp/tpl/inc/part.j2"
printf 'shared' >"$tmp/other/shared.j2"
check search_path 'part|shared' jinja_render -I "$tmp/other" "$tmp/tpl/main.j2"
check string_path 'shared' jinja_render_string -I "$tmp/other" '{% include "shared.j2" %}'
jinja_render -I "$tmp/other" -o "$tmp/out.txt" "$tmp/tpl/main.j2"
check output_file 'part|shared' cat "$tmp/out.txt"
check_rc missing_template 1 jinja_render "$tmp/nope.j2"
check_rc syntax_error 1 jinja_render_string '{% if %}'
check_rc bad_option 2 jinja_render_string --nope 'x'
check_rc no_template 2 jinja_render
check_rc two_templates 2 jinja_render a b
check_rc missing_arg 2 jinja_render_string -D

# --- options
check trim 'a
' jinja_render_string --trim-blocks --keep-trailing-newline "{% if 1 %}${nl}a${nl}{% endif %}${nl}"
check autoescape '&lt;b&gt;' jinja_render_string --autoescape -D 'v=<b>' '{{ v }}'
check strict "jinja: <template>:1: UndefinedError: 'x' is undefined
" jinja_render_string --strict '{{ x }}'
check ext_loop '01' jinja_render_string --ext loopcontrols '{% for i in range(5) %}{% if i > 1 %}{% break %}{% endif %}{{ i }}{% endfor %}'

# --- the caller's state is left alone
set -- keep1 keep2
REPLY=keep
ifs_before=$IFS
lc_before=${LC_ALL-unset}
jinja_render_string -D x=1 '{{ x }}' >/dev/null
[ "$IFS" = "$ifs_before" ] && ifs_same=yes || ifs_same=no
check caller_state "keep|$lc_before|keep1 keep2|yes" printf '%s' "$REPLY|${LC_ALL-unset}|$*|$ifs_same"

# --- CLI
# shellcheck disable=SC2086  # $sh may be "busybox sh"
{
	check cli_string '6' $sh "$root/bin/jinja" -s '{{ 2 * 3 }}'
	check cli_stdin 'hi you' $sh -c "printf 'hi {{ who }}' | $sh '$root/bin/jinja' -D who=you -"
	check cli_file 'part|shared' $sh "$root/bin/jinja" -I "$tmp/other" "$tmp/tpl/main.j2"
	check cli_version "jinja $JINJA_VERSION
" $sh "$root/bin/jinja" --version
	check_rc cli_help 0 $sh "$root/bin/jinja" --help
	check_rc cli_extra_arg 2 $sh "$root/bin/jinja" -s x y
	check cli_direct 'ok' $sh "${JINJA_SH:-$root/jinja.sh}" -s 'ok'
	check cli_env_var 'exported' env JINJA_TEST_X=exported $sh "$root/bin/jinja" -v JINJA_TEST_X -s '{{ JINJA_TEST_X }}'
}

printf '%d passed, %d failed (cli, %s, %s)\n' "$pass" "$fail" "$sh" "${JINJA_AWK:-awk}"
[ "$fail" -eq 0 ]
