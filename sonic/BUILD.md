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
- **The resources' time:** rcc stamps every compiled-in file with one time,
  from a hash of their contents (`sonic/resource-time.py`), instead of each
  file's own.
- **Why from their contents:** Qt's QML disk cache on the watch
  (`~/.cache/System/qmlcache`) takes a compiled file as current while its
  source's time matches. A fixed time made each new build run whatever QML an
  older build had compiled there.

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
- **The stock launcher starts silenced** whenever the wrapper runs it: after a
  crash loop, at boot or any time later, with no deploy script around, or
  with no fork build.
  - **Its sound:** the stock binary's own QML has its NotificationView play
    `/usr/share/sounds/notification.wav` through a QtMultimedia `SoundEffect`
    for each notification it shows, whatever the profile.
  - **`PULSE_SERVER=unix:/dev/null`:** `SoundEffect` is a PulseAudio client
    of the launcher's own, which `QT_GSTREAMER_PLAYBIN_AUDIOSINK` doesn't
    reach. So the wrapper gives the stock launcher no server to play on.
    lipstick's volume control reaches PulseAudio over D-Bus, and ngfd plays
    the profile's sounds from its own process, so neither changes. It sets
    `QT_GSTREAMER_PLAYBIN_AUDIOSINK=fakesink` too, for anything that would
    play through GStreamer's playbin.
  - **Its own process only:** the speaker isn't muted. Nothing could safely
    unmute it later: a reboot clears the fallback, with no deploy to follow,
    and PulseAudio keeps a mute across reboots.
  - **The apps it starts** may inherit `PULSE_SERVER`, since invoker passes
    its environment on, and be silent too. That's acceptable in the fallback.
  - `sonic/stock-silent-test.sh` checks the first against the SDK's
    QtMultimedia, the watch's exact build, and a PulseAudio in a container:
    a `SoundEffect` opens a stream as it is, still does with `fakesink`
    alone, and opens none with `PULSE_SERVER=unix:/dev/null`.
- A deploy restarts the launcher, which closes any open app. Then it shows the
  launcher's QML errors and warnings. Five `TypeError`s from `compositor.qml`
  at startup are normal: the stock launcher prints them too.
- The speaker stays muted while the launcher restarts. The stock 2.1 launcher
  plays a sound from every notification view it creates, so its start fired
  one per stored notification at once. On 2026-10-31 that was 17 at the same
  time. A crash loop ends in that stock launcher, when the wrapper falls
  back. So:
  - the speaker comes back, as it was, only once the launcher that should run
    (the fork's build, or the stock one for `--stock`) has run with the same
    pid for 20 s, with no fallback;
  - otherwise it stays muted, after up to 150 s, and the deploy fails with a
    loud warning and the line to unmute it by hand.
- **Between the stop and the start,** a deploy deletes the launcher's QML disk
  cache, `~/.cache/System/qmlcache`. The start then recompiles all of it.
  Builds before the resources were stamped from their contents all carried
  the same time, so the cache let a new build run an older build's QML.

  `sonic/deploy-test.sh` tests that, and the wrapper, in a container, with
  stand-ins for `systemctl`, `pactl` and the launchers.

To uninstall completely:
1. Run `sonic/deploy.sh --stock`.
2. Delete `/usr/local/lib/sonic-launcher/` and `/usr/local/libexec/sonic/launcher`.

## The app list

- **Order:** `src/qml/misc/AppList.qml` lists the apps that come first, by
  desktop file ID: Check-in, Alarm clock, Heart rate, Timer, Stopwatch,
  Weather, Flashlight, Diamonds. Every other app follows, by title.
- **Weather is Sonic Screwdriver's own,** `sonic-weather` (the main repo's
  `weather/`), fed by the iPhone through ioslink. The stock `asteroid-weather`
  is hidden with the others; shown again, it would follow them by title.
- **So are Timer and Stopwatch,** `sonic-timer` and `sonic-stopwatch` (the
  main repo's `clock/watch/`), the same as Sonic's timers and stopwatches
  through ioslink. The stock `asteroid-timer` and `asteroid-stopwatch` are
  hidden with the others.
- **And Heart Rate,** `sonic-heartrate` (the main repo's `health/heartrate/`),
  which measures the heart rate and then blood oxygen through the health
  collector. The stock `asteroid-hrm` is hidden with the others.
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
  Weather's disc is a blue sky, Flashlight's a dark grey; `sonic-weather.svg`
  is an alias of `asteroid-weather.svg`, so both Weathers wear it, and
  `sonic-timer.svg` and `sonic-stopwatch.svg` are the Timer's and the
  Stopwatch's, the same way. `sonic-heartrate.svg` is a drawing of its own:
  Heart rate's red heart and pulse line, with a blue drop for blood oxygen;
  the stock app keeps `asteroid-hrm.svg`. Qt draws them with
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
sonic/hide-apps.sh                  # hide Music, Calculator, Agenda, Settings, and the stock Weather, Timer, Stopwatch and Heart Rate
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
anywhere, with the display off too. A single press on Sonic Screwdriver's
rings face opens its app (below); anywhere else, it and the top button do
what they did.
- **The button:** gpio-keys' `multi_function_key`, on GPIO 48 (the board's
  `rover-keys.dtsi`), which sends `KEY_MENU` (139) from an input device of its
  own, `gpio-keys`: `/dev/input/event2`, `root:system` 0660, and the launcher's
  user, ceres, is in `system`. It wakes the watch from suspend.
  - Not `KEY_VOLUMEDOWN` (114): that's the PMIC's RESIN key, on `qpnp_pon`
    with the power key, and no physical button is wired to it. Its interrupt
    count stays 0 while the bottom button's goes up with each press. The
    first build of this feature waited for 114, and its double-click never
    fired.
  - No other device on the watch sends `KEY_MENU`: the touchscreen driver's
    touch keys aren't built in.
- **Its single press does nothing,** and still doesn't:
  - nothing in the launcher, lipstick 2.1 or qml-asteroid handles `Key_Menu`;
  - lipstick hands a key event to the app in front, as any key, and none
    uses it;
  - mce, by its heuristics, takes a device that sends only `KEY_MENU` for
    "user activity": a press keeps the display on as a touch would, and mce
    never grabs it.
- **Read from the device:** `ButtonDoubleClick` (`src/buttondoubleclick.cpp`)
  reads `/dev/input/event*` itself, the devices that can send the key, as
  Qt's key events stop while the display is off: lipstick hides its window
  then. It only reads and never grabs, so lipstick's own reader of the device
  carries on.
- **Its clock:** it times the presses by the kernel's times of the events, on
  the boot-time clock, so presses that wake the watch still count as they
  were pressed. The watch can suspend again between two presses, and the
  monotonic clock stops then: on it, presses seconds apart could look like a
  double-click.
- **A single press on the rings face** (the main repo's docs/prd/clock.md
  § 8.8 and § 8.9): the face that the user's watch face becomes while a timer
  or a stopwatch runs says which view it shows in its `sonicRingsView`, which
  `MainScreen.qml` reads from the active face into `desktop.ringsView`.
  `ButtonDoubleClick` emits `singleClicked()` for a press that stays alone and
  is let go before the hold's 0.5 s: at the later of 400 ms after the press and
  the release, with no second press, or at once when the next press comes too
  late to pair with it; a double-click emits none, and neither does a hold.
  `compositor.qml` then asks `ringsbutton.js` which app to open:
  `sonic-stopwatch` or `sonic-timer`, only with the display on and not ambient,
  the home in front, and the panels on the face itself; anywhere else, none.
- **The flashlight:** asteroid-flashlight, as the quick panel's button opens
  it (`src/qml/compositor/Flashlight.qml`).
  - On: the display on first when it's off, through mce's
    `req_display_state_on`, then the app, which goes to full brightness.
  - Off: the app closes, as a swipe closes it, and restores the brightness.
  - It opens over the app on the screen without closing it, unlike other
    apps, and turned off by the button, it gives the screen back to that app.
  - Its window is the one whose process's command line names
    asteroid-flashlight, however it was opened.

## The bottom button: a hold records a voice note

Holding the bottom button records a voice note for as long as it's held, and
the screen draws the loudness scrolling by, with the duration (the main repo's
docs/prd/voice_notes.md § 8.2 and § 8.4). ioslink records and keeps the note;
the launcher is the button and the screen. A click and a double-click do what
they did.
- **The hold, in `ButtonDoubleClick`:** it reads the button's releases too.
  - `holdStarted(pressedAt)` for any press that isn't a double-click's second
    press, at once, with the event's boot-time stamp in ms.
  - `holdConfirmed()` when the button is still down `longInterval` (500 ms)
    after the press, counted from the event's own time: a press that woke the
    watch, and was read 100 ms late, confirms 100 ms early. An event's age
    counts only if it's plausible, not in the future and under a second;
    otherwise the event counts from when it arrives.
  - `holdEnded(releasedAt, confirmed)` at the release, with `confirmed` false
    for a click. A press and its release read together after a stall, 0.5 s
    apart, are a hold all the same.
  - A confirmed hold never ends in `singleClicked()` or `doubleClicked()`.
  - A hold ends without its release if its device goes away, or if another press
    comes with the release lost, and it's no click then.
- **Where a hold records** (the user's rule: "on the main watchface (not in an
  app)", with music playing, with stopwatches or timers on, "not just when the
  regular watchface is shown"; and with the screen off, where the user can't see
  what is in front, wherever the watch was): `voicebutton.js`'s
  `canRecord(displayOn, ambient, homeActive, panelX, panelY)`.
  - **With the display on, or ambient:** `homeActive` with the panels at (0, 0),
    the home's face page, whatever the face shows (the music face's cover, the
    rings face with timers or stopwatches, the door, the plain face). It never
    reads the face's mode, which only the short press does (`ringsbutton.js`).
    **Never** inside an app, nor on another panel (the notifications at (-1, 0),
    the quick panel at (0, -1), the app list at (0, 1), Today at (1, 0)): a hold
    does nothing there.
  - **With the display off:** always. An app in front, the app list, the quick
    panel, anything. The recording screen comes up over what is there (it is
    above the layers of the home, the apps, the notifications and the agents),
    and nothing in the hold, in its screen or in the guard closes, moves or opens
    a window, or touches the panels or the 5 s timer that closes the app (a test
    greps for it). mce lights the display at 0.5 s, and lipstick's
    `displayAboutToBeOn` stops compositor.qml's `delayTimer`, so what was in front
    is in front when the screen has gone. A hold that begins in the last 0.5 s of
    those 5 s finds the app closed by the timer, as it would have been anyway,
    and records all the same, over the face.
  - **Ambient counts as the display on.** Lipstick emits `displayOff` for mce's
    off state, which is the ambient display when ambient is enabled, so
    compositor.qml's `displayOn` is false in ambient too. The display is off when
    `displayOn` is false and `ambient` is false. With ambient enabled the watch
    is never off in that sense, and a hold records on the face page only.
  - **After the display goes off:** MainScreen moves the panels back to (0, 0)
    150 ms after `displayOff`, ambient included, and compositor.qml closes the app
    in front 5 s after. So in ambient, an app that is still in front during those
    5 s makes a hold do nothing; with the display off, it records.
- **What the hold does** (`src/qml/compositor/VoiceNoteHold.qml`, a piece of the
  compositor that the tests run with stand-ins, as `Flashlight.qml` is):
  - **At the press,** where the guard allows and ioslink is on the session bus:
    mce's `req_cpu_keepalive_start`, first, because the watch can suspend within
    150 ms of the press; then ioslink's `Arm(pressedAt)`, asynchronously. With no
    ioslink on the bus, nothing at all.
  - **At 0.5 s:** the recording screen shows, `req_display_state_on` if the
    display was off or ambient, the screen is kept on (below), and `Keep(id)`.
  - **At the release:** `Stop(id, releasedAt)`, or `Cancel(id)` for a click.
  - **Arm's answer comes when it comes.** It holds the id that Keep, Stop and
    Cancel need, so they wait for it, in that order. `""` is a refusal (State's
    `last` says why), which the screen shows at 0.5 s; an error from Arm (ioslink
    busy, or without VoiceNotes) shows nothing.
  - **What it holds are leases:** mce's keepalive, which ends if it isn't renewed
    within 75 s, and the blanking pause, within 60 s. Both are renewed every 30 s
    (half of `req_cpu_keepalive_period`'s answer for the keepalive) for as long
    as the hold or the note lasts, and let go once the screen has finished, 2 s
    after the note ended. A click lets them go at the release. The keepalive's
    period is asked of mce under a session of its own: a period query renews its
    session to 2 s, which would cut the real one short. A hard limit lets go of
    everything 635 s after the press whatever happens. mce drops a client's
    keepalive and blanking pause when the client leaves the bus, so a launcher
    that crashes or is killed leaves neither behind.
  - **The screen kept on: the touch lock, then the pause.** The watch face is
    mce's lockscreen (`compositor.qml` sets `lipstickSettings.lockscreenVisible`
    from `longTimeout`: true on the face, false elsewhere). While it is locked,
    mce blanks the display 10 s after it came on ("blank from lockscreen") and
    allows no blanking pause. mce allows a pause only with the display on and
    the touch lock off, ignores one asked otherwise, and drops one it holds as
    soon as that stops (its `display.c`, `mdy_blanking_pause_evaluate_allowed`).
    And it refuses to unlock unless the display is on or on its way
    (`tklock.c`: "tkunlock denied due to display=OFF"). #19 let the lockscreen go
    at 0.5 s, before the display was on, for a note that woke the watch: mce
    refused, stayed locked, ignored every pause, and blanked the display 10 s in
    (the user's note of 23:57, 2026-11-03). So, from 0.5 s until the screen is
    away (`VoiceNoteHold.screenKept`):
    - **the unlock waits for the display:** `req_tklock_mode_change("unlocked")`
      once the display is on (`displayLit`), never before;
    - **mce's touch lock is followed:** its `tklock_mode_ind`, which mce sends
      after every request too, and `get_tklock_mode` at each renewal. While it is
      still locked, the unlock is asked again every second; locked again
      mid-note, at once;
    - **then the pause,** once mce says the touch lock is unlocked or a pause is
      allowed (`display_blanking_pause_allowed_ind`), and again whenever mce
      allows it after dropping it. It is renewed every 20 s, well inside mce's
      60 s;
    - **at the end,** after the keepalive and the pause, the touch lock is locked
      again, `req_tklock_mode_change("locked-delay")` as lipstick's
      `lockScreen()` asks it, if the note asked to unlock it and the face is in
      front (`lockWanted`, the compositor's `longTimeout`). Every way a note ends
      comes through there: the save, a slip too short to keep, the 10:00 limit,
      a refusal, ioslink gone, ioslink silent and the hard limit. Off the face,
      an app in front, it stays unlocked, as the compositor has it there.
    - `compositor.qml` leaves the lockscreen alone meanwhile: the panels moving
      during a note don't lock it.
    - **A launcher that dies** leaves no pause: mce drops a client's when the
      client leaves the bus. Its next start locks the screen
      (`MainScreen.qml`'s `LipstickSettings.lockScreen(true)`).

    Find My's effects keep the find screen lit by the same pause, which works
    there because that screen is an app, and an app has the lockscreen unlocked.
  - The names it uses: ioslink's `org.sonicscrewdriver.ioslink` on the session
    bus, object `/org/sonicscrewdriver/ioslink`, interface
    `org.sonicscrewdriver.ioslink.VoiceNotes`: the methods `Arm`, `Keep`, `Stop`
    and `Cancel`, the property `State` and the signal `Levels` (the main repo's
    bridge/PROTOCOL.md § 6.14.4); and mce's `req_cpu_keepalive_start`,
    `req_cpu_keepalive_period`, `req_cpu_keepalive_stop`, `req_display_state_on`,
    `req_tklock_mode_change`, `get_tklock_mode`, `req_display_blanking_pause` and
    `req_display_cancel_blanking_pause`, and its signals `tklock_mode_ind` and
    `display_blanking_pause_allowed_ind` on `/com/nokia/mce/signal`.
- **The recording screen** (`src/qml/compositor/VoiceNoteOverlay.qml`): an item
  between the gesture area (z 5) and the round mask (z 6), created at start and
  hidden. Black, in the family of the clock apps and Heart Rate.
  - **What's on it,** in the 454 × 454 mockup's pixels, scaled to the screen:
    - the red dot, 16 px at (227, 92), which breathes once a second, and the
      green check in its place once the note is saved;
    - the duration, Noto Sans Light 104 px, centred on y 150, `0:00` to `9:59`
      and then `10:00`, on the note's own clock, State's `startedAt`;
    - the waveform: round-ended bars 6 px wide every 10 px about y 272, up to
      100 px tall, one per 100 ms, the mean in dB of its two 50 ms levels (the louder of the two hid the gaps between words), the
      newest at x 330 and a red 2 px "now" line at x 340, the oldest fading out to
      the left of x 116. About 30 Rectangles of the scene graph, and no Canvas.
      What a level draws as is measured from the room's floor (voicenoteview.js):
      the floor is the 15th percentile of the last 8 s of bars, between -60 and
      -50 dBFS, starting at -52, falling at once and rising 0.1 dB a second at the
      most; a bar is flat (6 px) up to 8 dB over it, full height from -27 dBFS, and
      between the two a smoothstep. A quiet room draws as a flat line and speech
      as tall bars with gaps between the words; a room louder than -50 dBFS draws
      as activity, while speech keeps its height;
    - one line, 26 px, centred on y 372: "Release to save", then from 9:30 "30 s
      left" to "1 s left" in amber, and at the end "Saved · sending", "Saved · 3 on
      watch", "Saved · 18:02 dropped" (amber; "Saved · 3 dropped" for several),
      "10 min limit · saved", "Too short" (the duration dimmed), "Watch storage
      full" and "Microphone unavailable" (amber, before anything records).
    - More lines for what § 8.4 doesn't cover: "Saving…" between the release
      and State's outcome, "Recorder stopped" (amber) when ioslink leaves the bus
      mid-note, and "Couldn't record" for a failed note with another reason. And
      the early ends that State's `last.reason` tells (PROTOCOL.md § 6.14.4), all
      amber, with the duration short of what was held: "Storage full · saved" for
      a note alone past the cache's cap, which ends as a limit before 10:00,
      "Microphone lost · saved" and "Encoder failed · saved" for a note cut short
      and kept.
  - **Where it gets its data:** ioslink's `Levels(id, fromMs, centibels)`, every
    100 ms while a note is armed or records, from the press on, so that the
    waveform is already drawn when the screen shows; and State's `recording` and
    `last`. Nemo.DBus reads both afresh whenever ioslink comes back.
  - **How it ends:** the outcome shows 2 s (2.5 s for a drop), then it fades
    out in 250 ms, and `finished()` lets the hold let go of its leases. If ioslink
    never says how a released note ended, it goes after 5 s with no claim about
    the note.
  - **Its motion, one bar a tick, a bar drawn once:** a bar is drawn only once
    all its levels are in, and keeps its height from then on; the row moves one
    bar at each tick, never two, never back. The levels come in bursts: on the
    watch (a hold at 00:10 on 2026-11-04, its Levels as they came) a level
    reaches the launcher 135 to 190 ms after its 50 ms end, the capture's delay
    and ioslink's 100 ms between sends, so a bar has its second level about
    315 ms after it began. So the row runs 300 ms behind the note's clock, and
    each tick is set for the middle between two bars' starts on that clock, so
    that a tick a frame early or late still moves it one bar. When the levels
    are later than that, the row waits, then catches up a bar every 60 ms.
    Levels that come in a burst once the screen shows are drawn bar by bar at
    that pace, never several at once; those gathered before it shows open it.
    #19 drew the clock's newest bar, 150 ms behind, whatever had come: on that
    hold, 68 bars changed height after they were drawn (a bar empty, or with one
    of its two levels, then both), by up to 100 px, and the first second peaked
    at 98 px where its whole bars are 85 at the most (its room, about -40 dBFS,
    and -29 after the start tick, which #19's floor draws as activity); and the
    row stalled or skipped a bar when a tick fell near a bar's start.
  - **Its frames:** the row of bars slides 10 px over each 100 ms, or with
    `slide` false steps 10 px every 100 ms, which draws about a sixth of the frames
    (10 a second, not 60). The dot's breathing steps with it.
  - **No touch:** it has no touch handling, so touches reach what's under it.
  - **Nothing within 12 px of the round edge:** the scene checks every
    screenshot, pixel by pixel, against the circle 215 px from the middle.

## The quick panel's Find phone button

The first button of the quick panel's sliding row rings the iPhone, through
silent mode and Focus, until it's stopped there or here (Sonic Screwdriver's
find_phone.md). Never a sound or a vibration on the watch: the button's light
is the feedback.
- **ioslink's FindPhone interface,** on its object on the session bus
  (`src/qml/quickpanel/FindPhone.qml`):
  - `Ring()` and `Stop()`, which turn `Ringing` true or false at once, before
    the iPhone answers; a tap that doesn't take puts it back, with `Problem`;
  - `Ringing`, the button's light, which has no state of its own;
  - `Available`;
  - `Problem`, shown for 3 s from `ProblemAt`, in Unix seconds, such as
    "Allow alarms in Sonic".
- **A tap:** idle, it rings; while ringing, it stops. Without the iPhone, it
  says "Phone not connected" for 3 s, over the battery meter, and asks
  nothing. A tap clears the last tap's line.
- **A failed call** shows the line that `Problem` would: "Phone didn't
  answer" for `org.freedesktop.DBus.Error.Failed`, ioslink busy, and for the
  bus's `NoReply`; "Phone not connected" for `NotConnected` and the bus's
  other errors, such as no ioslink.
- **Its glyph** is `sonic/icons/find-phone.svg`, compiled in;
  `QuickPanelToggle` takes a picture of its own, `iconSource`.
- **In the watch's settings:** the launcher's defaults put the button first,
  enabled, but settings that list the toggles, as the watch's do, need it
  added:

  ```sh
  sonic/quickpanel-findphone.sh            # first in the sliding row, enabled
  sonic/quickpanel-findphone.sh --undo     # take it out again
  sonic/quickpanel-findphone.sh --status   # where it is
  ```

  It runs `sonic/watch/quickpanel-findphone` on the watch, which changes the
  user's dconf keys `/desktop/asteroid/quickpanel/slider` and `enabled`; the
  panel follows at once. The Settings app's quick panel page keeps only the
  toggles it knows, so it needs the button too: the settings fork's
  `findPhoneButton` entry.

## The watch face's fallback

A watch face that fails to load shows the default face instead, so that the
watch always shows the time (Sonic Screwdriver's
todos/tech-debt/04-watch-face-fallback.md). A stock `Loader` has no error
branch: a missing face, a typo, or a plugin gone after an upgrade left a
screen with no time on it.
- **`src/qml/misc/FaceLoader.qml`** loads the face for both of MainScreen's
  face loaders, the watch face and the nightstand face.
- **The fallback:** `000-default-digital.qml`, and one warning in the
  journal, `sonic: the watch face <url> failed to load; showing the default
  face`.
- **The choice stays bound** to dconf's key: the fallback never assigns the
  `Loader`'s `source`. Choosing another face in Settings loads it, and
  choosing the failed one again tries it again. A face fixed and reinstalled
  at the same path is tried again at the next launcher start, which the
  main repo's `watchface/install.sh` does anyway.
- **If the default face fails too,** its error shows, as with a stock
  `Loader`, with no loop.
- **Only a load error counts.** A face that loads, then throws at run time,
  isn't covered.

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
- **What it checks:** first, that the launcher loads on the watch:
  - `src/main.cpp` registers the launcher's QML types,
    `registerLauncherTypes()`, before lipstick's `setCompositorPath()`, which
    compiles `compositor.qml` at once;
  - `load` compiles `compositor.qml` and `MainScreen.qml` as lipstick does,
    with the launcher's types, the watch's own lipstick QML plugin and the
    SDK's real plugins, so that a module or a type missing on the watch
    fails here. It first compiles `compositor.qml` without the launcher's
    types, which must fail as it did on the watch, to check the check.

  Then the scenes check what they show, and save screenshots and contact
  sheets to `sonic/out/test/shots/`.
  - `applist` checks the order, the hidden apps with `sonic/watch/hide-apps`
    itself, and that lipstick alone honours no override. It reads each logo
    back from the screenshots by its colours, and checks the names.
  - `quickpanel` draws the quick panel on black, with the system services it
    reads stood in for by `sonic/test/stubs/`. Its Find phone button runs
    against a stand-in for ioslink's FindPhone interface on the test bus, in
    the harness, and `sonic/watch/quickpanel-findphone` against the SDK's own
    dconf service. The sound toggle's unmute sound, a `SoundEffect` that opens
    an audio stream as soon as it exists, is there only with the toggle.
  - `today` runs the Today screen with the SDK's real AgendaModel over mkcal.
    `seed-calendar.cpp` fills four coloured notebooks with the mockup's
    sample days, invented, and changes them under the open screen.
  - `button` feeds invented input events to `ButtonDoubleClick` through a
    FIFO, and drives `Flashlight.qml` with a stand-in for the compositor's
    windows: from the home, over an app, with the display off, and more. The
    hold's cases stamp their events on the real boot-time clock, as the kernel
    does: a click, a double-click, a hold, a release at 0.45 s, a press read
    late, a lost release, a device that goes away. So does `voicebutton.js`'s
    guard: on each of the five faces with the display on, ambient (as lipstick
    has it, and with `displayOn` true) and off; in an app and on each other
    panel, where it is false with the display on or ambient and true with it off.
  - `voicenote` runs the recording screen, `VoiceNoteOverlay.qml`, and the hold
    that drives it, `VoiceNoteHold.qml`, against stand-ins in the harness for
    ioslink's VoiceNotes and for mce, on the test bus.
    - **The screens,** fed through the bus as ioslink feeds them: recording, the
      last 30 s, the second before the outcome, saved with the iPhone in reach
      and away, a drop, the limit, too short, storage full, no microphone and
      ioslink gone. The mockup's own levels draw the bars. Each is a screenshot
      of the screen alone, `voicenote-<name>.png`, checked pixel by pixel:
      nothing that isn't black beyond the circle 12 px inside the round edge,
      and the red dot or the green check, the red or grey bars, the "now" line
      and the line's colour where each belongs. `voicenote-sheet.png` has them
      all.
    - **The hold,** with the button's own events through a FIFO: what it calls,
      and in what order, for a long hold, a click, a double-click, no ioslink, a
      refusal, an error from Arm, an Arm answered late, the display off,
      ioslink leaving mid-note, the limit with the button still held, ioslink
      never answering, and a second hold over the first's screen; that the
      leases go only when the screen has; and the screen's 2 s, 2.5 s and 250 ms.
    - **Where a hold records,** with compositor.qml's wiring of the button, the
      guard, `ringsbutton.js`, the hold and the screen, and the scene's state in
      place of the compositor's. A short press on the rings face opens its
      Timer or Stopwatch app after the release, and a click to ioslink (Arm,
      Cancel) shows nothing; a long press there records and opens no app. A
      hold records on each of the five faces with the display on, ambient and
      off, and mce is asked to light the display when it wasn't. With the
      display off it records in an app, on the app list, the quick panel, Today
      and the notifications, with the screen up over them, and leaves them where
      they were. With the display on or ambient, in an app or on another panel,
      a hold calls nothing at all.
    - **The waveform's mapping,** against the fixtures of
      `voicenote-levels.js`: the user's own note of 22:30 (its quiet room, 11 to
      15.5 s, draws as a flat line, and his speech around it tall with the gaps
      between his words showing; the screen at five moments of it,
      `voicenote-note-*.png` and the sheet `voicenote-note2230.png`), and the
      earlier ones, the mockup's speech and room note, a busier room and two
      synthetic quiet rooms: a quiet room flat, the busier room low and far lower
      than his speech, the mockup's speech (5 to 8 dB under his) still shown, and
      none of them becoming the floor over a long note; and the floor: a quieter room lowers it, a louder
      one raises it 0.1 dB a second and never above -50 dBFS, a bar's floor depends
      on the bars before it, and a late chunk of levels gives what the whole would
      have. A tick of the view costs 0.3 ms under emulation.
    - **The waveform live** (`voicenote-live.js`), through the screen's own tick,
      frame by frame, on a clock the scene holds: the hold of 00:10 on the
      watch, its Levels signals at the times they came (`LIVE_0010` in
      `voicenote-levels.js`, the room at about -40 dBFS); and the user's note,
      its levels as they are heard, a level every 50 ms from the press, as
      ioslink sends them on the watch (every 100 ms, 135 ms after), the first
      half second's in a burst as the screen shows, the first second's held
      back to 1.2 s, and 235 ms late, past the row's lag. Each time every bar is
      drawn and keeps its height, the row moves one bar a tick at the most and
      never back, and never waits on the watch's own timing; the first second
      isn't full height (the hold's room 85 px at the most, nothing before
      0.5 s over 30; the note's start tick 58); the note's quiet room stays flat
      and his speech reaches the top; and every bar is the view's, as it draws
      the whole at once.
    - **The screen kept on,** against the stand-in for mce, which plays mce's own
      rules (it's checked first): it refuses an unlock with the display off and
      takes it once the display is on, says its touch lock's mode after every
      request, ignores a pause unless the display is on and the touch lock off,
      drops a pause held when that stops, and blanks a locked display 1.5 s after
      it came on (the watch's 10 s), an unlocked one after 3 s. From the screen
      off, as the user's note of 23:57 was: the wake, the display on, only then
      the unlock, then the pause; from the screen on: the unlock at 0.5 s, then
      the pause; either way the display stays on past both blanks, and the
      touch lock is locked again after the leases. Locked again mid-note, it is
      unlocked again at once; an unlock refused is asked again until mce takes
      it; the pause is renewed and the touch lock asked about at each renewal,
      and nothing once the screen is away; the panels moving meanwhile leave the
      lockscreen alone (a model of `compositor.qml`'s, which `button` shows is
      the real file's), and the face in front after a note is locked again while
      an app or another panel is left unlocked; every way a note ends locks it
      again; a click leaves it alone; and `MainScreen.qml` locks it at the
      launcher's start.
    - **What the screen costs,** per second in the software renderer under
      emulation, hidden, stepping and sliding: only the relation between the
      three means anything, as the watch draws on the GPU. The log has it.
  - `voicenote-fake`, on request, not in the full run: the same screen and hold
    against the main repo's contract fake, `fakeioslink voicenotes`, which
    serves VoiceNotes through godbus and busapi as ioslink does, where the
    harness' stand-in is Qt's. It checks that Nemo.DBus reads what godbus
    exports (State, its PropertiesChanged, Levels' `ai`, Arm's `x`), and each
    way a note ends, as the fake is told to end it. The fork can't build the
    fake, which is Go: build it for the test container, 32-bit ARM Linux, with
    `GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -o
    <fork>/sonic/out/test/fakeioslink ./cmd/fakeioslink` in the main repo's
    `ioslink/`, then `sonic/test/test.sh voicenote-fake`. Without it the scene
    says so, and passes.
  - `voicenote-docs`, on request, not in the full run: the pictures of
    `sonic/docs/`, the recording screen live on the user's note of 22:30 as
    ioslink sends its levels on the watch: `voicenote-docs-first2s.png`, the
    screen at eight moments of the first 2 s, and `voicenote-docs-whole.png`,
    every bar of the note as it was first drawn, with the height it changed to
    after, if it did; and `voicenote-docs-watch-first2s.png`, the hold of 00:10
    on the watch at the same moments, its Levels as they came.
    It loads the recording screen alone, so that it runs on an older build: the
    pictures of before are this scene on that build's QML.
  - `face` runs `FaceLoader` with invented faces that it writes to
    `/tmp/faces`: a good face shows itself; a broken one and a missing one
    show the default face; another choice loads, and the failed one chosen
    again is tried again; a broken default face shows its error, with no
    loop.
  - `preview` puts the others' screenshots on one sheet,
    `preview-dark-theme.png`.
- **The software renderer** draws no shader effects: the quick panel's
  battery bar, which an opacity mask shapes, doesn't show in the screenshots.
  It does on the watch.
- **What it needs from the watch:** two libraries that lipstick needs and the
  SDK lacks, `libmce-qt5` and `libngf-qt5`, lipstick's QML plugin, and the
  watch's Noto Sans for the screenshots. They are copied once over SSH and checked against the SHA-256
  in `test.sh`. Nothing runs on the watch.
