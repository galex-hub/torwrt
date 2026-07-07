#!/bin/sh
# torwrt installer for OpenWrt >= 25.12.4.
# Usage on the router:
#   wget -4 -O /tmp/torwrt-install.sh https://raw.githubusercontent.com/galex-hub/torwrt/main/install.sh
#   sh /tmp/torwrt-install.sh [--proxy socks5://[user:pass@]host:port]
# Re-running updates an existing install; user config is preserved.
# Nothing is changed on the system until connectivity to every required
# resource has been confirmed.
# Options:
#   --proxy <url>   route ALL downloads through a SOCKS5 proxy (requires curl).
#                   Accepts socks5://host:port, host:port, or user:pass@host:port.
# Env overrides: TORWRT_BRANCH=<branch>  TORWRT_FORCE=1 (skip version gate)
#                TORWRT_PROXY=<url> (same as --proxy)
set -eu

REPO_OWNER="galex-hub"
REPO_NAME="torwrt"
BRANCH="${TORWRT_BRANCH:-main}"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
FEEDS_PROBE_URL="https://downloads.openwrt.org/"
MIN_VERSION="25.12.4"
DEPS="tor curl obfs4proxy"
WORKDIR="/tmp/torwrt-install.$$"
SRC_DIR=""
NET_FLAGS="-4"
DEPS_MISSING=""
OLD_VERSION=""
PROXY="${TORWRT_PROXY:-}"
CURL_PROXY=""
MODE="direct"

log() { echo "torwrt: $*"; }
ok()  { printf '\033[1;32mtorwrt: %s\033[0m\n' "$*"; }
die() { echo "torwrt: ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

usage() {
	cat <<EOF
torwrt installer (OpenWrt >= $MIN_VERSION)

  sh install.sh [--proxy <socks5-url>]

  --proxy <url>   route all downloads through a SOCKS5 proxy (needs curl).
                  Forms: socks5://host:port | host:port | user:pass@host:port
  -h, --help      show this help

Env: TORWRT_BRANCH, TORWRT_FORCE=1, TORWRT_PROXY
EOF
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--proxy) [ $# -ge 2 ] || die "--proxy needs a value"; PROXY="$2"; shift 2 ;;
			--proxy=*) PROXY="${1#*=}"; shift ;;
			-h|--help) usage; exit 0 ;;
			*) die "unknown option: $1 (see --help)" ;;
		esac
	done
}

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

# any proxy string -> curl form: socks5h://[user:pass@]host:port (h = resolve via proxy)
normalize_proxy() {
	p="$1"
	case "$p" in *://*) p=${p#*://} ;; esac
	printf 'socks5h://%s' "$p"
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

# decide the download mechanism; verify the proxy before touching anything
setup_download() {
	[ -n "$PROXY" ] || return 0
	command -v curl >/dev/null 2>&1 ||
		die "installing through a SOCKS5 proxy requires 'curl', which is not installed — install it first (from a direct connection) or run without --proxy"
	CURL_PROXY=$(normalize_proxy "$PROXY")
	MODE="proxy"
	log "routing all downloads through SOCKS5 proxy: $CURL_PROXY"
	log "verifying proxy reachability..."
	curl -fsS -x "$CURL_PROXY" -m 20 -o /dev/null "$FEEDS_PROBE_URL" ||
		die "proxy check failed — cannot reach $FEEDS_PROBE_URL through the proxy (aborted, nothing was installed)"
	ok "proxy OK"
}

collect_missing_deps() {
	local pkg
	DEPS_MISSING=""
	# deps are checked by binary name (every dep ships a same-named binary)
	# shellcheck disable=SC2086 -- DEPS is a word list
	for pkg in $DEPS; do
		command -v "$pkg" >/dev/null 2>&1 || DEPS_MISSING="$DEPS_MISSING $pkg"
	done
	# ca-bundle ships no binary — check the cert file; curl needs it for TLS
	[ -f /etc/ssl/certs/ca-certificates.crt ] || DEPS_MISSING="$DEPS_MISSING ca-bundle"
}

# one direct tarball fetch into tmpfs; $1 = wget flags ("-4" or "")
fetch_tar() {
	rm -rf "$WORKDIR/src"
	mkdir -p "$WORKDIR/src"
	# shellcheck disable=SC2086 -- $1 is optional wget flags
	wget $1 -q -O - -T 20 "$TARBALL_URL" 2>/dev/null | tar -xzf - -C "$WORKDIR/src" 2>/dev/null
}

fetch_source() {
	log "downloading ${TARBALL_URL}"
	if [ "$MODE" = "proxy" ]; then
		rm -rf "$WORKDIR/src"; mkdir -p "$WORKDIR/src"
		curl -fsSL -x "$CURL_PROXY" -m 120 "$TARBALL_URL" | tar -xzf - -C "$WORKDIR/src" 2>/dev/null ||
			die "cannot download the torwrt archive through the proxy — aborted, nothing was installed"
	elif fetch_tar "-4"; then
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
	if [ "$MODE" = "proxy" ]; then
		curl -fsS -x "$CURL_PROXY" -m 15 -o /dev/null "$FEEDS_PROBE_URL"
	else
		# shellcheck disable=SC2086 -- NET_FLAGS is an optional flag word
		wget $NET_FLAGS -q -O /dev/null -T 15 "$FEEDS_PROBE_URL"
	fi
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

# apk downloads by spawning `wget`; interpose a wrapper so its traffic follows
# the chosen network mode (IPv4-only, or the SOCKS5 proxy via curl)
make_wget_wrapper() {
	local real_wget
	mkdir -p "$WORKDIR/bin"
	if [ "$MODE" = "proxy" ]; then
		# translate wget-style calls (apk uses -O <file>/-O -) into curl+proxy
		cat > "$WORKDIR/bin/wget" <<EOF
#!/bin/sh
url=""; out="-"
while [ \$# -gt 0 ]; do
	case "\$1" in
		-O) out="\$2"; shift 2; continue ;;
		-O*) out="\${1#-O}"; shift; continue ;;
		--output-document=*) out="\${1#*=}"; shift; continue ;;
		-T) shift 2; continue ;;
		http://*|https://*|ftp://*) url="\$1"; shift; continue ;;
		-*) shift; continue ;;
		*) [ -z "\$url" ] && url="\$1"; shift; continue ;;
	esac
done
[ -n "\$url" ] || exit 4
if [ "\$out" = "-" ]; then
	exec curl -fsSL --connect-timeout 30 -x "$CURL_PROXY" "\$url"
else
	exec curl -fsSL --connect-timeout 30 -x "$CURL_PROXY" -o "\$out" "\$url"
fi
EOF
	else
		real_wget=$(command -v wget) || die "wget not found"
		printf '#!/bin/sh\nexec %s %s "$@"\n' "$real_wget" "$NET_FLAGS" > "$WORKDIR/bin/wget"
	fi
	chmod 755 "$WORKDIR/bin/wget"
}

install_deps() {
	if [ -z "$DEPS_MISSING" ]; then
		log "dependencies already installed: $DEPS"
		return 0
	fi
	log "installing packages:$DEPS_MISSING"
	make_wget_wrapper
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
	parse_args "$@"
	log "installer starting (target: OpenWrt >= ${MIN_VERSION})"
	check_system
	setup_download
	collect_missing_deps
	fetch_source
	if [ -n "$DEPS_MISSING" ]; then preflight_feeds; fi
	install_deps
	install_files
	activate
	summary
}

main "$@"
