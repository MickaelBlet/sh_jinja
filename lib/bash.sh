# shellcheck shell=bash
# lib/bash.sh - bash additions to jinja.sh, loaded when it runs in bash.
#
# -v NAME also exports integers (declare -i), indexed arrays (list),
# associative arrays (dict, bash >= 4) and follows namerefs (bash >= 4.3).
# Works with bash >= 3.2: no namerefs or associative arrays are used here.

# faster than the POSIX loop
_jinja_esc() {
	_jinja_r=${1//\\/\\\\}
	_jinja_r=${_jinja_r//$'\n'/\\n}
	_jinja_r=${_jinja_r//$'\t'/\\t}
}

# append the records of bash variable $1
_jinja_add_var() {
	local _jinja_name=$1 _jinja_as=$1 _jinja_decl _jinja_flags _jinja_ename _jinja_v _jinja_n _jinja_i
	local -a _jinja_keys _jinja_vals _jinja_kv
	_jinja_isname "$_jinja_name" || { _jinja_err "-v $_jinja_name: invalid variable name"; return; }
	_jinja_decl=$(declare -p "$_jinja_name" 2>/dev/null) || {
		_jinja_err "-v $_jinja_name: variable is not set"
		return
	}
	_jinja_flags=${_jinja_decl#declare -}
	_jinja_flags=${_jinja_flags%% *}
	if [[ $_jinja_flags == *n* ]]; then
		# nameref: export the referenced value under this name
		_jinja_name=${_jinja_decl#*=\"}
		_jinja_name=${_jinja_name%\"}
		_jinja_decl=$(declare -p "$_jinja_name" 2>/dev/null) || {
			_jinja_err "-v $_jinja_as: referenced variable \"$_jinja_name\" is not set"
			return
		}
		_jinja_flags=${_jinja_decl#declare -}
		_jinja_flags=${_jinja_flags%% *}
	fi
	_jinja_esc "$_jinja_as"
	_jinja_ename=$_jinja_r
	if [[ $_jinja_flags == *[aA]* ]]; then
		# keys and values come in the same order; escape them all at once
		eval "_jinja_n=\${#${_jinja_name}[@]}"
		if [[ $_jinja_flags == *A* ]]; then
			_jinja_buf+="A	$_jinja_ename	$_jinja_n"$'\n'
		else
			_jinja_buf+="L	$_jinja_ename	$_jinja_n"$'\n'
		fi
		# bash < 4.4: "${a[@]}" of an empty array is unset under set -u
		((_jinja_n)) || return 0
		eval "_jinja_keys=(\"\${!${_jinja_name}[@]}\")"
		eval "_jinja_vals=(\"\${${_jinja_name}[@]}\")"
		_jinja_vals=("${_jinja_vals[@]//\\/\\\\}")
		_jinja_vals=("${_jinja_vals[@]//$'\n'/\\n}")
		_jinja_vals=("${_jinja_vals[@]//$'\t'/\\t}")
		if [[ $_jinja_flags == *A* ]]; then
			_jinja_keys=("${_jinja_keys[@]//\\/\\\\}")
			_jinja_keys=("${_jinja_keys[@]//$'\n'/\\n}")
			_jinja_keys=("${_jinja_keys[@]//$'\t'/\\t}")
			for ((_jinja_i = 0; _jinja_i < _jinja_n; _jinja_i++)); do
				_jinja_kv+=("${_jinja_keys[_jinja_i]}" "${_jinja_vals[_jinja_i]}")
			done
			printf -v _jinja_r 'K\t%s\t%s\n' "${_jinja_kv[@]}"
		else
			printf -v _jinja_r 'E\t%s\n' "${_jinja_vals[@]}"
		fi
		_jinja_buf+=$_jinja_r
	elif [[ $_jinja_flags == *i* ]]; then
		eval "_jinja_v=\$$_jinja_name"
		_jinja_buf+="I	$_jinja_ename	$_jinja_v"$'\n'
	else
		eval "_jinja_v=\${$_jinja_name-}"
		_jinja_esc "$_jinja_v"
		_jinja_buf+="S	$_jinja_ename	$_jinja_r"$'\n'
	fi
}
