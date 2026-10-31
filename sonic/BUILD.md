# Building and running this launcher on the watch

The Sonic Screwdriver fork of asteroid-launcher, for a TicWatch Pro 3 Ultra
(AsteroidOS 2.1 rubyfish image). Branch `asteroidos-2.1` is upstream's `2.1` tag plus
this tooling. The tag is the launcher the watch shipped with: all 26 QML and
resource files in the stock binary are byte-identical to it. Each change lands as
a pull request into `asteroidos-2.1`, and is merged after it has run on the
watch.

## Build

```sh
sonic/build.sh            # incremental, about 30 s
sonic/build.sh --clean    # from an empty build directory
```

The output is `sonic/out/asteroid-launcher`, stripped, with its debug symbols in
`sonic/out/asteroid-launcher.debug`.

The build runs in Docker with AsteroidOS's 2.1 SDK.
- The SDK's Qt 5.15.16, mlite, timed and libngf are the exact builds on the
  watch, down to their git hashes.
- The SDK is x86_64-only, so the container is `linux/amd64` and runs under
  Rosetta on Apple Silicon.

The first run sets up everything else:
- **Docker image** `sonic-asteroid-launcher-sdk:2.1`, from `sonic/Dockerfile`.
- **SDK installer:** 1.2 GB, downloaded from release.asteroidos.org into
  `~/.cache/sonic-screwdriver/asteroid-sdk-2.1/`, with its SHA-512 checked.
- **SDK:** about 6.5 GB, installed into the Docker volume `sonic-asteroid-sdk-2.1`.
- **lipstick:** the SDK lacks it.
  - Its public headers come from lipstick's `2.1` tag, staged in
    `~/.cache/sonic-screwdriver/launcher-stage/`.
  - The launcher links against the watch's own `liblipstick-qt5.so.1.0.0`
    (package lipstick 2.1-r1). It is copied over SSH once and checked against
    the SHA-256 in `build.sh`.
  - The link uses `--allow-shlib-undefined`, because some of liblipstick's own
    libraries are missing from the SDK. They all exist on the watch.
- **Build tree:** the Docker volume `sonic-asteroid-launcher-build`.

The watch is the `sonic-screwdriver` host in `~/.ssh/config`. Set `SONIC_WATCH`
to use another.

## Run it on the watch

```sh
sonic/deploy.sh           # install sonic/out/asteroid-launcher and restart the launcher
sonic/deploy.sh --stock   # back to the stock launcher
sonic/deploy.sh --status  # which launcher runs
```

The stock `/usr/bin/asteroid-launcher` is never modified.
- `deploy.sh` installs these files:
  - the build, as `/usr/local/lib/sonic-launcher/asteroid-launcher`, with the
    previous build kept as `asteroid-launcher.prev`;
  - `/usr/local/libexec/sonic/launcher`, from `sonic/watch/launcher`;
  - a systemd user drop-in that starts that wrapper,
    `/etc/systemd/user/asteroid-launcher.service.d/sonic.conf`, from
    `sonic/watch/sonic.conf`;
  - the icons in `sonic/icons/`, into `/usr/share/icons/asteroid/sonic/`
    (see [Icons](#icons)).
- The wrapper runs the fork's build. After 3 starts within 2 minutes, which
  means a crash loop, it starts the stock launcher instead, until the next
  deploy or reboot. systemd would give up after 5 starts in 10 s and leave the
  watch with no launcher at all, so the wrapper switches first.
- A deploy restarts the launcher, which closes any open app. Then it shows the
  launcher's QML errors and warnings. Five `TypeError`s from `compositor.qml`
  at startup are normal: the stock launcher prints them too.
- The speaker stays muted while the launcher restarts. The stock 2.1 launcher
  plays a sound from every notification view it creates, so its start fired
  one per stored notification at once. On 2026-10-31 that was 17 at the same
  time.

To uninstall completely:
1. Run `sonic/deploy.sh --stock`.
2. Delete `/usr/local/lib/sonic-launcher/` and `/usr/local/libexec/sonic/launcher`.
3. Once the Settings fork is uninstalled too, delete
   `/usr/share/icons/asteroid/sonic/`.

## Icons

AsteroidOS's `Icon` draws `/usr/share/icons/asteroid/<name>.svg` in a single
colour, so an icon is a monochrome SVG in that directory. The icons that the
stock theme (package asteroid-icons-ion) lacks are in `sonic/icons/`.
`deploy.sh` installs them into `/usr/share/icons/asteroid/sonic/`, and QML
names them `sonic/<name>`. `--stock` leaves them there; nothing stock uses them.

| Icon | Shows | Drawn from |
|---|---|---|
| `ios-globe-off` | Quick panel: no internet | `ios-globe-outline`, crossed by the slash of the `ios-*-off` icons. The globe's strokes are cut 25 px either side of the slash, as in `ios-notifications-off`. |

The Settings fork, usr-ein/asteroid-settings, ships the same files and installs
them in the same place. Keep both copies identical.
