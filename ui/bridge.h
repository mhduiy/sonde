#pragma once

#include <QByteArray>
#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "messagemodel.h"

struct SondeCore;

/// Rust 核心的 C ABI 声明。
extern "C" {
using SondeBatchCb = void (*)(void *, const char *, unsigned int);
using SondeReplyCb = void (*)(void *, const char *);

SondeCore *sonde_core_new();
void sonde_core_free(SondeCore *);
void sonde_string_free(char *);
char *sonde_version();
char *sonde_type_tree(const char *sig);
char *sonde_list_names(SondeCore *, const char *bus);
char *sonde_introspect(SondeCore *, const char *bus, const char *dest, const char *path);
void sonde_call(SondeCore *, const char *bus, const char *dest, const char *path,
                const char *iface, const char *member, const char *argsSig,
                const char *argsJson, SondeReplyCb cb, void *ctx);
int sonde_monitor_start(SondeCore *, const char *bus, SondeBatchCb cb, void *ctx);
void sonde_monitor_stop(SondeCore *);
char *sonde_name_owner(SondeCore *, const char *bus, const char *name);
}

/// 界面与 Rust 核心之间唯一的桥。
///
/// 线程规则：Rust 的回调都在非 GUI 线程触发，一律用 `Qt::QueuedConnection`
/// 投递回 GUI 线程后才碰模型。
class Bridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MessageModel *messages READ messages CONSTANT)
    Q_PROPERTY(MessageFilter *filter READ filter CONSTANT)
    Q_PROPERTY(bool monitoring READ monitoring NOTIFY monitoringChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(int pending READ pending NOTIFY pendingChanged)
    Q_PROPERTY(int total READ total NOTIFY totalChanged)

public:
    explicit Bridge(QObject *parent = nullptr);
    ~Bridge() override;

    MessageModel *messages() { return &m_model; }
    MessageFilter *filter() { return &m_filter; }
    bool monitoring() const { return m_monitoring; }
    bool paused() const { return m_paused; }
    void setPaused(bool p);
    int pending() const { return static_cast<int>(m_pending.size()); }
    int total() const { return m_total; }

    Q_INVOKABLE void startMonitor(const QString &bus);
    Q_INVOKABLE void stopMonitor();
    Q_INVOKABLE void clear();

    Q_INVOKABLE QString version() const;
    Q_INVOKABLE QStringList listNames(const QString &bus);
    Q_INVOKABLE QVariantMap introspectTree(const QString &bus, const QString &dest,
                                           const QString &path);
    Q_INVOKABLE QVariantList typeTree(const QString &sig);
    Q_INVOKABLE QVariantList flattenNodes(const QVariantList &nodes) const;

    /// 发起方法调用；返回调用 id（结果通过 callFinished 回传）
    Q_INVOKABLE quint64 call(const QString &bus, const QString &dest, const QString &path,
                             const QString &iface, const QString &member,
                             const QString &sig, const QVariantList &args);

    /// 读取属性（内部走 org.freedesktop.DBus.Properties.Get）
    Q_INVOKABLE quint64 callGetProperty(const QString &bus, const QString &dest,
                                        const QString &path, const QString &iface,
                                        const QString &prop);

    /// 读取接口的全部属性（Properties.GetAll）
    Q_INVOKABLE quint64 callGetAllProperties(const QString &bus, const QString &dest,
                                             const QString &path, const QString &iface);

    /// 写入属性（内部走 org.freedesktop.DBus.Properties.Set，参数按 typeSig 构造变体）
    Q_INVOKABLE quint64 callSetProperty(const QString &bus, const QString &dest,
                                        const QString &path, const QString &iface,
                                        const QString &prop, const QString &typeSig,
                                        const QString &valueText);

    /// 把公共名解析成唯一名（:1.x）。
    /// 信号的 sender 是唯一名，不解析的话"监听某个服务的信号"永远匹配不上。
    Q_INVOKABLE QString messageToText(const QVariantMap &msg) const;
    Q_INVOKABLE QString nodeToText(const QVariantMap &node, int indent = 0) const;
    /// JSON 语法高亮：返回按行切好的 HTML，供 CodeView 渲染（带行号、可选中）
    Q_INVOKABLE QStringList jsonLines(const QString &json, const QVariantMap &colors) const;
    /// 把值节点转成**真正的 JSON 文本**（结构体→数组、字典→对象、变体→内层值）
    Q_INVOKABLE QString nodeToJson(const QVariantMap &node) const;
    Q_INVOKABLE QString nodesToJson(const QVariantList &nodes) const;

public slots:
    void handleBatch(const QByteArray &payload);
    void finishCall(quint64 id, const QByteArray &payload);

signals:
    void monitoringChanged();
    void pausedChanged();
    void pendingChanged();
    void totalChanged();
    void callFinished(quint64 id, const QVariantMap &result);
    void propertyRead(quint64 id, const QVariantMap &node, const QString &iface,
                      const QString &name, const QString &error);
    void propertyWritten(quint64 id, bool ok, const QString &error);
    void notice(const QString &level, const QString &text);

private:
    quint64 dispatchCall(const QString &bus, const QString &dest, const QString &path,
                         const QString &iface, const QString &member, const QString &sig,
                         const QVariantList &args, int kind);
    /// 由签名生成一个变体参数节点，供 Properties.Set 使用
    QVariantMap makeVariantArg(const QString &typeSig, const QString &valueText) const;
    void flushPending();
    /// 公共名 → 唯一名（过滤器用它把服务名也匹配上信号的 sender）
    QString nameOwner(const QString &bus, const QString &name) const;
    /// 一行摘要：PropertiesChanged 抽出"属性 = 值"，其它把参数紧凑列出
    QString summarizeMessage(const QVariantMap &m) const;

    SondeCore *m_core = nullptr;
    MessageModel m_model;
    MessageFilter m_filter;
    bool m_monitoring = false;
    bool m_paused = false;
    QString m_bus = QStringLiteral("session");
    QList<QVariantMap> m_pending;
    quint64 m_nextCallId = 1;
    int m_total = 0;
    QHash<quint64, int> m_callKind;            // 0 = call, 1 = getProp, 2 = getAll
    QHash<quint64, QStringList> m_callMeta;    // getProp 的 (iface, name)
};
