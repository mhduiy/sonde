import QtQuick

/// 不可见的剪贴板搬运工。用法：`clip.put("要复制的文本")`
TextEdit {
    id: root
    visible: false
    width: 0
    height: 0

    function put(s) {
        text = s
        selectAll()
        copy()
        deselect()
    }
}
