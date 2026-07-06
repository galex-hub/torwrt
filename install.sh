#!/bin/sh
# torwrt installer for OpenWrt >= 25.12.4.
# Usage on the router:
#   wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh
#   sh /tmp/torwrt-install.sh
# Re-running updates an existing install; user config is preserved.
# Env overrides: TORWRT_BRANCH=<branch>   TORWRT_FORCE=1 (skip version gate)
set -eu

REPO_OWNER="galex-hub"
REPO_NAME="torwrt"
BRANCH="${TORWRT_BRANCH:-main}"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
MIN_VERSION="25.12.4"
DEPS="tor curl"
WORKDIR="/tmp/torwrt-install.$$"
SRC_DIR=""

log() { echo "torwrt: $*"; }
die() { echo "torwrt: ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# "25.12.4[-suffix]" -> 25012004; non-numeric ("SNAPSHOT", "r12345-...") -> 0
ver_num() {
	v=${1%%[!0-9.]*}
	[ -n "$v" ] || { echo 0; return 0; }
	old_ifs=$IFS
	IFS=.
	# shellcheck disable=SC2086 -- splitting on dots is the point
	set -- $v
	IFS=$old_ifs
	a=${1:-0}; b=${2:-0}; c=${3:-0}
	# strip one leading zero so "08"/"09" don't parse as octal in $(( ))
	a=${a#0}; b=${b#0}; c=${c#0}
	echo $(( ${a:-0} * 1000000 + ${b:-0} * 1000 + ${c:-0} ))
}

check_system() {
	[ "$(id -u)" = "0" ] || die "must run as root"
	[ -f /etc/openwrt_release ] || die "not an OpenWrt system (/etc/openwrt_release missing)"
	# shellcheck disable=SC1091
	release=$(. /etc/openwrt_release && echo "${DISTRIB_RELEASE:-}")
	if [ "$(ver_num "$release")" -lt "$(ver_num "$MIN_VERSION")" ]; then
		[ "${TORWRT_FORCE:-0}" = "1" ] ||
			die "OpenWrt $release detected, >= $MIN_VERSION required (set TORWRT_FORCE=1 to try anyway)"
	fi
	command -v apk >/dev/null 2>&1 || die "apk not found (OpenWrt >= 25.12 ships apk)"
	[ "$(date +%Y)" -ge 2025 ] ||
		die "system clock is wrong ($(date)) so TLS will fail; sync time first: /etc/init.d/sysntpd restart"
	[ -d /www/luci-static ] || log "warning: LuCI not detected — the web UI will not be available"
}

fetch_source() {
	log "downloading ${TARBALL_URL}"
	mkdir -p "$WORKDIR"
	# tarball is extracted in /tmp (tmpfs): repo docs/tests never touch flash
	# -4: IPv4 only — half-configured IPv6 on routers stalls downloads
	wget -4 -q -O - -T 30 "$TARBALL_URL" | tar -xzf - -C "$WORKDIR" ||
		die "download or extract failed (check internet access and DNS)"
	set -- "$WORKDIR/${REPO_NAME}-"*
	SRC_DIR="$1"
	[ -d "$SRC_DIR/files" ] || die "unexpected archive layout (no files/ inside)"
}

install_deps() {
	local missing pkg real_wget
	missing=""
	# deps are checked by binary name (every current dep ships a same-named binary)
	# shellcheck disable=SC2086 -- DEPS is a word list
	for pkg in $DEPS; do
		command -v "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
	done
	if [ -z "$missing" ]; then
		log "dependencies already installed: $DEPS"
		return 0
	fi
	log "installing packages:$missing"
	# apk fetches by spawning `wget` from PATH and has no IPv4 switch;
	# interpose a tmpfs wrapper so apk downloads follow the IPv4-only rule too
	real_wget=$(command -v wget) || die "wget not found"
	mkdir -p "$WORKDIR/bin"
	printf '#!/bin/sh\nexec %s -4 "$@"\n' "$real_wget" > "$WORKDIR/bin/wget"
	chmod 755 "$WORKDIR/bin/wget"
	PATH="$WORKDIR/bin:$PATH" apk update >/dev/null ||
		die "apk update failed — test from the router: wget -4 -O /dev/null https://downloads.openwrt.org/"
	# shellcheck disable=SC2086 -- missing is a word list
	PATH="$WORKDIR/bin:$PATH" apk add $missing >/dev/null ||
		die "apk add failed (see errors above)"
}

install_files() {
	log "installing torwrt files"
	# never clobber existing user config on update
	if [ -f /etc/config/torwrt ]; then
		cp /etc/config/torwrt "$WORKDIR/config.keep"
	fi
	tar -C "$SRC_DIR/files" -cf - . | tar -C / -xf - || die "copying files failed"
	if [ -f "$WORKDIR/config.keep" ]; then
		mv "$WORKDIR/config.keep" /etc/config/torwrt
	fi
	mkdir -p /usr/lib/torwrt
	cp "$SRC_DIR/VERSION" /usr/lib/torwrt/VERSION
	# insurance in case exec bits get lost on the way through git/tar
	chmod 755 /etc/init.d/torwrt /usr/bin/torwrt /usr/libexec/rpcd/luci.torwrt
}

activate() {
	log "activating service and web UI"
	# tor package usually auto-starts on install; make sure it is enabled and up
	if [ -x /etc/init.d/tor ]; then
		/etc/init.d/tor enabled || /etc/init.d/tor enable || true
		pidof tor >/dev/null || /etc/init.d/tor start || die "failed to start tor"
	fi
	rm -f /tmp/torwrt.torver
	/etc/init.d/torwrt enable
	/etc/init.d/torwrt restart
	/etc/init.d/rpcd restart
	# LuCI caches menu/ACL: clear so Services -> Torwrt appears without a reboot
	rm -f /tmp/luci-indexcache*
	rm -rf /tmp/luci-modulecache/
}

main() {
	log "installer starting (target: OpenWrt >= ${MIN_VERSION})"
	check_system
	fetch_source
	install_deps
	install_files
	activate
	log "done — torwrt $(cat /usr/lib/torwrt/VERSION) installed"
	log "open LuCI -> Services -> Torwrt (hard-refresh the browser if the menu is missing)"
	log "to update later: re-run this installer"
}

main "$@"
