#!/usr/bin/env bash
# Sonic Screwdriver: build asteroid-launcher for the watch (rubyfish, AsteroidOS 2.1).
#
#   sonic/build.sh           incremental build
#   sonic/build.sh --clean   start from an empty build directory
#
# Output: sonic/out/asteroid-launcher (stripped) and its debug symbols,
# sonic/out/asteroid-launcher.debug. Install it with sonic/deploy.sh.
# The first run downloads and installs the AsteroidOS 2.1 SDK (1.2 GB download,
# about 6.5 GB installed in a Docker volume). See sonic/BUILD.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
src=$(dirname "$here")
cache=${SONIC_CACHE:-$HOME/.cache/sonic-screwdriver}
watch=${SONIC_WATCH:-sonic-screwdriver}

# The SDK's Qt 5.15.16, mlite, timed and libngf are the exact builds on the watch.
sdk=oecore-meta-toolchain-qt5-x86_64-armv7vehf-neon-sturgeon-toolchain-nodistro.0.sh
sdk_url=https://release.asteroidos.org/2.1/sdk/$sdk
sdk_sha512=90dbbaf5c5ae26471a7d874549cb8c6f7247245eb9d475465ee4fff290a335beb3d336167da6671a7397b46046c499db55aef47c3056c3307da521b5faa52e40
sdk_dir=/opt/asteroid-sdk
# The SDK lacks lipstick. Its headers come from lipstick's 2.1 tag, and the
# launcher links against the watch's own library (package lipstick 2.1-r1).
lipstick_tag=2.1
lipstick_lib_sha256=26e5f0291b34c977ffdfbe60c9d5265fde828e2530dd52bea3d67d82fe20e144

image=sonic-asteroid-launcher-sdk:2.1
sdk_volume=sonic-asteroid-sdk-2.1
build_volume=sonic-asteroid-launcher-build

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
run() { docker run --rm --platform linux/amd64 "$@"; }

clean=0
case "${1:-}" in
	--clean) clean=1 ;;
	"") ;;
	*) echo "usage: $0 [--clean]" >&2; exit 64 ;;
esac

if ! docker image inspect "$image" >/dev/null 2>&1; then
	log "building the Docker image $image"
	docker build --platform linux/amd64 -t "$image" "$here"
fi

if ! run -v "$sdk_volume:$sdk_dir" "$image" test -f "$sdk_dir/environment-setup-armv7vehf-neon-oe-linux-gnueabi"; then
	dl=$cache/asteroid-sdk-2.1
	mkdir -p "$dl"
	if ! echo "$sdk_sha512  $dl/$sdk" | shasum -a 512 -c - >/dev/null 2>&1; then
		log "downloading the AsteroidOS 2.1 SDK (1.2 GB)"
		curl -fL --retry 3 -C - -o "$dl/$sdk" "$sdk_url"
		echo "$sdk_sha512  $dl/$sdk" | shasum -a 512 -c -
	fi
	log "installing the SDK into the Docker volume $sdk_volume"
	run -v "$sdk_volume:$sdk_dir" -v "$dl:/dl:ro" "$image" sh "/dl/$sdk" -y -d "$sdk_dir"
fi

stage=$cache/launcher-stage
if [ ! -f "$stage/include/lipstick-qt5/homeapplication.h" ]; then
	log "staging the lipstick $lipstick_tag headers"
	lip=$cache/lipstick-$lipstick_tag
	[ -d "$lip/.git" ] || git clone -q --depth 1 --branch "$lipstick_tag" https://github.com/AsteroidOS/lipstick.git "$lip"
	mkdir -p "$stage/include/lipstick-qt5"
	# src.pro and compositor.pri list the public headers, which lipstick installs flat.
	(cd "$lip/src" && sed -n '/PUBLICHEADERS *+= *\\/,/[^\\]$/p' src.pro compositor/compositor.pri |
		tr -d '\\' | tr ' \t' '\n\n' | sed 's|\$\$PWD|compositor|' | grep '\.h$' |
		while read -r h; do [ ! -f "$h" ] || cp "$h" "$stage/include/lipstick-qt5/"; done)
fi
lib=$stage/lib/liblipstick-qt5.so.1
if [ ! -f "$lib" ]; then
	log "copying liblipstick-qt5 from the watch ($watch)"
	mkdir -p "$stage/lib"
	scp -q "$watch:/usr/lib/liblipstick-qt5.so.1.0.0" "$lib"
fi
if ! echo "$lipstick_lib_sha256  $lib" | shasum -a 256 -c - >/dev/null 2>&1; then
	echo "$lib is not the lipstick 2.1-r1 library this build expects" >&2
	exit 1
fi

if [ $clean = 1 ]; then
	log "emptying the build directory"
	run -v "$build_volume:/build" "$image" sh -c 'rm -rf /build/* /build/.[!.]*'
fi

log "building asteroid-launcher"
mkdir -p "$here/out"
run -v "$sdk_volume:$sdk_dir:ro" -v "$build_volume:/build" -v "$src:/src:ro" -v "$stage:/stage:ro" -v "$here/out:/out" \
	"$image" bash -ec '
	. '"$sdk_dir"'/environment-setup-armv7vehf-neon-oe-linux-gnueabi
	# liblipstick needs libraries the SDK lacks; they all exist on the watch.
	export LDFLAGS="$LDFLAGS -Wl,--allow-shlib-undefined"
	cmake -S /src -B /build -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
		-DLipstick_INCLUDE_DIRS="/stage/include/lipstick-qt5;/stage/include" \
		-DLipstick_LIBRARIES=/stage/lib/liblipstick-qt5.so.1 >/dev/null
	cmake --build /build -j"$(nproc)"
	$OBJCOPY --only-keep-debug /build/src/asteroid-launcher /out/asteroid-launcher.debug
	$STRIP -o /out/asteroid-launcher /build/src/asteroid-launcher
	$OBJCOPY --add-gnu-debuglink=/out/asteroid-launcher.debug /out/asteroid-launcher
'
log "built $(cd "$here/out" && ls -l asteroid-launcher | awk '{print $5}') bytes: sonic/out/asteroid-launcher ($(git -C "$src" describe --always --dirty))"
