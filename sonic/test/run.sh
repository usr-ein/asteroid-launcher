#!/bin/sh
# Inside sonic/test/test.sh's container, a 32-bit ARM Alpine that Docker runs
# through QEMU: the watch's apps and icons where the watch has them, a session
# bus, then each scene in the harness, with the SDK's own loader and
# libraries. A scene's log goes to /out/<scene>.log; a QML warning from the
# fork's own QML fails it.
set -eu

S=/opt/asteroid-sdk/sysroots/armv7vehf-neon-oe-linux-gnueabi
arm() {
	"$S/lib/ld-linux-armhf.so.3" --library-path "/stage/lib:$S/lib:$S/usr/lib" "$@"
}

# The watch's apps, as its /usr/share/applications has them (2026-11-01).
mkdir -p /usr/share/applications
while IFS='|' read -r id name icon center outer; do
	cat > "/usr/share/applications/$id.desktop" <<-END
		[Desktop Entry]
		Type=Application
		Categories=Applications;
		Exec=$id
		Icon=$icon
		X-Asteroid-Center-Color=$center
		X-Asteroid-Outer-Color=$outer
		Name=$name
	END
done <<-END
	asteroid-alarmclock|Alarm Clock|ios-alarm-outline|#CC9800|#0C0500
	asteroid-calculator|Calculator|ios-calculator-outline|#7CA600|#0C0B00
	asteroid-calendar|Agenda|ios-calendar-outline|#CC7700|#0C0300
	asteroid-diamonds|Diamonds|2048|#009933|#000C00
	asteroid-flashlight|Flashlight|ios-bulb-outline|#00A698|#000C07
	asteroid-hrm|Heart Rate|ios-heart-outline|#0097A6|#00060C
	asteroid-music|Music|ios-musical-notes-outline|#2577B3|#000619
	asteroid-settings|Settings|ios-settings-outline|#0044A6|#00010C
	asteroid-stopwatch|Stopwatch|ios-stopwatch-outline|#9800A6|#0C0009
	asteroid-timer|Timer|ios-timer-outline|#A6005F|#0C0003
	asteroid-weather|Weather|ios-cloudy-outline|#990019|#0C0200
	sonic-checkin|Check-in|ios-happy-outline|#11868F|#021314
END
# Check-in's second entry, hidden by its own NoDisplay=true.
printf '[Desktop Entry]\nType=Application\nName=Check-in\nIcon=ios-happy-outline\nExec=sonic-checkin\nNoDisplay=true\n' \
	> /usr/share/applications/sonic-health.desktop
mkdir -p /usr/local/share

# The watch's machine.conf, which qml-asteroid's DeviceSpecs reads.
mkdir -p /etc/asteroid
printf '[Display]\nROUND = true\n\n[Capabilities]\nHAS_SPEAKER = true\nHAS_WLAN = true\n\n[Identity]\nMACHINE = rubyfish\n' \
	> /etc/asteroid/machine.conf

# qml-asteroid's Icon reads /usr/share/icons/asteroid/<name>.svg.
mkdir -p /usr/share/icons/asteroid
ln -s "$S"/usr/share/icons/asteroid/*.svg /usr/share/icons/asteroid/

# Time zones, which Qt reads: the SDK's, as Alpine's minimal image has none.
ln -s "$S/usr/share/zoneinfo" /usr/share/zoneinfo
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
export TZ=UTC

export HOME=/home/ceres XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# The weather that the Today screen shows: partly sunny, 12° and 7°, as the
# weather app leaves it in dconf, compiled into the user's database.
mkdir -p "$HOME/.config/dconf" /tmp/dconf-keys
cat > /tmp/dconf-keys/weather <<-END
	[org/asteroidos/weather]
	timestamp-day0=$(date +%s)

	[org/asteroidos/weather/day0]
	id=801
	min-temp=280
	max-temp=285
END
arm "$S/usr/bin/dconf" compile "$HOME/.config/dconf/user" /tmp/dconf-keys

# The Today scene's calendar: mkcal's database under HOME, with the busy day.
export ARM="$S/lib/ld-linux-armhf.so.3 --library-path /stage/lib:$S/lib:$S/usr/lib"
arm /out/seed-calendar busy
arm "$S/usr/bin/dbus-daemon" --config-file=/src/sonic/test/dbus.conf --fork --nopidfile
# The test bus stands in for the system bus too, where nothing answers.
export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/test-bus DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/test-bus

export LANG=en_GB.UTF-8 QT_QPA_PLATFORM=vnc:size=454x454 QT_QUICK_BACKEND=software
export QT_PLUGIN_PATH=$S/usr/lib/plugins QML2_IMPORT_PATH=/src/sonic/test/stubs:$S/usr/lib/qml
export FONTCONFIG_FILE=/src/sonic/test/fonts.conf QT_LOGGING_RULES='qt.qpa.*=false'

status=0
for scene in "$@"; do
	echo "== $scene"
	scene_status=0
	timeout 900 "$S/lib/ld-linux-armhf.so.3" --library-path "/stage/lib:$S/lib:$S/usr/lib" \
		/out/launcher-test "/src/sonic/test/$scene.qml" > "/out/$scene.log" 2>&1 || scene_status=$?
	grep -v -e '^QVncServer created' "/out/$scene.log" || true
	# A warning from the fork's own QML, or from the scene, fails it.
	if grep -q -e '^qrc:/qml/' -e '^file:///src/' "/out/$scene.log"; then
		echo "$scene: QML warnings" >&2
		scene_status=1
	fi
	[ $scene_status = 0 ] || status=1
done
exit $status
