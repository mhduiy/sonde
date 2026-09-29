# Sonde

> D-Bus 观察台 —— 一条时间线上的全量消息流 + 签名驱动的参数编辑器。

**Sonde**（法语"探针"）是一个 D-Bus 调试工具。它要解决 d-feet / d-spy 那两个绕不过去的
毛病：**看不了事件流**，**写不对参数**。

现有工具的根因是同一个：它们把 D-Bus 建模成"一棵可以点的树"，于是信号、属性变更、
调用时序这些**流动的东西**只能硬塞进树节点。Sonde 反过来——把**一条 D-Bus 消息**当作一等公民。

---

## 三个核心能力

| 能力 | 说明 |
|---|---|
| **Monitor-first** | 默认视图就是一条统一的消息流：方法调用、返回、错误、信号、属性变更全在一条时间线上，可过滤、可暂停、可清空。 |
| **签名驱动的参数编辑器** | 参数表单由 D-Bus 签名**生成**，你不用手写 `a{sv}`。数组/字典用 ＋/－ 增删，变体可改内层类型。 |
| **捕获即模板** | 看到任何一条真实调用，都能照着它的签名把参数补出来发出去（详见路线图里的"复用为调用"）。 |

外加 d-spy 对等的**总线浏览**：名字列表 → 内省 → 接口/方法/信号/属性全展开，点方法直接跳到调用面板。

---

## 架构

```
rustcore/                Rust 核心：zbus + zvariant（纯 Rust 的 D-Bus 栈，不依赖 libdbus）
  src/sig.rs             签名 ⇄ 类型树 ⇄ zvariant Value 的双向转换
  src/lib.rs             监控线程 + 工作线程 + 稳定的 C ABI
        ↓  只让字符串跨越 FFI 边界（JSON 节点），不留任何生命周期风险
ui/                      Qt 6.8 + QML
  bridge.cpp/h           Rust ↔ QML 的桥；内省 XML 解析
  messagemodel.cpp/h     环形缓冲 + 批量插入的消息模型 + 过滤代理
  qml/main.qml           消息流 + 标签页
  qml/DetailPane.qml     选中消息的完整类型化解码
  qml/BrowserPane.qml    总线浏览
  qml/CallPane.qml       签名驱动参数编辑器 + 调用
```

### 为什么是 Rust 引擎 + Qt 界面

这是个**运行时才知道类型**的应用（要显示任意一条消息的参数），所以最难的部分是
**动态类型系统**。zvariant 是 spec 完整的动态类型系统（签名解析、值树、变体嵌套、
fd、wire 编解码），在 Rust 里是免费的；QtDBus 是静态 marshal 的客户端库，做通用检查器
要手写这一整套。反过来，界面这块 Qt/QML 在 UOS/DDE 上是原生的，且签名驱动的递归表单
用 QML 写最省事。所以：**引擎用 Rust，界面用 Qt**。

### FFI 契约

只传字符串。一条消息序列化成这样的递归节点：

```json
{ "sig": "a{sv}", "kind": "dict", "text": "", "items": [ { "label": "...", "key": {...}, "val": {...} } ] }
```

`kind` ∈ bool/u8/i16/u16/i32/u32/i64/u64/f64/str/path/sig/fd/variant/array/dict/struct。
**解码和编码共用同一套形状**——Rust 用它向下给界面，界面的表单也用它向上给 Rust。

C ABI 共 10 个符号，全部在 `nm` 下可见：
`sonde_core_new/free`、`sonde_version`、`sonde_type_tree`、`sonde_list_names`、
`sonde_introspect`、`sonde_call`、`sonde_monitor_start/stop`、`sonde_string_free`。

### 线程规则（硬性）

Rust 的三个线程：工作线程（调用/内省）、监控线程（收消息）。
两者都**绝不直接碰 QObject**，一律通过 `Qt::QueuedConnection` 投递回 GUI 线程。
监控回调按 **256 条 / 80ms** 批量下发，界面侧一次 `beginInsertRows` 完成——这是高频流不卡的前提。

---

## 实测结论（不是推测，是在 UOS Desktop 25 上跑出来的）

| 场景 | 结果 |
|---|---|
| session 总线监控 | ✅ **全量**：`BecomeMonitor` 直接成功，方法调用/返回/信号全可见 |
| system 总线监控（非 root） | ⚠️ `BecomeMonitor` 被策略拒绝，**自动降级为仅监听广播信号** |
| 降级后能看到什么 | ✅ 能收到真实广播信号，例如 `fi.w1.wpa_supplicant1.Interface.EAP`、`PropertiesChanged` |
| 降级后看不到什么 | ❌ **进程之间的方法调用与返回**（单播消息不会送到你的连接） |
| 调用链路 | ✅ 端到端验证：QML 表单 → C ABI → zbus → 总线 → 应答解码回显 |

> 对照实验：`dbus-monitor --system "type='signal',sender='org.freedesktop.DBus'"`
> 在 8 秒窗口内只抓到 **1** 条广播信号。所以系统总线上广播信号本来就稀疏，
> 降级模式下数量少是**事实**而非缺陷。

**要拿到系统总线全量监控，只有两条路：**
1. 安装一个 D-Bus 策略文件 `/usr/share/dbus-1/system.d/<app>.conf`，
   给指定用户/组放行 `send_interface="org.freedesktop.DBus.Monitoring"`；
2. 监控进程提权运行（polkit）。

这也意味着：如果 Sonde 主打系统总线监控，**玲珑（linglong）沙箱可能与系统级策略文件冲突**，
交付形式需要单独决策。

---

## 构建与运行

依赖：Qt 6.8（base + declarative + tools，Debian 系还要 `qt6-base-dev` 的 QuickControls2）、
Rust 工具链、cmake + ninja。本机全部已具备。

```bash
./build.sh                # 或见下
cd rustcore && cargo build --release
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/sonde             # 图形界面；点"开始监听"
```

### 命令行

```
--bus session|system      启动后自动监听的总线
--tab 0|1|2               初始标签页（0=详情 1=浏览 2=调用）
--select-first            自动选中一条参数最丰富的消息
--demo-call               自动发一次调用
--screenshot <path>       渲染一帧保存 PNG 后退出
--screenshot-delay <ms>   截图前等待毫秒数
```

后四个是自检/截图用的，方便在无显示环境（`QT_QPA_PLATFORM=offscreen`）里回归。

### 过滤语法

空格分隔即 AND，支持字段前缀；未知字段自动退回全域搜索：

```
type:signal  iface:org.freedesktop.DBus  member:PropertiesChanged  path:/org/foo  sender::1.42
```

---

## 已知限制与路线图

**当前没做的：**
- **收藏夹**（保存调用模板）——设计已想好，未实现。
- **"复用为调用"**——从消息流里右键一条消息，一键把它的签名和参数灌进调用面板。这是
  Monitor-first 真正的杀手锏，也是下一步第一件事。
- **发送 fd（`h` 类型）**——解码显示已支持，发送暂未实现（需要管好 fd 所有权）。
- **重新开始监听时的竞态**：旧监控线程要等收到下一条消息才会看到停止标志，切换总线后
  可能短暂收到旧总线的消息。
- **`listNames` / `introspect` 是同步调用**，卡在 GUI 线程上（通常很快，但慢服务会卡界面）。

**打包：** 目前 QML 从源码目录加载（`SONDE_QML_DIR`），开发期改完即生效。
正式打包需要 `qt_add_qml_module` + qrc 固化，并决定 deb（可装策略文件）还是玲珑。
