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

/// 解析内省 XML（树形解析，避免 QDomDocument 的已弃用写法）。
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
    while (!r.atEnd()) {
        r.readNext();
        if (r.isEndElement()) {
            const QString n = r.name().toString();
            if (n == QLatin1String("method") || n == QLatin1String("signal"))
                flushMember();
            else if (n == QLatin1String("interface")) {
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

        const QString n = r.name().toString();
        if (n == QLatin1String("node")) {
            const QString nm = r.attributes().value(QStringLiteral("name")).toString();
            if (!nm.isEmpty())
                childNodes.append(QVariantMap{ { QStringLiteral("kind"), QStringLiteral("node") },
                                               { QStringLiteral("name"), nm } });
        } else if (n == QLatin1String("interface")) {
            ifaceName = r.attributes().value(QStringLiteral("name")).toString();
        } else if (n == QLatin1String("method")) {
            curMember = QVariantMap{ { QStringLiteral("kind"), QStringLiteral("method") },
                                     { QStringLiteral("name"),
                                       r.attributes().value(QStringLiteral("name")).toString() } };
        } else if (n == QLatin1String("signal")) {
            curMember = QVariantMap{ { QStringLiteral("kind"), QStringLiteral("signal") },
                                     { QStringLiteral("name"),
                                       r.attributes().value(QStringLiteral("name")).toString() } };
        } else if (n == QLatin1String("arg")) {
            curArgs.append(QVariantMap{
                { QStringLiteral("name"), r.attributes().value(QStringLiteral("name")).toString() },
                { QStringLiteral("type"), r.attributes().value(QStringLiteral("type")).toString() },
                { QStringLiteral("direction"),
                  r.attributes().value(QStringLiteral("direction")).toString() },
            });
        } else if (n == QLatin1String("property")) {
            props.append(QVariantMap{
                { QStringLiteral("kind"), QStringLiteral("property") },
                { QStringLiteral("name"), r.attributes().value(QStringLiteral("name")).toString() },
                { QStringLiteral("type"), r.attributes().value(QStringLiteral("type")).toString() },
                { QStringLiteral("access"),
                  r.attributes().value(QStringLiteral("access")).toString() },
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

/// 调用上下文：把「哪个 Bridge + 哪次调用」带过 FFI 边界，回调里再 free。
struct CallCtx {
    Bridge *bridge;
    quint64 id;
};

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

    out.append(QVariantMap{
        { QStringLiteral("depth"), depth },
        { QStringLiteral("label"), label },
        { QStringLiteral("kind"), kind },
        { QStringLiteral("sig"), node.value(QStringLiteral("sig")).toString() },
        { QStringLiteral("display"), display },
        { QStringLiteral("composite"), composite },
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

} // namespace

// --------------------------------------------------------------- Rust → GUI 投递

extern "C" void sondeMonitorTrampoline(void *ctx, const char *json, unsigned int count)
{
    Q_UNUSED(count);
    auto *b = static_cast<Bridge *>(ctx);
    if (!b || !json)
        return;
    // 这里跑在 Rust 监控线程上。绝不可直接碰 QObject，
    // 一律排队投递到 GUI 线程。
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
        msgs.append(m);
    }
    if (msgs.isEmpty())
        return;

    m_total += msgs.size();
    emit totalChanged();

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

void Bridge::finishCall(quint64 id, const QByteArray &payload)
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    QVariantMap result;
    if (doc.isObject())
        result = doc.object().toVariantMap();
    emit callFinished(id, result);
}

QStringList Bridge::listNames(const QString &bus)
{
    if (!m_core)
        return {};
    const QByteArray b = utf8(bus);
    const QJsonDocument doc = QJsonDocument::fromJson(takeRust(sonde_list_names(m_core, b.constData())).toUtf8());
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
    const QJsonDocument doc = QJsonDocument::fromJson(takeRust(sonde_type_tree(s.constData())).toUtf8());
    return doc.isArray() ? doc.array().toVariantList() : QVariantList{};
}

quint64 Bridge::call(const QString &bus, const QString &dest, const QString &path,
                     const QString &iface, const QString &member, const QString &sig,
                     const QVariantList &args)
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
    auto *ctx = new CallCtx{ this, id };
    sonde_call(m_core, b.constData(), d.constData(), p.constData(), i.constData(),
               m.constData(), s.constData(), a.constData(), &sondeReplyTrampoline, ctx);
    return id;
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
