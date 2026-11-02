#!/usr/bin/env bash
# Sonic Screwdriver: tests deploy.sh's restart, which keeps the speaker muted
# until the launcher that should run has run steadily, off the watch: in a
# throwaway Alpine container, with systemctl, pactl, readlink and sleep stood
# in for, as root, as on the watch.
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
run() {
	mkdir -p /run/user/1000 /tmp/t
	rm -f /run/user/1000/sonic-launcher-fallback /tmp/t/*
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

[ $fail = 0 ] && echo passed || { echo "failed"; exit 1; }
TEST
