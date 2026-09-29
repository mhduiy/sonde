#include <QCommandLineParser>
#include <QDebug>
#include <QGuiApplication>
#include <QImage>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#include "bridge.h"
#include "objecttree.h"
#include "theme.h"

namespace {

/// 把主题映射到 Qt 控件的调色板，这样 TextField/Button/ComboBox 等
/// 原生控件会自动跟着浅色/深色切换，不用逐个手写样式。
void applyPalette(const Theme &t)
{
    QPalette p;
    p.setColor(QPalette::Window, t.bg());
    p.setColor(QPalette::WindowText, t.text());
    p.setColor(QPalette::Base, t.surface());
    p.setColor(QPalette::AlternateBase, t.surfaceAlt());
    p.setColor(QPalette::Text, t.text());
    p.setColor(QPalette::Button, t.surfaceAlt());
    p.setColor(QPalette::ButtonText, t.text());
    p.setColor(QPalette::Highlight, t.accent());
    p.setColor(QPalette::HighlightedText, t.accentText());
    p.setColor(QPalette::PlaceholderText, t.textFaint());
    p.setColor(QPalette::ToolTipBase, t.surface());
    p.setColor(QPalette::ToolTipText, t.text());
    p.setColor(QPalette::Mid, t.border());
    p.setColor(QPalette::Dark, t.borderStrong());
    p.setColor(QPalette::Disabled, QPalette::Text, t.textFaint());
    p.setColor(QPalette::Disabled, QPalette::ButtonText, t.textFaint());
    p.setColor(QPalette::Disabled, QPalette::WindowText, t.textFaint());
    QGuiApplication::setPalette(p);
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sonde"));
    app.setApplicationDisplayName(QStringLiteral("Sonde"));
    app.setOrganizationName(QStringLiteral("Sonde"));
    app.setApplicationVersion(QStringLiteral("0.2.0"));

    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Sonde —— D-Bus 观察台"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption busOpt(QStringLiteral("bus"),
                              QStringLiteral("要监听的总线 (session|system)"),
                              QStringLiteral("bus"), QStringLiteral("session"));
    QCommandLineOption serviceOpt(QStringLiteral("service"),
                                  QStringLiteral("启动时自动打开的服务名"),
                                  QStringLiteral("dest"));
    QCommandLineOption darkOpt(QStringLiteral("dark"), QStringLiteral("以深色主题启动"));
    QCommandLineOption demoOpt(QStringLiteral("demo"),
                               QStringLiteral("自检：自动监听 + 打开服务 + 加一条监听"));
    QCommandLineOption shotOpt(QStringLiteral("screenshot"),
                               QStringLiteral("渲染一帧后保存为 PNG 并退出"),
                               QStringLiteral("path"));
    QCommandLineOption delayOpt(QStringLiteral("screenshot-delay"),
                                QStringLiteral("截图前的等待毫秒数"),
                                QStringLiteral("ms"), QStringLiteral("1800"));
    parser.addOption(busOpt);
    parser.addOption(serviceOpt);
    parser.addOption(darkOpt);
    parser.addOption(demoOpt);
    parser.addOption(shotOpt);
    parser.addOption(delayOpt);
    parser.process(app);

    Theme theme;
    if (parser.isSet(darkOpt))
        theme.setDark(true);
    applyPalette(theme);
    QObject::connect(&theme, &Theme::changed, &app, [&theme] { applyPalette(theme); });

    // 故意不 delete：监控线程把 Bridge 当作回调上下文，
    // 让它活到进程结束，避免退出瞬间出现悬垂指针。
    auto *bridge = new Bridge();
    auto *tree = new ObjectTree(bridge);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("bridge"), bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("tree"), tree);
    engine.rootContext()->setContextProperty(QStringLiteral("theme"), &theme);
    engine.rootContext()->setContextProperty(QStringLiteral("msgFilter"), bridge->filter());
    engine.rootContext()->setContextProperty(QStringLiteral("initialBus"), parser.value(busOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("initialService"),
                                            parser.value(serviceOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("demoMode"), parser.isSet(demoOpt));

    engine.load(QUrl::fromLocalFile(QStringLiteral(SONDE_QML_DIR) + QStringLiteral("/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "QML 加载失败，检查目录:" << QStringLiteral(SONDE_QML_DIR);
        return 2;
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
