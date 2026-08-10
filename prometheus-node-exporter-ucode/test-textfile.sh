#!/bin/sh
# Regression test for the textfile collector (files/extra/textfile.uc).
#
# Creates a temp directory with .prom files and checks that the collector
# emits node_textfile_mtime_seconds files and passes the raw contents through.
#
# Usage: ucode test-textfile.uc   (run from the package directory)

set -u

if command -v ucode >/dev/null 2>&1; then
	UCODE=ucode
elif [ -x ./ucode ]; then
	UCODE=./ucode
else
	echo "ucode interpreter not found; skipping textfile collector test" >&2
	exit 0
fi

cd "$(dirname "$0")"

TF_DIR="$(mktemp -d)"
trap 'rm -rf "$TF_DIR"' EXIT

printf '# HELP my_metric_total A counter\n# TYPE my_metric_total counter\nmy_metric_total 42\n' \
	> "$TF_DIR/a.prom"
printf '# HELP second Something\n# TYPE second gauge\nsecond{label="x"} 1\n' \
	> "$TF_DIR/b.prom"
printf 'ignored\n' > "$TF_DIR/ignored.txt"

export TF_DIR
exec "$UCODE" test-textfile.uc