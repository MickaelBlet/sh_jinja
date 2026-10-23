#!/usr/bin/env bash
# jinja.sh - render Jinja2 templates from bash (bash >= 4.3 + POSIX awk).
#
#   source jinja.sh
#   jinja_render [options] TEMPLATE        render a template file
#   jinja_render_string [options] SOURCE   render a template given as a string
#
# Options:
#   -d, --data FILE         load variables from a .json/.yaml/.yml file
#   -v, --var NAME          export the bash variable NAME (scalar, -i integer,
#                           indexed array -> list, associative array -> dict);
#                           NAME may be a glob pattern ('app_*')
#   -v, --var NAME=VALUE    define NAME without declaring it: '(a b)' -> list,
#                           '([k]=v ...)' -> dict, anything else -> string
#   -i, --int NAME=INT      define an integer variable
#   -D, --define KEY=VALUE  define a string variable
#   -J, --json KEY=JSON     define a variable from a JSON value
#   -e, --env               expose environment variables as variables
#   -I, --path DIR          add DIR to the template search path
#   -o, --output FILE       write the result to FILE
#       --strict            undefined variables raise an error
#       --trim-blocks       remove the first newline after a block tag
#       --lstrip-blocks     strip whitespace before a block tag on its line
#       --keep-trailing-newline
#       --autoescape        HTML-escape variable output
#       --ext NAME          enable an extension: loopcontrols, do
#
# Sources are merged in command line order (later wins); environment
# variables (-e) have the lowest priority.
# Environment: JINJA_AWK selects the awk implementation (default: gawk when
# installed, else awk).

# shellcheck disable=SC2034
JINJA_VERSION=0.1.0

if [[ -z ${_JINJA_LIB:-} ]]; then
	_JINJA_LIB=${BASH_SOURCE[0]%/*}
	[[ $_JINJA_LIB == "${BASH_SOURCE[0]}" ]] && _JINJA_LIB=.
	_JINJA_LIB=$(cd "$_JINJA_LIB" && pwd)/lib/awk
fi

_JINJA_AWK_FILES=(value utf8 lexer parser runtime filters tests builtins json yaml main)

# escape a protocol value: backslash, newline, tab
_jinja_esc() {
	local v=${1//\\/\\\\}
	v=${v//$'\n'/\\n}
	REPLY=${v//$'\t'/\\t}
}

_jinja_err() {
	printf 'jinja: %s\n' "$*" >&2
	return 2
}

# append a single-line protocol record: TYPE NAME VALUE
_jinja_add_rec() {
	_jinja_esc "$2"
	_jinja_buf+="$1	$REPLY	"
	_jinja_esc "$3"
	_jinja_buf+="$REPLY"$'\n'
}

# append protocol records for bash variable $1 (exported as $2, default $1)
_jinja_add_var() {
	local _jinja_name=$1 _jinja_as=${2:-$1} _jinja_decl _jinja_flags _jinja_key
	if ! _jinja_decl=$(declare -p "$_jinja_name" 2>/dev/null); then
		_jinja_err "-v $_jinja_name: variable is not set"
		return
	fi
	[[ $_jinja_decl =~ ^declare\ -([a-zA-Z-]*)\  ]] && _jinja_flags=${BASH_REMATCH[1]} || _jinja_flags=
	if [[ $_jinja_flags == *n* ]]; then
		# nameref: export the referenced value under this name
		local _jinja_target=${_jinja_decl#*=\"}
		_jinja_target=${_jinja_target%\"}
		_jinja_decl=$(declare -p "$_jinja_target" 2>/dev/null) || {
			_jinja_err "-v $_jinja_name: referenced variable '$_jinja_target' is not set"
			return
		}
		[[ $_jinja_decl =~ ^declare\ -([a-zA-Z-]*)\  ]] && _jinja_flags=${BASH_REMATCH[1]} || _jinja_flags=
		_jinja_name=$_jinja_target
	fi
	_jinja_esc "$_jinja_as"
	local _jinja_ename=$REPLY
	local -n __jinja_ref=$_jinja_name
	if [[ $_jinja_flags == *A* ]]; then
		_jinja_buf+="A	$_jinja_ename	${#__jinja_ref[@]}"$'\n'
		for _jinja_key in "${!__jinja_ref[@]}"; do
			_jinja_esc "$_jinja_key"
			_jinja_buf+="K	$REPLY	"
			_jinja_esc "${__jinja_ref[$_jinja_key]}"
			_jinja_buf+="$REPLY"$'\n'
		done
	elif [[ $_jinja_flags == *a* ]]; then
		_jinja_buf+="L	$_jinja_ename	${#__jinja_ref[@]}"$'\n'
		for _jinja_key in "${__jinja_ref[@]}"; do
			_jinja_esc "$_jinja_key"
			_jinja_buf+="E	$REPLY"$'\n'
		done
	elif [[ $_jinja_flags == *i* ]]; then
		_jinja_buf+="I	$_jinja_ename	${__jinja_ref}"$'\n'
	else
		_jinja_esc "${__jinja_ref-}"
		_jinja_buf+="S	$_jinja_ename	$REPLY"$'\n'
	fi
}

# append the protocol record for -v NAME=VALUE (the value is parsed by awk)
_jinja_add_inline() {
	[[ ${1%%=*} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _jinja_err "-v $1: invalid variable name"; return; }
	_jinja_add_rec V "${1%%=*}" "${1#*=}"
}

# parse options into _jinja_buf / _jinja_args; sets _jinja_out
_jinja_parse() {
	local _jinja_opt _jinja_val _jinja_v _jinja_env=0 _jinja_matched
	_jinja_buf=
	_jinja_args=()
	_jinja_paths=()
	while (($#)); do
		_jinja_opt=$1
		case $_jinja_opt in
		-d | --data | -v | --var | -i | --int | -D | --define | -J | --json | -I | --path | -o | --output | --ext)
			(($# >= 2)) || { _jinja_err "option $_jinja_opt requires an argument"; return; }
			_jinja_val=$2
			shift 2
			;;
		--data=* | --var=* | --int=* | --define=* | --json=* | --path=* | --output=* | --ext=*)
			_jinja_val=${_jinja_opt#*=}
			_jinja_opt=${_jinja_opt%%=*}
			shift
			;;
		--)
			shift
			_jinja_args+=("$@")
			break
			;;
		-?*)
			_jinja_val=
			shift
			;;
		*)
			_jinja_args+=("$_jinja_opt")
			shift
			continue
			;;
		esac
		case $_jinja_opt in
		-d | --data)
			_jinja_esc "$_jinja_val"
			_jinja_buf+="F	$REPLY"$'\n'
			;;
		-v | --var)
			if [[ $_jinja_val == *=* ]]; then
				_jinja_add_inline "$_jinja_val" || return
			elif [[ $_jinja_val == *[\*\?\[]* ]]; then
				_jinja_matched=0
				for _jinja_v in $(compgen -v); do
					# shellcheck disable=SC2053
					[[ $_jinja_v == $_jinja_val && $_jinja_v != _jinja_* && $_jinja_v != __jinja_* ]] || continue
					_jinja_add_var "$_jinja_v" || return
					_jinja_matched=1
				done
				((_jinja_matched)) || { _jinja_err "-v $_jinja_val: no variable matches"; return; }
			else
				_jinja_add_var "$_jinja_val" || return
			fi
			;;
		-i | --int)
			[[ $_jinja_val =~ ^[^=]+=[+-]?[0-9]+$ ]] || { _jinja_err "-i expects NAME=INTEGER, got '$_jinja_val'"; return; }
			_jinja_add_rec I "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		-D | --define)
			[[ $_jinja_val == *=* ]] || { _jinja_err "-D expects KEY=VALUE, got '$_jinja_val'"; return; }
			_jinja_add_rec S "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		-J | --json)
			[[ $_jinja_val == *=* ]] || { _jinja_err "-J expects KEY=JSON, got '$_jinja_val'"; return; }
			_jinja_add_rec J "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		-I | --path) _jinja_paths+=("$_jinja_val") ;;
		-o | --output)
			_jinja_esc "$_jinja_val"
			_jinja_buf+="O	out	$REPLY"$'\n'
			;;
		--ext)
			_jinja_esc "$_jinja_val"
			_jinja_buf+="O	ext	$REPLY"$'\n'
			;;
		-e | --env) _jinja_env=1 ;;
		--strict) _jinja_buf+="O	strict	1"$'\n' ;;
		--trim-blocks) _jinja_buf+="O	trim_blocks	1"$'\n' ;;
		--lstrip-blocks) _jinja_buf+="O	lstrip_blocks	1"$'\n' ;;
		--keep-trailing-newline) _jinja_buf+="O	keep_trailing_newline	1"$'\n' ;;
		--autoescape) _jinja_buf+="O	autoescape	1"$'\n' ;;
		*) _jinja_err "unknown option: $_jinja_opt"; return ;;
		esac
	done
	((_jinja_env)) && _jinja_buf="X"$'\n'"$_jinja_buf"
	return 0
}

declare -gA _JINJA_MATH 2>/dev/null || declare -A _JINJA_MATH

_jinja_run() {
	local -a _jinja_awk_cmd _jinja_progs=()
	local _jinja_f _jinja_key=${JINJA_AWK:-}
	# default: gawk when installed (no recursion limit), else awk
	if [[ -z $_jinja_key ]]; then
		[[ -n ${_JINJA_DEFAULT_AWK:-} ]] || { if type -P gawk >/dev/null; then _JINJA_DEFAULT_AWK='gawk'; else _JINJA_DEFAULT_AWK='awk'; fi; }
		_jinja_key=$_JINJA_DEFAULT_AWK
	fi
	read -ra _jinja_awk_cmd <<<"$_jinja_key"
	# busybox awk may be built without math support (no pow/exp/log)
	if [[ -z ${_JINJA_MATH[$_jinja_key]:-} ]]; then
		if "${_jinja_awk_cmd[@]}" 'BEGIN { x = 2 ^ 0.5 }' </dev/null >/dev/null 2>&1; then
			_JINJA_MATH[$_jinja_key]=1
		else
			_JINJA_MATH[$_jinja_key]=0
		fi
	fi
	_jinja_buf="O	math	${_JINJA_MATH[$_jinja_key]}"$'\n'"$_jinja_buf"
	if [[ -n ${_JINJA_AWK_SRC:-} ]]; then
		LC_ALL=C "${_jinja_awk_cmd[@]}" -f <(printf '%s' "$_JINJA_AWK_SRC") <<<"$_jinja_buf"
		return
	fi
	for _jinja_f in "${_JINJA_AWK_FILES[@]}"; do
		_jinja_progs+=(-f "$_JINJA_LIB/$_jinja_f.awk")
	done
	LC_ALL=C "${_jinja_awk_cmd[@]}" "${_jinja_progs[@]}" <<<"$_jinja_buf"
}

_jinja_paths_proto() {
	local _jinja_p
	for _jinja_p in "$@"; do
		_jinja_esc "$_jinja_p"
		_jinja_buf+="O	path	$REPLY"$'\n'
	done
}

jinja_render() {
	local _jinja_buf _jinja_args _jinja_paths _jinja_tpl _jinja_dir
	_jinja_parse "$@" || return
	((${#_jinja_args[@]} == 1)) || { _jinja_err "jinja_render: expected exactly one TEMPLATE"; return; }
	_jinja_tpl=${_jinja_args[0]}
	if [[ $_jinja_tpl == */* ]]; then _jinja_dir=${_jinja_tpl%/*}; _jinja_tpl=${_jinja_tpl##*/}; else _jinja_dir=.; fi
	[[ -n $_jinja_dir ]] || _jinja_dir=/
	_jinja_paths_proto "$_jinja_dir" ${_jinja_paths[@]+"${_jinja_paths[@]}"}
	_jinja_esc "$_jinja_tpl"
	_jinja_buf+="M	$REPLY"$'\n'
	_jinja_run
}

jinja_render_string() {
	local _jinja_buf _jinja_args _jinja_paths
	_jinja_parse "$@" || return
	((${#_jinja_args[@]} == 1)) || { _jinja_err "jinja_render_string: expected exactly one SOURCE"; return; }
	_jinja_paths_proto ${_jinja_paths[@]+"${_jinja_paths[@]}"}
	_jinja_esc "${_jinja_args[0]}"
	_jinja_buf+="T	$REPLY"$'\n'
	_jinja_run
}

_jinja_usage() {
	cat <<'EOF'
Usage: jinja [options] TEMPLATE
       jinja [options] -s SOURCE
       jinja [options] -          (template read from stdin)

Render a Jinja2 template.

Options:
  -s, --string SOURCE     template source given on the command line
  -d, --data FILE         load variables from a .json/.yaml/.yml file
  -v, --var NAME          export a bash variable (glob patterns allowed)
  -v, --var NAME=VALUE    define a variable: '(a b)' list, '([k]=v)' dict,
                          else string
  -i, --int NAME=INT      define an integer variable
  -D, --define KEY=VALUE  define a string variable
  -J, --json KEY=JSON     define a variable from a JSON value
  -e, --env               expose environment variables
  -I, --path DIR          add DIR to the template search path
  -o, --output FILE       write the result to FILE
      --strict            undefined variables raise an error
      --trim-blocks       remove the first newline after a block tag
      --lstrip-blocks     strip whitespace before a block tag on its line
      --keep-trailing-newline
      --autoescape        HTML-escape variable output
      --ext NAME          enable an extension: loopcontrols, do
  -h, --help              show this help
      --version           show the version
EOF
}

# command line entry point
jinja_main() {
	local -a _jinja_args=()
	local _jinja_src='' _jinja_has_src=0
	while (($#)); do
		case $1 in
		-h | --help) _jinja_usage; return 0 ;;
		--version) printf 'jinja %s\n' "$JINJA_VERSION"; return 0 ;;
		-s | --string)
			(($# >= 2)) || { _jinja_err "option $1 requires an argument"; return; }
			_jinja_src=$2 _jinja_has_src=1
			shift 2
			;;
		--string=*) _jinja_src=${1#*=} _jinja_has_src=1; shift ;;
		-)
			IFS= read -r -d '' _jinja_src || true
			_jinja_has_src=1
			shift
			;;
		*) _jinja_args+=("$1"); shift ;;
		esac
	done
	if ((_jinja_has_src)); then
		jinja_render_string ${_jinja_args[@]+"${_jinja_args[@]}"} -- "$_jinja_src"
	else
		jinja_render ${_jinja_args[@]+"${_jinja_args[@]}"}
	fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	set -u
	jinja_main "$@"
	exit
fi
