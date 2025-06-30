#!/bin/sh

[ -d "$1" ] || exit 1
cd "$1" || exit 1
shift

exec /usr/bin/lldap "$@"
