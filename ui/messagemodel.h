#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QList>
#include <QVariantMap>
#include <QStringList>

#include <functional>

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
        SummaryRole,  // 一行摘要（属性名=值 / 参数紧凑列表）
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

/// 过滤：空格分隔的多个条件，全部命中（AND）才显示。
///
/// 语法：`字段:值`，字段省略则在整个摘要串里找子串。
///
/// | 字段 | 含义 |
/// |---|---|
/// | `type` | method_call / method_return / signal / error |
/// | `iface` | 接口名 |
/// | `member` | 成员名 |
/// | `path` | 对象路径 |
/// | `sender` / `dest` | 发送者 / 接收者 |
/// | `svc` | 发送者**或**接收者 |
/// | `prop` | 属性名（匹配一行摘要） |
/// | `sig` | 签名 |
///
/// `svc` / `sender` / `dest` 会额外把服务名解析成唯一名一起比——
/// **信号的 sender 是唯一名（:1.x）**，不解析的话按服务名过滤信号永远不中。
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

    /// 公共名 → 唯一名的解析器（由 Bridge 注入，会走一次总线查询）
    void setNameResolver(std::function<QString(const QString &)> f) { m_resolver = std::move(f); }

    /// 取第 row 行（代理坐标）对应的原始消息
    Q_INVOKABLE QVariantMap at(int row) const;

    /// 追加一个过滤词条（已存在则忽略）。右键"加入过滤条件"用它，
    /// 这样任何 QML 文件都能直接改过滤框，不用层层传信号。
    Q_INVOKABLE void addQuery(const QString &term);

signals:
    void queryChanged();
    void countChanged();

protected:
    bool filterAcceptsRow(int row, const QModelIndex &parent) const override;

private:
    struct Term {
        QString field;   // 空 = 全字段子串
        QString value;   // 已小写
        QString alt;     // 唯一名（svc/sender/dest 用），已小写
    };

    QString m_query;
    QList<Term> m_terms;
    std::function<QString(const QString &)> m_resolver;
};
