import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0 as D

/// 结构化输出：让用户自己选展示方式，并自动识别挑一个默认页签。
///
/// - 数组里全是对象 / 对象里全是标量 → **表格**（真正的列，可直接看）
/// - 其它合法 JSON（含 JSON 字符串）  → **JSON**（带行号 + 语法高亮）
/// - 其它                            → **文本**
///
/// 结构体 → JSON 数组、字典 → JSON 对象，所以 D-Bus 的 a{sv} / a{...}
/// 这类返回值也能直接进表格。
ColumnLayout {
    id: root

    property var nodes: []          // 值节点数组（Rust 解码出来的）
    property string singleText: ""  // 或者直接喂一段文本
    property string tab: ""         // "" = 跟随自动识别
    property int maxHeight: 340

    spacing: 6

    readonly property string jsonText:
        root.innerParsed !== null ? root.rawStringValue
        : (root.nodes.length > 0
           ? (root.nodes.length === 1 ? bridge.nodeToJson(root.nodes[0])
                                      : bridge.nodesToJson(root.nodes))
           : root.singleText)

    /// 单个字符串值（deepin 的接口经常把 JSON 塞在字符串里返回）
    readonly property string rawStringValue:
        (root.nodes.length === 1 && root.nodes[0] && root.nodes[0].kind === "str")
        ? ("" + (root.nodes[0].text || "")) : ""

    function tryParse(s) {
        if (!s)
            return null
        var t = ("" + s).trim()
        if (t.length < 2)
            return null
        var head = t.charAt(0)
        var tail = t.charAt(t.length - 1)
        if (!((head === "{" && tail === "}") || (head === "[" && tail === "]")))
            return null
        try {
            return JSON.parse(t)
        } catch (e) {
            return null
        }
    }

    /// 字符串里如果装着 JSON，就解析出来当结构化数据用（表格/JSON 页签都基于它）
    readonly property var innerParsed: root.rawStringValue !== ""
                                       ? root.tryParse(root.rawStringValue) : null

    readonly property var parsed: {
        if (root.innerParsed !== null)
            return root.innerParsed
        return root.tryParse(root.jsonText)
    }

    readonly property bool tableable: {
        var v = root.parsed
        if (v === null || typeof v !== "object")
            return false
        if (Array.isArray(v)) {
            if (v.length === 0)
                return false
            for (var i = 0; i < v.length; ++i) {
                if (v[i] === null || typeof v[i] !== "object" || Array.isArray(v[i]))
                    return false
            }
            return true
        }
        var keys = Object.keys(v)
        if (keys.length === 0)
            return false
        for (var k = 0; k < keys.length; ++k) {
            var val = v[keys[k]]
            if (val !== null && typeof val === "object")
                return false
        }
        return true
    }

    /// 表格数据：{cols, rows}，列顺序按 JSON 里第一次出现的顺序
    readonly property var table: {
        var v = root.parsed
        if (v === null || v === undefined || typeof v !== "object")
            return { cols: [], rows: [] }
        if (Array.isArray(v)) {
            var cols = []
            var seen = {}
            for (var i = 0; i < v.length; ++i) {
                for (var k in v[i]) {
                    if (!seen[k]) {
                        seen[k] = true
                        cols.push(k)
                    }
                }
            }
            return { cols: cols, rows: v }
        }
        var keys = Object.keys(v)
        var rows2 = []
        for (var j = 0; j < keys.length; ++j) {
            var o = {}
            o["键"] = keys[j]
            o["值"] = v[keys[j]]
            rows2.push(o)
        }
        return { cols: ["键", "值"], rows: rows2 }
    }

    /// 列宽：按最长内容估算并夹在 [76, 300]
    readonly property var colWidths: {
        var cols = root.table.cols
        var rows = root.table.rows
        var out = []
        for (var c = 0; c < cols.length; ++c) {
            var maxLen = ("" + cols[c]).length
            for (var r = 0; r < rows.length; ++r) {
                var l = root.cellText(rows[r][cols[c]]).length
                if (l > maxLen)
                    maxLen = l
            }
            out.push(Math.max(76, Math.min(300, maxLen * 8 + 20)))
        }
        return out
    }

    readonly property int tableWidth: {
        var w = 0
        var cw = root.colWidths
        for (var i = 0; i < cw.length; ++i)
            w += cw[i]
        return Math.max(120, w)
    }

    readonly property string defaultTab: tableable ? "table" : (parsed !== null ? "json" : "text")
    readonly property var tabNames: ["table", "json", "text"]
    readonly property string activeTab: root.tab !== "" ? root.tab : root.defaultTab
    readonly property int activeIndex: Math.max(0, tabNames.indexOf(activeTab))

    /// 文本页签的内容：单个字符串就给原文，否则给可读的伪 JSON
    readonly property string plainText: {
        if (root.rawStringValue !== "")
            return root.rawStringValue
        if (root.nodes.length === 1)
            return bridge.nodeToText(root.nodes[0])
        return root.jsonText
    }

    function cellText(v) {
        if (v === null || v === undefined)
            return ""
        if (typeof v === "object")
            return JSON.stringify(v)
        return "" + v
    }

    onJsonTextChanged: {
        root.tab = ""
        // 用户点过页签会破坏 currentIndex 的绑定，换内容时重新接上
        tabs.currentIndex = Qt.binding(function () { return root.activeIndex })
    }

    // ------------------------------------------------------------ 页签栏
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TabBar {
            id: tabs
            Layout.alignment: Qt.AlignVCenter
            currentIndex: root.activeIndex
            // 不用 TabBar 的信号（Controls 的 TabBar 没有 activated），
            // 让每个 TabButton 自己响应点击——clicked 只在用户点击时触发，
            // 不会和 activeTab 形成绑定循环。

            TabButton {
                text: "表格"
                implicitWidth: 64
                enabled: root.tableable
                onClicked: root.tab = "table"
            }
            TabButton {
                text: "JSON"
                implicitWidth: 64
                enabled: root.parsed !== null
                onClicked: root.tab = "json"
            }
            TabButton {
                text: "文本"
                implicitWidth: 64
                onClicked: root.tab = "text"
            }
        }

        Item { Layout.fillWidth: true }

        Label {
            visible: root.activeTab === "table"
            text: root.table.rows.length + " 行 × " + root.table.cols.length + " 列"
            color: theme.textFaint
            font.pixelSize: 10
        }
        Label {
            visible: root.activeTab === "json"
            text: bridge.jsonLines(root.jsonText, root.jsonColors()).length + " 行"
            color: theme.textFaint
            font.pixelSize: 10
        }

        D.ToolButton {
            text: "放大"
            implicitHeight: 22
            visible: root.activeTab !== "text"
            onClicked: viewer.open()
        }
        D.ToolButton {
            text: "复制"
            implicitHeight: 22
            onClicked: {
                if (root.activeTab === "json")
                    clip.put(root.jsonText)
                else if (root.activeTab === "table")
                    clip.put(root.tableAsTsv())
                else
                    clip.put(root.plainText)
            }
        }
    }

    function jsonColors() {
        return {
            key: theme.accent,
            str: theme.valStr,
            num: theme.valNum,
            bool: theme.valBool,
            punct: theme.textFaint
        }
    }

    function tableAsTsv() {
        var cols = root.table.cols
        var rows = root.table.rows
        var lines = [cols.join("\t")]
        for (var r = 0; r < rows.length; ++r) {
            var cells = []
            for (var c = 0; c < cols.length; ++c)
                cells.push(root.cellText(rows[r][cols[c]]))
            lines.push(cells.join("\t"))
        }
        return lines.join("\n")
    }

    // ------------------------------------------------------------ 内容
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: root.maxHeight
        currentIndex: root.activeIndex

        // ---- 表格 ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            // 横向用 Flickable（只吃横向手势），纵向交给内层 ListView
            Flickable {
                anchors.fill: parent
                anchors.margins: 1
                contentWidth: root.tableWidth
                contentHeight: root.maxHeight
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    width: root.tableWidth

                    Row {
                        Repeater {
                            model: root.table.cols
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: root.colWidths[index]
                                height: 26
                                color: theme.surfaceAlt

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    height: parent.height + 1
                                    color: theme.border
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: theme.border
                                }
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData
                                    color: theme.text
                                    font.bold: true
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    ListView {
                        width: root.tableWidth
                        height: Math.max(30, root.maxHeight - 28)
                        model: root.table.rows
                        clip: true
                        reuseItems: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Row {
                            id: tableRow
                            required property var modelData

                            Repeater {
                                model: root.table.cols
                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    width: root.colWidths[index]
                                    height: 24
                                    color: "transparent"

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        height: parent.height + 1
                                        color: theme.border
                                    }
                                    Label {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 4
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.cellText(tableRow.modelData[modelData])
                                        color: theme.text
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- JSON ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            CodeView {
                anchors.fill: parent
                anchors.margins: 2
                text: root.jsonText
            }
        }

        // ---- 文本 ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            ScrollView {
                anchors.fill: parent
                anchors.margins: 2
                clip: true
                TextEdit {
                    width: Math.max(200, parent.width - 8)
                    text: root.plainText
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    wrapMode: TextEdit.WrapAnywhere
                    color: theme.text
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }
        }
    }

    // 放大：表格放大成一个大弹窗，JSON 交给我们已有的查看器
    JsonViewerPopup {
        id: viewer
        text: root.activeTab === "table" ? root.tableAsTsv() : root.jsonText
        title: root.activeTab === "table"
               ? ("表格 — " + root.table.rows.length + " 行 × " + root.table.cols.length + " 列（制表符分隔）")
               : ("JSON")
    }

    Clip { id: clip }
}
