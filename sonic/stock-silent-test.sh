#!/usr/bin/env bash
# Sonic Screwdriver: checks what sonic/watch/launcher relies on to silence the
# stock launcher, off the watch. The stock launcher's notification sound is a
# QtMultimedia SoundEffect, in its NotificationView; this plays one as it
# does:
# - as it is, it opens a PulseAudio stream: the check sees it;
# - with QT_GSTREAMER_PLAYBIN_AUDIOSINK=fakesink alone, it still does;
# - with PULSE_SERVER=unix:/dev/null, as the wrapper sets, it opens none, the
#   app runs on, and it doesn't keep trying to connect.
# It uses the SDK's QtMultimedia and libpulse, the watch's exact builds,
# against Alpine's PulseAudio with only a null sink, in a throwaway 32-bit ARM
# container: nothing can sound, and what it plays is silence anyway.
#
#   sonic/stock-silent-test.sh
#
# Needs what sonic/build.sh sets up, and the network, for Alpine's PulseAudio.
set -euo pipefail

docker run --rm -i --platform linux/arm/v7 -v sonic-asteroid-sdk-2.1:/opt/asteroid-sdk:ro alpine:3.20 sh -s <<'TEST'
set -eu
apk add --no-cache -q pulseaudio pulseaudio-utils
S=/opt/asteroid-sdk/sysroots/armv7vehf-neon-oe-linux-gnueabi
export HOME=/root XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$XDG_RUNTIME_DIR" /tmp/t
chmod 700 "$XDG_RUNTIME_DIR"

# 1 s of silence: 16-bit mono at 44.1 kHz.
printf 'RIFF\254\130\001\000WAVEfmt \020\000\000\000\001\000\001\000\104\254\000\000\210\130\001\000\002\000\020\000data\210\130\001\000' > /tmp/t/silence.wav
head -c 88200 /dev/zero >> /tmp/t/silence.wav
# As NotificationView: a SoundEffect, played; then 9 s more.
cat > /tmp/t/sound.qml <<'QML'
import QtQuick 2.9
import QtMultimedia 5.4

Item {
    SoundEffect {
        id: notifSound
        source: "file:///tmp/t/silence.wav"
    }
    Timer { interval: 1000; running: true; onTriggered: notifSound.play() }
    Timer { interval: 10000; running: true; onTriggered: Qt.quit() }
}
QML

pulseaudio -n --daemonize=no --exit-idle-time=-1 --log-target=file:/tmp/t/pulse.log \
	-L "module-null-sink sink_name=speaker" \
	-L "module-native-protocol-unix auth-anonymous=1 socket=/tmp/t/pulse" &
for i in $(seq 100); do [ -S /tmp/t/pulse ] && break; sleep 0.2; done

fail=0
check() {
	if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: got $1, expected $2"; fail=1; fi
}

# play <env>...: plays it, and counts the most streams on the speaker meanwhile.
play() {
	env QT_PLUGIN_PATH="$S/usr/lib/plugins" QML2_IMPORT_PATH="$S/usr/lib/qml" QT_QPA_PLATFORM=offscreen "$@" \
		"$S/lib/ld-linux-armhf.so.3" --library-path "$S/lib:$S/usr/lib:$S/usr/lib/pulseaudio" \
		"$S/usr/bin/qmlscene" /tmp/t/sound.qml > /tmp/t/log 2>&1 &
	pid=$!
	streams=0
	while kill -0 $pid 2>/dev/null; do
		n=$(pactl -s unix:/tmp/t/pulse list short sink-inputs | wc -l)
		[ "$n" -le "$streams" ] || streams=$n
		sleep 0.2
	done
	status=0
	wait $pid || status=$?
}

play PULSE_SERVER=unix:/tmp/t/pulse
check "$status $([ $streams -ge 1 ] && echo stream || echo none)" "0 stream" "as it is: a stream on the speaker"
play PULSE_SERVER=unix:/tmp/t/pulse QT_GSTREAMER_PLAYBIN_AUDIOSINK=fakesink
check "$status $([ $streams -ge 1 ] && echo stream || echo none)" "0 stream" "fakesink alone: still a stream"
play PULSE_SERVER=unix:/dev/null QT_GSTREAMER_PLAYBIN_AUDIOSINK=fakesink
check "$status $streams" "0 0" "PULSE_SERVER=unix:/dev/null, as the wrapper: no stream, and it runs on"
tries=$(grep -c 'pa_context_connect() failed' /tmp/t/log || true)
check "$([ "$tries" -ge 1 ] && [ "$tries" -le 2 ] && echo yes || echo "no, $tries")" yes \
	"it tries to connect at its start only, not again in the 9 s after"

[ $fail = 0 ] && echo passed || { echo failed; exit 1; }
TEST
