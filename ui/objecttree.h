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
    Q_PROPERTY(QString focusId READ focusId NOTIFY rowsChanged)
    Q_PROPERTY(bool hideStandard READ hideStandard WRITE setHideStandard NOTIFY hideStandardChanged)

public:
    explicit ObjectTree(Bridge *bridge, QObject *parent = nullptr);

    QVariantList rows() const { return m_rows; }
    QString service() const { return m_dest; }
    QString bus() const { return m_bus; }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    QString error() const { return m_error; }
    bool ready() const { return m_ready; }
    /// 选服务时自动定位到的节点 id（界面用它滚动过去）
    QString focusId() const { return m_focusId; }
    bool hideStandard() const { return m_hideStandard; }
    void setHideStandard(bool v);

    Q_INVOKABLE void setService(const QString &bus, const QString &dest);
    Q_INVOKABLE void toggle(const QString &id);
    Q_INVOKABLE void expandAll();
    Q_INVOKABLE void collapseAll();
    Q_INVOKABLE void refresh();
    /// 重新定位到"与服务名对应的对象路径"
    Q_INVOKABLE void locateService();
    Q_INVOKABLE QVariantMap nodeById(const QString &id) const;

signals:
    void rowsChanged();
    void serviceChanged();
    void filterChanged();
    void hideStandardChanged();

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
        QString argText;   // 参数（写进签名括号，带名字）
        QString retText;   // 返回值
        QString inSig;
        QString outSig;
        QStringList children;
        QStringList ownIfaces;   // 这个路径自己报告的接口名
        QString parentId;        // 父路径节点，用于判断"继承来的接口"
        bool standard = false;   // 是不是 org.freedesktop.DBus.* 这类标准接口
        bool loaded = false;
        bool expanded = false;
    };

    Node *node(const QString &id) const { return m_nodes.value(id, nullptr); }
    static QString pathForDest(const QString &dest);
    static bool isStandardIface(const QString &name);
    void genericExpand();
    QString expandPath(const QString &target);
    void createRoot();
    void load(const QString &id);
    void loadPath(Node *n);
    void autoExpandChain(Node *n, int guard);
    void buildRows();
    bool visible(const Node *n) const;
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
    QString m_focusId;
    bool m_hideStandard = true;
    bool m_ready = false;
    QVariantList m_rows;
};
