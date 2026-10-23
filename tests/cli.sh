#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables below are exported through -v
# Tests for the bash side: variable export, options, CLI.
#
# Usage: tests/cli.sh [-a AWK]
set -u
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
root=${here%/*}
# shellcheck disable=SC1091
source "$root/jinja.sh"

while getopts a: opt; do
	case $opt in
	a) export JINJA_AWK=$OPTARG ;;
	*) exit 2 ;;
	esac
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0

# check NAME EXPECTED COMMAND...
check() {
	local _t_name=$1 _t_want=$2 _t_got
	shift 2
	_t_got=$("$@" 2>&1; printf x)
	_t_got=${_t_got%x}
	if [[ $_t_got == "$_t_want" ]]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n  want: %q\n  got:  %q\n' "$_t_name" "$_t_want" "$_t_got"
	fi
}

# check_rc NAME RC COMMAND...
check_rc() {
	local _t_name=$1 _t_want=$2 _t_rc
	shift 2
	"$@" >/dev/null 2>&1
	_t_rc=$?
	if ((_t_rc == _t_want)); then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL %s: rc=%d, want %d\n' "$_t_name" "$_t_rc" "$_t_want"
	fi
}

# --- bash variables (used through -v)
name="World"
declare -i count=41
list=(a "b c" $'d\te' 'f\g')
declare -A map=([zeta]=1 [alpha]=2 [mid]=$'x\ny')
app_host=localhost
app_port=8080
declare -n ref=name
empty=

check scalar 'Hello World' jinja_render_string -v name 'Hello {{ name }}'
check integer '42 True' jinja_render_string -v count '{{ count + 1 }} {{ count is integer }}'
check array "4 b c|['a', 'b c', 'd\\te', 'f\\\\g']" jinja_render_string -v list '{{ list|length }} {{ list[1] }}|{{ list }}'
check assoc "alpha=2 mid=x
y zeta=1 " jinja_render_string -v map '{% for k, v in map.items() %}{{ k }}={{ v }} {% endfor %}'
check glob 'localhost:8080' jinja_render_string -v 'app_*' '{{ app_host }}:{{ app_port }}'
check nameref 'World' jinja_render_string -v ref '{{ ref }}'
check empty '[]' jinja_render_string -v empty '[{{ empty }}]'
check inline_str 'World a=b []' jinja_render_string -v name=World -v 'eq=a=b' -v e= '{{ name }} {{ eq }} [{{ e }}]'
check inline_list "['web1', 'web 2'] []" jinja_render_string -v 'hosts=(web1 "web 2")' -v 'nil=()' '{{ hosts }} {{ nil }}'
check inline_dict "{'name': 'alice', 'role': 'x y'}" jinja_render_string -v 'user=([role]="x y" [name]=alice)' '{{ user }}'
check inline_long "['1', '2']" jinja_render_string --var='l=(1 2)' '{{ l }}'
check inline_bad 'jinja: -v 1x=a: invalid variable name
' jinja_render_string -v '1x=a' 'x'
check int '8081 True -3' jinja_render_string -i port=8080 --int=neg=-3 '{{ port + 1 }} {{ port is integer }} {{ neg }}'
check int_bad "jinja: -i expects NAME=INTEGER, got 'n=1.5'
" jinja_render_string -i n=1.5 'x'
check special_chars $'a\\b\tc\nd' jinja_render_string -D $'v=a\\b\tc\nd' '{{ v }}'
check unset_var 'jinja: -v nope_not_set: variable is not set
' jinja_render_string -v nope_not_set 'x'

# --- other sources and priority
export JINJA_TEST_ENV=from-env
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

# --- options
check trim 'a
' jinja_render_string --trim-blocks --keep-trailing-newline $'{% if 1 %}\na\n{% endif %}\n'
check autoescape '&lt;b&gt;' jinja_render_string --autoescape -D 'v=<b>' '{{ v }}'
check strict "jinja: <template>:1: UndefinedError: 'x' is undefined
" jinja_render_string --strict '{{ x }}'
check ext_loop '01' jinja_render_string --ext loopcontrols '{% for i in range(5) %}{% if i > 1 %}{% break %}{% endif %}{{ i }}{% endfor %}'

# --- CLI
check cli_string '6' "$root/bin/jinja" -s '{{ 2 * 3 }}'
check cli_stdin 'hi you' bash -c "printf 'hi {{ who }}' | '$root/bin/jinja' -D who=you -"
check cli_file 'part|shared' "$root/bin/jinja" -I "$tmp/other" "$tmp/tpl/main.j2"
check cli_version "jinja $JINJA_VERSION
" "$root/bin/jinja" --version
check_rc cli_help 0 "$root/bin/jinja" --help
check cli_direct 'ok' "$root/jinja.sh" -s 'ok'

printf '%d passed, %d failed (cli, %s)\n' "$pass" "$fail" "${JINJA_AWK:-awk}"
((fail == 0))
