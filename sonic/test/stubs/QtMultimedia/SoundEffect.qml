import QtQuick 2.9

// Never a sound in a test.
QtObject {
    property url source
    property real volume: 1
    function play() { }
    function stop() { }
}
