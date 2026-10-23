# shellcheck shell=bash
# shellcheck disable=SC2034  # variables below are exported through -v
# bash-only part of tests/cli.sh (lib/bash.sh): integers, arrays, namerefs.

declare -i count=41
list=(a "b c" $'d\te' 'f\g')
nil=()
check integer '42 True' jinja_render_string -v count '{{ count + 1 }} {{ count is integer }}'
check array "4 b c|['a', 'b c', 'd\\te', 'f\\\\g']" jinja_render_string -v list '{{ list|length }} {{ list[1] }}|{{ list }}'
check array_empty '[]' jinja_render_string -v nil '{{ nil }}'
app_list=(x y)
check glob_array "['x', 'y'] localhost" jinja_render_string -v 'app_*' '{{ app_list }} {{ app_host }}'
unset app_list
if ((BASH_VERSINFO[0] >= 4)); then
	declare -A map=([zeta]=1 [alpha]=2 [mid]=$'x\ny' ['k]"']=q)
	check assoc "alpha=2 k]\"=q mid=x
y zeta=1 " jinja_render_string -v map '{% for k, v in map.items() %}{{ k }}={{ v }} {% endfor %}'
fi
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
	declare -n ref=name
	declare -n badref=nope_not_set
	check nameref 'World' jinja_render_string -v ref '{{ ref }}'
	check nameref_unset 'jinja: -v badref: referenced variable "nope_not_set" is not set
' jinja_render_string -v badref 'x'
fi

# function-local variables of the caller are visible
_t_local() {
	local title=$1
	jinja_render_string -v title '{{ title }}'
}
check local_var 'Hi' _t_local Hi
