#!/bin/sh
# jinja.sh - render Jinja2 templates from a POSIX shell (+ POSIX awk).
#
#   . jinja.sh
#   jinja_render [options] TEMPLATE        render a template file
#   jinja_render_string [options] SOURCE   render a template given as a string
#
# Options:
#   -d, --data FILE         load variables from a .json/.yaml/.yml file
#   -v, --var NAME          export the shell variable NAME (string; in bash
#                           also -i integer, indexed array -> list,
#                           associative array -> dict); NAME may be a glob
#                           pattern ('app_*')
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
# installed, else awk). JINJA_LIB is the lib/ directory next to this file;
# it is found automatically in bash and zsh, set it before sourcing from
# another shell.
#
# Shell code: POSIX sh without `local` (ksh93 has none), so every variable
# and function named _jinja_* is reserved. bash extras live in lib/bash.sh.

# shellcheck disable=SC2034
JINJA_VERSION=0.1.0

_jinja_nl='
'
_jinja_tab=$(printf '\t')
_JINJA_AWK_FILES='value utf8 lexer parser runtime filters tests builtins json yaml main'

# @jinja-engine-begin (replaced by tools/build.sh)
if [ -n "${JINJA_LIB:-}" ]; then
	_jinja_lib=$JINJA_LIB
else
	if [ -n "${BASH_VERSION:-}" ]; then
		eval '_jinja_lib=${BASH_SOURCE[0]}'
	elif [ -n "${ZSH_VERSION:-}" ]; then
		eval '_jinja_lib=${(%):-%x}'
	else
		_jinja_lib=$0
	fi
	case $_jinja_lib in
	*/*) _jinja_lib=${_jinja_lib%/*} ;;
	*) _jinja_lib=. ;;
	esac
	_jinja_lib=$(CDPATH='' cd -- "$_jinja_lib" && pwd)/lib
fi

# run the awk command "$@" on the engine; the protocol is on stdin
_jinja_exec() {
	[ -f "$_jinja_lib/awk/main.awk" ] || {
		_jinja_err "awk engine not found in '$_jinja_lib/awk': set JINJA_LIB"
		return
	}
	for _jinja_f in $_JINJA_AWK_FILES; do
		set -- "$@" -f "$_jinja_lib/awk/$_jinja_f.awk"
	done
	LC_ALL=C "$@"
}
# @jinja-engine-end

_jinja_err() {
	printf 'jinja: %s\n' "$*" >&2
	return 2
}

_jinja_isname() {
	case $1 in
	'' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;;
	esac
}

# _jinja_r = $1 with every $2 replaced by $3
_jinja_repl() {
	_jinja_r=
	_jinja_s=$1
	while :; do
		case $_jinja_s in
		*"$2"*)
			_jinja_r=$_jinja_r${_jinja_s%%"$2"*}$3
			_jinja_s=${_jinja_s#*"$2"}
			;;
		*)
			_jinja_r=$_jinja_r$_jinja_s
			return 0
			;;
		esac
	done
}

# awk version of _jinja_esc for large values (linear time), input ends with x
# shellcheck disable=SC2016  # awk program
_JINJA_ESC_AWK='{
	n = split($0, p, "\\"); s = n ? p[1] : ""
	for (i = 2; i <= n; i++) s = s "\\\\" p[i]
	n = split(s, p, "\t"); s = n ? p[1] : ""
	for (i = 2; i <= n; i++) s = s "\\t" p[i]
	printf "%s%s", (NR > 1 ? "\\n" : ""), s
}'

# escape a protocol value into _jinja_r: backslash, newline, tab
_jinja_esc() {
	case $1 in
	*\\* | *"$_jinja_nl"* | *"$_jinja_tab"*)
		if [ ${#1} -gt 4096 ]; then
			# _jinja_repl copies the rest of the value at each match
			_jinja_pick_awk
			# shellcheck disable=SC2086
			_jinja_r=$(printf '%sx' "$1" | LC_ALL=C $_jinja_awk "$_JINJA_ESC_AWK") || return
			_jinja_r=${_jinja_r%x}
			return 0
		fi
		_jinja_repl "$1" "\\" "\\\\"
		_jinja_repl "$_jinja_r" "$_jinja_nl" '\n'
		_jinja_repl "$_jinja_r" "$_jinja_tab" '\t'
		;;
	*) _jinja_r=$1 ;;
	esac
}

# append a protocol record: TYPE VALUE, or TYPE NAME VALUE
_jinja_add_rec() {
	_jinja_esc "$2"
	_jinja_buf=$_jinja_buf$1$_jinja_tab$_jinja_r
	if [ $# -ge 3 ]; then
		_jinja_esc "$3"
		_jinja_buf=$_jinja_buf$_jinja_tab$_jinja_r
	fi
	_jinja_buf=$_jinja_buf$_jinja_nl
}

# append the record of shell variable $1 (strings only; see lib/bash.sh)
_jinja_add_var() {
	_jinja_isname "$1" || { _jinja_err "-v $1: invalid variable name"; return; }
	eval "_jinja_av=\${$1+x}"
	[ -n "$_jinja_av" ] || { _jinja_err "-v $1: variable is not set"; return; }
	eval "_jinja_av=\$$1"
	_jinja_add_rec S "$1" "$_jinja_av"
}

# print the names of the shell variables, one per line
_jinja_var_names() {
	set | while IFS= read -r _jinja_l; do
		_jinja_l=${_jinja_l%%=*}
		_jinja_isname "$_jinja_l" && printf '%s\n' "$_jinja_l"
	done
}

# append the records of the variables whose name matches the glob $1
_jinja_add_glob() {
	_jinja_m=0
	for _jinja_g in $(_jinja_var_names); do
		case $_jinja_g in _jinja_* | __jinja_*) continue ;; esac
		# shellcheck disable=SC2254
		case $_jinja_g in $1) ;; *) continue ;; esac
		eval "_jinja_av=\${$_jinja_g+x}"
		[ -n "$_jinja_av" ] || continue
		_jinja_add_var "$_jinja_g" || return
		_jinja_m=1
	done
	[ "$_jinja_m" = 1 ] || _jinja_err "-v $1: no variable matches"
}

# parse options into _jinja_buf and _jinja_pbuf (search path records);
# positional arguments: count in _jinja_nargs, the first one in _jinja_arg.
# With _jinja_cli=1, also accepts -s/--string, - (stdin), -h and --version
# (which set _jinja_done=1).
_jinja_parse() {
	_jinja_buf=
	_jinja_pbuf=
	_jinja_env=0
	_jinja_nargs=0
	_jinja_arg=
	_jinja_done=0
	_jinja_has_src=0
	while [ $# -gt 0 ]; do
		_jinja_opt=$1
		shift
		case $_jinja_opt in
		-d | --data | -v | --var | -i | --int | -D | --define | -J | --json | -I | --path | -o | --output | --ext | -s | --string)
			[ $# -ge 1 ] || { _jinja_err "option $_jinja_opt requires an argument"; return; }
			_jinja_val=$1
			shift
			;;
		--data=* | --var=* | --int=* | --define=* | --json=* | --path=* | --output=* | --ext=* | --string=*)
			_jinja_val=${_jinja_opt#*=}
			_jinja_opt=${_jinja_opt%%=*}
			;;
		--)
			[ $# -eq 0 ] || [ "$_jinja_nargs" -gt 0 ] || _jinja_arg=$1
			_jinja_nargs=$((_jinja_nargs + $#))
			break
			;;
		- | [!-]* | '')
			if [ "$_jinja_opt" = - ] && [ "$_jinja_cli" = 1 ]; then
				_jinja_src=$(cat && printf x) || return
				_jinja_src=${_jinja_src%x}
				_jinja_has_src=1
				continue
			fi
			[ "$_jinja_nargs" -gt 0 ] || _jinja_arg=$_jinja_opt
			_jinja_nargs=$((_jinja_nargs + 1))
			continue
			;;
		esac
		case $_jinja_cli$_jinja_opt in
		?-d | ?--data) _jinja_add_rec F "$_jinja_val" ;;
		?-v | ?--var)
			case $_jinja_val in
			*=*)
				_jinja_isname "${_jinja_val%%=*}" || { _jinja_err "-v $_jinja_val: invalid variable name"; return; }
				_jinja_add_rec V "${_jinja_val%%=*}" "${_jinja_val#*=}"
				;;
			*[*?[]*) _jinja_add_glob "$_jinja_val" || return ;;
			*) _jinja_add_var "$_jinja_val" || return ;;
			esac
			;;
		?-i | ?--int)
			_jinja_n=${_jinja_val#*=}
			_jinja_n=${_jinja_n#[+-]}
			case $_jinja_val in
			[!=]*=*) ;;
			*) _jinja_n= ;;
			esac
			case $_jinja_n in
			'' | *[!0-9]*) _jinja_err "-i expects NAME=INTEGER, got '$_jinja_val'"; return ;;
			esac
			_jinja_add_rec I "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		?-D | ?--define)
			case $_jinja_val in *=*) ;; *) _jinja_err "-D expects KEY=VALUE, got '$_jinja_val'"; return ;; esac
			_jinja_add_rec S "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		?-J | ?--json)
			case $_jinja_val in *=*) ;; *) _jinja_err "-J expects KEY=JSON, got '$_jinja_val'"; return ;; esac
			_jinja_add_rec J "${_jinja_val%%=*}" "${_jinja_val#*=}"
			;;
		?-I | ?--path)
			_jinja_esc "$_jinja_val"
			_jinja_pbuf=$_jinja_pbuf"O${_jinja_tab}path$_jinja_tab$_jinja_r$_jinja_nl"
			;;
		?-o | ?--output) _jinja_add_rec O out "$_jinja_val" ;;
		?--ext) _jinja_add_rec O ext "$_jinja_val" ;;
		?-e | ?--env) _jinja_env=1 ;;
		?--strict) _jinja_add_rec O strict 1 ;;
		?--trim-blocks) _jinja_add_rec O trim_blocks 1 ;;
		?--lstrip-blocks) _jinja_add_rec O lstrip_blocks 1 ;;
		?--keep-trailing-newline) _jinja_add_rec O keep_trailing_newline 1 ;;
		?--autoescape) _jinja_add_rec O autoescape 1 ;;
		1-s | 1--string)
			_jinja_src=$_jinja_val
			_jinja_has_src=1
			;;
		1-h | 1--help)
			_jinja_usage
			_jinja_done=1
			return 0
			;;
		1--version)
			printf 'jinja %s\n' "$JINJA_VERSION"
			_jinja_done=1
			return 0
			;;
		*) _jinja_err "unknown option: $_jinja_opt"; return ;;
		esac
	done
	[ "$_jinja_env" = 0 ] || _jinja_buf=X$_jinja_nl$_jinja_buf
	return 0
}

# set _jinja_awk to the awk command line
_jinja_pick_awk() {
	_jinja_awk=${JINJA_AWK:-}
	# default: gawk when installed (no recursion limit), else awk
	if [ -z "$_jinja_awk" ]; then
		if command -v gawk >/dev/null 2>&1; then _jinja_awk='gawk'; else _jinja_awk='awk'; fi
	fi
}

# pipe the protocol into the selected awk
_jinja_run() {
	_jinja_pick_awk
	# split on purpose: JINJA_AWK may be "busybox awk"
	# shellcheck disable=SC2086
	set -- $_jinja_awk
	# busybox awk may be built without math support (no pow/exp/log)
	if [ "${_jinja_math_awk-}" != "$_jinja_awk" ]; then
		if "$@" 'BEGIN { x = 2 ^ 0.5 }' </dev/null >/dev/null 2>&1; then _jinja_math=1; else _jinja_math=0; fi
		_jinja_math_awk=$_jinja_awk
	fi
	printf 'O\tmath\t%s\n%s' "$_jinja_math" "$_jinja_buf" | _jinja_exec "$@"
}

# render the template file _jinja_arg
_jinja_file() {
	[ "$_jinja_nargs" -eq 1 ] || { _jinja_err "expected exactly one TEMPLATE"; return; }
	case $_jinja_arg in
	*/*)
		_jinja_d=${_jinja_arg%/*}
		_jinja_t=${_jinja_arg##*/}
		;;
	*)
		_jinja_d=.
		_jinja_t=$_jinja_arg
		;;
	esac
	[ -n "$_jinja_d" ] || _jinja_d=/
	_jinja_add_rec O path "$_jinja_d"
	_jinja_buf=$_jinja_buf$_jinja_pbuf
	_jinja_add_rec M "$_jinja_t"
	_jinja_run
}

# render the template source _jinja_arg
_jinja_string() {
	[ "$_jinja_nargs" -eq 1 ] || { _jinja_err "expected exactly one SOURCE"; return; }
	_jinja_buf=$_jinja_buf$_jinja_pbuf
	_jinja_add_rec T "$_jinja_arg"
	_jinja_run
}

jinja_render() {
	[ -z "${ZSH_VERSION:-}" ] || emulate -L sh
	_jinja_cli=0
	_jinja_parse ${1+"$@"} || return
	_jinja_file
}

jinja_render_string() {
	[ -z "${ZSH_VERSION:-}" ] || emulate -L sh
	_jinja_cli=0
	_jinja_parse ${1+"$@"} || return
	_jinja_string
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
  -v, --var NAME          export a shell variable (glob patterns allowed)
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
	[ -z "${ZSH_VERSION:-}" ] || emulate -L sh
	_jinja_cli=1
	_jinja_parse ${1+"$@"} || return
	[ "$_jinja_done" = 0 ] || return 0
	if [ "$_jinja_has_src" = 1 ]; then
		[ "$_jinja_nargs" -eq 0 ] || { _jinja_err "unexpected argument: $_jinja_arg"; return; }
		_jinja_arg=$_jinja_src
		_jinja_nargs=1
		_jinja_string
	else
		_jinja_file
	fi
}

# @jinja-bash-begin (replaced by tools/build.sh)
if [ -n "${BASH_VERSION:-}" ] && [ -f "$_jinja_lib/bash.sh" ]; then
	# shellcheck source=lib/bash.sh
	. "$_jinja_lib/bash.sh"
fi
# @jinja-bash-end

# run jinja_main when executed rather than sourced
if [ -z "${_jinja_noauto:-}" ]; then
	_jinja_noauto=1
	if [ -n "${BASH_VERSION:-}" ]; then
		eval '[ "${BASH_SOURCE[0]}" = "$0" ]' && _jinja_noauto=
	elif [ -n "${ZSH_VERSION:-}" ]; then
		[ "${ZSH_EVAL_CONTEXT:-}" != toplevel ] || _jinja_noauto=
	else
		case ${0##*/} in jinja.sh | jinja) _jinja_noauto= ;; esac
	fi
	if [ -z "$_jinja_noauto" ]; then
		set -u
		jinja_main ${1+"$@"}
		exit
	fi
fi
