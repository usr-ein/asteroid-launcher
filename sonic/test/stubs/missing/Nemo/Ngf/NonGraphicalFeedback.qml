import QtQuick 2.9
import "plays.js" as Plays

// Never a sound or a vibration in a test: each play() is recorded in
// plays.js, which a scene imports to read them.
QtObject {
    property string event
    function play() { Plays.played(event) }
    function stop() { }
}
