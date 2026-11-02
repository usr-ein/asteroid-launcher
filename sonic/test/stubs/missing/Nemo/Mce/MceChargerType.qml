import QtQuick 2.9

QtObject {
    enum Type { None, USB, DCP, HVDCP, CDP, Wireless, Other }
    property bool valid: true
    property int type: 0
}
