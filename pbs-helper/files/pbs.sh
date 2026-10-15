#!/bin/sh
# Compatibility wrapper: the backup job is now /usr/bin/pbs-backup (ucode).
exec /usr/bin/pbs-backup "$@"
