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

### Logos and the dark theme

- **Logos:** `sonic/icons/<desktop file ID>.svg`, one per app, compiled into
  the binary: Check-in, Alarm clock, Heart rate, Timer, Stopwatch, Weather,
  Flashlight and Diamonds. They are original drawings in one style: a disc of
  the app's colour, darkened, with a flat, rounded, full-colour symbol on it.
  Weather's disc is a blue sky, Flashlight's a dark grey. Qt draws them with
  its SVG Tiny renderer, so they use no clip paths, masks, filters or CSS.
- **The list:** each page shows the app's logo, the size of the stock icon
  circle, with its name under it, smaller and in sentence case ("Alarm
  clock"). `AppListModel`'s `logo` role is the logo's `qrc:` URL, or empty.
  An app without a logo gets the stock drawing, its icon on a circle, in the
  theme's dark grey.
- **Adding a logo:** put the SVG in `sonic/icons/` and list it in
  `src/resources-qml.qrc`.
- **Black panels:** the wallpaper is the watch face's alone. MainScreen's
  darkener is opaque behind every other panel, so the app list, the Today
  screen, the quick panel and the notifications are black. The wallpaper
  fades out as a panel comes in. The quick panel's unchecked toggles keep a
  dark grey circle, which shows on black.

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

## The Today screen

The screen right of the watch face is a timeline of the day, as the approved
mockup draws it (`src/qml/today/`).
- **The timeline:** 00:00 to 24:00, 76 px an hour, scrolling up and down.
  Hour labels on the left, faint hour lines across, and a red line at now
  with its time.
- **Events,** from the same AgendaModel as before:
  - each timed event is a block from its start to its end, in its calendar's
    colour, the notebook's colour that the iPhone sync sets;
  - events that overlap share the width;
  - a block shows its title, on two lines at most, above its time. A longer
    title rolls up, slowly, with a pause at each end;
  - a block shorter than 56 px, about 45 minutes, is one line with the time
    first, and a longer title slides sideways;
  - all-day events are chips under the date and the weather, two and then
    "+n", in a band that stays.
- **While it scrolls,** a bubble on the right edge shows the time at the
  middle of the screen, rounded to five minutes, with a dashed line across.
  It fades out a second after the scrolling stops.
- **It centres on now** whenever it comes into view.
- **Battery:** the minute clock runs only while the screen shows, and a
  title moves only while the screen shows and its block is in view.
- `timeline.js` lays the day out in the mockup's pixels, and `Today.qml`
  scales them to the screen. `TodayEvent.qml` draws one block.

## The bottom button: double-click for the flashlight

Two presses of the bottom button within 400 ms toggle the flashlight, from
anywhere, with the display off too. A single press, and the top button, do
what they did.
- **The button:** on this watch, the PMIC's RESIN key, which sends
  `KEY_VOLUMEDOWN` (114) from the same input device as the power key,
  `qpnp_pon`. mce never grabs that device, as it also sends `KEY_POWER`.
- **Read from the device:** `ButtonDoubleClick` (`src/buttondoubleclick.cpp`)
  reads `/dev/input/event*` itself, the devices that can send the key, as
  Qt's key events stop while the display is off: lipstick hides its window
  then. It only reads and never grabs, and it times the presses by the
  kernel's times of the events, so presses that wake the watch still count.
- **The flashlight:** asteroid-flashlight, as the quick panel's button opens
  it (`src/qml/compositor/Flashlight.qml`).
  - On: the display on first when it's off, through mce's
    `req_display_state_on`, then the app, which goes to full brightness.
  - Off: the app closes, as a swipe closes it, and restores the brightness.
  - It opens over the app on the screen without closing it, unlike other
    apps, and turned off by the button, it gives the screen back to that app.
  - Its window is the one whose process's command line names
    asteroid-flashlight, however it was opened.

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
  renderer.
- **Another worktree** of the fork can build in Docker volumes of its own:
  `SONIC_BUILD_VOLUME=<name> sonic/test/test.sh`, also for `sonic/build.sh`.
- **What it checks:** the scenes check what they show, then save screenshots
  and contact sheets to `sonic/out/test/shots/`.
  - `applist` checks the order, the hidden apps with `sonic/watch/hide-apps`
    itself, and that lipstick alone honours no override. It reads each logo
    back from the screenshots by its colours, and checks the names.
  - `quickpanel` draws the quick panel on black, with the system services it
    reads stood in for by `sonic/test/stubs/`.
  - `today` runs the Today screen with the SDK's real AgendaModel over mkcal.
    `seed-calendar.cpp` fills four coloured notebooks with the mockup's
    sample days, invented, and changes them under the open screen.
  - `button` feeds invented input events to `ButtonDoubleClick` through a
    FIFO, and drives `Flashlight.qml` with a stand-in for the compositor's
    windows: from the home, over an app, with the display off, and more.
  - `preview` puts the others' screenshots on one sheet,
    `preview-dark-theme.png`.
- **The software renderer** draws no shader effects: the quick panel's
  battery bar, which an opacity mask shapes, doesn't show in the screenshots.
  It does on the watch.
- **What it needs from the watch:** two libraries that lipstick needs and the
  SDK lacks, `libmce-qt5` and `libngf-qt5`, and the watch's Noto Sans for the
  screenshots. They are copied once over SSH and checked against the SHA-256
  in `test.sh`. Nothing runs on the watch.
