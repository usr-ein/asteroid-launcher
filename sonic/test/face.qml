/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The face scene of sonic/test/test.sh: FaceLoader, the launcher's own, which
 * MainScreen uses for the watch face and the nightstand face. It loads
 * invented faces from /tmp/faces, written here: a good one, a broken one, a
 * missing one, and the default face that stands in, as
 * 000-default-digital.qml does on the watch. They live outside /src, so that
 * their load errors, which are the point, don't count as the fork's warnings.
 * - A good face shows itself.
 * - A broken face, and a missing one, show the default face instead.
 * - Choosing another face loads it, and choosing the failed one again tries it
 *   again.
 * - A broken default face shows the error, as a stock Loader does, with no
 *   loop.
 */
import QtQuick 2.9
import "qrc:/qml/"

Scene {
    id: scene

    readonly property string dir: "file:///tmp/faces/"

    FaceLoader {
        id: faces
        anchors.fill: parent
        defaultFace: dir + "default.qml"
        property int errors: 0
        onStatusChanged: if (status === Loader.Error) errors++
    }

    // A second one, whose default face is broken too. Its loads are counted
    // by source: a Loader already in Error that fails again emits no
    // statusChanged.
    FaceLoader {
        id: brokenDefault
        visible: false
        defaultFace: dir + "broken-default.qml"
        property var sources: []
        onSourceChanged: sources = sources.concat([String(source)])
    }

    function shown(loader) {
        return loader.status === Loader.Ready && loader.item ? loader.item.objectName : ""
    }

    // A face: its name, as text on its own colour.
    function face(name, color) {
        return "import QtQuick 2.9\n" +
            "Rectangle {\n" +
            "    objectName: \"" + name + "\"\n" +
            "    color: \"" + color + "\"\n" +
            "    Text { anchors.centerIn: parent; text: \"" + name + "\"; color: \"white\"; font.pixelSize: 64 }\n" +
            "}\n"
    }

    function write(name, text) {
        return sh("mkdir -p /tmp/faces && cat > /tmp/faces/" + name + " <<'END'\n" + text + "END\n").status === 0
    }

    steps: [
        function(done) {
            check(write("default.qml", face("default", "#202020")) && write("good.qml", face("good", "#0044A6")) &&
                  write("broken.qml", "import QtQuick 2.9\nRectangle { color: }\n") &&
                  write("broken-default.qml", "import org.sonic.nothere 1.0\nRectangle {}\n"),
                  "the faces are written")
            check(faces.source.toString() === "" && faces.status === Loader.Null, "no face before one is chosen")
            faces.face = dir + "good.qml"
            waitFor(function() { return shown(faces) === "good" }, 5000, "a good face shows itself", done)
        },
        function(done) {
            check(!faces.fellBack, "no fallback for a good face")
            shot("face-good", done)
        },
        function(done) {
            faces.face = dir + "broken.qml"
            waitFor(function() { return shown(faces) === "default" }, 5000, "a broken face shows the default face", done)
        },
        function(done) {
            expectEqual(faces.errors, 1, "one load error, the broken face's")
            check(faces.fellBack && faces.failedFace === dir + "broken.qml", "the broken face is the failed one")
            expectEqual(faces.face, dir + "broken.qml", "the choice stays as it was: the binding is kept")
            shot("face-fallback", done)
        },
        function(done) {
            faces.face = dir + "missing.qml"
            waitFor(function() { return shown(faces) === "default" && faces.failedFace === dir + "missing.qml" },
                    5000, "a missing face shows the default face", done)
        },
        function(done) {
            faces.face = dir + "good.qml"
            waitFor(function() { return shown(faces) === "good" }, 5000, "choosing another face loads it", done)
        },
        function(done) {
            check(faces.failedFace === "" && !faces.fellBack, "a new choice clears the failed face")
            var before = faces.errors
            faces.face = dir + "broken.qml"
            waitFor(function() { return faces.errors === before + 1 && shown(faces) === "default" }, 5000,
                    "choosing the failed face again tries it again, and falls back again", done)
        },
        function(done) {
            // A transient empty choice, as MainScreen's locale change makes,
            // unloads the face, and doesn't load the default.
            faces.face = ""
            check(faces.source.toString() === "" && !faces.fellBack, "an empty choice loads nothing")
            faces.face = dir + "good.qml"
            waitFor(function() { return shown(faces) === "good" }, 5000, "and the face after it loads", done)
        },
        function(done) {
            brokenDefault.face = dir + "broken.qml"
            waitFor(function() { return brokenDefault.sources.length === 2 }, 5000,
                    "a broken face, then the broken default face", done)
        },
        function(done) {
            // A second for any loop to show.
            after(1000, function() {
                expectEqual(brokenDefault.sources, [dir + "broken.qml", dir + "broken-default.qml"],
                            "no loop: the same two loads a second later")
                check(brokenDefault.status === Loader.Error && brokenDefault.fellBack,
                      "the default face's error shows, as a stock Loader's would")
                done()
            })
        }
    ]
}
