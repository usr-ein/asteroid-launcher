/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The flashlight that the bottom button's double-click toggles (Sonic
 * Screwdriver's watch UI PRD, § 2.1): asteroid-flashlight, the white screen
 * at full brightness that the quick panel's flashlight button opens.
 * - toggle() turns it off when it shows: it closes the app, which restores
 *   the brightness itself.
 * - Otherwise it turns it on: the display first, when it's off or dimmed to
 *   ambient, then the app, or the open one brought back to the front.
 * - It opens over the app on the screen without closing it, unlike any other
 *   app, so that a running timer, say, goes on. Turned off by toggle(), it
 *   gives the screen back to that app; closed any other way, by a swipe for
 *   one, it leaves the app in the background, as a swipe leaves the home. If
 *   the display went off meanwhile, that app is closed, as any app is then.
 * compositor.qml hands each new and each closed app window to opened() and
 * closed(), and the flashlight's window is the one whose process is
 * asteroid-flashlight, however it was opened.
 */
import QtQuick 2.9

QtObject {
    id: flashlight

    // compositor.qml's Compositor: topmostWindow, topmostApplicationWindow,
    // homeWindow and setCurrentWindow().
    property var comp
    // Whether the display is fully on: neither off nor ambient.
    property bool displayOn: true
    // function(window): whether a compositor window is the flashlight's.
    property var isFlashlight
    // function(wrapper): closes an app's window.
    property var closeWindow
    // function(): starts the flashlight app.
    property var launch
    // function(): turns the display on.
    property var wake

    // The flashlight's window while it is open, the app below it, and what
    // was on the screen when it opened: the home or that app.
    property QtObject window: null
    property QtObject below: null
    property QtObject before: null
    // Whether toggle() is closing it.
    property bool closing: false

    // Whether it shines: open, on top, and the display on.
    readonly property bool lit: window !== null && comp.topmostWindow === window && displayOn

    function toggle() {
        if (lit) {
            closing = true
            closeWindow(window)
            return
        }
        if (!displayOn)
            wake()
        if (window !== null)
            comp.setCurrentWindow(window)
        else
            launch()
    }

    // A new app window: true when it is the flashlight's, which then keeps
    // the app below it instead of closing it.
    function opened(wrapper) {
        if (!isFlashlight(wrapper.window))
            return false
        window = wrapper
        before = comp.topmostWindow
        below = comp.topmostApplicationWindow
        return true
    }

    // Another app opens over the flashlight: the app below it goes too, as
    // only one app runs at a time.
    function closeBelow() {
        if (below !== null) {
            closeWindow(below)
            below = null
        }
    }

    // An app window closed: when it was the flashlight's, turned off by
    // toggle(), the app to show again, the one it opened over; otherwise
    // null.
    function closed(wrapper) {
        if (wrapper !== window || window === null)
            return null
        var app = below
        var shown = before
        var restore = closing
        window = null
        below = null
        before = null
        closing = false
        if (app === null)
            return null
        if (!displayOn) {
            closeWindow(app)
            return null
        }
        if (restore && shown === app)
            return app
        // In the background, the app that the next one replaces.
        comp.topmostApplicationWindow = app
        return null
    }
}
