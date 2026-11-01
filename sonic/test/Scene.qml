/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * What every scene of sonic/test/test.sh shares: the watch's 454 × 454 round
 * screen, a timeline of steps, checks and screenshots.
 *
 * A scene puts its steps in `steps`: functions that take `done` and call it
 * when finished. The scene ends after the last one, and the harness exits 1
 * if a check failed.
 */
import QtQuick 2.9

Item {
    id: scene
    width: 454
    height: 454

    property var steps: []
    property int failures: 0
    // Where the screenshots go (test.sh mounts sonic/out/test there).
    property string shots: "/out/shots"

    // The round screen: what's outside it isn't on the watch.
    property alias roundMask: mask
    Rectangle {
        id: mask
        z: 1000
        x: -100
        y: -100
        width: parent.width + 200
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 100
        border.color: "black"
    }

    function check(ok, what) {
        if (ok) {
            test.log("ok   " + what)
        } else {
            failures++
            test.log("FAIL " + what)
        }
        return ok
    }

    function expectEqual(actual, expected, what) {
        var a = JSON.stringify(actual), e = JSON.stringify(expected)
        if (!check(a === e, what))
            test.log("     got      " + a + "\n     expected " + e)
    }

    function sh(command) {
        var result = test.sh(command)
        if (result.status !== 0)
            test.log("     $ " + command + "\n     exit " + result.status + ": " + result.output)
        return result
    }

    Timer {
        id: delay
        property var callback
        onTriggered: callback()
    }

    function after(ms, callback) {
        delay.callback = callback
        delay.interval = ms
        delay.restart()
    }

    // Polls until predicate() holds, then checks it, at most timeout ms.
    function waitFor(predicate, timeout, what, done) {
        var start = Date.now()
        function poll() {
            if (predicate()) {
                check(true, what + " (" + (Date.now() - start) + " ms)")
                done()
            } else if (Date.now() - start > timeout) {
                check(false, what + " (gave up after " + timeout + " ms)")
                done()
            } else {
                after(100, poll)
            }
        }
        poll()
    }

    // Saves the screen, or one item, as <shots>/<name>.png.
    function shot(name, done, item) {
        var target = item || scene
        var ok = target.grabToImage(function(result) {
            check(result.saveToFile(shots + "/" + name + ".png"), "screenshot " + name + ".png")
            done()
        })
        if (!ok) {
            check(false, "screenshot " + name + ".png: grabToImage refused")
            done()
        }
    }

    property int stepIndex: 0
    function next() {
        if (stepIndex === steps.length) {
            test.log(failures === 0 ? "passed" : failures + " check(s) failed")
            test.exit(failures === 0 ? 0 : 1)
            return
        }
        var step = steps[stepIndex++]
        step(function() { after(0, next) })
    }

    // The first frames first, then the timeline.
    Component.onCompleted: after(500, next)
}
