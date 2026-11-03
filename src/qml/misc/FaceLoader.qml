/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Sonic Screwdriver: a watch face's Loader that falls back to the default
 * face when the chosen one fails to load, so that the watch always shows the
 * time. A stock Loader leaves a screen with no time on it when its face is
 * missing, has a typo, or imports a plugin that is gone.
 *
 * - face is the chosen face, the dconf key's value. It stays bound: the
 *   fallback never assigns source, so a new choice in Settings applies.
 * - When face fails to load, defaultFace shows instead, and the journal gets
 *   one warning naming the face.
 * - Choosing another face loads it, and choosing the failed one again tries
 *   it again: failedFace clears whenever face changes. A face fixed and
 *   reinstalled at the same path is tried again at the next launcher start.
 * - If the default face fails too, its error shows, as with a stock Loader:
 *   no loop.
 * - Only a load error counts. A face that loads, then throws at run time,
 *   isn't covered.
 */
import QtQuick 2.9

Loader {
    id: loader

    // The chosen face's URL.
    property string face: ""
    // What shows when face fails to load.
    property string defaultFace: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
    // The face that failed to load, until another one is chosen.
    property string failedFace: ""
    // Whether the default face shows in face's place.
    readonly property bool fellBack: face !== "" && face === failedFace

    source: fellBack ? defaultFace : face

    onFaceChanged: failedFace = ""

    // Each load is judged once it's over, outside the Loader's own signals.
    // A load that fails right after another failed keeps the status at Error,
    // with no statusChanged, so a new source is judged too; Qt.callLater runs
    // judge once for both.
    onSourceChanged: Qt.callLater(judge)
    onStatusChanged: Qt.callLater(judge)

    function judge() {
        if (status !== Loader.Error)
            return
        var failed = String(source)
        if (failed === defaultFace) {
            console.warn("sonic: the default watch face " + defaultFace + " failed to load too")
        } else if (failed === face && failedFace !== face) {
            console.warn("sonic: the watch face " + face + " failed to load; showing the default face")
            failedFace = face
        }
    }
}
