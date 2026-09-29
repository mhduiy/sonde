#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QList>
#include <QVariantMap>
#include <QStringList>

/// 消息环形缓冲。**核心性能点**：批量插入 + 上限淘汰，
/// 每条消息只触发一次 beginInsertRows，绝不逐条刷新。
class MessageModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        RawRole = Qt::UserRole + 1,
        TypeRole,
        TimeRole,
        SenderRole,
        DestRole,
        PathRole,
        IfaceRole,
        MemberRole,
        SigRole,
        ArgsRole,
        SearchRole,   // 预计算的小写搜索串
    };

    explicit MessageModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void appendBatch(const QList<QVariantMap> &msgs);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void setCapacity(int n) { m_capacity = qMax(100, n); }

signals:
    void countChanged();

private:
    QList<QVariantMap> m_msgs;
    QStringList m_search;
    int m_capacity = 5000;
};

/// 过滤：支持 `type:signal iface:org.foo 子串` 这样的空格分隔查询，
/// 每个词都必须命中（AND）。
class MessageFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit MessageFilter(QObject *parent = nullptr);

    QString query() const { return m_query; }
    int count() const { return rowCount(); }
    void setQuery(const QString &q);

    /// 取第 row 行（代理坐标）对应的原始消息
    Q_INVOKABLE QVariantMap at(int row) const;

signals:
    void queryChanged();
    void countChanged();

protected:
    bool filterAcceptsRow(int row, const QModelIndex &parent) const override;

private:
    QString m_query;
    QStringList m_terms;
};
