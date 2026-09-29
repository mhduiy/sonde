#include "messagemodel.h"

#include <QRegularExpression>

namespace {

QString haystack(const QVariantMap &m)
{
    return QStringLiteral("%1 %2 %3 %4 %5 %6 %7")
        .arg(m.value(QStringLiteral("type")).toString(),
             m.value(QStringLiteral("interface")).toString(),
             m.value(QStringLiteral("member")).toString(),
             m.value(QStringLiteral("path")).toString(),
             m.value(QStringLiteral("sender")).toString(),
             m.value(QStringLiteral("destination")).toString(),
             m.value(QStringLiteral("signature")).toString())
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

    // 过滤结果条数变化时同步刷新 QML 里绑定的 count
    connect(this, &QAbstractItemModel::rowsInserted, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::rowsRemoved, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::modelReset, this, [this] { emit countChanged(); });
    connect(this, &QAbstractItemModel::layoutChanged, this, [this] { emit countChanged(); });
}

QVariantMap MessageFilter::at(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    return data(index(row, 0), MessageModel::RawRole).toMap();
}

void MessageFilter::setQuery(const QString &q)
{
    if (m_query == q)
        return;
    m_query = q;
    m_terms = q.toLower().split(QRegularExpression(QStringLiteral("\\s+")),
                                Qt::SkipEmptyParts);
    invalidateFilter();
    emit queryChanged();
    emit countChanged();
}

bool MessageFilter::filterAcceptsRow(int row, const QModelIndex &parent) const
{
    if (m_terms.isEmpty())
        return true;

    auto *src = sourceModel();
    if (!src)
        return true;

    const QModelIndex idx = src->index(row, 0, parent);
    const QString hay = src->data(idx, MessageModel::SearchRole).toString();

    for (const QString &term : m_terms) {
        const int colon = term.indexOf(QLatin1Char(':'));
        if (colon > 0) {
            // field:value —— 在对应字段里找
            const QString field = term.left(colon);
            const QString value = term.mid(colon + 1);
            const QString actual = src->data(idx, fieldRole(field)).toString().toLower();
            if (!actual.contains(value))
                return false;
        } else if (!hay.contains(term)) {
            return false;
        }
    }
    return true;
}
