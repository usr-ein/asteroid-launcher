/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The app list's apps, as every app list style reads them (launcherModel):
 * lipstick's LauncherModel through AppListModel. The apps below come first, in
 * this order, then the others by title. An override hides an app: a .desktop
 * file of the same name with NoDisplay=true in /usr/local/share/applications
 * (sonic/hide-apps.sh writes them) or ~/.local/share/applications.
 *
 * Weather, Timer and Stopwatch are Sonic Screwdriver's own, sonic-weather,
 * sonic-timer and sonic-stopwatch; the stock asteroid-weather, asteroid-timer
 * and asteroid-stopwatch, which hide-apps hides, would follow the others by
 * title.
 */

import org.nemomobile.lipstick 0.1
import org.asteroid.launcher 1.0

AppListModel {
    sourceModel: LauncherModel { }
    order: [
        "sonic-checkin",
        "asteroid-alarmclock",
        "asteroid-hrm",
        "sonic-timer",
        "sonic-stopwatch",
        "sonic-weather",
        "asteroid-flashlight",
        "asteroid-diamonds"
    ]
}
