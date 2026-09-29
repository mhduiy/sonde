#include <QCommandLineParser>
#include <QDebug>
#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#include "bridge.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sonde"));
    app.setApplicationDisplayName(QStringLiteral("Sonde"));
    app.setOrganizationName(QStringLiteral("Sonde"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));

    // 统一用 Fusion + 深色调色板，保证在 DDE 主题下也长得一样。
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    QPalette pal;
    pal.setColor(QPalette::Window, QColor(QStringLiteral("#161b21")));
    pal.setColor(QPalette::WindowText, QColor(QStringLiteral("#d7dde4")));
    pal.setColor(QPalette::Base, QColor(QStringLiteral("#0f1216")));
    pal.setColor(QPalette::AlternateBase, QColor(QStringLiteral("#1b2229")));
    pal.setColor(QPalette::Text, QColor(QStringLiteral("#d7dde4")));
    pal.setColor(QPalette::Button, QColor(QStringLiteral("#1b2229")));
    pal.setColor(QPalette::ButtonText, QColor(QStringLiteral("#d7dde4")));
    pal.setColor(QPalette::Highlight, QColor(QStringLiteral("#2f6fb0")));
    pal.setColor(QPalette::HighlightedText, QColor(QStringLiteral("#ffffff")));
    pal.setColor(QPalette::PlaceholderText, QColor(QStringLiteral("#7b8794")));
    pal.setColor(QPalette::ToolTipBase, QColor(QStringLiteral("#1b2229")));
    pal.setColor(QPalette::ToolTipText, QColor(QStringLiteral("#d7dde4")));
    QGuiApplication::setPalette(pal);

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Sonde —— D-Bus 观察台"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption busOpt(QStringLiteral("bus"),
                              QStringLiteral("启动后自动监听的总线 (session|system)"),
                              QStringLiteral("bus"));
    QCommandLineOption shotOpt(QStringLiteral("screenshot"),
                               QStringLiteral("渲染一帧后保存为 PNG 并退出"),
                               QStringLiteral("path"));
    QCommandLineOption delayOpt(QStringLiteral("screenshot-delay"),
                                QStringLiteral("截图前的等待毫秒数"),
                                QStringLiteral("ms"), QStringLiteral("1500"));
    QCommandLineOption selectOpt(QStringLiteral("select-first"),
                                 QStringLiteral("自动选中第一条消息（截图/自检用）"));
    QCommandLineOption tabOpt(QStringLiteral("tab"),
                              QStringLiteral("启动时显示的标签页 (0=详情 1=浏览 2=调用)"),
                              QStringLiteral("n"), QStringLiteral("0"));
    QCommandLineOption demoCallOpt(QStringLiteral("demo-call"),
                                   QStringLiteral("启动后自动发一次调用（自检用）"));
    parser.addOption(busOpt);
    parser.addOption(shotOpt);
    parser.addOption(delayOpt);
    parser.addOption(selectOpt);
    parser.addOption(tabOpt);
    parser.addOption(demoCallOpt);
    parser.process(app);

    // 故意不 delete：监控线程把 this 当作回调上下文，
    // 让 Bridge 活到进程结束，避免退出瞬间出现悬垂指针。
    auto *bridge = new Bridge();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("bridge"), bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("msgModel"), bridge->messages());
    engine.rootContext()->setContextProperty(QStringLiteral("msgFilter"), bridge->filter());
    engine.rootContext()->setContextProperty(QStringLiteral("autoSelectFirst"),
                                            parser.isSet(selectOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("initialTab"),
                                            parser.value(tabOpt).toInt());
    engine.rootContext()->setContextProperty(QStringLiteral("demoCall"),
                                            parser.isSet(demoCallOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("initialBus"),
                                            parser.value(busOpt));

    const QString qmlDir = QStringLiteral(SONDE_QML_DIR);
    engine.load(QUrl::fromLocalFile(qmlDir + QStringLiteral("/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "QML 加载失败，检查目录:" << qmlDir;
        return 2;
    }

    if (parser.isSet(busOpt)) {
        const QString bus = parser.value(busOpt);
        QTimer::singleShot(200, bridge, [bridge, bus] { bridge->startMonitor(bus); });
    }

    if (parser.isSet(shotOpt)) {
        const QString path = parser.value(shotOpt);
        const int delay = parser.value(delayOpt).toInt();
        QTimer::singleShot(delay, &app, [&engine, path] {
            if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst())) {
                const QImage img = w->grabWindow();
                if (img.isNull())
                    qCritical() << "截图失败：grabWindow 返回空图像";
                else
                    qInfo() << (img.save(path) ? "截图已保存:" : "截图保存失败:") << path;
            } else {
                qCritical() << "根对象不是 QQuickWindow，无法截图";
            }
            QGuiApplication::quit();
        });
    }

    return app.exec();
}
