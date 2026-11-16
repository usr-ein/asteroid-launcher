/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The notification scene of sonic/test/test.sh (P-032): an opened
 * notification, NotificationView.qml, compiled in, with invented ones:
 *   - a long WhatsApp group message, with no actions of its own: its Clear
 *     is the watch's Dismiss;
 *   - the check-in, with Answer and "Ask me in 10 min";
 *   - an incoming WhatsApp call, with the iPhone's Accept and Decline.
 * On P-032's round-fit view it checks:
 *   - the pills: their order and labels, and no Snooze anywhere; Dismiss
 *     last and Dismiss all just before it, so the pin's place at the end
 *     holds Dismiss (Sam: "Dismiss all first-safe");
 *   - the main action pinned at the bottom while the text is read, and the
 *     last pill there at the end;
 *   - their size: one height, 80% of the screen near the middle, narrower
 *     toward the rim with their rounded ends inside the circle, never
 *     overlapping, fading at the rim, the pinned one never;
 *   - taps, as real presses and releases: a pill's key invoked, Dismiss
 *     removing the notification, Dismiss all removing every one; and a press
 *     on a pill that moves scrolls instead of tapping.
 * Screenshots: each notification at its start, its middle and its end, and a
 * contact sheet of them. On the view from before P-032 it only saves the
 * screenshots, for the before and after.
 */
import QtQuick 2.9
import "qrc:/qml/"

Scene {
    id: desktop

    QtObject {
        id: localeManager
        property string changesObserver: ""
    }

    // Lipstick's notification, as the view uses it; got keeps what the view
    // did with it.
    QtObject {
        id: whatsapp
        property string appName: "WhatsApp"
        property string summary: "Léa Martin"
        property string body: "Climbing Crew\nOk so plan for Saturday: we meet at Monk Bouldergym at 10, Tom has the car so he can pick up Sanne and Max on the way. I booked the 10:30 slot for the lead wall, 6 people, it's paid already so just send me €14 each whenever. After that lunch at the market, and if the weather holds we could drive to the quarry in the afternoon? Bring your own rope if you have one, theirs are pretty worn. Also @Sam did you still have my belay device from last week? I need it back before Sat…"
        property date timestamp: new Date(Date.now() - 4 * 60 * 1000)
        property var actions: []
        property bool userRemovable: true
        property string icon: ""
        property string appIcon: ""
        property var got: []
        signal actionInvoked(string action)
        signal removeRequested
        onActionInvoked: got = got.concat(["action " + action])
        onRemoveRequested: got = got.concat(["remove"])
    }
    QtObject {
        id: checkin
        property string appName: "Check-in"
        property string summary: "How are you?"
        property string body: "Tap to check in."
        property date timestamp: new Date()
        property var actions: ["default", "Answer", "later", "Ask me in 10 min"]
        property bool userRemovable: true
        property string icon: "ios-happy-outline"
        property string appIcon: ""
        property var got: []
        signal actionInvoked(string action)
        signal removeRequested
        onActionInvoked: got = got.concat(["action " + action])
        onRemoveRequested: got = got.concat(["remove"])
    }
    QtObject {
        id: call
        property string appName: "WhatsApp"
        property string summary: "Tom"
        property string body: "WhatsApp Audio..."
        property date timestamp: new Date()
        property var actions: ["ancs-positive", "Accept", "ancs-negative", "Decline"]
        property bool userRemovable: true
        property string icon: ""
        property string appIcon: ""
        property var got: []
        signal actionInvoked(string action)
        signal removeRequested
        onActionInvoked: got = got.concat(["action " + action])
        onRemoveRequested: got = got.concat(["remove"])
    }

    // NotificationsPanel's model, for Dismiss all.
    QtObject {
        id: model
        property int itemCount: 3
        function get(i) {
            return [whatsapp, checkin, call][i]
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    NotificationView {
        id: view
        width: desktop.width
        height: desktop.height
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 3
    }

    readonly property var cases: [
        { n: whatsapp, name: "whatsapp", pills: ["Dismiss all", "Dismiss"],
          keys: ["dismiss-all", "dismiss"], main: "Dismiss", pinned: true },
        { n: checkin, name: "checkin", pills: ["Answer", "Ask me in 10 min", "Dismiss all", "Dismiss"],
          keys: ["default", "later", "dismiss-all", "dismiss"], main: "Answer", pinned: false },
        { n: call, name: "call", pills: ["Accept", "Decline", "Dismiss all", "Dismiss"],
          keys: ["ancs-positive", "ancs-negative", "dismiss-all", "dismiss"], main: "Dismiss", pinned: true }
    ]
    property var files: []
    property var labels: []

    function find(item, predicate, out) {
        if (predicate(item))
            out.push(item)
        for (var i = 0; i < item.children.length; i++)
            find(item.children[i], predicate, out)
        return out
    }

    // The round-fit view's parts; null, or none, on the view from before.
    function fit() {
        var f = find(view, function(i) { return i.objectName === "notificationFit" }, [])
        return f.length ? f[0] : null
    }
    function pills() {
        var p = find(view, function(i) { return i.objectName === "notificationPill" }, [])
        p.sort(function(a, b) { return a.order - b.order })
        return p
    }

    function keep(name, label, done) {
        var file = (fit() ? "notification-" : "notification-before-") + name
        shot(file, function() {
            files.push(shots + "/" + file + ".png")
            labels.push(label)
            done()
        })
    }

    // The view from before P-032: its text is a Column it moves itself.
    function scrollOld(share) {
        var column = view.children[0]
        column.y = -Math.max(0, column.height - view.height) * share
    }

    function show(c, done) {
        if ("notificationModel" in view)
            view.notificationModel = model
        view.notification = c.n
        if (!fit())
            scrollOld(0) // the view from before keeps its scroll from the last one
        after(400, done)
    }

    function scrollTo(share, done) {
        var f = fit()
        if (f)
            f.positionTo(f.contentHeight * share)
        else
            scrollOld(share)
        after(400, done)
    }

    // The pills' geometry, at the position they're at.
    function checkPills(c, where) {
        var p = pills()
        var R = view.width / 2
        var visible = p.filter(function(x) { return x.shown })
        for (var i = 0; i < visible.length; i++) {
            var x = visible[i]
            check(Math.abs(x.pillHeight - 76 * view.width / 454) < 0.5, c.name + " " + where + ": " + x.label + " is 76 px tall")
            check(x.pillWidth <= 0.8 * view.width + 0.5, c.name + " " + where + ": " + x.label + " at most 80% wide")
            // Its rounded ends inside the circle.
            var d = Math.abs(x.centreY - view.height / 2)
            var r = x.pillHeight / 2
            var end = Math.sqrt(Math.pow(x.pillWidth / 2 - r, 2) + d * d) + r
            check(end <= R + 0.5, c.name + " " + where + ": " + x.label + " inside the circle (" + end.toFixed(1) + " of " + R + ")")
            // Two pills in the list keep their gap; one nearing the pinned
            // pill fades out before it would touch it.
            if (i > 0) {
                var apart = x.pinned || visible[i - 1].pinned ? x.pillHeight : x.pillHeight + 20 * view.width / 454
                check(x.centreY - visible[i - 1].centreY >= apart - 0.5,
                      c.name + " " + where + ": " + x.label + " doesn't overlap the pill above it")
            }
            if (x.pinned)
                check(x.opacity === 1, c.name + " " + where + ": the pinned pill isn't faded")
            else
                check(x.opacity <= fit().opacityAt(x.centreY) + 1e-6, c.name + " " + where + ": " + x.label + " fades like the text")
            if (d < 100 * view.width / 454 && !x.pinned)
                check(Math.abs(x.pillWidth - 0.8 * view.width) < 0.5, c.name + " " + where + ": " + x.label + " is 80% wide near the middle")
        }
    }

    function centreOf(x) {
        return Qt.point(view.width / 2, x.centreY)
    }

    // A real press and release on each visible pill, the last first, as Dismiss
    // all and Dismiss would close the view on the watch.
    function tapAll(c, done) {
        var p = pills().filter(function(x) { return x.shown && x.opacity > 0.9 })
        var i = p.length - 1
        function one() {
            if (i < 0) {
                done()
                return
            }
            var x = p[i--]
            var before = c.n.got.length
            var all = [whatsapp.got.length, checkin.got.length, call.got.length]
            var at = centreOf(x)
            test.touch("press", at.x, at.y)
            test.touch("release", at.x, at.y)
            after(200, function() {
                var key = c.keys[c.pills.indexOf(x.label)]
                if (key === "dismiss-all") {
                    check(whatsapp.got.length === all[0] + 1 && checkin.got.length === all[1] + 1 && call.got.length === all[2] + 1,
                          c.name + ": a tap on Dismiss all removes every notification")
                } else if (key === "dismiss") {
                    expectEqual(c.n.got.slice(before), ["remove"], c.name + ": a tap on Dismiss removes it")
                } else {
                    expectEqual(c.n.got.slice(before), ["action " + key], c.name + ": a tap on " + x.label + " invokes " + key)
                }
                one()
            })
        }
        one()
    }

    // A press on a pill that moves scrolls, and taps nothing.
    function dragFrom(c, done) {
        var p = pills().filter(function(x) { return x.shown && x.opacity > 0.9 })
        var x = p[p.length - 1]
        var at = centreOf(x)
        var before = fit().position, got = c.n.got.length
        test.touch("press", at.x, at.y)
        var steps = 0
        function move() {
            if (steps++ < 8) {
                test.touch("move", at.x, at.y + steps * 12)
                after(16, move)
                return
            }
            test.touch("release", at.x, at.y + 96)
            after(600, function() {
                check(fit().position < before - 40, c.name + ": a drag that starts on a pill scrolls (" + before.toFixed(0) + " to " + fit().position.toFixed(0) + ")")
                check(c.n.got.length === got, c.name + ": and taps nothing")
                done()
            })
        }
        after(16, move)
    }

    function steps_for(c) {
        return [
            function(done) { show(c, done) },
            function(done) {
                var f = fit()
                if (f) {
                    var p = pills()
                    expectEqual(p.map(function(x) { return x.label }), c.pills, c.name + ": its pills, in order")
                    check(p.every(function(x) { return x.label !== "Snooze" }), c.name + ": no Snooze")
                    check(p[p.length - 1].label === "Dismiss" && p[p.length - 2].label === "Dismiss all",
                          c.name + ": Dismiss last, Dismiss all just before it, never last")
                    var mains = p.filter(function(x) { return x.main })
                    check(mains.length === 1 && mains[0].label === c.main, c.name + ": its main action is " + c.main)
                    if (c.pinned) {
                        check(mains[0].pinned && Math.abs(mains[0].centreY - 0.852 * view.height) < 1,
                              c.name + ": its main action is pinned at the bottom while the text is read")
                    }
                    checkPills(c, "at the start")
                }
                keep(c.name + "-start", c.name + ": opened", done)
            },
            function(done) { scrollTo(0.5, done) },
            function(done) {
                if (fit())
                    checkPills(c, "half way")
                keep(c.name + "-middle", c.name + ": half way", done)
            },
            function(done) { scrollTo(1, done) },
            function(done) {
                var f = fit()
                if (f) {
                    var p = pills()
                    var last = p[p.length - 1]
                    check(Math.abs(last.centreY - 0.852 * view.height) < 1 && last.label === "Dismiss",
                          c.name + ": at the end, Dismiss is where the main one was pinned")
                    var main = p.filter(function(x) { return x.main })[0]
                    if (main !== last)
                        check(!main.pinned && main.centreY < last.centreY, c.name + ": at the end, the main action has left its pin, above the others")
                    checkPills(c, "at the end")
                }
                keep(c.name + "-end", c.name + ": the end", done)
            },
            function(done) {
                if (fit())
                    tapAll(c, done)
                else
                    done()
            },
            function(done) {
                if (fit()) {
                    fit().positionTo(fit().contentHeight)
                    after(300, function() { dragFrom(c, done) })
                } else {
                    done()
                }
            }
        ]
    }

    steps: {
        var s = []
        for (var i = 0; i < cases.length; i++)
            s = s.concat(steps_for(cases[i]))
        s.push(function(done) {
            sheet.title = fit() ? "An opened notification, read round-fit, its actions in a round-fit list (P-032)"
                                : "An opened notification, before P-032"
            sheet.files = files
            sheet.labels = labels
            after(400, function() { shot(fit() ? "notification-sheet" : "notification-sheet-before", done, sheet) })
        })
        return s
    }
}
