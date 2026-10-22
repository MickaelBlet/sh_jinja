#!/usr/bin/env bash
# Run golden tests (tests/cases) against every available awk.
#
# Usage: tests/run.sh [-a AWK]... [CASE...]
#   -a AWK   awk command to test (repeatable, default: gawk mawk "busybox awk")
set -u
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck disable=SC1091
source "$here/../jinja.sh"

awks=()
while getopts a: opt; do
	case $opt in
	a) awks+=("$OPTARG") ;;
	*) exit 2 ;;
	esac
done
shift $((OPTIND - 1))
if ((${#awks[@]} == 0)); then
	for a in gawk mawk "busybox awk"; do
		read -ra cmd <<<"$a"
		if command -v "${cmd[0]}" >/dev/null && "${cmd[@]}" 'BEGIN{}' </dev/null 2>/dev/null; then awks+=("$a"); fi
	done
fi

cases=("$@")
if ((${#cases[@]} == 0)); then
	for d in "$here"/cases/*/; do
		d=${d%/}
		cases+=("${d##*/}")
	done
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
for c in "${cases[@]}"; do
	d=$here/cases/$c
	args=()
	[[ -f $d/data.json ]] && args+=(-d "$d/data.json")
	[[ -f $d/data.yaml ]] && args+=(-d "$d/data.yaml")
	if [[ -f $d/opts ]]; then
		while IFS= read -r line || [[ -n $line ]]; do
			case $line in
			'' | '#'*) ;;
			trim_blocks) args+=(--trim-blocks) ;;
			lstrip_blocks) args+=(--lstrip-blocks) ;;
			keep_trailing_newline) args+=(--keep-trailing-newline) ;;
			autoescape) args+=(--autoescape) ;;
			strict) args+=(--strict) ;;
			ext=*) args+=(--ext "${line#ext=}") ;;
			*) echo "$c: unknown opt '$line'" >&2 ;;
			esac
		done <"$d/opts"
	fi
	for a in "${awks[@]}"; do
		JINJA_AWK=$a jinja_render "${args[@]}" "$d/template.j2" >"$tmp/out" 2>"$tmp/err"
		rc=$?
		if [[ -f $d/expected_error ]]; then
			want=$(<"$d/expected_error")
			if ((rc != 0)) && grep -q ": $want: " "$tmp/err"; then
				pass=$((pass + 1))
			else
				fail=$((fail + 1))
				printf 'FAIL %s [%s]: expected %s, got rc=%d\n' "$c" "$a" "$want" "$rc"
				sed 's/^/    /' "$tmp/err" "$tmp/out" | head -20
			fi
		elif ((rc == 0)) && cmp -s "$tmp/out" "$d/expected"; then
			pass=$((pass + 1))
		else
			fail=$((fail + 1))
			printf 'FAIL %s [%s] rc=%d\n' "$c" "$a" "$rc"
			sed 's/^/    /' "$tmp/err" | head -5
			diff <(cat -A "$d/expected" 2>/dev/null) <(cat -A "$tmp/out") | head -20 | sed 's/^/    /'
		fi
	done
done
printf '%d passed, %d failed (%s)\n' "$pass" "$fail" "${awks[*]}"
((fail == 0))
