.pragma library

// 树节点类型的显示与配色，供各面板共用。

function label(kind) {
    switch (kind) {
    case "path": return "路径"
    case "interface": return "接口"
    case "method": return "方法"
    case "signal": return "信号"
    case "property": return "属性"
    case "arg": return "参数"
    case "service": return "服务"
    default: return kind
    }
}

function shortLabel(kind) {
    switch (kind) {
    case "path": return "PATH"
    case "interface": return "IFACE"
    case "method": return "METHOD"
    case "signal": return "SIGNAL"
    case "property": return "PROP"
    case "arg": return "ARG"
    case "service": return "SVC"
    default: return kind
    }
}

function colorFor(theme, kind) {
    switch (kind) {
    case "method": return theme.chipCall
    case "signal": return theme.chipSignal
    case "property": return theme.valNum
    case "interface": return theme.accent
    case "arg": return theme.valBool
    case "path": return theme.textDim
    default: return theme.textDim
    }
}

function msgLabel(type) {
    switch (type) {
    case "method_call": return "CALL"
    case "method_return": return "RET"
    case "signal": return "SIGNAL"
    case "error": return "ERROR"
    default: return type
    }
}

function msgColor(theme, type) {
    switch (type) {
    case "method_call": return theme.chipCall
    case "method_return": return theme.chipRet
    case "signal": return theme.chipSignal
    case "error": return theme.chipError
    default: return theme.textDim
    }
}

function valueColor(theme, kind, composite) {
    if (composite)
        return theme.accent
    switch (kind) {
    case "str":
    case "path":
    case "sig": return theme.valStr
    case "bool": return theme.valBool
    case "fd": return theme.valFd
    default: return theme.valNum
    }
}

function clockOf(us) {
    if (!us)
        return ""
    var d = new Date(us / 1000)
    function p(n) { return (n < 10 ? "0" : "") + n }
    return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
}
