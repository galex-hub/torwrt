# torwrt shared library — busybox ash, sourced only (no shebang).
# All real logic lives here; rpcd plugin / CLI / init stay thin (.ai/architecture.md).
# No `set -e` here: functions use return codes as data.

. /usr/share/libubox/jshn.sh

TORWRT_VERSION_FILE="/usr/lib/torwrt/VERSION"
TORWRT_TOR_INIT="/etc/init.d/tor"
TORWRT_TORVER_CACHE="/tmp/torwrt.torver"

twrt_version() {
	cat "$TORWRT_VERSION_FILE" 2>/dev/null || echo "unknown"
}

# twrt_uci_get <option> <default>
twrt_uci_get() {
	local v
	v=$(uci -q get "torwrt.main.$1" || :)
	[ -n "$v" ] && echo "$v" || echo "$2"
}

# prints first tor PID; rc 1 and no output when not running
twrt_tor_pid() {
	# shellcheck disable=SC2046 -- pidof output is a safe word list
	set -- $(pidof tor 2>/dev/null || :)
	[ $# -gt 0 ] || return 1
	echo "$1"
}

twrt_tor_installed() {
	[ -x "$TORWRT_TOR_INIT" ]
}

twrt_tor_enabled() {
	twrt_tor_installed && "$TORWRT_TOR_INIT" enabled >/dev/null 2>&1
}

# "Tor version 0.4.8.13." -> "0.4.8.13"; cached in tmpfs (poll calls this often)
twrt_tor_version() {
	local v
	if [ -s "$TORWRT_TORVER_CACHE" ]; then
		cat "$TORWRT_TORVER_CACHE"
		return 0
	fi
	v=$(tor --version 2>/dev/null | head -n 1 | sed -e 's/^Tor version //' -e 's/\.$//')
	[ -n "$v" ] && echo "$v" > "$TORWRT_TORVER_CACHE"
	echo "$v"
}

# sets TWRT_BOOTSTRAP_PCT (-1 = unknown) and TWRT_BOOTSTRAP_MSG from syslog
twrt_bootstrap_read() {
	local line pct
	TWRT_BOOTSTRAP_PCT=-1
	TWRT_BOOTSTRAP_MSG=""
	line=$(logread 2>/dev/null | grep 'Bootstrapped' | tail -n 1)
	[ -n "$line" ] || return 0
	TWRT_BOOTSTRAP_MSG=${line##*\]: }
	pct=$(echo "$line" | sed -n 's/.*Bootstrapped \([0-9][0-9]*\)%.*/\1/p')
	[ -n "$pct" ] && TWRT_BOOTSTRAP_PCT=$pct
	return 0
}

# twrt_tor_ctl start|stop|restart|enable|disable
twrt_tor_ctl() {
	twrt_tor_installed || return 1
	"$TORWRT_TOR_INIT" "$1" >/dev/null 2>&1
}

twrt_logs_text() {
	local n
	n=$(twrt_uci_get log_lines 50)
	logread 2>/dev/null | grep -E ' (Tor|tor)\[|torwrt' | tail -n "$n"
}

twrt_status_json() {
	local pid running enabled installed
	pid=$(twrt_tor_pid || :)
	running=0; [ -n "$pid" ] && running=1
	enabled=0; twrt_tor_enabled && enabled=1
	installed=0; twrt_tor_installed && installed=1
	twrt_bootstrap_read
	json_init
	json_add_string "torwrt_version" "$(twrt_version)"
	json_add_string "tor_version" "$(twrt_tor_version)"
	json_add_boolean "tor_installed" "$installed"
	json_add_boolean "running" "$running"
	[ -n "$pid" ] && json_add_int "pid" "$pid"
	json_add_boolean "enabled" "$enabled"
	json_add_int "bootstrap" "$TWRT_BOOTSTRAP_PCT"
	json_add_string "bootstrap_msg" "$TWRT_BOOTSTRAP_MSG"
	json_dump
}

twrt_logs_json() {
	json_init
	json_add_string "log" "$(twrt_logs_text)"
	json_dump
}

# curl exit code -> human message; args: <rc> <addr> <port>
twrt_curl_error() {
	case "$1" in
		6)   echo "DNS resolution of the check URL failed" ;;
		7)   echo "cannot connect to tor SOCKS at $2:$3 — is tor running?" ;;
		28)  echo "timed out — tor may not be connected (bootstrapped) yet" ;;
		127) echo "curl is not installed" ;;
		*)   echo "request failed (curl exit code $1)" ;;
	esac
}

# clean torwrt removal; the tor daemon and installed packages stay untouched
twrt_uninstall() {
	if [ -x /etc/init.d/torwrt ]; then
		/etc/init.d/torwrt stop >/dev/null 2>&1
		/etc/init.d/torwrt disable >/dev/null 2>&1
	fi
	rm -f /etc/init.d/torwrt \
		/etc/config/torwrt \
		/usr/bin/torwrt \
		/usr/libexec/rpcd/luci.torwrt \
		/usr/share/luci/menu.d/luci-app-torwrt.json \
		/usr/share/rpcd/acl.d/luci-app-torwrt.json \
		"$TORWRT_TORVER_CACHE"
	rm -rf /usr/lib/torwrt /www/luci-static/resources/view/torwrt
	/etc/init.d/rpcd restart >/dev/null 2>&1
	# clear LuCI caches so the menu entry disappears right away
	rm -f /tmp/luci-indexcache*
	rm -rf /tmp/luci-modulecache/
	return 0
}

# live connectivity test: web request through the tor SOCKS proxy
twrt_check_json() {
	local addr port url t0 t1 rc resp istor ip
	addr=$(twrt_uci_get socks_addr "127.0.0.1")
	port=$(twrt_uci_get socks_port "9050")
	url=$(twrt_uci_get check_url "https://check.torproject.org/api/ip")
	t0=$(date +%s)
	# -4: IPv4 only, project-wide rule for all downloads (see .ai/project.md)
	resp=$(curl -4 -s -m 12 --socks5-hostname "$addr:$port" "$url" 2>/dev/null)
	rc=$?
	t1=$(date +%s)
	if [ "$rc" -ne 0 ]; then
		json_init
		json_add_boolean "ok" 0
		json_add_string "error" "$(twrt_curl_error "$rc" "$addr" "$port")"
		json_add_int "elapsed_s" $((t1 - t0))
		json_dump
		return 0
	fi
	istor=""; ip=""
	if json_load "$resp" 2>/dev/null; then
		json_get_var istor IsTor
		json_get_var ip IP
	fi
	json_init
	if [ -z "$ip" ]; then
		json_add_boolean "ok" 0
		json_add_string "error" "unexpected response from check URL"
	else
		json_add_boolean "ok" 1
		json_add_boolean "is_tor" "${istor:-0}"
		json_add_string "ip" "$ip"
	fi
	json_add_int "elapsed_s" $((t1 - t0))
	json_dump
}
