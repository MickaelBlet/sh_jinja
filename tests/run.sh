#!/usr/bin/env bash
# Run golden tests (tests/cases) against every available awk.
#
# Usage: tests/run.sh [-a AWK]... [CASE...]
#   -a AWK   awk command to test (repeatable, default: gawk mawk "busybox awk")
# Environment: JINJA_SH selects the library to test (e.g. dist/jinja.sh)
set -u
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck disable=SC1090,SC1091
source "${JINJA_SH:-$here/../jinja.sh}"

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

# optional awk features a case may require (tests/cases/*/requires)
declare -A feat=()
for a in "${awks[@]}"; do
	read -ra cmd <<<"$a"
	# BWK awk normalizes -0 to 0
	[[ $("${cmd[@]}" 'BEGIN { x = 0; printf "%.1f", -x }' </dev/null) == -0.0 ]] && feat[$a,negzero]=1
	# BWK awk converts subnormal numbers to 0
	[[ $("${cmd[@]}" 'BEGIN { printf "%s", ("5e-324" + 0 > 0) }' </dev/null) == 1 ]] && feat[$a,denormal]=1
done

cases=("$@")
if ((${#cases[@]} == 0)); then
	for d in "$here"/cases/*/; do
		d=${d%/}
		cases+=("${d##*/}")
	done
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0 skip=0
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
	reqs=()
	[[ -f $d/requires ]] && read -ra reqs <"$d/requires"
	for a in "${awks[@]}"; do
		for r in ${reqs[@]+"${reqs[@]}"}; do
			[[ -n ${feat[$a,$r]:-} ]] || { skip=$((skip + 1)); continue 2; }
		done
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
			diff <(cat -vet "$d/expected" 2>/dev/null) <(cat -vet "$tmp/out") | head -20 | sed 's/^/    /'
		fi
	done
done
printf '%d passed, %d failed, %d skipped (%s)\n' "$pass" "$fail" "$skip" "${awks[*]}"
((fail == 0))
