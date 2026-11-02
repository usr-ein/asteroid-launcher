import QtQuick 2.9

QtObject {
    enum State { Unknown, Charging, Discharging, NotCharging, Full }
    property bool valid: true
    property int value: 2
}
