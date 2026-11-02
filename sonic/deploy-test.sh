#!/usr/bin/env bash
# Sonic Screwdriver: tests deploy.sh's restart, which keeps the speaker muted
# until the launcher that should run has run steadily, and the watch's
# wrapper, sonic/watch/launcher, which silences the stock launcher when it
# runs it, off the watch: in a throwaway Alpine container, with systemctl,
# pactl, readlink, sleep and the two launchers stood in for, as root.
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
# With $wrapper_muted set: what the wrapper says the speaker was, before it
# muted it for the stock launcher.
marker=/home/ceres/.local/state/sonic-launcher-muted
run() {
	mkdir -p /run/user/1000 /tmp/t "$(dirname $marker)"
	rm -f /run/user/1000/sonic-launcher-fallback /tmp/t/* $marker
	[ -z "${wrapper_muted:-}" ] || echo "$wrapper_muted" > $marker
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

run no "$fork" "4242 4242 4242 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999 999" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: no" "a restart midway: steady again for 20 s, then unmuted"
# 3 calls on the old pid, 1 on the new one that resets the count, 20 more,
# and the status line's own.
check "$(cat /tmp/t/calls)" 25 "after 20 s on the new pid"

# The wrapper muted the speaker for the stock launcher: what it was before.
wrapper_muted=no run yes "$fork" "4242" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: no" "muted by the wrapper, unmuted before: a steady deploy unmutes it"
check "$([ -e $marker ] && echo kept || echo gone)" gone "and forgets the wrapper's mute"
wrapper_muted=yes run yes "$fork" "4242" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: yes" "muted by the wrapper, muted before too: it stays muted"
wrapper_muted=no run yes "$fork" "100 101 102 103 104 105" "$fork" 6
check "$(cat /tmp/t/mute)" "Mute: yes" "muted by the wrapper, and the deploy falls back: muted"
check "$([ -e $marker ] && echo kept || echo gone)" kept "and the wrapper's mute kept, for the next deploy"
wrapper_muted=unknown run yes "$fork" "4242" "$fork" 0
check "$(cat /tmp/t/mute)" "Mute: yes" "muted by the wrapper, from a state it couldn't read: muted"
check "$(grep -c 'stays MUTED' /tmp/t/out)" 1 "with the line to unmute it"
unset wrapper_muted

# The wrapper, as the launcher's unit runs it, with stand-ins for pactl and
# the two launchers, which say how they were started.
mkdir -p /usr/local/lib/sonic-launcher /tmp/w/bin
printf '#!/bin/sh\necho "$0|${PULSE_SERVER-unset}|${QT_GSTREAMER_PLAYBIN_AUDIOSINK-unset}|$*" > /tmp/w/ran\n' > /tmp/w/launcher
chmod 755 /tmp/w/launcher
cp /tmp/w/launcher /usr/bin/asteroid-launcher
printf '#!/bin/sh
echo "$*" >> /tmp/w/pactl
case "$(cat /tmp/w/pulse)" in down) exit 1 ;; hang) exec sleep 10 ;; esac
case "$1" in
get-sink-mute) cat /tmp/w/mute ;;
set-sink-mute) echo "Mute: $([ "$3" = 1 ] && echo yes || echo no)" > /tmp/w/mute ;;
esac
' > /tmp/w/bin/pactl
chmod 755 /tmp/w/bin/pactl

# wrap <a fork build: yes|no> <the fallback flag: yes|no> <PulseAudio: up|down|hang>
# <muted at first: yes|no>, with $keep_home set to keep the last run's HOME.
wrap() {
	[ -n "${keep_home:-}" ] || rm -rf /tmp/w/home
	rm -rf /tmp/w/run /tmp/w/ran /tmp/w/pactl
	mkdir -p /tmp/w/home /tmp/w/run
	if [ "$1" = yes ]; then cp /tmp/w/launcher "$fork"; else rm -f "$fork"; fi
	[ "$2" = no ] || : > /tmp/w/run/sonic-launcher-fallback
	echo "$3" > /tmp/w/pulse
	echo "Mute: $4" > /tmp/w/mute
	t=$(date +%s)
	HOME=/tmp/w/home XDG_RUNTIME_DIR=/tmp/w/run PATH="/tmp/w/bin:$PATH" sh /sonic/watch/launcher --systemd 2> /tmp/w/err
	took=$(($(date +%s) - t))
}
silenced="$stock|unix:/dev/null|fakesink|--systemd"
wmarker=/tmp/w/home/.local/state/sonic-launcher-muted

wrap yes no up no
check "$(cat /tmp/w/ran)" "$fork|unset|unset|--systemd" "the wrapper: the fork's build, with its sounds as they are"
check "$([ -e /tmp/w/pactl ] && echo called || echo none)" none "and the speaker left alone"

wrap yes yes up no
check "$(cat /tmp/w/ran)" "$silenced" "after a fallback: the stock launcher, its own sounds silenced"
check "$(cat /tmp/w/mute)" "Mute: yes" "and the speaker muted"
check "$(cat $wmarker)" no "and what it was before kept"
check "$(grep -c 'muted the speaker' /tmp/w/err)" 1 "and says so"
check "$(grep -c 'its own sounds silenced' /tmp/w/err)" 1 "both"

keep_home=1 wrap yes yes up yes
check "$(cat $wmarker)" no "a second stock start, the speaker muted then: what it was before the first kept"
check "$(grep -c get-sink-mute /tmp/w/pactl)" 0 "without reading it again"

wrap no no up no
check "$(cat /tmp/w/ran)" "$silenced" "without a fork build: the stock launcher, silenced"
check "$(cat /tmp/w/mute)" "Mute: yes" "and the speaker muted"

wrap yes yes up yes
check "$(cat $wmarker)" yes "the speaker muted before: that's kept"

rm -rf /tmp/w/run; mkdir -p /tmp/w/run
now=$(cut -d. -f1 /proc/uptime)
printf '%s\n%s\n%s\n' $now $now $now > /tmp/w/run/sonic-launcher-starts
rm -rf /tmp/w/home; mkdir -p /tmp/w/home; echo up > /tmp/w/pulse; echo "Mute: no" > /tmp/w/mute; cp /tmp/w/launcher "$fork"
HOME=/tmp/w/home XDG_RUNTIME_DIR=/tmp/w/run PATH="/tmp/w/bin:$PATH" sh /sonic/watch/launcher --systemd 2> /tmp/w/err
check "$(cat /tmp/w/ran)" "$silenced" "a fourth start in 2 minutes: the stock launcher, silenced"
check "$([ -e /tmp/w/run/sonic-launcher-fallback ] && echo yes || echo no)" yes "and the fallback flag set"

wrap yes yes down no
check "$(cat /tmp/w/ran)" "$silenced" "PulseAudio not up: the stock launcher starts all the same, silenced"
check "$(grep -c "couldn't mute the speaker" /tmp/w/err)" 1 "and says it couldn't mute the speaker"
check "$([ -e $wmarker ] && echo kept || echo none)" none "and keeps no mute of its own"

wrap yes yes hang no
check "$(cat /tmp/w/ran)" "$silenced" "PulseAudio hung: the stock launcher starts, silenced"
check "$([ $took -le 8 ] && echo yes || echo "no, $took s")" yes "within 8 s"

[ $fail = 0 ] && echo passed || { echo "failed"; exit 1; }
TEST
