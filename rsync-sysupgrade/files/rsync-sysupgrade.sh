#!/bin/sh
# rsync-sysupgrade - fetch firmware via rsync and run sysupgrade
# shellcheck shell=dash

set -e

TAG="rsync-sysupgrade"

. /lib/functions.sh

usage() {
	cat <<'EOF'
Usage: rsync-sysupgrade [options]

Fetch firmware image via rsync and run sysupgrade.
Configuration: /etc/config/rsync-sysupgrade

Options:
  -r TAG      Use specific release tag (default: latest)
  -l          List available releases and exit
  -f          Force: skip confirmation prompt
  -c          Check only: download and verify, don't flash
  -K          Keep image in /tmp after check (-c)
  -v          Verbose rsync output
  -h          Show this help
EOF
	exit "${1:-0}"
}

log() { logger -s -t "$TAG" "$@"; }
die() { log "$@"; exit 1; }

FORCE=0
CHECK_ONLY=0
VERBOSE=0
LIST_ONLY=0
KEEP=0
RELEASE=""

while getopts "r:lfcKvh" opt; do
	case "$opt" in
		r) RELEASE="$OPTARG" ;;
		l) LIST_ONLY=1 ;;
		f) FORCE=1 ;;
		c) CHECK_ONLY=1 ;;
		K) KEEP=1 ;;
		v) VERBOSE=1 ;;
		h) usage 0 ;;
		*) usage 1 ;;
	esac
done

config_load rsync-sysupgrade

config_get_bool ENABLED settings enabled 0
config_get RSYNC_URL settings rsync_url ''
config_get PROFILE settings profile ''
config_get FILENAME settings filename ''
config_get RSYNC_ARGS settings rsync_args '-P'
config_get SYSUPGRADE_ARGS settings sysupgrade_args ''

[ "$ENABLED" = 1 ] || die "disabled. Enable in /etc/config/rsync-sysupgrade"
[ -n "$RSYNC_URL" ] || die "rsync_url is not configured"
[ -n "$PROFILE" ] || die "profile is not configured"
[ -n "$FILENAME" ] || die "filename is not configured"

# Ensure trailing slash on URL
case "$RSYNC_URL" in
	*/) ;;
	*) RSYNC_URL="${RSYNC_URL}/" ;;
esac

# List releases and pick the latest tag
log "Looking for releases in ${RSYNC_URL}releases/"
RELEASES=$(rsync --list-only "${RSYNC_URL}releases/" 2>/dev/null \
	| awk '/^d/ {print $NF}' \
	| sort -t. -k1,1n -k2,2n -k3,3n)
[ -n "$RELEASES" ] || die "no releases found at ${RSYNC_URL}releases/"

if [ "$LIST_ONLY" = 1 ]; then
	echo "Available releases:"
	echo "$RELEASES"
	exit 0
fi

if [ -n "$RELEASE" ]; then
	# Validate that the specified release exists
	echo "$RELEASES" | grep -qxF "$RELEASE" || die "release '$RELEASE' not found"
else
	RELEASE=$(echo "$RELEASES" | tail -n1)
fi
log "Using release: $RELEASE"

SRC="${RSYNC_URL}releases/${RELEASE}/${PROFILE}/${FILENAME}"
DST="/tmp/${FILENAME}"

log "Fetching firmware: $SRC"

rsync_cmd_args="$RSYNC_ARGS"
[ "$VERBOSE" = 1 ] && rsync_cmd_args="$rsync_cmd_args -v"

# shellcheck disable=SC2086
rsync $rsync_cmd_args "$SRC" "$DST" || die "rsync failed"

[ -f "$DST" ] || die "Downloaded file not found: $DST"

SIZE=$(wc -c < "$DST")
log "Downloaded: $FILENAME ($SIZE bytes)"

if [ "$CHECK_ONLY" = 1 ]; then
	log "Check-only mode, verifying image..."
	sysupgrade -T "$DST" && log "Image verification OK" || die "Image verification FAILED"
	[ "$KEEP" = 1 ] && log "Keeping image: $DST" || rm -f "$DST"
	exit 0
fi

sysup_args="$SYSUPGRADE_ARGS"

if [ "$FORCE" = 0 ]; then
	printf "Flash %s (%s bytes)? [y/N] " "$FILENAME" "$SIZE"
	read -r answer
	case "$answer" in
		y|Y|yes|YES) ;;
		*) log "Aborted."; rm -f "$DST"; exit 1 ;;
	esac
fi

log "Starting sysupgrade..."
# shellcheck disable=SC2086
exec sysupgrade $sysup_args "$DST"
