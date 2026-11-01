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
`sonic/out/asteroid-launcher.debug`. A build is reproducible: the same
sources give the same binary, byte for byte, incremental or clean, so its
SHA-256 names it.

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
    `sonic/watch/sonic.conf`.
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

## The app list

- **Order:** `src/qml/misc/AppList.qml` lists the apps that come first, by
  desktop file ID: Check-in, Alarm clock, Heart rate, Timer, Stopwatch,
  Weather, Flashlight, Diamonds. Every other app follows, by title.
- **The list opens on Check-in:** once it has been left for the watch face, by
  a swipe, an app closing or the display going off, it goes back to its first
  app. Coming back from a minimised app keeps the page.
- **The horizontal list is compiled in.** MainScreen loads the app list style
  that dconf's `/desktop/asteroid/applauncher` names. For the stock default,
  `000-default-horizontal.qml`, it loads the fork's own copy from the binary,
  so `deploy.sh --stock` takes it back too. The other styles stay the files
  in `/usr/share/asteroid-launcher/applauncher/`.

### Hiding apps

```sh
sonic/hide-apps.sh                  # hide Music, Calculator, Agenda and Settings
sonic/hide-apps.sh <id>...          # hide these apps, by desktop file ID (asteroid-music)
sonic/hide-apps.sh --show <id>...   # show these apps again
sonic/hide-apps.sh --undo           # show again every app the script hid
sonic/hide-apps.sh --status         # list the hidden apps
```

Nothing is uninstalled. Settings stays in the quick panel, the music player
behind the watch face's cover, and the agenda on the Today screen.
- An app is hidden by an override:
  `/usr/local/share/applications/<id>.desktop`, with `NoDisplay=true`. The
  script writes it from `sonic/watch/hide-apps`, run on the watch over SSH.
  Deleting the file shows the app again.
- **Only the fork's launcher honours it,** at once, without a restart.
  lipstick's own LauncherModel honours no override: it lists each `.desktop`
  file of `/usr/share/applications` and `~/.local/share/applications` on its
  own, keyed by path, and never reads `/usr/local/share/applications`. So the
  fork reads lipstick's model through `AppListModel`
  (`src/applistmodel.cpp`). It hides an app when a `.desktop` file of the
  same name in `~/.local/share/applications` or
  `/usr/local/share/applications` says `NoDisplay=true` or `Hidden=true`.
- The stock launcher, after `deploy.sh --stock`, shows every app again.

## Testing off the watch

```sh
sonic/test/test.sh               # every scene
sonic/test/test.sh applist       # one scene
```

Each scene, `sonic/test/<scene>.qml`, runs the fork's own QML, compiled in as
in the launcher, in a 454 × 454 view: the watch's screen.
- **What runs it:** the SDK's Qt, qml-asteroid and Nemo plugins, the watch's
  exact builds, and the watch's own liblipstick. They run in a 32-bit ARM
  Alpine container, which Docker runs through QEMU, with Qt Quick's software
  renderer. Shader effects, such as the stock list's drop shadow, don't show
  there.
- **What it checks:** the scenes check what they show, then save screenshots
  and contact sheets to `sonic/out/test/shots/`. `applist` checks the order,
  the hidden apps with `sonic/watch/hide-apps` itself, and that lipstick alone
  honours no override.
- **What it needs from the watch:** two libraries that lipstick needs and the
  SDK lacks, `libmce-qt5` and `libngf-qt5`, and the watch's Noto Sans for the
  screenshots. They are copied once over SSH and checked against the SHA-256
  in `test.sh`. Nothing runs on the watch.
