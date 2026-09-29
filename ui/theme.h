#pragma once

#include <QColor>
#include <QObject>

/// 语义化调色板。界面里所有颜色都绑定到 `theme.xxx`，
/// 切换深浅色只改一个 bool，所有绑定自动重算。
///
/// 默认**浅色**，深色是可选。
class Theme : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)

public:
    explicit Theme(QObject *parent = nullptr);

    bool dark() const { return m_dark; }
    void setDark(bool d);

#define SONDE_COLOR(name)      \
    Q_PROPERTY(QColor name READ name NOTIFY changed) \
    QColor name() const;

    // 结构层
    SONDE_COLOR(bg)
    SONDE_COLOR(surface)
    SONDE_COLOR(surfaceAlt)
    SONDE_COLOR(border)
    SONDE_COLOR(borderStrong)

    // 文字层
    SONDE_COLOR(text)
    SONDE_COLOR(textDim)
    SONDE_COLOR(textFaint)

    // 交互层
    SONDE_COLOR(accent)
    SONDE_COLOR(accentSoft)
    SONDE_COLOR(accentText)
    SONDE_COLOR(selected)
    SONDE_COLOR(hover)
    SONDE_COLOR(pressed)

    // 语义色
    SONDE_COLOR(ok)
    SONDE_COLOR(warn)
    SONDE_COLOR(error)

    // 值的类型色
    SONDE_COLOR(valStr)
    SONDE_COLOR(valNum)
    SONDE_COLOR(valBool)
    SONDE_COLOR(valFd)

    // 消息类型徽标
    SONDE_COLOR(chipCall)
    SONDE_COLOR(chipRet)
    SONDE_COLOR(chipSignal)
    SONDE_COLOR(chipError)

#undef SONDE_COLOR

signals:
    void changed();

private:
    bool m_dark = false;
};
