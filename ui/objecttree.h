#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class Bridge;

/// 服务 → 对象路径 → 接口 → 方法/信号/属性 的层级树。
///
/// 这是新界面的**主体**（对标 d-spy 的核心视图）。
/// 实现要点：
/// - 按需内省：展开某个 path 时才去拉它的内省 XML，避免一次性拉整棵树
/// - 对 QML 暴露"拍平后的可见行"（带 depth），而不是 QAbstractItemModel 树，
///   这样样式和展开逻辑完全由自己掌控
class ObjectTree : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList rows READ rows NOTIFY rowsChanged)
    Q_PROPERTY(QString service READ service NOTIFY serviceChanged)
    Q_PROPERTY(QString bus READ bus NOTIFY serviceChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QString error READ error NOTIFY rowsChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY rowsChanged)

public:
    explicit ObjectTree(Bridge *bridge, QObject *parent = nullptr);

    QVariantList rows() const { return m_rows; }
    QString service() const { return m_dest; }
    QString bus() const { return m_bus; }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    QString error() const { return m_error; }
    bool ready() const { return m_ready; }

    Q_INVOKABLE void setService(const QString &bus, const QString &dest);
    Q_INVOKABLE void toggle(const QString &id);
    Q_INVOKABLE void expandAll();
    Q_INVOKABLE void collapseAll();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap nodeById(const QString &id) const;

signals:
    void rowsChanged();
    void serviceChanged();
    void filterChanged();

private:
    struct Node {
        QString id;
        QString kind; // path | interface | method | signal | property | arg
        QString name;
        QString detail;
        QString path;
        QString iface;
        QString member;
        QString argType;
        QString access;
        QString inSig;
        QString outSig;
        QStringList children;
        QStringList ownIfaces;   // 这个路径自己报告的接口名
        QString parentId;        // 父路径节点，用于判断"继承来的接口"
        bool loaded = false;
        bool expanded = false;
    };

    Node *node(const QString &id) const { return m_nodes.value(id, nullptr); }
    void createRoot();
    void load(const QString &id);
    void loadPath(Node *n);
    void autoExpandChain(Node *n, int guard);
    void buildRows();
    bool collect(const Node *n, int depth, QVariantList &out) const;
    QVariantMap rowOf(const Node *n, int depth) const;
    static QString joinPath(const QString &base, const QString &child);

    Bridge *m_bridge = nullptr;
    QHash<QString, Node *> m_nodes;
    QStringList m_roots;
    QString m_bus = QStringLiteral("session");
    QString m_dest;
    QString m_filter;
    QString m_error;
    bool m_ready = false;
    QVariantList m_rows;
};
