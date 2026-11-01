import QtQuick 2.9

// Never a sound or a vibration in a test.
QtObject {
    property string event
    function play() { }
    function stop() { }
}
