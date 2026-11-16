/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The notification scene of sonic/test/test.sh (P-032): an opened
 * notification, NotificationView.qml, compiled in, with invented ones:
 *   - a long WhatsApp group message, with no actions of its own: its Clear
 *     is the watch's Dismiss;
 *   - the check-in, with Answer and "Ask me in 10 min";
 *   - an incoming WhatsApp call, with the iPhone's Accept and Decline.
 * On the round-fit view (P-032, with P-042's layout) it checks:
 *   - the start: the first line near the top, whole, the title just below
 *     it, and no scrolling further up (Sam, P-042: "I want the title at the
 *     top");
 *   - the pills: their order and labels, and no Snooze anywhere; Dismiss
 *     first and Dismiss all last (Sam, P-042: "I want the other buttons to
 *     scroll into view below the dismiss button");
 *   - nothing pinned: every pill comes after the text, in order down the
 *     screen, and the last one ends the list at the bottom;
 *   - their size: one height, 80% of the screen near the middle, narrower
 *     toward the rim with their rounded ends inside the circle, never
 *     overlapping, fading at the rim;
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

    // main: the "default" action's label, drawn as the main one; none
    // without one.
    readonly property var cases: [
        { n: whatsapp, name: "whatsapp", pills: ["Dismiss", "Dismiss all"],
          keys: ["dismiss", "dismiss-all"], main: "" },
        { n: checkin, name: "checkin", pills: ["Dismiss", "Answer", "Ask me in 10 min", "Dismiss all"],
          keys: ["dismiss", "default", "later", "dismiss-all"], main: "Answer" },
        { n: call, name: "call", pills: ["Dismiss", "Accept", "Decline", "Dismiss all"],
          keys: ["dismiss", "ancs-positive", "ancs-negative", "dismiss-all"], main: "" }
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

    function lines() {
        var l = find(view, function(i) { return i.objectName === "notificationLine" }, [])
        l.sort(function(a, b) { return a.y - b.y })
        return l
    }
    function middleOf(line) {
        return line.y + line.height / 2
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
            // Two pills keep their gap, in their order down the screen.
            if (i > 0) {
                check(x.order > visible[i - 1].order
                      && x.centreY - visible[i - 1].centreY >= x.pillHeight + 20 * view.width / 454 - 0.5,
                      c.name + " " + where + ": " + x.label + " is below the pill above it, a gap apart")
            }
            check(x.opacity <= fit().opacityAt(x.centreY) + 1e-6, c.name + " " + where + ": " + x.label + " fades like the text")
            if (d < 100 * view.width / 454)
                check(Math.abs(x.pillWidth - 0.8 * view.width) < 0.5, c.name + " " + where + ": " + x.label + " is 80% wide near the middle")
        }
        // Nothing pinned: the pills come after the text, which ends above
        // the first one shown.
        var l = lines().filter(function(x) { return x.visible })
        if (visible.length > 0 && l.length > 0)
            check(middleOf(l[l.length - 1]) < visible[0].centreY - visible[0].pillHeight / 2,
                  c.name + " " + where + ": the text ends above the pills")
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
                    check(p[0].label === "Dismiss" && p[p.length - 1].label === "Dismiss all",
                          c.name + ": Dismiss first, Dismiss all last")
                    var mains = p.filter(function(x) { return x.main }).map(function(x) { return x.label })
                    expectEqual(mains, c.main ? [c.main] : [], c.name + ": its main action is " + (c.main || "none"))
                    // The start: the first line near the top, whole; the
                    // title just below it.
                    var l = lines().filter(function(x) { return x.visible })
                    check(f.position === 0, c.name + ": it opens at its start (" + f.position.toFixed(1) + ")")
                    check(l.length > 1 && Math.abs(middleOf(l[0]) - 0.19 * view.height) < 1.5 && l[0].opacity === 1,
                          c.name + ": its first line is near the top, whole (" + (l.length ? middleOf(l[0]).toFixed(1) : "none") + ")")
                    check(l.length > 1 && l[1].text === c.n.summary && middleOf(l[1]) < 0.3 * view.height && l[1].opacity === 1,
                          c.name + ": its title is next, at the top (" + (l.length > 1 ? middleOf(l[1]).toFixed(1) : "none") + ")")
                    checkPills(c, "at the start")
                }
                keep(c.name + "-start", c.name + ": opened", done)
            },
            function(done) {
                // Nothing further up: the start is the top.
                var f = fit()
                if (f)
                    f.positionTo(-200)
                after(300, function() {
                    if (f) {
                        var l = lines().filter(function(x) { return x.visible })
                        check(f.position === 0 && Math.abs(middleOf(l[0]) - 0.19 * view.height) < 1.5,
                              c.name + ": it scrolls no further up than its start")
                    }
                    done()
                })
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
                    check(Math.abs(last.centreY - 0.852 * view.height) < 1 && last.label === "Dismiss all",
                          c.name + ": at the end, Dismiss all ends the list at the bottom (" + last.centreY.toFixed(1) + ")")
                    check(p[0].shown && p[0].centreY < p[1].centreY, c.name + ": at the end, Dismiss is above the others")
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
            sheet.title = fit() ? "An opened notification: the title at the top, Dismiss the first pill, nothing pinned (P-042)"
                                : "An opened notification, before P-032"
            sheet.files = files
            sheet.labels = labels
            after(400, function() { shot(fit() ? "notification-sheet" : "notification-sheet-before", done, sheet) })
        })
        return s
    }
}
