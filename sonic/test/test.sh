#!/usr/bin/env bash
# Sonic Screwdriver: the launcher's QML off the watch, under emulation.
#
#   sonic/test/test.sh             every scene
#   sonic/test/test.sh <scene>...  these scenes: applist, quickpanel, today,
#                                  button, then preview, a sheet of the
#                                  others' screenshots
#
# Each scene (sonic/test/<scene>.qml) runs the fork's own QML, compiled in as
# in the launcher, in a 454 × 454 view: the watch's screen. It uses the SDK's
# Qt 5.15.16, qml-asteroid 2.1 and Nemo plugins, the watch's exact builds, and
# the watch's own liblipstick, in a 32-bit ARM container that Docker runs
# through QEMU, with Qt Quick's software renderer. The scenes check what they
# show and save screenshots to sonic/out/test/shots/. Invented data only:
# nothing runs on the watch. The watch is read once, over SSH, for the two
# libraries that lipstick needs and the SDK lacks, and for its Noto Sans.
#
# Needs Docker and what sonic/build.sh sets up; this runs it first.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
sonic=$(dirname "$here")
src=$(dirname "$sonic")
cache=${SONIC_CACHE:-$HOME/.cache/sonic-screwdriver}
watch=${SONIC_WATCH:-sonic-screwdriver}
out=$sonic/out/test
image='sonic-asteroid-launcher-sdk:2.1'
sdk_volume='sonic-asteroid-sdk-2.1'
build_volume=${SONIC_BUILD_VOLUME:-sonic-asteroid-launcher-build}-test
sdk_dir=/opt/asteroid-sdk
stage=$cache/launcher-stage
fonts=$cache/watch-fonts
all_scenes="applist quickpanel today button preview"

# <local name> <path on the watch> <sha256>
watch_libs="
libmce-qt5.so.1 /usr/lib/libmce-qt5.so.1.4.2 ddeb3e7677d0b077dbed37fb4ba96a2081c6ae219e1e679812bf6db47ebc19fe
libngf-qt5.so.0 /usr/lib/libngf-qt5.so.0.4.0 ff0ac3c2f1de243bb9c938135789858c33894218dd2331db91472537f3decb28
"
watch_fonts="
NotoSans-Regular.ttf /usr/share/fonts/NotoSans-Regular.ttf 84cf0b0d86f1a765eec2297bd7e9fc9d146500e0fb7e2723f9f93aaff988f83d
NotoSans-Medium.ttf /usr/share/fonts/NotoSans-Medium.ttf e5ed793c4aacb920bd9eaaa683b920d7fa3a8bc4891a30d499bd164c82104aeb
NotoSans-SemiBold.ttf /usr/share/fonts/NotoSans-SemiBold.ttf 2ba924f1ae62968fa0f2b029194138a7b75d5094dc5d4807ab5ef806d4d7a0ac
NotoSans-Bold.ttf /usr/share/fonts/NotoSans-Bold.ttf 1b9bb20fb26b8c3cdc48a303bdd189a25dc73a1a3a4fa36c5e4f9621c9621aca
NotoSans-Light.ttf /usr/share/fonts/NotoSans-Light.ttf c4d8904add6a71c0864a1056cf952bdffb88ed27fcc838b14724fd2b64e548d7
NotoSans-Condensed.ttf /usr/share/fonts/NotoSans-Condensed.ttf d10e760dc99e7c0e27232fc32c104d543097c97186d363445fc909144020d2ec
NotoSans-CondensedMedium.ttf /usr/share/fonts/NotoSans-CondensedMedium.ttf 43c28184ab73b4f5e627046da537a6ad5c7249a3513dd9f0674176849a48c6bb
NotoSans-CondensedSemiBold.ttf /usr/share/fonts/NotoSans-CondensedSemiBold.ttf ffd123b721e534ee9fe161ed0ff0ec29a396bed46e9733bc877484ea6feb569b
"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# from_watch <directory> <list>: copies what's missing, and checks every file.
from_watch() {
	local dir=$1 name path sum
	mkdir -p "$dir"
	while read -r name path sum; do
		[ -n "$name" ] || continue
		if ! echo "$sum  $dir/$name" | shasum -a 256 -c - >/dev/null 2>&1; then
			log "copying $path from the watch ($watch)"
			scp -q "$watch:$path" "$dir/$name"
			echo "$sum  $dir/$name" | shasum -a 256 -c - >/dev/null || {
				echo "$dir/$name is not the file this test expects" >&2
				exit 1
			}
		fi
	done <<<"$2"
}

scenes=("$@")
[ ${#scenes[@]} -gt 0 ] || read -r -a scenes <<<"$all_scenes"
for scene in "${scenes[@]}"; do
	[ -f "$here/$scene.qml" ] || { echo "no scene $here/$scene.qml" >&2; exit 64; }
done

"$sonic/build.sh"
from_watch "$stage/lib" "$watch_libs"
from_watch "$fonts" "$watch_fonts"

log "checking the QML and building the test harness"
mkdir -p "$out"
docker run --rm --platform linux/amd64 -v "$sdk_volume:$sdk_dir:ro" -v "$build_volume:/build" \
	-v "$src:/src:ro" -v "$stage:/stage:ro" -v "$out:/out" "$image" bash -ec '
	. '"$sdk_dir"'/environment-setup-armv7vehf-neon-oe-linux-gnueabi
	# Every QML file of the launcher and of the scenes, as the SDK parses and
	# compiles it: MainScreen and the rest that no scene loads too.
	bin=$OECORE_NATIVE_SYSROOT/usr/bin
	for f in $(find /src/src/qml /src/src/applauncher /src/sonic/test -name "*.qml"); do
		"$bin/qmllint" "$f"
		"$bin/qmlcachegen" -o /tmp/check.qmlc "$f"
	done
	# liblipstick needs libraries the SDK lacks; the container has them.
	export LDFLAGS="$LDFLAGS -Wl,--allow-shlib-undefined"
	cmake -S /src/sonic/test -B /build -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
		-DCMAKE_BUILD_TYPE=Release \
		-DLipstick_INCLUDE_DIRS="/stage/include/lipstick-qt5;/stage/include" \
		-DLipstick_LIBRARIES=/stage/lib/liblipstick-qt5.so.1 >/dev/null
	cmake --build /build -j"$(nproc)"
	cp /build/launcher-test /build/seed-calendar /out/
	# The English the watch shows, from the translations that the qsTrId()s need.
	mkdir -p /out/translations
	"$bin/lrelease" -silent -idbased /src/i18n/asteroid-launcher.en_GB.ts -qm /out/translations/asteroid-launcher.en_GB.qm
'

log "running ${scenes[*]} under emulation"
mkdir -p "$out/shots"
for scene in "${scenes[@]}"; do
	rm -f "$out/shots/$scene"*.png
done
status=0
docker run --rm --platform linux/arm/v7 \
	-v "$sdk_volume:$sdk_dir:ro" -v "$stage:/stage:ro" -v "$fonts:/fonts:ro" \
	-v "$src:/src:ro" -v "$out:/out" \
	alpine:3.20 sh /src/sonic/test/run.sh "${scenes[@]}" || status=$?
if [ $status = 0 ]; then
	log "passed; screenshots in sonic/out/test/shots/"
else
	echo "failed; logs in sonic/out/test/" >&2
fi
exit $status
