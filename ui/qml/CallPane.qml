import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 签名驱动的参数编辑器 + 方法调用。
//
// 关键点：参数表单完全由 D-Bus 签名生成（Rust 的 type_tree），
// 用户不用手写 GVariant 文本，只要填值、按 +/- 增删元素。
// 值树在 JS 里递归拍平成行，界面用非递归列表渲染。
Item {
    id: root

    property string bus: "session"
    property color fg: "#d7dde4"
    property color dim: "#7b8794"
    property color accent: "#4aa8ff"
    property color line: "#242c35"
    readonly property color strColor: "#9ece6a"
    readonly property color numColor: "#e0af68"
    readonly property color boolColor: "#bb9af7"
    readonly property color errColor: "#e06c75"

    property var nodes: []
    property var rows: []
    property var resultRows: []
    property var result: null
    property bool busy: false
    property double lastCallId: 0

    function clone(x) { return JSON.parse(JSON.stringify(x)) }

    function loadFrom(d, p, i, m, sig) {
        destField.text = d
        pathField.text = p
        ifaceField.text = i
        memberField.text = m
        sigField.text = sig
        // 必须 JSON 往返：`property var` 持有 QVariantList 时元素是临时副本，
        // 直接改 nodes[0].text 写不回去。
        root.nodes = clone(bridge.typeTree(sig))
        root.result = null
        root.resultRows = []
        rebuild()
    }

    function isComposite(kind) {
        return kind === "array" || kind === "dict" || kind === "struct" || kind === "variant"
    }

    function rebuild() {
        var out = []
        for (var i = 0; i < root.nodes.length; ++i)
            walk(root.nodes[i], 0, "[" + i + "]", null, -1, out)
        root.rows = out
    }

    function walk(node, depth, label, parent, index, out) {
        if (!node)
            return
        var kind = node.kind || ""
        out.push({
            depth: depth, label: label, node: node, kind: kind,
            composite: isComposite(kind),
            parent: parent, index: index,
            removable: parent !== null && (parent.kind || "") !== "struct"
        })
        var items = node.items || []
        for (var i = 0; i < items.length; ++i) {
            var e = items[i]
            if (e.key !== undefined && e.val !== undefined) {
                out.push({
                    depth: depth + 1, label: "key", node: e.key,
                    kind: e.key.kind || "", composite: false,
                    parent: node, index: i, removable: true
                })
                walk(e.val, depth + 1, "val", node, i, out)
            } else if (e.node !== undefined) {
                var lbl = kind === "array"
                          ? ("[" + i + "]")
                          : (e.label !== undefined ? e.label : ("·" + i))
                walk(e.node, depth + 1, lbl, node, i, out)
            }
        }
    }

    function summaryOf(node) {
        var k = node.kind || ""
        var n = (node.items || []).length
        if (k === "array") return "[" + n + "]"
        if (k === "dict") return "{" + n + "}"
        if (k === "struct") return "(" + n + ")"
        if (k === "variant") {
            var inner = (node.items && node.items[0] && node.items[0].node) ? node.items[0].node.kind : ""
            return "<" + inner + ">"
        }
        return node.text !== undefined ? ("" + node.text) : ""
    }

    function addChild(node) {
        if (node.kind === "array") {
            node.items = (node.items || []).concat([clone(node.elemTemplate)])
        } else if (node.kind === "dict") {
            node.items = (node.items || []).concat([{
                label: "", key: clone(node.keyTemplate), val: clone(node.valTemplate)
            }])
        }
        rebuild()
    }

    function removeChild(row) {
        if (row.parent && row.parent.items && row.index >= 0) {
            row.parent.items.splice(row.index, 1)
            rebuild()
        }
    }

    function applyVariant(node) {
        var sig = (node.text || "s").trim()
        var t = clone(bridge.typeTree(sig))
        if (t && t.length > 0)
            node.items = [{ label: "value", node: t[0] }]
        rebuild()
    }

    function doCall() {
        root.busy = true
        root.result = null
        root.resultRows = []
        root.lastCallId = bridge.call(root.bus, destField.text, pathField.text,
                                      ifaceField.text, memberField.text,
                                      sigField.text, root.nodes)
    }

    function colorFor(kind, composite) {
        if (composite) return root.accent
        if (kind === "str" || kind === "path" || kind === "sig") return root.strColor
        if (kind === "bool") return root.boolColor
        return root.numColor
    }

    Connections {
        target: bridge
        function onCallFinished(id, res) {
            if (id !== root.lastCallId)
                return
            root.busy = false
            root.result = res
            root.resultRows = res.ok && res.args ? bridge.flattenNodes(res.args) : []
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Component.onCompleted: {
            // 开箱给一个能跑通的例子，省得对着空表单发呆
            if (root.nodes.length === 0 && destField.text === "") {
                root.loadFrom("org.freedesktop.DBus", "/org/freedesktop/DBus",
                              "org.freedesktop.DBus", "GetNameOwner", "s")
                if (root.nodes.length === 1)
                    root.nodes[0].text = "org.freedesktop.DBus"
                root.rebuild()
            }
            if (typeof demoCall !== "undefined" && demoCall)
                Qt.callLater(root.doCall)
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 6
            columnSpacing: 6
            rowSpacing: 6

            Label { text: "目标"; color: root.dim }
            TextField {
                id: destField
                Layout.fillWidth: true
                Layout.columnSpan: 5
                placeholderText: "org.freedesktop.DBus"
                font.family: "monospace"
            }

            Label { text: "路径"; color: root.dim }
            TextField {
                id: pathField
                Layout.fillWidth: true
                Layout.columnSpan: 3
                text: "/"
                font.family: "monospace"
            }
            Label { text: "方法"; color: root.dim }
            TextField {
                id: memberField
                Layout.fillWidth: true
                placeholderText: "ListNames"
                font.family: "monospace"
            }

            Label { text: "接口"; color: root.dim }
            TextField {
                id: ifaceField
                Layout.fillWidth: true
                Layout.columnSpan: 3
                placeholderText: "org.freedesktop.DBus"
                font.family: "monospace"
            }
            Label { text: "签名"; color: root.dim }
            TextField {
                id: sigField
                Layout.fillWidth: true
                font.family: "monospace"
                onEditingFinished: {
                    root.nodes = clone(bridge.typeTree(text))
                    rebuild()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: root.line }

        Label {
            text: "参数（由签名生成，直接填值；数组/字典用 ＋ 增删）"
            color: root.dim
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            visible: root.rows.length === 0
            text: "该签名没有参数。填好目标/路径/接口/方法后直接发送。"
            color: root.dim
            font.pixelSize: 12
        }

        // 参数编辑区
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, Math.max(60, root.rows.length * 34 + 12))
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 3

                Repeater {
                    model: root.rows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        Item {
                            Layout.preferredWidth: modelData.depth * 16
                            Layout.fillHeight: true
                        }
                        Label {
                            Layout.preferredWidth: 92
                            text: modelData.label
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        TextField {
                            Layout.fillWidth: true
                            visible: !modelData.composite && !(modelData.node.kind === "variant")
                            text: modelData.node.text !== undefined ? ("" + modelData.node.text) : ""
                            placeholderText: modelData.kind
                            font.family: "monospace"
                            onTextEdited: modelData.node.text = text
                        }

                        // 变体：允许改内层类型
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: modelData.node.kind === "variant"
                            TextField {
                                Layout.preferredWidth: 70
                                text: modelData.node.text || "s"
                                placeholderText: "内层签名"
                                font.family: "monospace"
                                onEditingFinished: modelData.node.text = text
                            }
                            Button {
                                text: "应用"
                                onClicked: {
                                    modelData.node.text = modelData.node.text || "s"
                                    root.applyVariant(modelData.node)
                                }
                            }
                        }

                        Label {
                            visible: modelData.composite
                            Layout.preferredWidth: 150
                            text: modelData.composite ? root.summaryOf(modelData.node) : ""
                            color: root.accent
                            font.family: "monospace"
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.preferredWidth: 40
                            text: modelData.kind
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 10
                            opacity: 0.75
                        }

                        Button {
                            visible: modelData.node.kind === "array" || modelData.node.kind === "dict"
                            text: "＋"
                            implicitWidth: 32
                            onClicked: root.addChild(modelData.node)
                        }
                        Button {
                            visible: modelData.removable
                            text: "－"
                            implicitWidth: 32
                            onClicked: root.removeChild(modelData)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "发送调用"
                enabled: !root.busy && destField.text !== "" && memberField.text !== ""
                onClicked: root.doCall()
            }
            Label {
                visible: root.busy
                text: "调用中…"
                color: root.dim
            }
            Label {
                Layout.fillWidth: true
                visible: root.result !== null && !root.result.ok
                wrapMode: Text.WordWrap
                text: root.result ? ("✗ " + root.result.error) : ""
                color: root.errColor
                font.family: "monospace"
                font.pixelSize: 12
            }
            Label {
                visible: root.result !== null && root.result.ok
                text: root.result ? ("✓ 返回签名: " + (root.result.signature || "")) : ""
                color: root.strColor
                font.family: "monospace"
                font.pixelSize: 12
            }
        }

        // 返回结果
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 3

                Repeater {
                    model: root.resultRows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            Layout.preferredWidth: modelData.depth * 16
                            Layout.fillHeight: true
                        }
                        Label {
                            Layout.preferredWidth: 110
                            text: modelData.label
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.display
                            color: root.colorFor(modelData.kind, modelData.composite)
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }
}
