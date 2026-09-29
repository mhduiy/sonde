import QtQuick
import QtQuick.Controls

/// 代码查看器：行号 + 语法高亮 + 可选中复制 + 双向滚动。
///
/// 高亮由 C++ 的 `bridge.jsonLines()` 生成（按行切好的 HTML）。
/// 用 QtQuick 的 `TextEdit` 而不是 Controls 的 `TextArea`——后者没有暴露
/// `lineHeight`，行号栏就没法跟正文严格对齐。
///
/// 滚动用「Flickable + 自己摆的 ScrollBar」而不是 ScrollView：
/// ScrollView 的附着滚动条在内容超宽时位置不可靠（会跑到左边去），
/// 自己摆位置和尺寸都确定。
Item {
    id: root

    property string text: ""
    property bool wrap: false

    readonly property var colors: ({
        key: theme.accent,
        str: theme.valStr,
        num: theme.valNum,
        bool: theme.valBool,
        punct: theme.textFaint
    })

    readonly property var lines: bridge.jsonLines(root.text, root.colors)
    readonly property int gutterWidth: Math.max(26, ("" + root.lines.length).length * 9 + 12)
    // RichText 会把 \n 当空白折叠掉，必须用 <br/> 才能真正换行
    readonly property string html: root.lines.join("<br/>")

    FontMetrics {
        id: fm
        font: code.font
    }
    // TextEdit 的行高由字体决定（约 = height + leading），行号栏必须用同一个值
    readonly property int lineH: Math.ceil(fm.height + fm.leading)

    readonly property int barThickness: 11

    Flickable {
        id: flick
        anchors.fill: parent
        // 固定预留滚动条的位置：不能按 vbar.size 动态算，
        // 那样 vbar.size ← flick.height ← bottomMargin ← vbar.size 会成环
        anchors.rightMargin: root.barThickness
        anchors.bottomMargin: root.barThickness
        contentWidth: Math.max(width, content.implicitWidth)
        contentHeight: Math.max(height, content.implicitHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            topPadding: 6
            bottomPadding: 10

            Row {
                spacing: 0

                // 行号栏（自动换行时行高会漂，索性隐藏）
                Column {
                    visible: !root.wrap
                    leftPadding: 8
                    rightPadding: 6

                    Repeater {
                        model: root.lines.length
                        delegate: Label {
                            required property int index
                            width: root.gutterWidth
                            height: root.lineH
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignTop
                            text: index + 1
                            color: theme.textFaint
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }
                }

                Rectangle {
                    visible: !root.wrap
                    width: 1
                    height: Math.max(code.height, root.lines.length * root.lineH)
                    color: theme.border
                }

                TextEdit {
                    id: code
                    width: root.wrap
                           ? Math.max(200, flick.width - root.gutterWidth - 24)
                           : implicitWidth
                    textFormat: TextEdit.RichText
                    text: root.html
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                    color: theme.text
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }
        }
    }

    // 纵向：常显，内容长了必须一眼看出能滚
    ScrollBar {
        id: vbar
        orientation: Qt.Vertical
        policy: ScrollBar.AlwaysOn
        active: true
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.barThickness
        size: Math.min(1, flick.height / Math.max(1, flick.contentHeight))
        position: flick.contentY / Math.max(1, flick.contentHeight)
        onPositionChanged: flick.contentY = position * flick.contentHeight
    }

    ScrollBar {
        id: hbar
        orientation: Qt.Horizontal
        policy: ScrollBar.AsNeeded
        active: true
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.barThickness
        anchors.bottom: parent.bottom
        size: Math.min(1, flick.width / Math.max(1, flick.contentWidth))
        position: flick.contentX / Math.max(1, flick.contentWidth)
        onPositionChanged: flick.contentX = position * flick.contentWidth
    }
}
