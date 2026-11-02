#!/usr/bin/env bash
# Sonic Screwdriver: run the fork's asteroid-launcher on the watch.
#
#   sonic/deploy.sh           install sonic/out/asteroid-launcher and restart the launcher
#   sonic/deploy.sh --stock   switch back to the stock launcher and restart it
#   sonic/deploy.sh --status  show which launcher runs
#
# The stock /usr/bin/asteroid-launcher is never modified. A systemd user
# drop-in (sonic/watch/sonic.conf) starts /usr/local/libexec/sonic/launcher
# (sonic/watch/launcher), which runs the fork's build from
# /usr/local/lib/sonic-launcher/. After 3 starts within 2 minutes, it falls
# back to the stock launcher until the next deploy or reboot.
# Restarting the launcher closes any open app on the watch.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
watch=${SONIC_WATCH:-sonic-screwdriver}
bin=$here/out/asteroid-launcher

user_systemctl='systemctl --user -M ceres@'
# Wakelocks time out after 5 minutes, so a deploy that dies midway can't keep
# the watch awake.
wakelock_ns=300000000000
status='
	pid=$('"$user_systemctl"' show -p MainPID --value asteroid-launcher)
	exe=$(readlink /proc/$pid/exe 2>/dev/null || echo none)
	echo "launcher: $('"$user_systemctl"' is-active asteroid-launcher), pid $pid, $exe"
	[ -f /etc/systemd/user/asteroid-launcher.service.d/sonic.conf ] && echo "drop-in: installed (fork enabled)" || echo "drop-in: none (stock launcher)"
	[ -e /run/user/1000/sonic-launcher-fallback ] && echo "fallback: ACTIVE, the fork crash-looped; the stock launcher runs until the next deploy or reboot"
	[ -f /usr/local/lib/sonic-launcher/asteroid-launcher ] && echo "installed build: $(sha256sum /usr/local/lib/sonic-launcher/asteroid-launcher | cut -c1-12)"
	true'
# The stock launcher plays a sound from every notification view it creates, so
# its start can fire one per stored notification at once, and a crash loop
# ends in the stock launcher: the wrapper falls back to it after 3 starts. So
# the speaker sink stays muted until the launcher that should run ($expect,
# set before) has run with the same pid for 20 s, with no fallback. If it
# never does, the speaker stays muted, with a loud warning. A wakelock keeps
# the watch awake meanwhile.
# Between the stop and the start, the launcher's QML disk cache goes: Qt takes
# a cached compiled file as current while its source's time matches, and
# builds before resources were stamped from their contents all had the same
# time, so a new build could run an older build's QML. The start recompiles.
restart='
	echo "sonic_deploy '"$wakelock_ns"'" > /sys/power/wake_lock
	export PULSE_SERVER=unix:/run/user/1000/pulse/native PULSE_COOKIE=/home/ceres/.config/pulse/cookie
	case "$(pactl get-sink-mute speaker 2>/dev/null)" in *yes*) was_muted=1 ;; *) was_muted=0 ;; esac
	pactl set-sink-mute speaker 1 2>/dev/null || true
	t0=$(date +%s)
	rm -f /run/user/1000/sonic-launcher-starts /run/user/1000/sonic-launcher-fallback
	'"$user_systemctl"' daemon-reload
	'"$user_systemctl"' stop asteroid-launcher || true
	rm -rf /home/ceres/.cache/System/qmlcache
	'"$user_systemctl"' start asteroid-launcher || true
	steady=0 last= pid= waited=0 settled=0 fell_back=0
	while [ $waited -lt 150 ]; do
		sleep 1
		waited=$((waited + 1))
		if [ -e /run/user/1000/sonic-launcher-fallback ]; then
			fell_back=1
			break
		fi
		pid=$('"$user_systemctl"' show -p MainPID --value asteroid-launcher 2>/dev/null || echo 0)
		exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
		if [ "$pid" != 0 ] && [ "$pid" = "$last" ] && [ "${exe% (deleted)}" = "$expect" ]; then
			steady=$((steady + 1))
			if [ $steady -ge 20 ]; then
				settled=1
				break
			fi
		else
			steady=0
		fi
		last=$pid
	done
	if [ $settled = 1 ]; then
		[ "$was_muted" = 1 ] || pactl set-sink-mute speaker 0 2>/dev/null || true
		echo "$expect ran steadily for 20 s (pid $pid): the speaker is back as it was"
	else
		echo
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		if [ $fell_back = 1 ]; then
			echo "!!! WARNING: the fork crash-looped, and the wrapper fell back to the stock launcher."
		else
			echo "!!! WARNING: $expect did not run steadily for 20 s within 150 s."
		fi
		echo "!!! The speaker stays MUTED. Once the launcher is right, unmute it by hand:"
		echo "!!!   PULSE_SERVER=unix:/run/user/1000/pulse/native PULSE_COOKIE=/home/ceres/.config/pulse/cookie pactl set-sink-mute speaker 0"
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		echo
	fi
	echo sonic_deploy > /sys/power/wake_unlock
	'"$status"'
	echo "QML errors and warnings since the restart:"
	journalctl -q -o cat --since "@$t0" _SYSTEMD_USER_UNIT=asteroid-launcher.service 2>/dev/null |
		grep -E "qrc:|file:///|Error|error:|TypeError|ReferenceError" | head -n 20 | sed "s/^/  /"
	[ $settled = 1 ]'

case "${1:-}" in
--status)
	ssh "$watch" "$status"
	;;
--stock)
	ssh "$watch" "rm -f /etc/systemd/user/asteroid-launcher.service.d/sonic.conf
		rmdir /etc/systemd/user/asteroid-launcher.service.d 2>/dev/null
		expect=/usr/bin/asteroid-launcher
		$restart"
	;;
"")
	[ -f "$bin" ] || { echo "no build at $bin; run sonic/build.sh first" >&2; exit 1; }
	file "$bin" | grep -q 'ELF 32-bit LSB.*ARM' || { echo "$bin is not a 32-bit ARM binary" >&2; exit 1; }
	# The wakelock keeps the watch from suspending mid-copy; restart releases it.
	ssh "$watch" "echo 'sonic_deploy $wakelock_ns' > /sys/power/wake_lock; mkdir -p /tmp/sonic-launcher"
	scp -q "$bin" "$here/watch/launcher" "$here/watch/sonic.conf" "$watch:/tmp/sonic-launcher/"
	ssh "$watch" "set -e
		cd /tmp/sonic-launcher
		install -D -m 755 launcher /usr/local/libexec/sonic/launcher
		install -D -m 644 sonic.conf /etc/systemd/user/asteroid-launcher.service.d/sonic.conf
		d=/usr/local/lib/sonic-launcher
		mkdir -p \$d
		[ -f \$d/asteroid-launcher ] && cp -p \$d/asteroid-launcher \$d/asteroid-launcher.prev
		install -m 755 asteroid-launcher \$d/asteroid-launcher.new
		mv \$d/asteroid-launcher.new \$d/asteroid-launcher
		cd / && rm -rf /tmp/sonic-launcher
		expect=\$d/asteroid-launcher
		$restart"
	;;
*)
	echo "usage: $0 [--stock | --status]" >&2
	exit 64
	;;
esac
