.PHONY: test lint dist fuzz

test:
	tests/run.sh
	for a in gawk mawk "busybox awk"; do tests/cli.sh -a "$$a" || exit 1; done

lint:
	tools/lint_awk.sh
	shellcheck jinja.sh bin/jinja tests/*.sh tools/*.sh

dist:
	tools/build.sh

fuzz:
	tests/fuzz.py expr 1 300
	tests/fuzz.py ws 1 300
