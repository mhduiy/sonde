#include "theme.h"

#include <QSettings>

namespace {

struct Palette {
    QColor bg, surface, surfaceAlt, border, borderStrong;
    QColor text, textDim, textFaint;
    QColor accent, accentSoft, accentText, selected, hover, pressed;
    QColor ok, warn, error;
    QColor valStr, valNum, valBool, valFd;
    QColor chipCall, chipRet, chipSignal, chipError;
};

const Palette &lightPalette()
{
    static const Palette p = [] {
        Palette p;
        p.bg = QColor("#f6f7f9");
        p.surface = QColor("#ffffff");
        p.surfaceAlt = QColor("#f0f2f5");
        p.border = QColor("#e3e6eb");
        p.borderStrong = QColor("#c9d0d9");

        p.text = QColor("#1c2024");
        p.textDim = QColor("#5c6672");
        p.textFaint = QColor("#98a1ad");

        p.accent = QColor("#2563eb");
        p.accentSoft = QColor("#e8f0fe");
        p.accentText = QColor("#ffffff");
        p.selected = QColor("#dbeafe");
        p.hover = QColor("#eef2f7");
        p.pressed = QColor("#e2e8f0");

        p.ok = QColor("#12864a");
        p.warn = QColor("#a15c07");
        p.error = QColor("#d1242f");

        p.valStr = QColor("#0a6b4a");
        p.valNum = QColor("#9a5b06");
        p.valBool = QColor("#6b21a8");
        p.valFd = QColor("#0e7490");

        p.chipCall = QColor("#1d4ed8");
        p.chipRet = QColor("#a15c07");
        p.chipSignal = QColor("#15803d");
        p.chipError = QColor("#b91c1c");
        return p;
    }();
    return p;
}

const Palette &darkPalette()
{
    static const Palette p = [] {
        Palette p;
        p.bg = QColor("#0f1216");
        p.surface = QColor("#161b21");
        p.surfaceAlt = QColor("#1b2229");
        p.border = QColor("#252d36");
        p.borderStrong = QColor("#39434e");

        p.text = QColor("#e6edf3");
        p.textDim = QColor("#8b949e");
        p.textFaint = QColor("#5c6672");

        p.accent = QColor("#58a6ff");
        p.accentSoft = QColor("#16263a");
        p.accentText = QColor("#0d1117");
        p.selected = QColor("#1f3a5f");
        p.hover = QColor("#1c242b");
        p.pressed = QColor("#232c35");

        p.ok = QColor("#3fb950");
        p.warn = QColor("#d29922");
        p.error = QColor("#f85149");

        p.valStr = QColor("#7ee787");
        p.valNum = QColor("#ffa657");
        p.valBool = QColor("#d2a8ff");
        p.valFd = QColor("#79c0ff");

        p.chipCall = QColor("#79c0ff");
        p.chipRet = QColor("#ffa657");
        p.chipSignal = QColor("#7ee787");
        p.chipError = QColor("#ff7b72");
        return p;
    }();
    return p;
}

} // namespace

Theme::Theme(QObject *parent)
    : QObject(parent)
{
    QSettings s;
    m_dark = s.value(QStringLiteral("ui/dark"), false).toBool();
}

void Theme::setDark(bool d)
{
    if (m_dark == d)
        return;
    m_dark = d;
    QSettings s;
    s.setValue(QStringLiteral("ui/dark"), d);
    emit changed();
}

#define SONDE_COLOR(name)                                       \
    QColor Theme::name() const                                  \
    {                                                           \
        return (m_dark ? darkPalette() : lightPalette()).name;  \
    }

SONDE_COLOR(bg)
SONDE_COLOR(surface)
SONDE_COLOR(surfaceAlt)
SONDE_COLOR(border)
SONDE_COLOR(borderStrong)
SONDE_COLOR(text)
SONDE_COLOR(textDim)
SONDE_COLOR(textFaint)
SONDE_COLOR(accent)
SONDE_COLOR(accentSoft)
SONDE_COLOR(accentText)
SONDE_COLOR(selected)
SONDE_COLOR(hover)
SONDE_COLOR(pressed)
SONDE_COLOR(ok)
SONDE_COLOR(warn)
SONDE_COLOR(error)
SONDE_COLOR(valStr)
SONDE_COLOR(valNum)
SONDE_COLOR(valBool)
SONDE_COLOR(valFd)
SONDE_COLOR(chipCall)
SONDE_COLOR(chipRet)
SONDE_COLOR(chipSignal)
SONDE_COLOR(chipError)

#undef SONDE_COLOR
