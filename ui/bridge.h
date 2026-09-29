#pragma once

#include <QObject>
#include <QByteArray>
#include <QList>
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
}

/// 界面与 Rust 核心之间唯一的桥。
///
/// 线程规则：Rust 的回调都在**非 GUI 线程**触发，桥接层一律用
/// `Qt::QueuedConnection` 投递回 GUI 线程后才碰模型，绝不在 Rust 线程里碰 QObject。
class Bridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MessageModel *messages READ messages CONSTANT)
    Q_PROPERTY(MessageFilter *filter READ filter CONSTANT)
    Q_PROPERTY(bool monitoring READ monitoring NOTIFY monitoringChanged)
    Q_PROPERTY(QString bus READ bus NOTIFY monitoringChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(int pending READ pending NOTIFY pendingChanged)
    Q_PROPERTY(int total READ total NOTIFY totalChanged)

public:
    explicit Bridge(QObject *parent = nullptr);
    ~Bridge() override;

    MessageModel *messages() { return &m_model; }
    MessageFilter *filter() { return &m_filter; }
    bool monitoring() const { return m_monitoring; }
    QString bus() const { return m_bus; }
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
    Q_INVOKABLE quint64 call(const QString &bus, const QString &dest, const QString &path,
                             const QString &iface, const QString &member,
                             const QString &sig, const QVariantList &args);
    Q_INVOKABLE QString messageToText(const QVariantMap &msg) const;
    Q_INVOKABLE QString nodeToText(const QVariantMap &node, int indent = 0) const;
    /// 把值树拍平成带 depth 的行，界面用非递归列表渲染（QML 不允许组件自递归）。
    Q_INVOKABLE QVariantList flattenNodes(const QVariantList &nodes) const;

public slots:
    void handleBatch(const QByteArray &payload);
    void finishCall(quint64 id, const QByteArray &payload);

signals:
    void monitoringChanged();
    void pausedChanged();
    void pendingChanged();
    void totalChanged();
    void callFinished(quint64 id, const QVariantMap &result);
    void notice(const QString &level, const QString &text);

private:
    void flushPending();

    SondeCore *m_core = nullptr;
    MessageModel m_model;
    MessageFilter m_filter;
    bool m_monitoring = false;
    bool m_paused = false;
    QString m_bus = QStringLiteral("session");
    QList<QVariantMap> m_pending;
    quint64 m_nextCallId = 1;
    int m_total = 0;
};
