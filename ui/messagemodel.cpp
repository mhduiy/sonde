#include "messagemodel.h"

#include <QRegularExpression>

namespace {

QString haystack(const QVariantMap &m)
{
    return QStringLiteral("%1 %2 %3 %4 %5 %6 %7 %8")
        .arg(m.value(QStringLiteral("type")).toString(),
             m.value(QStringLiteral("interface")).toString(),
             m.value(QStringLiteral("member")).toString(),
             m.value(QStringLiteral("path")).toString(),
             m.value(QStringLiteral("sender")).toString(),
             m.value(QStringLiteral("destination")).toString(),
             m.value(QStringLiteral("signature")).toString(),
             m.value(QStringLiteral("summary")).toString())
        .toLower();
}

/// 把 `iface:` / `member:` 这类字段前缀映射到模型角色。
/// 未知字段退回全域搜索串，保证不会因为写错字段名而查不到东西。
int fieldRole(const QString &f)
{
    if (f == QLatin1String("type"))
        return MessageModel::TypeRole;
    if (f == QLatin1String("iface") || f == QLatin1String("interface"))
        return MessageModel::IfaceRole;
    if (f == QLatin1String("member"))
        return MessageModel::MemberRole;
    if (f == QLatin1String("path"))
        return MessageModel::PathRole;
    if (f == QLatin1String("sender"))
        return MessageModel::SenderRole;
    if (f == QLatin1String("dest") || f == QLatin1String("destination"))
        return MessageModel::DestRole;
    if (f == QLatin1String("sig") || f == QLatin1String("signature"))
        return MessageModel::SigRole;
    return MessageModel::SearchRole;
}

} // namespace

// ------------------------------------------------------------------ MessageModel

MessageModel::MessageModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int MessageModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_msgs.size();
}

QVariant MessageModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_msgs.size())
        return {};

    const QVariantMap &m = m_msgs.at(index.row());
    switch (role) {
    case RawRole:
        return m;
    case TypeRole:
        return m.value(QStringLiteral("type"));
    case TimeRole:
        return m.value(QStringLiteral("timestamp_us"));
    case SenderRole:
        return m.value(QStringLiteral("sender"));
    case DestRole:
        return m.value(QStringLiteral("destination"));
    case PathRole:
        return m.value(QStringLiteral("path"));
    case IfaceRole:
        return m.value(QStringLiteral("interface"));
    case MemberRole:
        return m.value(QStringLiteral("member"));
    case SigRole:
        return m.value(QStringLiteral("signature"));
    case ArgsRole:
        return m.value(QStringLiteral("args"));
    case SummaryRole:
        return m.value(QStringLiteral("summary"));
    case SearchRole:
        return m_search.at(index.row());
    default:
        return {};
    }
}

QHash<int, QByteArray> MessageModel::roleNames() const
{
    return {
        { RawRole, "raw" },
        { TypeRole, "msgType" },
        { TimeRole, "timestampUs" },
        { SenderRole, "sender" },
        { DestRole, "destination" },
        { PathRole, "path" },
        { IfaceRole, "iface" },
        { MemberRole, "member" },
        { SigRole, "signature" },
        { ArgsRole, "args" },
        { SummaryRole, "summary" },
        { SearchRole, "search" },
    };
}

void MessageModel::appendBatch(const QList<QVariantMap> &msgs)
{
    if (msgs.isEmpty())
        return;

    // 先按上限淘汰最旧的，再一次性插入新的。
    const int overflow = m_msgs.size() + msgs.size() - m_capacity;
    if (overflow > 0) {
        const int drop = qMin(overflow, static_cast<int>(m_msgs.size()));
        if (drop > 0) {
            beginRemoveRows({}, 0, drop - 1);
            m_msgs.erase(m_msgs.begin(), m_msgs.begin() + drop);
            for (int i = 0; i < drop; ++i)
                m_search.removeFirst();
            endRemoveRows();
        }
    }

    beginInsertRows({}, m_msgs.size(), m_msgs.size() + msgs.size() - 1);
    for (const QVariantMap &m : msgs) {
        m_msgs.append(m);
        m_search.append(haystack(m));
    }
    endInsertRows();
    emit countChanged();
}

void MessageModel::clear()
{
    beginResetModel();
    m_msgs.clear();
    m_search.clear();
    endResetModel();
    emit countChanged();
}

// ----------------------------------------------------------------- MessageFilter

MessageFilter::MessageFilter(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    connect(this, &QAbstractItemModel::rowsInserted, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::rowsRemoved, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::modelReset, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::layoutChanged, this, [this] { emit countChanged(); });
}

void MessageFilter::setQuery(const QString &q)
{
    if (m_query == q)
        return;
    m_query = q;

    m_terms.clear();
    // 注意：**不能**把整条 query 先转小写再解析——D-Bus 名字大小写敏感，
    // 用转小写后的名字去 GetNameOwner 必然查不到。
    // 原样解析，只把用于"比较"的值转小写。
    const QStringList raw = q.split(
        QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    for (const QString &t : raw) {
        Term term;
        const int colon = t.indexOf(QLatin1Char(':'));
        if (colon > 0) {
            term.field = t.left(colon).toLower();
            const QString rawValue = t.mid(colon + 1);
            term.value = rawValue.toLower();
            // svc/sender/dest 额外解析唯一名：**信号的 sender 是 :1.x**
            if ((term.field == QLatin1String("svc") || term.field == QLatin1String("sender")
                 || term.field == QLatin1String("dest"))
                && m_resolver && !rawValue.isEmpty()) {
                const QString owner = m_resolver(rawValue); // 用原始大小写
                if (!owner.isEmpty())
                    term.alt = owner.toLower();
            }
        } else {
            term.value = t.toLower();
        }
        m_terms.append(term);
    }

    invalidateFilter();
    emit queryChanged();
    emit countChanged();
}

void MessageFilter::addQuery(const QString &term)
{
    const QString t = term.trimmed();
    if (t.isEmpty() || m_query.contains(t, Qt::CaseInsensitive))
        return;
    const QString cur = m_query.trimmed();
    setQuery(cur.isEmpty() ? t : (cur + QStringLiteral("  ") + t));
}

QVariantMap MessageFilter::at(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    return data(index(row, 0), MessageModel::RawRole).toMap();
}

bool MessageFilter::filterAcceptsRow(int row, const QModelIndex &parent) const
{
    if (m_terms.isEmpty())
        return true;

    auto *src = sourceModel();
    if (!src)
        return true;

    const QModelIndex idx = src->index(row, 0, parent);

    for (const Term &term : m_terms) {
        if (term.field.isEmpty()) {
            const QString hay = src->data(idx, MessageModel::SearchRole).toString();
            if (!hay.contains(term.value))
                return false;
            continue;
        }

        if (term.field == QLatin1String("svc")) {
            const QString sender =
                src->data(idx, MessageModel::SenderRole).toString().toLower();
            const QString dest =
                src->data(idx, MessageModel::DestRole).toString().toLower();
            const bool hit = sender.contains(term.value) || dest.contains(term.value)
                             || (!term.alt.isEmpty()
                                 && (sender.contains(term.alt) || dest.contains(term.alt)));
            if (!hit)
                return false;
        } else if (term.field == QLatin1String("prop")) {
            // 属性名只在摘要里找（两种信号风格都能覆盖）
            const QString summary =
                src->data(idx, MessageModel::SummaryRole).toString().toLower();
            if (!summary.contains(term.value))
                return false;
        } else {
            const int role = fieldRole(term.field);
            const QString actual = src->data(idx, role).toString().toLower();
            const bool hit = actual.contains(term.value)
                             || (!term.alt.isEmpty() && actual.contains(term.alt));
            if (!hit)
                return false;
        }
    }
    return true;
}
