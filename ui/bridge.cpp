#include "bridge.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QXmlStreamReader>

namespace {

/// 接住 Rust 交出来的字符串所有权，读完立刻归还，避免泄漏。
QString takeRust(char *p)
{
    if (!p)
        return QString();
    const QString s = QString::fromUtf8(p);
    sonde_string_free(p);
    return s;
}

QByteArray utf8(const QString &s)
{
    return s.toUtf8();
}

QVariantMap strNode(const QString &s)
{
    return QVariantMap{ { QStringLiteral("sig"), QStringLiteral("s") },
                        { QStringLiteral("kind"), QStringLiteral("str") },
                        { QStringLiteral("text"), s },
                        { QStringLiteral("items"), QVariantList{} } };
}

/// 解析内省 XML（树形解析）。
QVariantMap parseIntrospection(const QString &xml)
{
    QVariantList interfaces;
    QVariantList childNodes;

    QString ifaceName;
    QVariantList methods;
    QVariantList sigList; // 不能叫 signals —— 那是 Qt 的宏
    QVariantList props;
    QVariantMap curMember;
    QVariantList curArgs;

    auto flushMember = [&]() {
        if (curMember.isEmpty())
            return;
        QString inSig;
        QString outSig;
        for (const QVariant &av : curArgs) {
            const QVariantMap am = av.toMap();
            if (am.value(QStringLiteral("direction")).toString() == QLatin1String("out"))
                outSig += am.value(QStringLiteral("type")).toString();
            else
                inSig += am.value(QStringLiteral("type")).toString();
        }
        curMember[QStringLiteral("args")] = curArgs;
        curMember[QStringLiteral("inSig")] = inSig;
        curMember[QStringLiteral("outSig")] = outSig;
        if (curMember.value(QStringLiteral("kind")).toString() == QLatin1String("method"))
            methods.append(curMember);
        else
            sigList.append(curMember);
        curMember.clear();
        curArgs.clear();
    };

    QXmlStreamReader r(xml);
    // depth：-1 表示还没进入任何元素；0 是根 <node>。
    // 只认根节点的直接子元素，避免把嵌套 subtree 拍平。
    int depth = -1;
    while (!r.atEnd()) {
        r.readNext();

        if (r.isEndElement()) {
            const QString en = r.name().toString();
            --depth;
            if (en == QLatin1String("method") || en == QLatin1String("signal"))
                flushMember();
            else if (en == QLatin1String("interface")) {
                interfaces.append(QVariantMap{
                    { QStringLiteral("kind"), QStringLiteral("interface") },
                    { QStringLiteral("name"), ifaceName },
                    { QStringLiteral("methods"), methods },
                    { QStringLiteral("signals"), sigList },
                    { QStringLiteral("properties"), props },
                });
                ifaceName.clear();
                methods.clear();
                sigList.clear();
                props.clear();
            }
            continue;
        }
        if (!r.isStartElement())
            continue;

        ++depth;
        if (depth == 0)
            continue; // 根 <node> 自身

        const QString n = r.name().toString();
        if (depth == 1) {
            if (n == QLatin1String("node")) {
                // 注意：有些实现（例如 UOS 的 dbus-daemon）会在这里给出
                // 完整相对路径 "org/freedesktop/DBus" 而不是单段名，
                // 由 ObjectTree 负责拆成中间层级。
                const QString nm = r.attributes().value(QStringLiteral("name")).toString();
                if (!nm.isEmpty())
                    childNodes.append(QVariantMap{
                        { QStringLiteral("kind"), QStringLiteral("node") },
                        { QStringLiteral("name"), nm } });
            } else if (n == QLatin1String("interface")) {
                ifaceName = r.attributes().value(QStringLiteral("name")).toString();
            }
        } else if (depth == 2) {
            if (n == QLatin1String("method")) {
                curMember = QVariantMap{
                    { QStringLiteral("kind"), QStringLiteral("method") },
                    { QStringLiteral("name"),
                      r.attributes().value(QStringLiteral("name")).toString() } };
            } else if (n == QLatin1String("signal")) {
                curMember = QVariantMap{
                    { QStringLiteral("kind"), QStringLiteral("signal") },
                    { QStringLiteral("name"),
                      r.attributes().value(QStringLiteral("name")).toString() } };
            } else if (n == QLatin1String("property")) {
                props.append(QVariantMap{
                    { QStringLiteral("kind"), QStringLiteral("property") },
                    { QStringLiteral("name"),
                      r.attributes().value(QStringLiteral("name")).toString() },
                    { QStringLiteral("type"),
                      r.attributes().value(QStringLiteral("type")).toString() },
                    { QStringLiteral("access"),
                      r.attributes().value(QStringLiteral("access")).toString() },
                });
            }
        } else if (depth == 3 && n == QLatin1String("arg")) {
            curArgs.append(QVariantMap{
                { QStringLiteral("name"),
                  r.attributes().value(QStringLiteral("name")).toString() },
                { QStringLiteral("type"),
                  r.attributes().value(QStringLiteral("type")).toString() },
                { QStringLiteral("direction"),
                  r.attributes().value(QStringLiteral("direction")).toString() },
            });
        }
    }

    QVariantList items = interfaces;
    items += childNodes;

    QVariantMap out;
    out[QStringLiteral("ok")] = !items.isEmpty();
    out[QStringLiteral("items")] = items;
    if (items.isEmpty() && r.hasError())
        out[QStringLiteral("error")] = r.errorString();
    return out;
}

/// 递归展开一个节点，产出 (depth, label, display) 三元组的扁平行。
void flattenOne(const QVariantMap &node, int depth, const QString &label, QVariantList &out)
{
    const QString kind = node.value(QStringLiteral("kind")).toString();
    const QVariantList items = node.value(QStringLiteral("items")).toList();
    const bool composite = kind == QLatin1String("array") || kind == QLatin1String("dict")
                           || kind == QLatin1String("struct") || kind == QLatin1String("variant");

    QString display;
    if (kind == QLatin1String("array")) {
        display = QStringLiteral("[%1]").arg(items.size());
    } else if (kind == QLatin1String("dict")) {
        display = QStringLiteral("{%1}").arg(items.size());
    } else if (kind == QLatin1String("struct")) {
        display = QStringLiteral("(%1)").arg(items.size());
    } else if (kind == QLatin1String("variant")) {
        const QString inner = items.isEmpty()
            ? QString()
            : items.first().toMap().value(QStringLiteral("node")).toMap()
                  .value(QStringLiteral("kind")).toString();
        display = QStringLiteral("<%1>").arg(inner);
    } else {
        display = node.value(QStringLiteral("text")).toString();
    }

    // 字符串里如果装了 JSON（deepin 的很多接口就爱这么干，例如
    // Appearance1.List("icon") 返回一串图标主题 JSON），就认出来并预生成缩进版本，
    // 界面可以一键格式化查看 / 复制。
    bool isJson = false;
    QString jsonPretty;
    if (kind == QLatin1String("str")) {
        const QString t = display.trimmed();
        if (t.size() > 1
            && ((t.startsWith(QLatin1Char('{')) && t.endsWith(QLatin1Char('}')))
                || (t.startsWith(QLatin1Char('[')) && t.endsWith(QLatin1Char(']'))))) {
            QJsonParseError perr;
            const QJsonDocument doc = QJsonDocument::fromJson(t.toUtf8(), &perr);
            if (perr.error == QJsonParseError::NoError) {
                isJson = true;
                jsonPretty = QString::fromUtf8(doc.toJson(QJsonDocument::Indented)).trimmed();
            }
        }
    }

    out.append(QVariantMap{
        { QStringLiteral("depth"), depth },
        { QStringLiteral("label"), label },
        { QStringLiteral("kind"), kind },
        { QStringLiteral("sig"), node.value(QStringLiteral("sig")).toString() },
        { QStringLiteral("display"), display },
        { QStringLiteral("composite"), composite },
        { QStringLiteral("json"), isJson },
        { QStringLiteral("jsonPretty"), jsonPretty },
    });

    for (const QVariant &v : items) {
        const QVariantMap e = v.toMap();
        QString childLabel = e.value(QStringLiteral("label")).toString();
        QVariantMap child = e.value(QStringLiteral("node")).toMap();
        if (child.isEmpty() && e.contains(QStringLiteral("val"))) {
            child = e.value(QStringLiteral("val")).toMap();
            childLabel += QStringLiteral(" →");
        }
        flattenOne(child, depth + 1, childLabel, out);
    }
}

/// 变体剥一层：值节点是 variant 时取内层，摘要里就不用显示多余的 <>
QVariantMap unwrapVariant(const QVariantMap &n)
{
    if (n.value(QStringLiteral("kind")).toString() != QLatin1String("variant"))
        return n;
    const QVariantList items = n.value(QStringLiteral("items")).toList();
    if (items.isEmpty())
        return n;
    return items.first().toMap().value(QStringLiteral("node")).toMap();
}

/// PropertiesChanged 的第二个参数是 a{sv}，看里面有没有这个属性名
bool changedPropsContain(const QVariantMap &m, const QString &prop)
{
    const QVariantList args = m.value(QStringLiteral("args")).toList();
    if (args.size() < 2)
        return false;
    const QVariantMap dict = args.at(1).toMap();
    const QVariantList items = dict.value(QStringLiteral("items")).toList();
    for (const QVariant &iv : items) {
        if (iv.toMap().value(QStringLiteral("key")).toMap()
                .value(QStringLiteral("text")).toString() == prop)
            return true;
    }
    return false;
}

/// 调用上下文：把「哪个 Bridge + 哪次调用」带过 FFI 边界，回调里再 free。
struct CallCtx {
    Bridge *bridge;
    quint64 id;
};

// ---- 值节点 → 真正的 JSON ----

bool isNumericKind(const QString &k)
{
    return k == QLatin1String("u8") || k == QLatin1String("i16") || k == QLatin1String("u16")
           || k == QLatin1String("i32") || k == QLatin1String("u32") || k == QLatin1String("i64")
           || k == QLatin1String("u64") || k == QLatin1String("f64");
}

void escapeJson(const QString &s, QString &out)
{
    out += QLatin1Char('"');
    for (const QChar c : s) {
        switch (c.unicode()) {
        case u'"': out += QLatin1String("\\\""); break;
        case u'\\': out += QLatin1String("\\\\"); break;
        case u'\n': out += QLatin1String("\\n"); break;
        case u'\r': out += QLatin1String("\\r"); break;
        case u'\t': out += QLatin1String("\\t"); break;
        default:
            if (c.unicode() < 0x20)
                out += QStringLiteral("\\u%1").arg(c.unicode(), 4, 16, QLatin1Char('0'));
            else
                out += c;
        }
    }
    out += QLatin1Char('"');
}

void jsonInto(const QVariantMap &node, int indent, QString &out);

void jsonPad(int indent, QString &out)
{
    out += QString(indent * 2, QLatin1Char(' '));
}

void jsonInto(const QVariantMap &node, int indent, QString &out)
{
    const QString kind = node.value(QStringLiteral("kind")).toString();
    const QString text = node.value(QStringLiteral("text")).toString();
    const QVariantList items = node.value(QStringLiteral("items")).toList();

    if (kind == QLatin1String("bool")) {
        out += (text == QLatin1String("true") || text == QLatin1String("1"))
                   ? QLatin1String("true") : QLatin1String("false");
        return;
    }
    if (kind == QLatin1String("str") || kind == QLatin1String("path")
        || kind == QLatin1String("sig")) {
        escapeJson(text, out);
        return;
    }
    if (kind == QLatin1String("fd") || isNumericKind(kind)) {
        out += text.trimmed().isEmpty() ? QStringLiteral("0") : text.trimmed();
        return;
    }
    if (kind == QLatin1String("array") || kind == QLatin1String("struct")) {
        if (items.isEmpty()) {
            out += QLatin1String("[]");
            return;
        }
        out += QLatin1String("[\n");
        for (int i = 0; i < items.size(); ++i) {
            jsonPad(indent + 1, out);
            jsonInto(items.at(i).toMap().value(QStringLiteral("node")).toMap(), indent + 1, out);
            out += (i + 1 < items.size()) ? QLatin1String(",\n") : QLatin1String("\n");
        }
        jsonPad(indent, out);
        out += QLatin1Char(']');
        return;
    }
    if (kind == QLatin1String("dict")) {
        if (items.isEmpty()) {
            out += QLatin1String("{}");
            return;
        }
        out += QLatin1String("{\n");
        for (int i = 0; i < items.size(); ++i) {
            const QVariantMap e = items.at(i).toMap();
            jsonPad(indent + 1, out);
            escapeJson(e.value(QStringLiteral("key")).toMap()
                           .value(QStringLiteral("text")).toString(), out);
            out += QLatin1String(": ");
            jsonInto(e.value(QStringLiteral("val")).toMap(), indent + 1, out);
            out += (i + 1 < items.size()) ? QLatin1String(",\n") : QLatin1String("\n");
        }
        jsonPad(indent, out);
        out += QLatin1Char('}');
        return;
    }
    if (kind == QLatin1String("variant")) {
        if (items.isEmpty()) {
            out += QLatin1String("null");
            return;
        }
        jsonInto(items.first().toMap().value(QStringLiteral("node")).toMap(), indent, out);
        return;
    }
    escapeJson(text, out);
}

} // namespace

// --------------------------------------------------------------- Rust → GUI 投递

extern "C" void sondeMonitorTrampoline(void *ctx, const char *json, unsigned int count)
{
    Q_UNUSED(count);
    auto *b = static_cast<Bridge *>(ctx);
    if (!b || !json)
        return;
    // 跑在 Rust 监控线程上，绝不直接碰 QObject，一律排队投递到 GUI 线程。
    const QByteArray payload(json);
    QMetaObject::invokeMethod(b, "handleBatch", Qt::QueuedConnection, Q_ARG(QByteArray, payload));
}

extern "C" void sondeReplyTrampoline(void *ctx, const char *json)
{
    auto *c = static_cast<CallCtx *>(ctx);
    if (!c)
        return;
    Bridge *b = c->bridge;
    const quint64 id = c->id;
    const QByteArray payload(json ? json : "");
    delete c;

    if (!b)
        return;
    QMetaObject::invokeMethod(
        b, [b, id, payload] { b->finishCall(id, payload); }, Qt::QueuedConnection);
}

// ---------------------------------------------------------------------- Bridge

Bridge::Bridge(QObject *parent)
    : QObject(parent)
{
    m_filter.setSourceModel(&m_model);
    // 让过滤器能把"服务名"解析成唯一名（信号 sender 是 :1.x）
    m_filter.setNameResolver([this](const QString &n) { return nameOwner(m_bus, n); });
    m_core = sonde_core_new();
}

Bridge::~Bridge()
{
    if (m_core) {
        sonde_monitor_stop(m_core);
        sonde_core_free(m_core);
    }
}

QString Bridge::version() const
{
    return takeRust(sonde_version());
}

void Bridge::startMonitor(const QString &bus)
{
    if (!m_core)
        return;

    if (m_monitoring) {
        sonde_monitor_stop(m_core);
        m_monitoring = false;
    }

    m_paused = false;
    m_pending.clear();
    emit pausedChanged();
    emit pendingChanged();

    const QByteArray b = utf8(bus);
    if (sonde_monitor_start(m_core, b.constData(), &sondeMonitorTrampoline, this) != 0) {
        emit notice(QStringLiteral("error"), QStringLiteral("启动监听线程失败"));
        return;
    }
    m_bus = bus;
    m_monitoring = true;
    emit monitoringChanged();
}

void Bridge::stopMonitor()
{
    if (!m_core || !m_monitoring)
        return;
    sonde_monitor_stop(m_core);
    m_monitoring = false;
    emit monitoringChanged();
}

void Bridge::clear()
{
    m_model.clear();
    m_pending.clear();
    m_total = 0;
    emit pendingChanged();
    emit totalChanged();
}

void Bridge::setPaused(bool p)
{
    if (m_paused == p)
        return;
    m_paused = p;
    if (!m_paused)
        flushPending();
    emit pausedChanged();
}

void Bridge::flushPending()
{
    if (m_pending.isEmpty())
        return;
    const QList<QVariantMap> batch = m_pending;
    m_pending.clear();
    m_model.appendBatch(batch);
    emit pendingChanged();
}

void Bridge::handleBatch(const QByteArray &payload)
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isArray())
        return;

    QList<QVariantMap> msgs;
    const QJsonArray arr = doc.array();
    msgs.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        QVariantMap m = v.toObject().toVariantMap();
        // 系统提示（权限不足等）单独走 signal，不进消息流
        if (m.value(QStringLiteral("type")).toString() == QLatin1String("notice")) {
            emit notice(m.value(QStringLiteral("level")).toString(),
                        m.value(QStringLiteral("member")).toString());
            continue;
        }
        ++m_total;
        // 摘要在这里算一次：既给界面显示，也进搜索串（可按属性名过滤）
        m.insert(QStringLiteral("summary"), summarizeMessage(m));
        msgs.append(m);
    }
    emit totalChanged();
    if (msgs.isEmpty())
        return;

    if (m_paused) {
        m_pending += msgs;
        constexpr int kCap = 20000; // 暂停期间的缓冲上限，超出丢最旧的
        while (m_pending.size() > kCap)
            m_pending.removeFirst();
        emit pendingChanged();
        return;
    }
    m_model.appendBatch(msgs);
}

// ------------------------------------------------------------------- 调用

quint64 Bridge::dispatchCall(const QString &bus, const QString &dest, const QString &path,
                             const QString &iface, const QString &member, const QString &sig,
                             const QVariantList &args, int kind)
{
    if (!m_core)
        return 0;

    const QByteArray b = utf8(bus);
    const QByteArray d = utf8(dest);
    const QByteArray p = utf8(path);
    const QByteArray i = utf8(iface);
    const QByteArray m = utf8(member);
    const QByteArray s = utf8(sig);
    const QByteArray a = QJsonDocument::fromVariant(args).toJson(QJsonDocument::Compact);

    const quint64 id = m_nextCallId++;
    m_callKind.insert(id, kind);

    if (qEnvironmentVariableIsSet("SONDE_DEBUG_CALL")) {
        qWarning().noquote() << "[sonde] call" << iface + QLatin1Char('.') + member
                             << "sig=" << (sig.isEmpty() ? QStringLiteral("(空)") : sig)
                             << "args=" << QString::fromUtf8(a);
    }

    auto *ctx = new CallCtx{ this, id };
    sonde_call(m_core, b.constData(), d.constData(), p.constData(), i.constData(),
               m.constData(), s.constData(), a.constData(), &sondeReplyTrampoline, ctx);
    return id;
}

quint64 Bridge::call(const QString &bus, const QString &dest, const QString &path,
                     const QString &iface, const QString &member, const QString &sig,
                     const QVariantList &args)
{
    return dispatchCall(bus, dest, path, iface, member, sig, args, 0);
}

quint64 Bridge::callGetProperty(const QString &bus, const QString &dest, const QString &path,
                                const QString &iface, const QString &prop)
{
    const quint64 id = dispatchCall(bus, dest, path,
                                    QStringLiteral("org.freedesktop.DBus.Properties"),
                                    QStringLiteral("Get"), QStringLiteral("ss"),
                                    QVariantList{ strNode(iface), strNode(prop) }, 1);
    m_callMeta.insert(id, QStringList{ iface, prop });
    return id;
}

quint64 Bridge::callGetAllProperties(const QString &bus, const QString &dest,
                                     const QString &path, const QString &iface)
{
    return dispatchCall(bus, dest, path,
                        QStringLiteral("org.freedesktop.DBus.Properties"),
                        QStringLiteral("GetAll"), QStringLiteral("s"),
                        QVariantList{ strNode(iface) }, 2);
}

QVariantMap Bridge::makeVariantArg(const QString &typeSig, const QString &valueText) const
{
    // 用签名生成类型树，填上用户输入，再包一层变体 —— Properties.Set 的第三个参数是 v
    const QVariantList tys = const_cast<Bridge *>(this)->typeTree(typeSig);
    QVariantMap inner;
    if (tys.isEmpty()) {
        inner = QVariantMap{ { QStringLiteral("sig"), QStringLiteral("s") },
                             { QStringLiteral("kind"), QStringLiteral("str") },
                             { QStringLiteral("text"), valueText },
                             { QStringLiteral("items"), QVariantList{} } };
    } else {
        inner = tys.first().toMap();
        inner[QStringLiteral("text")] = valueText;
    }
    return QVariantMap{
        { QStringLiteral("sig"), QStringLiteral("v") },
        { QStringLiteral("kind"), QStringLiteral("variant") },
        { QStringLiteral("text"), typeSig.isEmpty() ? QStringLiteral("s") : typeSig },
        { QStringLiteral("items"),
          QVariantList{ QVariantMap{ { QStringLiteral("label"), QStringLiteral("value") },
                                     { QStringLiteral("node"), inner } } } },
    };
}

quint64 Bridge::callSetProperty(const QString &bus, const QString &dest, const QString &path,
                                const QString &iface, const QString &prop,
                                const QString &typeSig, const QString &valueText)
{
    const quint64 id = dispatchCall(bus, dest, path,
                                    QStringLiteral("org.freedesktop.DBus.Properties"),
                                    QStringLiteral("Set"), QStringLiteral("ssv"),
                                    QVariantList{ strNode(iface), strNode(prop),
                                                  makeVariantArg(typeSig, valueText) },
                                    3);
    m_callMeta.insert(id, QStringList{ iface, prop });
    return id;
}

void Bridge::finishCall(quint64 id, const QByteArray &payload)
{
    const int kind = m_callKind.take(id);
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    QVariantMap result;
    if (doc.isObject())
        result = doc.object().toVariantMap();

    if (kind == 0) {
        emit callFinished(id, result);
        return;
    }

    // 属性读取：把结果里的第一个参数取出来；Get 返回变体需要剥一层
    const QStringList meta = m_callMeta.take(id);
    const QString err = result.value(QStringLiteral("ok")).toBool()
                            ? QString()
                            : result.value(QStringLiteral("error")).toString();

    if (kind == 3) {
        emit propertyWritten(id, err.isEmpty(), err);
        return;
    }

    QVariantMap node;
    if (err.isEmpty()) {
        const QVariantList args = result.value(QStringLiteral("args")).toList();
        if (!args.isEmpty()) {
            QVariantMap first = args.first().toMap();
            if (kind == 1 && first.value(QStringLiteral("kind")).toString()
                                 == QLatin1String("variant")) {
                const QVariantList inner = first.value(QStringLiteral("items")).toList();
                if (!inner.isEmpty())
                    first = inner.first().toMap().value(QStringLiteral("node")).toMap();
            }
            node = first;
        }
    }
    emit propertyRead(id, node, meta.value(0), meta.value(1), err);
}

// ------------------------------------------------------------------- 内省/查询

QString Bridge::nameOwner(const QString &bus, const QString &name) const
{
    if (!m_core || name.isEmpty() || name.startsWith(QLatin1Char(':')))
        return QString();
    const QByteArray b = utf8(bus);
    const QByteArray n = utf8(name);
    const QString json = takeRust(sonde_name_owner(m_core, b.constData(), n.constData()));
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    const QString owner = doc.isObject()
                              ? doc.object().value(QStringLiteral("owner")).toString()
                              : QString();
    if (qEnvironmentVariableIsSet("SONDE_DEBUG_CALL"))
        qWarning() << "[sonde] nameOwner" << bus << name << "->" << owner;
    return owner;
}

QStringList Bridge::listNames(const QString &bus)
{
    if (!m_core)
        return {};
    const QByteArray b = utf8(bus);
    const QJsonDocument doc =
        QJsonDocument::fromJson(takeRust(sonde_list_names(m_core, b.constData())).toUtf8());
    QStringList out;
    for (const QJsonValue &v : doc.array())
        out << v.toString();
    return out;
}

QVariantMap Bridge::introspectTree(const QString &bus, const QString &dest, const QString &path)
{
    if (!m_core)
        return { { QStringLiteral("ok"), false },
                 { QStringLiteral("error"), QStringLiteral("核心未初始化") } };

    const QByteArray b = utf8(bus);
    const QByteArray d = utf8(dest);
    const QByteArray p = utf8(path);
    const QString xml = takeRust(sonde_introspect(m_core, b.constData(), d.constData(), p.constData()));

    if (xml.startsWith(QLatin1String("<!--"))) {
        QVariantMap e;
        e[QStringLiteral("ok")] = false;
        e[QStringLiteral("error")] = xml.mid(4, xml.size() - 7).trimmed();
        return e;
    }
    return parseIntrospection(xml);
}

QVariantList Bridge::typeTree(const QString &sig)
{
    if (!m_core)
        return {};
    const QByteArray s = utf8(sig);
    const QJsonDocument doc =
        QJsonDocument::fromJson(takeRust(sonde_type_tree(s.constData())).toUtf8());
    return doc.isArray() ? doc.array().toVariantList() : QVariantList{};
}

QVariantList Bridge::flattenNodes(const QVariantList &nodes) const
{
    QVariantList out;
    for (int i = 0; i < nodes.size(); ++i)
        flattenOne(nodes.at(i).toMap(), 0, QStringLiteral("[%1]").arg(i), out);
    return out;
}

QString Bridge::nodeToText(const QVariantMap &node, int indent) const
{
    const QString kind = node.value(QStringLiteral("kind")).toString();
    const QString text = node.value(QStringLiteral("text")).toString();
    const QVariantList items = node.value(QStringLiteral("items")).toList();

    if (kind == QLatin1String("struct")) {
        QStringList parts;
        for (const QVariant &v : items)
            parts << nodeToText(v.toMap().value(QStringLiteral("node")).toMap(), 0);
        return QStringLiteral("(") + parts.join(QStringLiteral(", ")) + QStringLiteral(")");
    }
    if (kind == QLatin1String("array")) {
        QStringList parts;
        for (const QVariant &v : items)
            parts << nodeToText(v.toMap().value(QStringLiteral("node")).toMap(), 0);
        return QStringLiteral("[") + parts.join(QStringLiteral(", ")) + QStringLiteral("]");
    }
    if (kind == QLatin1String("dict")) {
        QStringList parts;
        for (const QVariant &v : items) {
            const QVariantMap entry = v.toMap();
            parts << nodeToText(entry.value(QStringLiteral("key")).toMap(), 0)
                         + QStringLiteral(": ")
                         + nodeToText(entry.value(QStringLiteral("val")).toMap(), 0);
        }
        return QStringLiteral("{") + parts.join(QStringLiteral(", ")) + QStringLiteral("}");
    }
    if (kind == QLatin1String("variant")) {
        if (items.isEmpty())
            return QStringLiteral("<null>");
        return QStringLiteral("<")
                + nodeToText(items.first().toMap().value(QStringLiteral("node")).toMap(), 0)
                + QStringLiteral(">");
    }
    if (kind == QLatin1String("str") || kind == QLatin1String("path")
        || kind == QLatin1String("sig"))
        return QStringLiteral("\"") + text + QStringLiteral("\"");
    Q_UNUSED(indent);
    return text;
}

QStringList Bridge::jsonLines(const QString &json, const QVariantMap &colors) const
{
    const QString cKey = colors.value(QStringLiteral("key")).toString();
    const QString cStr = colors.value(QStringLiteral("str")).toString();
    const QString cNum = colors.value(QStringLiteral("num")).toString();
    const QString cBool = colors.value(QStringLiteral("bool")).toString();
    const QString cPunct = colors.value(QStringLiteral("punct")).toString();

    auto esc = [](QChar c) -> QString {
        if (c == QLatin1Char('<'))
            return QStringLiteral("&lt;");
        if (c == QLatin1Char('>'))
            return QStringLiteral("&gt;");
        if (c == QLatin1Char('&'))
            return QStringLiteral("&amp;");
        // 空格用不换行空格，否则富文本会把缩进吃掉
        if (c == QLatin1Char(' '))
            return QStringLiteral("&nbsp;");
        return QString(c);
    };
    auto span = [](const QString &color, const QString &body) {
        return QStringLiteral("<span style=\"color:%1\">%2</span>").arg(color, body);
    };
    // 无分配的字面量比较（Qt6 没有了 midRef）
    auto litAt = [&json](int pos, const char *lit) {
        int k = 0;
        while (lit[k] != '\0') {
            if (pos + k >= json.size() || json.at(pos + k) != QLatin1Char(lit[k]))
                return false;
            ++k;
        }
        return true;
    };

    QString out;
    out.reserve(json.size() * 2);
    const int n = json.size();
    int i = 0;
    while (i < n) {
        const QChar c = json.at(i);

        if (c == QLatin1Char('"')) {
            QString lit = QStringLiteral("&quot;");
            int j = i + 1;
            while (j < n) {
                const QChar d = json.at(j);
                if (d == QLatin1Char('\\') && j + 1 < n) {
                    lit += esc(json.at(j + 1));
                    j += 2;
                    continue;
                }
                if (d == QLatin1Char('"')) {
                    lit += QStringLiteral("&quot;");
                    ++j;
                    break;
                }
                lit += esc(d);
                ++j;
            }
            // 后面跳过空白是不是冒号，决定这是 key 还是普通字符串
            int k = j;
            while (k < n && json.at(k).isSpace())
                ++k;
            const bool isKey = (k < n && json.at(k) == QLatin1Char(':'));
            out += span(isKey ? cKey : cStr, lit);
            i = j;
            continue;
        }

        if (c == QLatin1Char('-') || c.isDigit()) {
            int j = i;
            while (j < n) {
                const QChar d = json.at(j);
                if (d.isDigit() || d == QLatin1Char('.') || d == QLatin1Char('-')
                    || d == QLatin1Char('e') || d == QLatin1Char('E') || d == QLatin1Char('+'))
                    ++j;
                else
                    break;
            }
            out += span(cNum, json.mid(i, j - i));
            i = j;
            continue;
        }

        if (litAt(i, "true") || litAt(i, "null")) {
            out += span(cBool, json.mid(i, 4));
            i += 4;
            continue;
        }
        if (litAt(i, "false")) {
            out += span(cBool, json.mid(i, 5));
            i += 5;
            continue;
        }

        if (c == QLatin1Char('\n')) {
            out += QLatin1Char('\n');
            ++i;
            continue;
        }
        out += span(cPunct, esc(c));
        ++i;
    }

    return out.split(QLatin1Char('\n'));
}

QString Bridge::nodeToJson(const QVariantMap &node) const
{
    QString out;
    jsonInto(node, 0, out);
    return out;
}

QString Bridge::nodesToJson(const QVariantList &nodes) const
{
    QString out = QStringLiteral("[\n");
    for (int i = 0; i < nodes.size(); ++i) {
        out += QStringLiteral("  ");
        jsonInto(nodes.at(i).toMap(), 1, out);
        out += (i + 1 < nodes.size()) ? QStringLiteral(",\n") : QStringLiteral("\n");
    }
    out += QLatin1Char(']');
    return out;
}

QString Bridge::summarizeMessage(const QVariantMap &m) const
{
    const QString member = m.value(QStringLiteral("member")).toString();
    const QVariantList args = m.value(QStringLiteral("args")).toList();
    if (args.isEmpty())
        return QString();

    // 属性变化：把"哪个属性 = 什么值"提出来——看属性监听时这是唯一有用的信息
    if (member == QLatin1String("PropertiesChanged") && args.size() >= 2) {
        QStringList parts;
        const QVariantMap dict = args.at(1).toMap();
        const QVariantList items = dict.value(QStringLiteral("items")).toList();
        for (const QVariant &iv : items) {
            const QVariantMap e = iv.toMap();
            const QString k = e.value(QStringLiteral("key")).toMap()
                                  .value(QStringLiteral("text")).toString();
            if (!k.isEmpty())
                parts << (k + QStringLiteral(" = ")
                          + nodeToText(unwrapVariant(
                                e.value(QStringLiteral("val")).toMap())));
        }
        if (args.size() >= 3) {
            const QVariantList inv = args.at(2).toMap()
                                         .value(QStringLiteral("items")).toList();
            for (const QVariant &iv : inv) {
                const QString k = iv.toMap().value(QStringLiteral("node")).toMap()
                                      .value(QStringLiteral("text")).toString();
                if (!k.isEmpty())
                    parts << (k + QStringLiteral("（失效）"));
            }
        }
        return parts.join(QStringLiteral(",  "));
    }

    // deepin 的自定义 Changed(ty, value)：第一参数是配置键
    if (member.endsWith(QLatin1String("Changed")) && args.size() >= 2
        && args.at(0).toMap().value(QStringLiteral("kind")).toString()
               == QLatin1String("str")) {
        const QString k = args.at(0).toMap().value(QStringLiteral("text")).toString();
        if (!k.isEmpty())
            return k + QStringLiteral(" = ")
                   + nodeToText(unwrapVariant(args.at(1).toMap()));
    }

    QStringList parts;
    for (int i = 0; i < args.size() && i < 3; ++i)
        parts << nodeToText(args.at(i).toMap());
    if (args.size() > 3)
        parts << QStringLiteral("…");
    return parts.join(QStringLiteral(",  "));
}

QString Bridge::messageToText(const QVariantMap &msg) const
{
    QString out;
    out += QStringLiteral("#%1  %2\n").arg(msg.value(QStringLiteral("serial")).toString(),
                                           msg.value(QStringLiteral("type")).toString());
    auto line = [&out, &msg](const char *label, const char *key) {
        const QString v = msg.value(QLatin1String(key)).toString();
        if (!v.isEmpty())
            out += QStringLiteral("  %1: %2\n").arg(QLatin1String(label), v);
    };
    line("sender", "sender");
    line("destination", "destination");
    line("path", "path");
    line("interface", "interface");
    line("member", "member");
    line("error", "error");
    line("signature", "signature");

    const QVariantList args = msg.value(QStringLiteral("args")).toList();
    if (!args.isEmpty()) {
        out += QStringLiteral("  args:\n");
        for (int i = 0; i < args.size(); ++i)
            out += QStringLiteral("    [%1] %2\n").arg(i).arg(nodeToText(args.at(i).toMap()));
    }
    return out;
}
