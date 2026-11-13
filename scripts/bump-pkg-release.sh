#!/bin/sh
# Increment PKG_RELEASE of a package Makefile.
#
# Run by Renovate (postUpgradeTasks in renovate.json) when it bumps the pin
# of a component built into a package, such as a CoreDNS plugin: the
# package version stays, so the release has to move for the rebuilt
# package to count as an update. A bump of PKG_VERSION itself resets the
# release to 1 and does not come through here.
#
#   scripts/bump-pkg-release.sh <package>/Makefile
set -eu

mk="${1:?usage: $0 <package>/Makefile}"

rel="$(sed -n 's/^PKG_RELEASE:=\([0-9][0-9]*\)$/\1/p' "$mk")"
case "$rel" in
'' | *[!0-9]*)
	echo "$mk: no numeric PKG_RELEASE:= line" >&2
	exit 1
	;;
esac

sed -i "s/^PKG_RELEASE:=$rel\$/PKG_RELEASE:=$((rel + 1))/" "$mk"
echo "$mk: PKG_RELEASE $rel -> $((rel + 1))"
