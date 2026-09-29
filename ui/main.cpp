#include <QCommandLineParser>
#include <QDebug>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTextStream>
#include <QTimer>

#include "bridge.h"
#include "objecttree.h"
#include "theme.h"

#ifdef SONDE_WITH_DTK
#include <dguiapplicationhelper.h>
#endif

namespace {

/// DTK 自己负责控件主题。用 DTK 之后**不要**再调 QGuiApplication::setPalette，
/// 否则 DTK 会警告 "Don't use it on DTK application"。
void applyDtkTheme(const Theme &t)
{
#ifdef SONDE_WITH_DTK
    using Helper = Dtk::Gui::DGuiApplicationHelper;
    Helper::instance()->setPaletteType(t.dark() ? Helper::DarkType : Helper::LightType);
#else
    Q_UNUSED(t)
#endif
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
    QCommandLineOption demoSeedOpt(QStringLiteral("demo-seed"),
                                   QStringLiteral("自检时给第一个字符串参数填的值"),
                                   QStringLiteral("value"), QStringLiteral("org.freedesktop.DBus"));
    QCommandLineOption demoMethodOpt(QStringLiteral("demo-method"),
                                     QStringLiteral("自检时优先选中的方法名"),
                                     QStringLiteral("name"), QString());
    QCommandLineOption expandJsonOpt(QStringLiteral("expand-json"),
                                     QStringLiteral("JSON 值默认展开显示（自检/截图用）"));
    QCommandLineOption shotOpt(QStringLiteral("screenshot"),
                               QStringLiteral("渲染一帧后保存为 PNG 并退出"),
                               QStringLiteral("path"));
    QCommandLineOption delayOpt(QStringLiteral("screenshot-delay"),
                                QStringLiteral("截图前的等待毫秒数"),
                                QStringLiteral("ms"), QStringLiteral("1800"));
    QCommandLineOption dumpOpt(QStringLiteral("dump-tree"),
                               QStringLiteral("打印对象树的行（id/kind/name/depth）后退出，调试用"));
    QCommandLineOption callOpt(QStringLiteral("call"),
                               QStringLiteral("无界面调用一次方法，格式 接口.成员"),
                               QStringLiteral("iface.member"));
    QCommandLineOption callDestOpt(QStringLiteral("call-dest"),
                                   QStringLiteral("调用的目标服务（必填）"),
                                   QStringLiteral("dest"), QString());
    QCommandLineOption callPathOpt(QStringLiteral("call-path"),
                                   QStringLiteral("调用的对象路径"),
                                   QStringLiteral("path"), QString());
    QCommandLineOption callSigOpt(QStringLiteral("call-sig"),
                                  QStringLiteral("调用的参数签名"),
                                  QStringLiteral("sig"), QString());
    QCommandLineOption callArgsOpt(QStringLiteral("call-args"),
                                   QStringLiteral("调用的参数（JSON 数组，每项为字符串）"),
                                   QStringLiteral("json"), QStringLiteral("[]"));
    parser.addOption(busOpt);
    parser.addOption(serviceOpt);
    parser.addOption(darkOpt);
    parser.addOption(demoOpt);
    parser.addOption(demoSeedOpt);
    parser.addOption(demoMethodOpt);
    parser.addOption(expandJsonOpt);
    parser.addOption(shotOpt);
    parser.addOption(delayOpt);
    parser.addOption(dumpOpt);
    parser.addOption(callOpt);
    parser.addOption(callDestOpt);
    parser.addOption(callPathOpt);
    parser.addOption(callSigOpt);
    parser.addOption(callArgsOpt);
    parser.process(app);

    Theme theme;
    if (parser.isSet(darkOpt))
        theme.setDark(true);
    // 应用启动时先让 DTK 的控件主题和 Sonde 自己的主题一致
    applyDtkTheme(theme);
    QObject::connect(&theme, &Theme::changed, &app, [&theme] { applyDtkTheme(theme); });

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
    engine.rootContext()->setContextProperty(QStringLiteral("demoSeed"),
                                            parser.value(demoSeedOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("demoMethod"),
                                            parser.value(demoMethodOpt));
    engine.rootContext()->setContextProperty(QStringLiteral("jsonExpanded"),
                                            parser.isSet(expandJsonOpt));

    engine.load(QUrl::fromLocalFile(QStringLiteral(SONDE_QML_DIR) + QStringLiteral("/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "QML 加载失败，检查目录:" << QStringLiteral(SONDE_QML_DIR);
        return 2;
    }

    if (parser.isSet(callOpt)) {
        // 无界面调用：走和界面表单完全相同的路径（typeTree 建节点树 → 填值 → call）
        const QString dotted = parser.value(callOpt);
        const int dot = dotted.lastIndexOf(QLatin1Char('.'));
        const QString iface = dot > 0 ? dotted.left(dot) : QString();
        const QString member = dot > 0 ? dotted.mid(dot + 1) : dotted;
        const QString sigStr = parser.value(callSigOpt);
        const QJsonArray plain =
            QJsonDocument::fromJson(parser.value(callArgsOpt).toUtf8()).array();

        QVariantList nodes = bridge->typeTree(sigStr);
        for (int i = 0; i < nodes.size() && i < plain.size(); ++i) {
            // 高级用法：如果传的就是节点对象（带 kind），直接用，方便测试复杂类型
            if (plain.at(i).isObject()
                && plain.at(i).toObject().contains(QStringLiteral("kind"))) {
                nodes[i] = plain.at(i).toObject().toVariantMap();
                continue;
            }
            QVariantMap n = nodes.at(i).toMap();
            n[QStringLiteral("text")] = plain.at(i).toVariant().toString();
            nodes[i] = n;
        }

        QObject::connect(bridge, &Bridge::callFinished, &app,
                         [](quint64, const QVariantMap &res) {
                             QTextStream out(stdout);
                             out << QJsonDocument::fromVariant(res)
                                        .toJson(QJsonDocument::Indented)
                                 << Qt::flush;
                             QGuiApplication::quit();
                         });
        const QString dest = parser.value(callDestOpt);
        const QString path = parser.value(callPathOpt);
        const QString busName = parser.value(busOpt);
        QTimer::singleShot(300, &app, [bridge, busName, dest, path, iface, member, sigStr, nodes] {
            bridge->call(busName, dest, path, iface, member, sigStr, nodes);
        });
    }

    if (parser.isSet(dumpOpt)) {
        QTimer::singleShot(1500, &app, [tree] {
            const QVariantList rows = tree->rows();
            qInfo().noquote() << "focusId =" << tree->focusId();
            for (const QVariant &v : rows) {
                const QVariantMap m = v.toMap();
                qInfo().noquote() << QString(m.value(QStringLiteral("depth")).toInt() * 2,
                                             QLatin1Char(' '))
                                         << m.value(QStringLiteral("kind")).toString()
                                         << m.value(QStringLiteral("id")).toString()
                                         << QStringLiteral("|")
                                         << m.value(QStringLiteral("name")).toString();
            }
            QGuiApplication::quit();
        });
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
