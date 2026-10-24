.PHONY: test lint dist fuzz bench

# shells tried by `make test` when installed
SHELLS = dash zsh ksh93 mksh posh "busybox sh"

test:
	tests/run.sh
	for a in gawk mawk "busybox awk"; do tests/cli.sh -s bash -a "$$a" || exit 1; done
	for s in $(SHELLS); do \
		set -- $$s; command -v "$$1" >/dev/null || continue; \
		tests/cli.sh -s "$$s" || exit 1; \
	done

lint:
	tools/lint_awk.sh
	shellcheck -x jinja.sh bin/jinja lib/bash.sh tests/*.sh tools/*.sh

dist:
	tools/build.sh

bench:
	tools/bench.py

fuzz:
	tests/fuzz.py expr 1 300
	tests/fuzz.py ws 1 300
