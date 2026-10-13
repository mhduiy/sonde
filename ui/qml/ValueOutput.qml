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
    property int maxHeight: -1      // >0 时固定用这个高度，否则按窗口高度算

    /// 查看区高度：由窗口高度算出来的**固定值**，绝不用内容撑。
    /// 内容一变高度就变，下面的控件被顶来顶去——那才是"闪动"。
    /// 窗口大小不变 → 这个值就不变，页签怎么切、轮询怎么刷都不动。
    ///
    /// 再夹一道 `bottomLimit`（面板底边，调用方传）：不然把底部的监听面板拉高，
    /// 输出框就被挤出可视区，滚动条跟着一起看不见——表现就是"表格不能滚"。
    readonly property int boxHeight: {
        var cap = root.maxHeight > 0
                  ? root.maxHeight
                  : Math.max(180, Math.min(420, Math.round((Window.height || 900) * 0.32)))
        if (root.bottomLimit <= 0)
            return cap
        // 内容区（StackLayout）自己在场景里的位置：它上面是页签栏
        var room = root.bottomLimit - contentBox.mapToItem(null, 0, 0).y - 8
        // 下限只保 3 行左右：再小就没法用，但宁可小也别让滚动条被挤出可视区
        return Math.max(100, Math.min(cap, room))
    }

    /// 面板（右栏）底边在场景里的 y；-1 = 不知道，就按窗口高度算。
    /// 有它才能把高度夹到"面板里还剩多少地方"：不然底部监听面板一拉高，
    /// 输出框连同它的滚动条就被挤出可视区——表现就是"表格不能滚"。
    property real bottomLimit: -1

    /// 页签栏右边那行信息（尺寸 / 行数）。合成一段文本，长度变了也只影响
    /// 它自己的省略号，不会推动旁边的按钮。
    readonly property string infoText: {
        if (root.activeTab === "image")
            return preview.status === Image.Loading ? "加载中…"
                  : (preview.status === Image.Error ? "读不到文件"
                     : (preview.sourceSize.width + " × " + preview.sourceSize.height))
        if (root.activeTab === "table")
            return root.table.rows.length + " 行 × " + root.table.cols.length + " 列"
        if (root.activeTab === "json")
            return bridge.jsonLines(root.jsonText, root.jsonColors()).length + " 行"
        return ""
    }

    spacing: 6

    /// 结构化视图用的 JSON 文本：
    /// - 字符串里装 JSON → 用**格式化后**的（deepin 接口返回的通常是压缩 JSON，
    ///   直接用原文就变成挤成一行，看不出来结构）
    /// - 其它 → 由值节点序列化（已经带缩进）
    readonly property string jsonText:
        root.innerParsed !== null ? JSON.stringify(root.innerParsed, null, 4)
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

    readonly property string defaultTab:
        (typeof forceTab !== "undefined" && forceTab !== "") ? forceTab
        : (root.hasImage ? "image"
                         : (tableable ? "table" : (parsed !== null ? "json" : "text")))
    /// 值是不是一张能显示的图片（file:// URI 或绝对路径 + 图片扩展名）。
    /// 只处理本地文件——远程 URL 不主动去抓（慢且可能失败）。
    function imageSourceOf(v) {
        if (typeof v !== "string" || v === "")
            return ""
        var s = v.trim().replace(/^["']|["']$/g, "")
        if (s.indexOf("file://") !== 0 && s.charAt(0) !== "/")
            return ""
        var lower = s.toLowerCase()
        var exts = [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".svg",
                    ".ico", ".xpm", ".tif", ".tiff", ".avif"]
        var ok = false
        for (var i = 0; i < exts.length; ++i) {
            if (lower.slice(-exts[i].length) === exts[i]) {
                ok = true
                break
            }
        }
        if (!ok)
            return ""
        // Image 只认 URL：裸绝对路径会被当成相对 QML 文件的路径
        if (s.charAt(0) === "/")
            s = "file://" + s
        return s
    }

    readonly property string imageSource: {
        var t = root.rawStringValue
        if (t === "" && root.nodes.length === 1 && root.nodes[0]
                && root.nodes[0].kind === "str")
            t = "" + (root.nodes[0].text || "")
        return root.imageSourceOf(t)
    }

    readonly property bool hasImage: root.imageSource !== ""

    readonly property var tabNames: ["image", "table", "json", "text"]
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
        // 换内容就回到自动识别的页签
        root.tab = ""
    }

    // ------------------------------------------------------------ 页签栏
    // 用 DTK 的按钮做分段选择器。不用 QtQuick.Controls 的 TabBar/TabButton：
    // main.cpp 里 QQuickStyle 设的是 Fusion，那套 TabButton 出来是灰底方块，
    // 跟 DTK 的圆角控件放一起很难看；D.Button 自带 DTK 样式，checked 时
    // 走 ButtonPanel 的高亮底，正好当"选中"用。
    // 四个页签**常驻**，不支持的置灰（DTK 自己会把 disabled 压到 0.4 透明度），
    // 不隐藏——隐藏会让后面所有控件左右横跳。
    //
    // 用 Flow 而不是 RowLayout：面板拖窄时换行，而不是把「复制」裁掉。
    // 这里所有子项的宽度都是**定值**（信息那格定宽 + 省略号），所以换行只跟
    // 面板宽度有关，跟内容无关——数据怎么刷，这一排都不会重排/闪动。
    Flow {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: [
                { key: "image", label: "图片", ok: root.hasImage },
                { key: "table", label: "表格", ok: root.tableable },
                { key: "json", label: "JSON", ok: root.parsed !== null },
                { key: "text", label: "原始值", ok: true }
            ]

            delegate: D.Button {
                required property var modelData
                text: modelData.label
                checkable: true
                enabled: modelData.ok
                implicitWidth: 52
                implicitHeight: 28
                checked: root.activeTab === modelData.key
                onClicked: {
                    root.tab = modelData.key
                    // 点击会就地改掉 checked、弄断绑定，这里重新接上
                    checked = Qt.binding(function () {
                        return root.activeTab === modelData.key
                    })
                }
            }
        }

        Label {
            width: 76
            height: 28
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.infoText
            color: theme.textFaint
            font.pixelSize: 10
        }

        D.ToolButton {
            text: "放大"
            implicitWidth: 46
            implicitHeight: 28
            // 置灰而不是藏起来：藏起来会把"复制"顶到左边，跟着内容闪
            enabled: root.activeTab === "json" || root.activeTab === "table"
            onClicked: viewer.open()
        }
        D.ToolButton {
            text: "复制"
            implicitWidth: 46
            implicitHeight: 28
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
        var lines = [root.table.cols.join("\t")]
        for (var r = 0; r < root.table.rows.length; ++r)
            lines.push(root.rowAsTsv(r))
        return lines.join("\n")
    }

    function rowAsTsv(i) {
        var cols = root.table.cols
        var row = root.table.rows[i]
        if (!row)
            return ""
        var cells = []
        for (var c = 0; c < cols.length; ++c)
            cells.push(root.cellText(row[cols[c]]))
        return cells.join("\t")
    }

    // ------------------------------------------------------------ 内容
    StackLayout {
        id: contentBox
        Layout.fillWidth: true
        // 不设 fillHeight：这是个有界高度的查看区，内部自己滚。
        // 之前设了 fillHeight，在 DetailPane 的 ScrollView 里高度被拉到内容高度，
        // 内层 ScrollView 就没有可滚区间了（表现就是"没有滚动条"）。
        // 高度固定（boxHeight 只跟窗口大小走），内容怎么变都不动
        Layout.preferredHeight: root.boxHeight
        Layout.maximumHeight: root.boxHeight
        currentIndex: root.activeIndex

        // ---- 图片 ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Image {
                    id: preview
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: root.hasImage ? root.imageSource : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        text: preview.status === Image.Error
                              ? ("✗  读不到 " + root.imageSource)
                              : root.imageSource
                        color: preview.status === Image.Error ? theme.error : theme.textFaint
                        font.pixelSize: 10
                    }
                    D.ToolButton {
                        text: "复制路径"
                        implicitWidth: 70
                        implicitHeight: 22
                        onClicked: clip.put(root.imageSource)
                    }
                }
            }
        }

        // ---- 表格 ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            // 横向用 Flickable（只吃横向手势），纵向交给内层 ListView
            Flickable {
                id: tableFlick
                anchors.fill: parent
                anchors.margins: 1
                contentWidth: root.tableWidth
                contentHeight: root.boxHeight
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                // AlwaysOn，不能用 AsNeeded：DTK 的滚动条在 AsNeeded 下初始是
                // "hide" 态（contentItem.opacity = 0），要等 active 变 true 才显形，
                // 而鼠标又摸不到一条看不见的条 → 表现就是"表格不能滚"
                D.ScrollBar.horizontal: D.ScrollBar { policy: D.ScrollBar.AlwaysOn }

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
                        id: tableList
                        width: root.tableWidth
                        height: Math.max(30, root.boxHeight - 28)
                        model: root.table.rows
                        clip: true
                        reuseItems: true

                        delegate: Row {
                            id: tableRow
                            required property int index
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
                                    Row {
                                        id: cellRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        readonly property string img:
                                            root.imageSourceOf(tableRow.modelData[modelData])
                                        readonly property bool showThumb:
                                            img !== "" && root.colWidths[index] >= 80
                                        readonly property string value:
                                            root.cellText(tableRow.modelData[modelData])

                                        // 缩略图：务必限制 sourceSize，
                                        // 否则每行都按原始分辨率解码（壁纸动辄几千万像素）
                                        Image {
                                            width: cellRow.showThumb ? 30 : 0
                                            height: 20
                                            y: (cellRow.height - height) / 2
                                            visible: cellRow.showThumb
                                            source: cellRow.showThumb ? cellRow.img : ""
                                            sourceSize.width: 30
                                            sourceSize.height: 20
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                        }

                                        // 用 TextEdit 而不是 Label：Label 是纯展示，
                                        // 永远选不了、复制不了。这里只读 + 可划词选中，
                                        // Ctrl+C 直接复制选中的部分。
                                        TextEdit {
                                            id: cellText
                                            width: Math.max(0, cellRow.width - x
                                                               - (cellRow.showThumb ? 36 : 0))
                                            height: cellRow.height
                                            verticalAlignment: TextEdit.AlignVCenter
                                            text: cellRow.value
                                            color: theme.text
                                            font.family: "monospace"
                                            font.pixelSize: 11
                                            readOnly: true
                                            selectByMouse: true
                                            persistentSelection: true
                                            wrapMode: TextEdit.NoWrap
                                            clip: true

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.RightButton
                                                onClicked: function (mouse) {
                                                    cellMenu.cellValue =
                                                        cellText.selectedText !== ""
                                                        ? cellText.selectedText : cellRow.value
                                                    cellMenu.rowValue = root.rowAsTsv(tableRow.index)
                                                    cellMenu.popup(mouse.x, mouse.y)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 纵向滚动条挂在 Flickable **外面**：ListView 在横向 Flickable 的内容里，
            // 它自己的滚动条会被摆到内容右端（x = contentWidth 处）→ 视口外，鼠标够不着
            D.ScrollBar {
                id: tableVBar
                orientation: Qt.Vertical
                policy: D.ScrollBar.AlwaysOn
                active: true
                anchors.right: parent.right
                anchors.rightMargin: 2
                y: tableFlick.y + tableList.y
                height: tableList.height
                size: Math.min(1, tableList.height / Math.max(1, tableList.contentHeight))
                position: tableList.contentY / Math.max(1, tableList.contentHeight)
                onPositionChanged: tableList.contentY = position * tableList.contentHeight
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

        // ---- 原始值 ----
        Rectangle {
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            D.ScrollView {
                id: rawScroll
                anchors.fill: parent
                anchors.margins: 2
                clip: true
                // 跟表格那边一个道理：DTK 的滚动条在 AsNeeded 下静止时是全透明的，
                // 长文本看不出能滚。换了实例就得自己摆位置（DTK 那套 x/y/height
                // 绑在它内部的实例上）。
                D.ScrollBar.vertical: D.ScrollBar {
                    parent: rawScroll
                    x: rawScroll.mirrored ? 0 : rawScroll.width - width
                    y: rawScroll.topPadding
                    height: rawScroll.availableHeight
                    policy: D.ScrollBar.AlwaysOn
                }
                TextEdit {
                    id: rawText
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

            // 右键菜单：DTK 的，跟别处一致（QtQuick 的 TextEdit 没有自带菜单）
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: function (mouse) {
                    rawMenu.popup(mouse.x, mouse.y)
                }
            }

            D.Menu {
                id: rawMenu

                D.MenuItem {
                    text: "复制选中"
                    enabled: rawText.selectedText !== ""
                    onTriggered: rawText.copy()
                }
                D.MenuItem {
                    text: "全选"
                    onTriggered: rawText.selectAll()
                }
                D.MenuSeparator {}
                D.MenuItem {
                    text: "复制全部"
                    onTriggered: clip.put(root.plainText)
                }
            }
        }
    }

    // 表格单元格的右键菜单（跟别处一样用 DTK 的）
    D.Menu {
        id: cellMenu

        property string cellValue: ""
        property string rowValue: ""

        D.MenuItem {
            text: "复制这个单元格"
            onTriggered: clip.put(cellMenu.cellValue)
        }
        D.MenuItem {
            text: "复制这一行（制表符分隔）"
            onTriggered: clip.put(cellMenu.rowValue)
        }
        D.MenuSeparator {}
        D.MenuItem {
            text: "复制整表（制表符分隔）"
            onTriggered: clip.put(root.tableAsTsv())
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
