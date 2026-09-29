#include "objecttree.h"

#include "bridge.h"

namespace {

constexpr int kExpandAllCap = 4000;   // 全展开的节点上限，防止被巨型服务拖死
constexpr int kAutoExpandDepth = 4;   // 单链自动展开的最大深度

QString nodeId(const QString &path)
{
    return QStringLiteral("p:") + path;
}
QString ifaceId(const QString &path, const QString &iface)
{
    return QStringLiteral("i:") + path + QLatin1Char('|') + iface;
}
QString memberId(const QString &path, const QString &iface, const QString &kind,
                 const QString &member)
{
    return QStringLiteral("m:") + path + QLatin1Char('|') + iface + QLatin1Char('|')
           + kind + QLatin1Char('|') + member;
}
QString argId(const QString &memberNodeId, int index)
{
    return memberNodeId + QStringLiteral("|a:") + QString::number(index);
}

} // namespace

ObjectTree::ObjectTree(Bridge *bridge, QObject *parent)
    : QObject(parent)
    , m_bridge(bridge)
{
}

QString ObjectTree::joinPath(const QString &base, const QString &child)
{
    if (base.endsWith(QLatin1Char('/')))
        return base + child;
    return base + QLatin1Char('/') + child;
}

void ObjectTree::setFilter(const QString &f)
{
    if (m_filter == f)
        return;
    m_filter = f;
    emit filterChanged();
    buildRows();
}

void ObjectTree::setService(const QString &bus, const QString &dest)
{
    m_bus = bus;
    m_dest = dest;
    m_error.clear();
    m_ready = false;

    qDeleteAll(m_nodes);
    m_nodes.clear();
    m_roots.clear();

    emit serviceChanged();
    if (dest.isEmpty()) {
        buildRows();
        return;
    }

    createRoot();
    buildRows();
}

void ObjectTree::refresh()
{
    if (m_dest.isEmpty())
        return;
    const QString bus = m_bus;
    const QString dest = m_dest;
    setService(bus, dest);
}

void ObjectTree::createRoot()
{
    auto *root = new Node;
    root->id = nodeId(QStringLiteral("/"));
    root->kind = QStringLiteral("path");
    root->name = QStringLiteral("/");
    root->path = QStringLiteral("/");
    root->expanded = true;
    m_nodes.insert(root->id, root);
    m_roots.append(root->id);
    load(root->id);

    // 对根节点下最多 2 个路径子节点做单链自动展开，
    // 这样一进来就能看到有内容的层级，而不是一串待点击的目录。
    int expandedPaths = 0;
    for (const QString &cid : std::as_const(root->children)) {
        Node *c = node(cid);
        if (c && c->kind == QLatin1String("path") && expandedPaths < 2) {
            autoExpandChain(c, 0);
            ++expandedPaths;
        }
    }

    m_ready = true;
}

void ObjectTree::toggle(const QString &id)
{
    Node *n = node(id);
    if (!n)
        return;
    if (!n->loaded)
        load(id);
    n->expanded = !n->expanded;
    buildRows();
}

void ObjectTree::autoExpandChain(Node *n, int guard)
{
    // 单链自动展开：让用户一进来就能看到有内容的层级，而不是一路点下去。
    // 判定条件是"路径子节点恰好一个"，接口有多少个不影响——
    // 因为有些实现（UOS 的 dbus-daemon）会在每一级祖先路径上重复报告
    // 总线驱动的接口，不能用"子节点总数==1"来判定。
    while (n && guard < kAutoExpandDepth) {
        if (!n->loaded)
            load(n->id);

        int pathChildren = 0;
        QString onlyPath;
        for (const QString &cid : n->children) {
            Node *c = node(cid);
            if (c && c->kind == QLatin1String("path")) {
                ++pathChildren;
                onlyPath = cid;
            }
        }

        n->expanded = true;
        if (pathChildren != 1)
            break;
        n = node(onlyPath);
        ++guard;
    }
}

void ObjectTree::load(const QString &id)
{
    Node *n = node(id);
    if (!n || n->loaded)
        return;
    if (n->kind == QLatin1String("path")) {
        loadPath(n);
    }
    n->loaded = true;
}

void ObjectTree::loadPath(Node *n)
{
    const QVariantMap res = m_bridge->introspectTree(m_bus, m_dest, n->path);
    if (!res.value(QStringLiteral("ok")).toBool()) {
        const QString err = res.value(QStringLiteral("error")).toString();
        if (n->path == QLatin1String("/"))
            m_error = err.isEmpty() ? QStringLiteral("该服务没有提供内省信息") : err;
        return;
    }

    const QVariantList items = res.value(QStringLiteral("items")).toList();

    // 有些实现（例如 UOS 的 dbus-daemon）会在每一级祖先路径上重复报告
    // 同一批接口。如果本级的接口集合与父级完全相同，就视为"继承而来"，
    // 不再重复显示——这样 / 和 /org、/org/freedesktop 不会各刷一遍。
    QStringList inherited;
    if (!n->parentId.isEmpty()) {
        if (const Node *p = node(n->parentId))
            inherited = p->ownIfaces;
    }
    QStringList ownIfaces;
    for (const QVariant &iv : items) {
        const QVariantMap im = iv.toMap();
        if (im.value(QStringLiteral("kind")).toString() == QLatin1String("interface"))
            ownIfaces.append(im.value(QStringLiteral("name")).toString());
    }
    n->ownIfaces = ownIfaces;
    const bool allInherited = !ownIfaces.isEmpty() && ownIfaces == inherited;

    for (const QVariant &iv : items) {
        const QVariantMap im = iv.toMap();
        const QString kind = im.value(QStringLiteral("kind")).toString();
        const QString name = im.value(QStringLiteral("name")).toString();

        if (kind == QLatin1String("node")) {
            // 有些实现会在一个 <node> 里给出完整相对路径
            // （UOS 的 dbus-daemon 就是 "org/freedesktop/DBus"），
            // 拆成逐级路径节点，保证层级关系正确。
            Node *attachTo = n;
            QString curPath = n->path;
            const QStringList segs = name.split(QLatin1Char('/'), Qt::SkipEmptyParts);
            for (const QString &seg : segs) {
                curPath = joinPath(curPath, seg);
                const QString cid = nodeId(curPath);
                Node *existing = m_nodes.value(cid, nullptr);
                if (existing) {
                    attachTo = existing;
                    continue;
                }
                auto *created = new Node;
                created->id = cid;
                created->path = curPath;
                created->kind = QStringLiteral("path");
                created->name = seg;
                created->parentId = attachTo->id;
                m_nodes.insert(cid, created);
                if (!attachTo->children.contains(cid))
                    attachTo->children.append(cid);
                attachTo = created;
            }
        } else if (kind == QLatin1String("interface")) {
            if (allInherited)
                continue; // 与父级完全相同 → 继承来的，不重复显示
            auto *iface = new Node;
            iface->id = ifaceId(n->path, name);
            iface->kind = QStringLiteral("interface");
            iface->name = name;
            iface->iface = name;
            iface->path = n->path;
            iface->loaded = true;
            if (m_nodes.contains(iface->id)) {
                delete iface;
                continue;
            }
            m_nodes.insert(iface->id, iface);

            auto addMembers = [&](const QVariantList &list, const QString &mkind) {
                for (const QVariant &mv : list) {
                    const QVariantMap mm = mv.toMap();
                    auto *m = new Node;
                    m->id = memberId(n->path, name, mkind,
                                     mm.value(QStringLiteral("name")).toString());
                    m->kind = mkind;
                    m->name = mm.value(QStringLiteral("name")).toString();
                    m->path = n->path;
                    m->iface = name;
                    m->member = m->name;
                    if (mkind == QLatin1String("property")) {
                        const QString type = mm.value(QStringLiteral("type")).toString();
                        const QString access = mm.value(QStringLiteral("access")).toString();
                        m->access = access;
                        m->argType = type;
                        m->detail = type + QStringLiteral("  [") + access + QLatin1Char(']');
                    } else {
                        m->inSig = mm.value(QStringLiteral("inSig")).toString();
                        m->outSig = mm.value(QStringLiteral("outSig")).toString();
                        m->detail = QStringLiteral("(") + m->inSig + QStringLiteral(")")
                                    + (mkind == QLatin1String("method")
                                           ? (QStringLiteral(" → (") + m->outSig + QStringLiteral(")"))
                                           : QString());
                    }
                    m->detail.replace(QStringLiteral("()"), QString());

                    // 参数作为子节点，层级关系一目了然
                    const QVariantList args = mm.value(QStringLiteral("args")).toList();
                    for (int i = 0; i < args.size(); ++i) {
                        const QVariantMap am = args.at(i).toMap();
                        auto *a = new Node;
                        a->id = argId(m->id, i);
                        a->kind = QStringLiteral("arg");
                        const QString an = am.value(QStringLiteral("name")).toString();
                        a->name = an.isEmpty() ? QStringLiteral("arg%1").arg(i) : an;
                        a->argType = am.value(QStringLiteral("type")).toString();
                        const QString dir = am.value(QStringLiteral("direction")).toString();
                        a->access = dir;
                        a->detail = (dir == QLatin1String("out") ? QStringLiteral("out ")
                                                                 : QStringLiteral("in "))
                                    + a->argType;
                        a->path = n->path;
                        a->iface = name;
                        a->member = m->name;
                        m->children.append(a->id);
                        m_nodes.insert(a->id, a);
                    }

                    iface->children.append(m->id);
                    m_nodes.insert(m->id, m);
                }
            };
            addMembers(im.value(QStringLiteral("methods")).toList(), QStringLiteral("method"));
            addMembers(im.value(QStringLiteral("signals")).toList(), QStringLiteral("signal"));
            addMembers(im.value(QStringLiteral("properties")).toList(), QStringLiteral("property"));

            n->children.append(iface->id);
        }
    }
}

void ObjectTree::buildRows()
{
    QVariantList out;
    for (const QString &id : std::as_const(m_roots)) {
        const Node *n = node(id);
        if (n)
            collect(n, 0, out);
    }
    m_rows = out;
    emit rowsChanged();
}

bool ObjectTree::collect(const Node *n, int depth, QVariantList &out) const
{
    if (!n)
        return false;

    const bool filtering = !m_filter.isEmpty();
    if (!filtering) {
        out.append(rowOf(n, depth));
        if (n->expanded) {
            for (const QString &cid : n->children) {
                const Node *c = node(cid);
                if (c)
                    collect(c, depth + 1, out);
            }
        }
        return true;
    }

    // 过滤模式：命中自身或任一后代才显示，并自动展开沿途
    const bool selfMatch =
        n->name.contains(m_filter, Qt::CaseInsensitive)
        || n->detail.contains(m_filter, Qt::CaseInsensitive)
        || n->iface.contains(m_filter, Qt::CaseInsensitive);

    QVariantList childRows;
    bool childMatch = false;
    for (const QString &cid : n->children) {
        const Node *c = node(cid);
        if (!c)
            continue;
        if (collect(c, depth + 1, childRows))
            childMatch = true;
    }

    if (selfMatch || childMatch) {
        out.append(rowOf(n, depth));
        out += childRows;
        return true;
    }
    return false;
}

QVariantMap ObjectTree::rowOf(const Node *n, int depth) const
{
    return QVariantMap{
        { QStringLiteral("id"), n->id },
        { QStringLiteral("kind"), n->kind },
        { QStringLiteral("name"), n->name },
        { QStringLiteral("detail"), n->detail },
        { QStringLiteral("path"), n->path },
        { QStringLiteral("iface"), n->iface },
        { QStringLiteral("member"), n->member },
        { QStringLiteral("argType"), n->argType },
        { QStringLiteral("access"), n->access },
        { QStringLiteral("inSig"), n->inSig },
        { QStringLiteral("outSig"), n->outSig },
        { QStringLiteral("depth"), depth },
        { QStringLiteral("hasChildren"), !n->children.isEmpty() },
        { QStringLiteral("expanded"), n->expanded },
        { QStringLiteral("bus"), m_bus },
        { QStringLiteral("dest"), m_dest },
    };
}

QVariantMap ObjectTree::nodeById(const QString &id) const
{
    const Node *n = node(id);
    if (!n)
        return {};
    return rowOf(n, 0);
}

void ObjectTree::expandAll()
{
    QList<QString> queue = m_roots;
    int guard = 0;
    while (!queue.isEmpty() && guard < kExpandAllCap) {
        const QString id = queue.takeFirst();
        Node *n = node(id);
        if (!n)
            continue;
        if (!n->loaded)
            load(n->id);
        n->expanded = true;
        ++guard;
        for (const QString &cid : std::as_const(n->children)) {
            Node *c = node(cid);
            if (c && !c->children.isEmpty())
                queue.append(cid);
        }
    }
    buildRows();
}

void ObjectTree::collapseAll()
{
    for (Node *n : std::as_const(m_nodes)) {
        if (n->id != nodeId(QStringLiteral("/")))
            n->expanded = false;
    }
    buildRows();
}
