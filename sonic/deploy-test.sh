#!/usr/bin/env bash
# Sonic Screwdriver: tests deploy.sh's restart, which keeps the speaker muted
# until the launcher that should run has run steadily, and the watch's
# wrapper, sonic/watch/launcher, which silences the stock launcher's own
# process when it runs it, off the watch: in a throwaway Alpine container,
# with systemctl, pactl, readlink, sleep and the two launchers stood in for,
# as root.
#
#   sonic/deploy-test.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
docker run --rm -i -v "$here:/sonic:ro" alpine:3.20 sh -s <<'TEST'
set -eu
# deploy.sh's variables, up to its case: user_systemctl, status and restart.
eval "$(sed -n '/^user_systemctl=/,/^case /p' /sonic/deploy.sh | sed '$d')"

fail=0
check() {
	if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: got $1, expected $2"; fail=1; fi
}

# run <muted at first: yes|no> <expected exe> <the pids MainPID gives, one per
# call> <the exe each runs> <the call after which the fallback flag appears, or 0>
qmlcache=/home/ceres/.cache/System/qmlcache
run() {
	mkdir -p /run/user/1000 /tmp/t $qmlcache
	rm -f /run/user/1000/sonic-launcher-fallback /tmp/t/*
	: > $qmlcache/stale.qmlc
	echo "Mute: $1" > /tmp/t/mute
	echo "$3" | tr ' ' '\n' > /tmp/t/pids
	echo "$4" > /tmp/t/exe
	echo "$5" > /tmp/t/fallback-at
	echo 0 > /tmp/t/calls
	(
		sleep() { :; }
		journalctl() { :; }
		pactl() {
			case "$1" in
			get-sink-mute) cat /tmp/t/mute ;;
			set-sink-mute) echo "Mute: $([ "$3" = 1 ] && echo yes || echo no)" > /tmp/t/mute; echo "$3" >> /tmp/t/mutes ;;
			esac
		}
		systemctl() {
			case "$*" in
			*"show -p MainPID"*)
				calls=$(($(cat /tmp/t/calls) + 1))
				echo $calls > /tmp/t/calls
				at=$(cat /tmp/t/fallback-at)
				[ "$at" = 0 ] || [ $calls -lt "$at" ] || : > /run/user/1000/sonic-launcher-fallback
				pid=$(sed -n "${calls}p" /tmp/t/pids)
				[ -n "$pid" ] || pid=$(tail -n 1 /tmp/t/pids)
				echo "$pid"
				;;
			*is-active*) echo active ;;
			*" stop "*) echo "stop: cache $([ -e $qmlcache ] && echo there || echo gone)" >> /tmp/t/order ;;
			*" start "*) echo "start: cache $([ -e $qmlcache ] && echo there || echo gone)" >> /tmp/t/order ;;
			esac
		}
		readlink() { cat /tmp/t/exe; }
		expect=$2
		eval "$restart" > /tmp/t/out 2>&1 && echo 0 > /tmp/t/status || echo 1 > /tmp/t/status
	)
}

fork=/usr/local/lib/sonic-launcher/asteroid-launcher
stock=/usr/bin/asteroid-launcher

run no "$fork" "4242" "$fork" 0
check "$(cat /tmp/t/status)" 0 "steady fork: it succeeds"
check "$(cat /tmp/t/mute)" "Mute: no" "and unmutes the speaker, as it was"
check "$(grep -c 'ran steadily for 20 s' /tmp/t/out)" 1 "and says so"
check "$(cat /tmp/t/order | tr '\n' ' ')" "stop: cache there start: cache gone " \
	"the QML cache cleared between the stop and the start"

run yes "$fork" "4242" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: yes" "steady, but muted before: it stays muted"

run no "$fork" "100 101 102 103 104 105" "$fork" 6
check "$(cat /tmp/t/status)" 1 "a crash loop that falls back: it fails"
check "$(cat /tmp/t/mute)" "Mute: yes" "and the speaker stays muted"
check "$(grep -c 'fell back to the stock launcher' /tmp/t/out)" 1 "with the loud warning"

run no "$fork" "$(seq -s ' ' 1 200)" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: yes" "a launcher that never stays up: muted"
check "$(grep -c 'did not run steadily' /tmp/t/out)" 1 "with the warning"

run no "$fork" "4242" "$stock" 0
check "$(cat /tmp/t/mute)" "Mute: yes" "the stock launcher where the fork should run: muted"

run no "$stock" "4242" "$stock" 0
check "$(cat /tmp/t/mute)" "Mute: no" "--stock: the stock launcher steady, the speaker as it was"
check "$(cat /tmp/t/order | tr '\n' ' ')" "stop: cache there start: cache gone " "and the QML cache cleared too"

run no "$fork" "4242 4242 4242 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: no" "a restart midway: steady again for 20 s, then unmuted"
# 3 calls on the old pid, 1 on the new one that resets the count, 20 more,
# and the status line's own.
check "$(cat /tmp/t/calls)" 25 "after 20 s on the new pid"

# The wrapper, as the launcher's unit runs it, with stand-ins for pactl and
# the two launchers, which say how they were started. The stand-in pactl hangs
# when /tmp/w/pulse says so, and logs each call.
mkdir -p /usr/local/lib/sonic-launcher /tmp/w/bin
printf '#!/bin/sh\necho "$0|${PULSE_SERVER-unset}|${QT_GSTREAMER_PLAYBIN_AUDIOSINK-unset}|$*" > /tmp/w/ran\n' > /tmp/w/launcher
chmod 755 /tmp/w/launcher
cp /tmp/w/launcher /usr/bin/asteroid-launcher
printf '#!/bin/sh
echo "$*" >> /tmp/w/pactl
case "$(cat /tmp/w/pulse)" in down) exit 1 ;; hang) exec sleep 10 ;; esac
' > /tmp/w/bin/pactl
chmod 755 /tmp/w/bin/pactl

# wrap <a fork build: yes|no> <the fallback flag: yes|no> <PulseAudio: up|down|hang>
wrap() {
	rm -rf /tmp/w/home /tmp/w/run /tmp/w/ran /tmp/w/pactl
	mkdir -p /tmp/w/home /tmp/w/run
	if [ "$1" = yes ]; then cp /tmp/w/launcher "$fork"; else rm -f "$fork"; fi
	[ "$2" = no ] || : > /tmp/w/run/sonic-launcher-fallback
	echo "$3" > /tmp/w/pulse
	t=$(date +%s)
	HOME=/tmp/w/home XDG_RUNTIME_DIR=/tmp/w/run PATH="/tmp/w/bin:$PATH" sh /sonic/watch/launcher --systemd 2> /tmp/w/err
	took=$(($(date +%s) - t))
}
silenced="$stock|unix:/dev/null|fakesink|--systemd"
nopactl() { [ -e /tmp/w/pactl ] && echo called || echo none; }

wrap yes no up
check "$(cat /tmp/w/ran)" "$fork|unset|unset|--systemd" "the wrapper: the fork's build, its environment as it is"
check "$(nopactl)" none "and no pactl"

wrap yes yes up
check "$(cat /tmp/w/ran)" "$silenced" "after a fallback: the stock launcher, its own process silenced"
check "$(nopactl)" none "and no pactl: the speaker as it is"
check "$(grep -c 'its own sounds silenced' /tmp/w/err)" 1 "and says so"

wrap no no up
check "$(cat /tmp/w/ran)" "$silenced" "without a fork build: the stock launcher, silenced"
check "$(nopactl)" none "and no pactl"

rm -rf /tmp/w/run /tmp/w/pactl; mkdir -p /tmp/w/run
now=$(cut -d. -f1 /proc/uptime)
printf '%s\n%s\n%s\n' $now $now $now > /tmp/w/run/sonic-launcher-starts
cp /tmp/w/launcher "$fork"
HOME=/tmp/w/home XDG_RUNTIME_DIR=/tmp/w/run PATH="/tmp/w/bin:$PATH" sh /sonic/watch/launcher --systemd 2> /tmp/w/err
check "$(cat /tmp/w/ran)" "$silenced" "a fourth start in 2 minutes: the stock launcher, silenced"
check "$([ -e /tmp/w/run/sonic-launcher-fallback ] && echo yes || echo no)" yes "and the fallback flag set"
check "$(nopactl)" none "and no pactl"

wrap yes yes hang
check "$(cat /tmp/w/ran)" "$silenced" "PulseAudio hung: the stock launcher starts all the same, silenced"
check "$([ $took -le 1 ] && echo yes || echo "no, $took s")" yes "at once: the start doesn't wait on PulseAudio"
wrap yes yes down
check "$(cat /tmp/w/ran)" "$silenced" "PulseAudio down: the same"

[ $fail = 0 ] && echo passed || { echo "failed"; exit 1; }
TEST
