#!/bin/sh
# torwrt installer for OpenWrt >= 25.12.4.
# Usage on the router:
#   wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh
#   sh /tmp/torwrt-install.sh
# Re-running updates an existing install; user config is preserved.
# Nothing is changed on the system until connectivity to every required
# resource has been confirmed.
# Env overrides: TORWRT_BRANCH=<branch>   TORWRT_FORCE=1 (skip version gate)
set -eu

REPO_OWNER="galex-hub"
REPO_NAME="torwrt"
BRANCH="${TORWRT_BRANCH:-main}"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
FEEDS_PROBE_URL="https://downloads.openwrt.org/"
MIN_VERSION="25.12.4"
DEPS="tor curl"
WORKDIR="/tmp/torwrt-install.$$"
SRC_DIR=""
NET_FLAGS="-4"
DEPS_MISSING=""
OLD_VERSION=""

log() { echo "torwrt: $*"; }
ok()  { printf '\033[1;32mtorwrt: %s\033[0m\n' "$*"; }
die() { echo "torwrt: ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# retry <attempts> <command...>
retry() {
	local n max
	n=1; max="$1"; shift
	while ! "$@"; do
		[ "$n" -ge "$max" ] && return 1
		n=$((n + 1))
		log "retrying ($n/$max)..."
		sleep 2
	done
	return 0
}

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

collect_missing_deps() {
	local pkg
	DEPS_MISSING=""
	# deps are checked by binary name (every current dep ships a same-named binary)
	# shellcheck disable=SC2086 -- DEPS is a word list
	for pkg in $DEPS; do
		command -v "$pkg" >/dev/null 2>&1 || DEPS_MISSING="$DEPS_MISSING $pkg"
	done
}

# one tarball fetch attempt into tmpfs; $1 = wget flags ("-4" or "")
fetch_tar() {
	rm -rf "$WORKDIR/src"
	mkdir -p "$WORKDIR/src"
	# shellcheck disable=SC2086 -- $1 is optional wget flags
	wget $1 -q -O - -T 20 "$TARBALL_URL" 2>/dev/null | tar -xzf - -C "$WORKDIR/src" 2>/dev/null
}

# downloads the repo tarball and picks the network mode for everything after:
# IPv4-only whenever it works (project rule), system default as a fallback
fetch_source() {
	log "downloading ${TARBALL_URL}"
	if fetch_tar "-4"; then
		NET_FLAGS="-4"
		log "network mode: IPv4-only"
	elif fetch_tar ""; then
		NET_FLAGS=""
		log "warning: IPv4-only download failed; using system default (IPv6 may be used)"
	else
		die "cannot download the torwrt archive (codeload.github.com unreachable) — aborted, nothing was installed"
	fi
	set -- "$WORKDIR/src/${REPO_NAME}-"*
	SRC_DIR="$1"
	[ -d "$SRC_DIR/files" ] || die "unexpected archive layout (no files/ inside)"
}

feeds_probe() {
	# shellcheck disable=SC2086 -- NET_FLAGS is an optional flag word
	wget $NET_FLAGS -q -O /dev/null -T 15 "$FEEDS_PROBE_URL" 2>/dev/null
}

preflight_feeds() {
	log "checking package feed reachability: $FEEDS_PROBE_URL"
	retry 2 feeds_probe ||
		die "downloads.openwrt.org is unreachable — aborted, nothing was installed (test: wget -4 -O /dev/null $FEEDS_PROBE_URL)"
}

apk_update_q() { PATH="$WORKDIR/bin:$PATH" apk update >/dev/null; }
apk_add_q() {
	# shellcheck disable=SC2086 -- DEPS_MISSING is a word list
	PATH="$WORKDIR/bin:$PATH" apk add $DEPS_MISSING >/dev/null
}

install_deps() {
	local real_wget
	if [ -z "$DEPS_MISSING" ]; then
		log "dependencies already installed: $DEPS"
		return 0
	fi
	log "installing packages:$DEPS_MISSING"
	# apk spawns `wget` for downloads and has no IPv4 switch: interpose a
	# tmpfs wrapper that applies the chosen network mode
	real_wget=$(command -v wget) || die "wget not found"
	mkdir -p "$WORKDIR/bin"
	printf '#!/bin/sh\nexec %s %s "$@"\n' "$real_wget" "$NET_FLAGS" > "$WORKDIR/bin/wget"
	chmod 755 "$WORKDIR/bin/wget"
	retry 3 apk_update_q || die "apk update failed (see errors above)"
	retry 2 apk_add_q || die "apk add failed (see errors above)"
}

install_files() {
	log "installing torwrt files"
	OLD_VERSION=$(cat /usr/lib/torwrt/VERSION 2>/dev/null || echo "")
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

summary() {
	local newv
	newv=$(cat /usr/lib/torwrt/VERSION 2>/dev/null || echo "?")
	if [ -n "$OLD_VERSION" ]; then
		ok "SUCCESS — torwrt updated: ${OLD_VERSION} -> ${newv}"
	else
		ok "SUCCESS — torwrt ${newv} installed"
	fi
	ok "web UI: LuCI -> Services -> Torwrt (hard-refresh the browser if the menu is missing)"
	log "update: re-run this installer | uninstall: torwrt uninstall"
}

main() {
	log "installer starting (target: OpenWrt >= ${MIN_VERSION})"
	check_system
	collect_missing_deps
	fetch_source
	if [ -n "$DEPS_MISSING" ]; then
		preflight_feeds
	fi
	install_deps
	install_files
	activate
	summary
}

main "$@"
