# Sonde

> D-Bus 观察台 —— 像 d-spy 一样浏览，但要顺手得多。

**Sonde**（法语"探针"）是一个 D-Bus 调试工具。

**主界面是浏览**：服务 → 对象路径 → 接口 → 方法/信号/属性，层层展开。
**监听是附属**：折叠在底部的一条面板里，靠右键「加入监听列表」把它拉起来。
**浅色为主**，右上角一键切深色。

---

## 界面结构

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Sonde — D-Bus 观察台   总线 [session▾]  监听中 · 59          ☰(主题/关于) │ ← DTK 标题栏
├──────────────┬────────────────────────────────────┬─────────────────────┤
│ 服务         │ 对象树                              │ 详情                │
│ [搜索服务名] │                                     │                     │
│ :1.1    唯一 │ ▾ PATH /                            │ METHOD  ReleaseName │
│ :1.102  唯一 │   ▾ IFACE org.freedesktop.DBus      │ / · org.… . Release │
│ org.foo 已知 │     ▸ METHOD Hello        () → (s)  │ 参数（s）           │
│ …      ⟳     │     ▸ METHOD ReleaseName  (s) → (u) │ [0] [___________]   │
│              │     ▸ METHOD ListNames    () → (as) │ [发送调用]          │
│              │     ▸ SIGNAL NameAcquired (s)       │                     │
├──────────────┴────────────────────────────────────┴─────────────────────┤
│ ▾ 监听 [开始/停止监听] [过滤: svc:org.foo prop:Opacity ✕]     显示/收到 ⋯ │
│ 17:05:00 SIGNAL :1.102 →（广播） org.…Properties PropertiesChanged Opacity=0.5│
│ 17:05:00 CALL   :1.9 → org.freedesktop.DBus GetNameOwner  "com.deepin.wm"  │
└──────────────────────────────────────────────────────────────────────────┘
```

### 怎么用

1. 左边**搜索 + 点一个服务** → 中间树会**自动定位到与服务名对应的对象路径**
   （`org.deepin.dde.Timedate1` → `/org/deepin/dde/Timedate1`），并且把它自己的接口一起展开，
   方法/信号/属性直接就在眼前。不用在几十个兄弟对象里翻找。
2. 中间**单击**选中；**双击**有子节点的就展开/收起，双击属性就直接读值。
   **方法的参数直接写在签名括号里并带名字**（`List (ty: s) → (list: s)`），
   参数用一种颜色、返回值用另一种，不展开也能看清签名；参数不再额外生成子节点。
3. **点一个方法** → 右边出现签名驱动的参数表单，填完「发送调用」。
   参数是**记录形态**时（`a{ss}` / `a{sd}` 这类字典，或"字段全是标量"的结构体数组）
   会自动改用**可编辑表格**：表头是列名，每行一个条目，「＋ 加一行」「✕」增删，
   单元格直接改。嵌套的复杂结构继续走行式编辑器。
4. **点（或双击）一个属性** → 右边读出当前值；可设「定时读取」轮询；
   属性可写时还会出现写入表单（走 `Properties.Set`，写完自动回读确认）
5. **右键任意节点** → 「加入过滤条件」，条件会**追加到底部的过滤框**里。
   监听面板不再有"监听列表"——只有这一个过滤框
6. 底部消息**点一下**可以看它的完整解码内容，还能一键「监听这条消息的来源」
7. 消息行里 **sender / 接收者可以直接点**，跳到那个服务的对象树
   （接收者为空时显示「（广播）」，因为信号大多是广播的）

**返回值里的 JSON 会被自动识别并当作结构化数据**：很多接口（例如
`org.deepin.dde.Appearance1.List("icon")` 返回 20 个图标主题）把 JSON 塞在字符串里返回。
Sonde 认出来之后给一组页签，并**自动挑一个默认页签**：

| 页签 | 什么时候可用 | 内容 |
|---|---|---|
| **图片** | 值是图片路径或 `file://` URI | 直接预览（`PreserveAspectFit`），显示像素尺寸，`复制路径` |
| **表格** | 数组里全是对象 / 对象里全是标量 | 真正的列，可横向滚动；**单元格是图片路径就给缩略图**，`复制` 导出制表符分隔文本 |
| **JSON** | 内容是合法 JSON | 带行号 + 语法高亮的代码视图，可选中复制 |
| **文本** | 总是 | 原始字符串 |

D-Bus 的 `struct` → JSON 数组、`dict` → JSON 对象，所以 `a{sv}` / `a(...)`
这类返回值同样进表格——`Properties.GetAll` 出来就是一张属性表。
两个方向都能滚、都能选中复制，「放大」可以开到全屏。

左侧服务列表：已知服务排在前面，`:1.x` 这类唯一名排到最后。

**控件与窗口用 DTK（Deepin Tool Kit）原生样式**：窗口是 `D.ApplicationWindow`，
标题栏是 `D.TitleBar`——总线选择就放在标题栏左侧，主题切换用它**内置的菜单**
（浅色 / 深色 / 跟随系统，`ThemeMenu`），所以 Sonde 不再自己做主题按钮。
按钮、下拉框、输入框、开关、复选框都是 DTK 观感；Sonde 自绘的部分
（对象树、表格、消息流）通过监听 `DGuiApplicationHelper::paletteTypeChanged`
跟随 DTK 的深浅色，两边不会脱节。

构建时 `pkg-config` 找到 `dtk6gui` 就自动链接；没装 DTK 也能构建，会回退到 Qt 默认样式
（此时标题栏用回 Qt 的 ToolBar，主题开关只能用命令行的 `--dark` / `--light`）。

各面板标题栏上的按钮：

| 位置 | 按钮 | 作用 |
|---|---|---|
| 服务 | 搜索框 | 按名字过滤服务（就在服务列表正上方） |
| 对象树 | 过滤本树 | 只显示匹配的节点及其祖先，自动展开 |
| 对象树 | **定位** | 重新跳到与服务名对应的对象路径 |
| 对象树 | **精简** | 隐藏 `org.freedesktop.DBus.*` 标准接口（默认开） |
| 对象树 | 展开 / 折叠 / ⟳ | 整棵树展开、折叠、重新内省 |
| 监听面板 | **开始监听 / 停止监听** | 收发开关（在监听面板上，不在主工具栏） |
| 监听面板 | 只看监听列表 | 只显示命中监听列表的消息 |
| 监听面板 | 暂停 / 清空消息 | 暂停（消息进缓冲不丢）和清空 |

### 右键能干什么

| 节点 | 菜单项 |
|---|---|
| 服务 | 打开 / 加入过滤条件（`svc:名字`）/ 复制名字 |
| 路径 | 加入过滤条件（`path:路径`）/ 展开 / 复制路径 |
| 接口 | 加入过滤条件（`iface:接口`）/ 复制接口名 |
| 方法 | 加入过滤条件（`iface:X member:Y`）/ 复制「接口.成员」 |
| 信号 | 同方法 / 复制 |
| 属性 | 加入过滤条件（`type:signal prop:Name`）/ **读取该属性** |

### 过滤语法

空格分隔的多个条件，**全部命中才显示**（AND）。`字段:值` 里的值是**子串**匹配；
不带字段名则在全部内容（含一行摘要）里找。

| 字段 | 含义 |
|---|---|
| `type` | `method_call` / `method_return` / `signal` / `error` |
| `iface` | 接口名 |
| `member` | 成员名 |
| `path` | 对象路径 |
| `sender` / `dest` | 发送者 / 接收者 |
| `svc` | 发送者**或**接收者 |
| `prop` | 属性名（匹配一行摘要，两种信号风格都能覆盖） |
| `sig` | 签名 |

例：`svc:org.deepin.dde.Appearance1 prop:Opacity`

---

## 架构

```
rustcore/                Rust 引擎（zbus + zvariant，纯 Rust D-Bus 栈）
  src/sig.rs             签名 ⇄ 类型树 ⇄ zvariant Value 双向转换
  src/lib.rs             监控线程 + 工作线程 + 10 个 C ABI 符号
        ↓  只让字符串跨越 FFI 边界（JSON 节点）
ui/                      Qt 6.8 + QML
  theme.cpp/h            语义化调色板，浅色/深色，QSettings 持久化
  objecttree.cpp/h       懒加载内省树（按需拉 XML，拍平成可见行给 QML）
  bridge.cpp/h           Rust ↔ QML 桥、监听列表与匹配、内省 XML 解析、属性读取
  messagemodel.cpp/h     环形缓冲 + 批量插入的流式消息模型
  qml/main.qml           外壳 + 工具栏 + 三栏浏览 + 底部监听面板
  qml/ServicePane.qml    左：服务
  qml/TreePane.qml       中：对象树（主体）
  qml/DetailPane.qml     右：详情 / 调用 / 读取属性
  qml/CallForm.qml       签名驱动的参数编辑器
  qml/WatchPane.qml      底：监听列表 + 实时流
  qml/MessagePopup.qml   单条消息的完整解码
  qml/kinds.js           类型配色与标签
  qml/Clip.qml           剪贴板
```

### 几个关键设计决定

**为什么 QML 收到的是"拍平的行"而不是树模型。**
QML 不允许组件自我实例化，递归树渲染器会直接报错；而且大结构下递归组件很慢。
所以 `ObjectTree` 在 C++ 侧把树按当前展开状态拍平成 `[{depth, kind, name, detail, …}]`，
QML 用一个 `ListView` 加缩进渲染。展开/折叠完全由自己掌控，没有 `QAbstractItemModel`
树模型的那些坑。

**为什么 `property var` 要用 JSON 往返，以及 delegate 只能拿 index。**

这一类坑踩了两次，都是"界面看起来填了、实际没发出去"：

1. QML 里 `property var` 持有**从 C++ 返回的** `QVariantList` 时，元素访问得到的是
   **临时副本**，`nodes[0].text = x` 静默写不回去。所以来自 Rust 的节点先过一遍
   `JSON.parse(JSON.stringify(...))` 变成纯 JS 结构。
2. 更隐蔽的一次：QML 把 JS 数组的元素交给 `Repeater` 的 delegate 时，
   `modelData` 同样是**副本**。参数编辑器原来写 `modelData.node.text = text`，
   于是界面上明明填了参数、发出去却是空的——用 `dbus-monitor` 抓包才看出来。
   现在 delegate 只拿 `index`，通过 `rowAt(index)` 实时取真正的行对象、
   用 `setRowText(index, ...)` 写回。

**线程规则（硬性）。** Rust 的监控线程和工作线程绝不直接碰 QObject，
一律 `Qt::QueuedConnection` 投递回 GUI 线程。监控回调按 **256 条 / 80ms** 批量下发，
界面侧一次 `beginInsertRows` 完成。

**主题。** 所有颜色绑定到 `theme.xxx`，切主题只改一个 bool；同时把主题映射到
Qt 控件的 `QPalette`，所以原生 `TextField`/`Button`/`ComboBox` 会自动跟着变。

---

## 实测中发现的两个真实世界问题

这两个都是跑起来才发现的，光看代码不会知道：

### 1. UOS 的 dbus-daemon 不按规范返回内省树

在 `/` 上它返回的是：

```xml
<node>
  <interface name="org.freedesktop.DBus">…</interface>
  <interface name="org.freedesktop.DBus.Introspectable">…</interface>
  <interface name="org.freedesktop.DBus.Peer">…</interface>
  <node name="org/freedesktop/DBus"/>   <!-- 节点名里塞了整条路径！ -->
</node>
```

也就是说它**每个祖先路径都重复报告一遍总线驱动的接口**（`/`、`/org`、
`/org/freedesktop` 都返回 `org.freedesktop.DBus`）。

对应两个处理：

- `bridge.cpp` 的内省解析**跟踪 `<node>` 嵌套深度**，只认根节点的直接子元素，
  并且把 `name="org/freedesktop/DBus"` 这样的多段名**拆成逐级路径节点**
- `objecttree.cpp` 里，如果某路径的接口集合与父路径**完全相同**，就判定为"继承来的"，
  不再重复显示——这样树不会被同一批接口刷三遍

### 2. 系统总线上非 root 拿不到 `BecomeMonitor`

```
dbus-monitor: unable to enable new-style monitoring:
  AccessDenied ... interface="org.freedesktop.DBus.Monitoring" member="BecomeMonitor"
  Falling back to eavesdropping.
```

| 场景 | 结果 |
|---|---|
| session 总线 | ✅ 全量：方法调用/返回/信号全可见 |
| system 总线（非 root） | ⚠️ 自动降级为**仅监听广播信号**，并在界面顶部给出明确提示 |
| 降级后能看到 | ✅ 真实广播信号（`wpa_supplicant` 的 `EAP`、`PropertiesChanged`…） |
| 降级后看不到 | ❌ 进程之间的方法调用与返回（单播消息不会送到你的连接） |

对照实验：`dbus-monitor --system` 用匹配规则订阅，8 秒只抓到 **1** 条广播信号——
所以降级模式下数量少是**事实**而非缺陷。

要拿全量系统总线监控只有两条路：装 D-Bus 策略文件
（`/usr/share/dbus-1/system.d/<app>.conf` 放行 `org.freedesktop.DBus.Monitoring`）
或提权运行。这也意味着**主打系统总线监控的话，玲珑沙箱与系统级策略文件存在冲突**，
交付形式要单独决策。

### 3. 一个服务背后可能挂了几十个对象

`org.deepin.dde.Timedate1` 的背后是同一个 deepin daemon 进程，它在
`/org/deepin/dde/` 下同时挂了几十个对象（`Audio1`、`Bluetooth1`、`Display1`、
`TrayManager1`…）。用户点 Timedate1 时，如果只从 `/` 开始展开，要翻过二十多个
兄弟节点才能找到真正想看的方法。

处理办法是**按约定自动定位**：服务名 `a.b.c` 对应对象路径 `/a/b/c`，
选服务时沿这条路径逐级展开（路径对不上就停在能到达的那一级，并回退到通用的
单链展开）。到达之后再把该对象**自己的接口**一并展开，于是方法立刻可见。

这也是 `--dump-tree` 存在的原因——树结构对不对，肉眼数一遍行比看截图快。

### 4. 到达对象后展开什么，得看它下面有什么

自动定位到对象之后，一开始我无脑展开"这个对象自己的接口"，结果
`org.freedesktop.Accounts` 出问题了：接口一展开就是 8 个方法 + 2 个信号 + 4 个属性，
把真正想看的 `User1000`…`User1008` 全挤到可视区域下面——用户以为"看不到用户账号"，
其实是在折叠线以下。

现在的规则按对象形态决定：

- **下面还有子路径**（如 `/org/freedesktop/Accounts` 底下一堆 `User*`）→
  子对象才是主体，接口**保持折叠**
- **没有子路径**（叶子对象，如 `/org/deepin/dde/Timedate1`）→
  展开它自己的接口，让方法直接可见

### 5. 还没加载的节点也要显示"可展开"

`org.deepin.dde.Accounts1` 的 `User1000`…`User23915` 一开始全都"点不开"：
行上没有展开箭头，双击也没反应。

原因是懒加载的副作用——`hasChildren` 是按"children 非空"算的，
而没加载过的节点 children 当然是空的；而双击处理器里我又写了
`else if (row.hasChildren) toggle(...)`，于是双击直接被短路掉了。

两处都改掉：**未加载的 path 节点乐观地认为可展开**（先给箭头），
双击/点箭头只排除 `arg` 节点，不再看 `hasChildren`。

### 6. 双标题栏：`D.DWindow.enabled` 才是那条开关

用 `D.ApplicationWindow` + `header: D.TitleBar` 之后，实机上出现了**两条标题栏**——
DDE 的窗口框架画一条，DTK 的 TitleBar 又画一条。

原因是我只换了窗口类型，没告诉窗口管理器"这个窗口自己画标题栏"。
参照 `dde-control-center` 的 `src/dde-control-center/plugin/DccWindow.qml`，
它有这么几项是必需的：

```qml
D.ApplicationWindow {
    D.DWindow.enabled: true          // ← 关键：让 DDE 不再画自己的标题栏
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint
           | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
    color: "transparent"             // 背景（圆角/阴影）交给 DTK 画
    D.StyledBehindWindowBlur { anchors.fill: parent; control: root }
    D.TitleBar { embedMode: false; autoHideOnFullscreen: true; focus: true }
}
```

`D.DWindow.enabled: true` 会让 DTK 去给窗口设置 "NoTitlebar"。离屏渲染没有窗口管理器时
会打印 `Failed to enable NoTitlebar for the window`——**这条日志本身就是机制生效的证据**，
实机上会设置成功，于是只剩 DTK 那一条标题栏。

### 7. 我把 JSON 显示改回退了

`ValueOutput` 里为了让"文本"页签显示原文，我把 `jsonText` 写成了用**字符串原文**。
但 deepin 接口返回的是**压缩 JSON**（没有换行缩进），于是 JSON 页签变成挤成一行、
行号只有 1 —— 看起来就像"JSON 被我改坏了"。

正确做法：结构化视图（JSON 页签）用 `JSON.stringify(parsed, null, 4)` 重新格式化，
只有"文本"页签才用原文。同一个数据，两个页签各取所需。

### 8. 长 JSON 没有滚动条

两个原因叠在一起：

1. `ValueOutput` 的 `StackLayout` 上同时写了 `Layout.fillHeight: true` 和
   `Layout.preferredHeight`。在 `DetailPane` 的外层 ScrollView 里，`fillHeight`
   把它撑到了内容高度，内层 `ScrollView` 于是没有可滚区间。
2. `ScrollView` 附着的 `ScrollBar` 在内容超宽（`NoWrap` 的代码行很长）时**位置不可靠**，
   会跑到内容左边去。

改法：`StackLayout` 只保留有界的 `preferredHeight`/`maximumHeight`；`CodeView`
换成「`Flickable` + 自己摆的 `ScrollBar`」，位置、尺寸、常显都由自己控制
（纵向常显，横向按需）。

---

依赖：Qt 6.8（含 QuickControls2）、Rust 工具链、cmake + ninja。

```bash
./build.sh
./build/sonde
```

### 命令行

```
--bus session|system    要监听的总线（默认 session）
--service <dest>        启动时自动打开的服务
--dark                  切到深色主题（走 DTK 的 setPaletteType）
--light                 切到浅色主题（走 DTK 的 setPaletteType）
--demo                  自检：监听 + 打开服务 + 加一条监听 + 选个方法/属性真跑一次
--demo-method <name>    自检时优先选中的方法或属性名
--demo-seed <value>     自检时给第一个字符串参数填的值
--expand-json           JSON 值默认展开（自检/截图用）
--force-tab <name>      强制输出页签 image|table|json|text（自检/截图用）
--size <WxH>            初始窗口尺寸，例如 1000x640（自检/截图用）
--filter <query>        启动时设置过滤条件并开始监听（自检用）
--dump-tree             打印对象树的行（id/kind/name/depth）后退出，调试树结构用
--screenshot <path>     渲染一帧保存 PNG 后退出
--screenshot-delay <ms> 截图前等待毫秒数
```

### 无界面调用（可脚本化）

```bash
# 读属性
./build/sonde --call org.freedesktop.DBus.Properties.Get \
  --call-dest org.deepin.dde.Appearance1 --call-path /org/deepin/dde/Appearance1 \
  --call-sig ss --call-args '["org.deepin.dde.Appearance1","IconTheme"]'

# 调方法
./build/sonde --call org.deepin.dde.Appearance1.List \
  --call-dest org.deepin.dde.Appearance1 --call-path /org/deepin/dde/Appearance1 \
  --call-sig s --call-args '["icon"]'
```

结果以 JSON 打到 stdout。`--call-args` 里如果传的是带 `kind` 的对象，
会被当作节点树直接使用（用来测 `a{sv}` / `v` 这类复杂类型）。
设置环境变量 `SONDE_DEBUG_CALL=1` 可以把每次调用的实际参数 JSON 打到 stderr——
排查"参数到底发出去没有"很有用。

`--demo` 是为无显示环境（`QT_QPA_PLATFORM=offscreen`）回归准备的，
一条命令就能把浏览、监听、调用三条链路全走一遍。

---

## 已知限制与路线图

- **收藏夹**：保存常用调用模板，未实现
- **"复用为调用"**：从消息流里把一条真实消息的签名和参数一键灌进调用面板
- **发送 fd（`h`）**：解码显示已支持，发送未实现（要管好 fd 所有权）
- **内省是同步调用**：卡在 GUI 线程上，慢服务会短暂冻结界面
- **切换总线时旧监控线程的竞态**：旧线程要等收到下一条消息才看到停止标志
- **打包**：QML 目前从源码目录加载（`SONDE_QML_DIR`），正式发布要
  `qt_add_qml_module` + qrc 固化
