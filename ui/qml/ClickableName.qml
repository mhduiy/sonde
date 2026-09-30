import QtQuick
import QtQuick.Controls

/// 可点击的服务名：点一下跳到那个服务的对象树。
/// 接收者为空时显示占位文案（例如广播信号）。
Item {
    id: root

    property string name: ""
    property string emptyText: "—"
    property color textColor: theme.accent
    property int pointSize: 11

    signal clicked()

    readonly property bool clickable: root.name !== ""
    readonly property string shown: clickable ? root.name : root.emptyText

    clip: true
    height: 20

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: (hover.hovered && root.clickable) ? theme.hover : "transparent"
    }

    Label {
        id: label
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        leftPadding: 3
        rightPadding: 3
        elide: Text.ElideMiddle
        text: root.shown
        color: root.clickable ? root.textColor : theme.textFaint
        font.family: "monospace"
        font.pixelSize: root.pointSize
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.clickable
        onTapped: root.clicked()
    }

    ToolTip.visible: hover.hovered && root.clickable
    ToolTip.text: "跳到 " + root.name
}
