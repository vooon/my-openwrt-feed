#!/bin/sh
# Print the top-level directories and files a change touches, one per line:
# what build.yml and ci.yml use to pick the packages to build or test.
#
# Compares BASE (env: the pull request base sha, or the previous master
# commit of a push) with HEAD; when BASE is unset or unknown (first push
# of a branch) HEAD's parent is used instead. Needs the history fetched
# (actions/checkout fetch-depth: 0).
#
#   BASE=<sha> ci/changed-dirs.sh
set -eu

base="${BASE:-}"
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2> /dev/null; then
	base="HEAD^"
fi

git diff --name-only "$base...HEAD" | cut -d/ -f1 | sort -u
