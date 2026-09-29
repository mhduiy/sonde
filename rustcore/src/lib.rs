//! Sonde 的 D-Bus 引擎与稳定的 C ABI。
//!
//! 设计原则：
//! - **只让字符串跨越 FFI 边界。** 所有富类型都序列化成 JSON 节点（见 `sig` 模块），
//!   避免 C++/Rust 之间传递复杂结构体带来的生命周期与 ABI 风险。
//! - **监控与调用用两条连接。** `BecomeMonitor` 之后连接只剩"收"的能力，
//!   绝不能再用来发方法调用。
//! - **高频消息按批下发。** 监控线程累积到 256 条或 80ms 才回调一次，
//!   让界面侧可以一次性 `beginInsertRows`，而不是每条消息触发一次刷新。

mod sig;

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value as J};
use zbus::blocking::{Connection, MessageIterator};

/// 批量消息回调：`ctx` 由调用方透传，`json` 是消息数组，`count` 是消息条数。
pub type BatchCb = extern "C" fn(*mut c_void, *const c_char, u32);
/// 单次调用/查询的回调。
pub type ReplyCb = extern "C" fn(*mut c_void, *const c_char);

/// 把裸指针包成 Send，让我们可以把它交给工作线程。
#[derive(Clone, Copy)]
struct Ctx(*mut c_void);
unsafe impl Send for Ctx {}
unsafe impl Sync for Ctx {}

enum Cmd {
    ListNames {
        bus: String,
        reply: Sender<Result<String, String>>,
    },
    Introspect {
        bus: String,
        dest: String,
        path: String,
        reply: Sender<Result<String, String>>,
    },
    Call {
        bus: String,
        dest: String,
        path: String,
        iface: String,
        member: String,
        args_sig: String,
        args: J,
        cb: ReplyCb,
        ctx: Ctx,
    },
}

pub struct SondeCore {
    tx: Sender<Cmd>,
    monitor_stop: Arc<AtomicBool>,
}

// ---------------------------------------------------------------- 工具函数

fn cstring(s: String) -> *mut c_char {
    let clean = s.replace('\0', "");
    CString::new(clean)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

unsafe fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    CStr::from_ptr(p).to_string_lossy().into_owned()
}

fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

/// 把 C ABI 的实现体包起来，任何 panic 都转成结构化错误而不是杀死进程。
fn guard<F: FnOnce() -> String>(f: F) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(s) => cstring(s),
        Err(_) => cstring(json!({ "error": "Rust 核心内部 panic" }).to_string()),
    }
}

fn err_json(msg: &str) -> String {
    json!({ "ok": false, "error": msg }).to_string()
}

// ---------------------------------------------------------------- 消息编码

fn encode_message(m: &zbus::message::Message) -> J {
    let h = m.header();
    let ty = match h.message_type() {
        zbus::message::Type::MethodCall => "method_call",
        zbus::message::Type::MethodReturn => "method_return",
        zbus::message::Type::Error => "error",
        zbus::message::Type::Signal => "signal",
    };
    let args: Vec<J> = {
        let body = m.body();
        match body.deserialize::<zvariant::Structure>() {
            Ok(st) => st.fields().iter().map(sig::encode).collect(),
            Err(_) => Vec::new(),
        }
    };
    json!({
        "type": ty,
        "serial": h.primary().serial_num().get(),
        "sender": h.sender().map(|s| s.to_string()),
        "destination": h.destination().map(|d| d.to_string()),
        "path": h.path().map(|p| p.to_string()),
        "interface": h.interface().map(|i| i.to_string()),
        "member": h.member().map(|m| m.to_string()),
        "error": h.error_name().map(|e| e.to_string()),
        "signature": h.signature().to_string(),
        "timestamp_us": now_us(),
        "args": args,
    })
}

fn notice(level: &str, text: &str) -> J {
    json!({
        "type": "notice",
        "level": level,
        "serial": 0,
        "member": text,
        "signature": "",
        "timestamp_us": now_us(),
        "args": [],
    })
}

fn emit_batch(cb: BatchCb, ctx: Ctx, msgs: &[J]) {
    if msgs.is_empty() {
        return;
    }
    let payload = J::Array(msgs.to_vec()).to_string();
    if let Ok(c) = CString::new(payload.replace('\0', "")) {
        let _ = catch_unwind(AssertUnwindSafe(|| cb(ctx.0, c.as_ptr(), msgs.len() as u32)));
    }
}

// ---------------------------------------------------------------- 工作线程

fn get_conn<'a>(
    conns: &'a mut HashMap<String, Connection>,
    bus: &str,
) -> Result<&'a Connection, String> {
    if !conns.contains_key(bus) {
        let c = if bus == "system" {
            Connection::system()
        } else {
            Connection::session()
        }
        .map_err(|e| format!("连接 {bus} 总线失败: {e}"))?;
        conns.insert(bus.to_string(), c);
    }
    Ok(conns.get(bus).expect("刚插入"))
}

fn list_names(c: &Connection) -> Result<String, String> {
    let m = c
        .call_method(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            Some("org.freedesktop.DBus"),
            "ListNames",
            &(),
        )
        .map_err(|e| e.to_string())?;
    let body = m.body();
    let st: zvariant::Structure = body.deserialize().map_err(|e| e.to_string())?;
    let mut names: Vec<String> = Vec::new();
    if let Some(zvariant::Value::Array(a)) = st.fields().first() {
        for v in a.inner() {
            if let zvariant::Value::Str(s) = v {
                names.push(s.to_string());
            }
        }
    }
    names.sort();
    Ok(serde_json::to_string(&names).unwrap_or_else(|_| "[]".into()))
}

fn introspect(c: &Connection, dest: &str, path: &str) -> Result<String, String> {
    let m = c
        .call_method(
            Some(dest),
            path,
            Some("org.freedesktop.DBus.Introspectable"),
            "Introspect",
            &(),
        )
        .map_err(|e| e.to_string())?;
    let body = m.body();
    let st: zvariant::Structure = body.deserialize().map_err(|e| e.to_string())?;
    match st.fields().first() {
        Some(zvariant::Value::Str(s)) => Ok(s.to_string()),
        _ => Err("对象没有返回可用的内省 XML".into()),
    }
}

fn do_call(
    c: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
    member: &str,
    args_sig: &str,
    args: &J,
) -> String {
    let values = match sig::from_json_args(args_sig, args) {
        Ok(v) => v,
        Err(e) => return err_json(&e),
    };

    let reply = if values.is_empty() {
        c.call_method(Some(dest), path, Some(iface), member, &())
    } else {
        let mut b = zvariant::StructureBuilder::new();
        for v in values {
            b = b.append_field(v);
        }
        match b.build() {
            Ok(st) => c.call_method(Some(dest), path, Some(iface), member, &st),
            Err(e) => return err_json(&e.to_string()),
        }
    };

    match reply {
        Ok(m) => {
            let body = m.body();
            let sig_str = body.signature().to_string();
            match body.deserialize::<zvariant::Structure>() {
                Ok(st) => json!({
                    "ok": true,
                    "signature": sig_str,
                    "args": st.fields().iter().map(sig::encode).collect::<Vec<J>>(),
                })
                .to_string(),
                Err(e) => json!({
                    "ok": true,
                    "signature": sig_str,
                    "args": [],
                    "note": format!("返回体无法解码: {e}"),
                })
                .to_string(),
            }
        }
        Err(e) => err_json(&e.to_string()),
    }
}

fn worker(rx: mpsc::Receiver<Cmd>) {
    let mut conns: HashMap<String, Connection> = HashMap::new();

    while let Ok(cmd) = rx.recv() {
        match cmd {
            Cmd::ListNames { bus, reply } => {
                let r = match get_conn(&mut conns, &bus) {
                    Ok(c) => list_names(c),
                    Err(e) => Err(e),
                };
                let _ = reply.send(r);
            }
            Cmd::Introspect {
                bus,
                dest,
                path,
                reply,
            } => {
                let r = match get_conn(&mut conns, &bus) {
                    Ok(c) => introspect(c, &dest, &path),
                    Err(e) => Err(e),
                };
                let _ = reply.send(r);
            }
            Cmd::Call {
                bus,
                dest,
                path,
                iface,
                member,
                args_sig,
                args,
                cb,
                ctx,
            } => {
                let out = match get_conn(&mut conns, &bus) {
                    Ok(c) => do_call(c, &dest, &path, &iface, &member, &args_sig, &args),
                    Err(e) => err_json(&e),
                };
                if let Ok(c) = CString::new(out.replace('\0', "")) {
                    let _ = catch_unwind(AssertUnwindSafe(|| cb(ctx.0, c.as_ptr())));
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 监控线程

fn monitor_loop(bus: String, cb: BatchCb, ctx: Ctx, stop: Arc<AtomicBool>) {
    let conn = if bus == "system" {
        Connection::system()
    } else {
        Connection::session()
    };
    let conn = match conn {
        Ok(c) => c,
        Err(e) => {
            emit_batch(cb, ctx, &[notice("error", &format!("连接 {bus} 总线失败: {e}"))]);
            return;
        }
    };

    // 先尝试成为总线监视器，拿到全量消息（含方法调用与返回）
    let became_monitor = conn
        .call_method(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            Some("org.freedesktop.DBus.Monitoring"),
            "BecomeMonitor",
            &(&[] as &[&str], 0u32),
        )
        .is_ok();

    let mut iter = if became_monitor {
        MessageIterator::from(conn)
    } else {
        // 降级：只能收到广播信号。系统总线上非特权用户走的就是这条路。
        emit_batch(
            cb,
            ctx,
            &[notice(
                "warn",
                "无法成为总线监视器（权限不足），已降级为仅监听广播信号：\n\
                 方法调用与返回不可见。若需系统总线全量监控，请安装 D-Bus 策略文件或提权运行。",
            )],
        );
        match MessageIterator::for_match_rule(
            zbus::MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .build(),
            &conn,
            None,
        ) {
            Ok(i) => i,
            Err(e) => {
                emit_batch(cb, ctx, &[notice("error", &format!("降级监听失败: {e}"))]);
                return;
            }
        }
    };

    let mut buf: Vec<J> = Vec::with_capacity(256);
    let mut last = Instant::now();
    loop {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        match iter.next() {
            Some(Ok(m)) => buf.push(encode_message(&m)),
            Some(Err(_)) => continue,
            None => break,
        }
        if buf.len() >= 256 || last.elapsed() >= Duration::from_millis(80) {
            emit_batch(cb, ctx, &buf);
            buf.clear();
            last = Instant::now();
        }
    }
    emit_batch(cb, ctx, &buf);
}

// ---------------------------------------------------------------- C ABI

#[no_mangle]
pub extern "C" fn sonde_version() -> *mut c_char {
    cstring(env!("CARGO_PKG_VERSION").to_string())
}

#[no_mangle]
pub extern "C" fn sonde_core_new() -> *mut SondeCore {
    let (tx, rx) = mpsc::channel::<Cmd>();
    let _ = thread::Builder::new()
        .name("sonde-worker".into())
        .spawn(move || worker(rx));
    let core = SondeCore {
        tx,
        monitor_stop: Arc::new(AtomicBool::new(false)),
    };
    Box::into_raw(Box::new(core))
}

#[no_mangle]
pub extern "C" fn sonde_core_free(p: *mut SondeCore) {
    if p.is_null() {
        return;
    }
    let core = unsafe { Box::from_raw(p) };
    core.monitor_stop.store(true, Ordering::Relaxed);
    drop(core);
}

#[no_mangle]
pub extern "C" fn sonde_string_free(p: *mut c_char) {
    if !p.is_null() {
        unsafe {
            drop(CString::from_raw(p));
        }
    }
}

/// 由签名生成参数表单所需的类型树（JSON 数组）。
#[no_mangle]
pub extern "C" fn sonde_type_tree(sig_str: *const c_char) -> *mut c_char {
    guard(move || {
        let s = unsafe { cstr(sig_str) };
        match sig::type_tree(&s) {
            Ok(v) => v.to_string(),
            Err(e) => json!({ "error": e }).to_string(),
        }
    })
}

/// 列出总线上的所有名字（JSON 字符串数组）。
#[no_mangle]
pub extern "C" fn sonde_list_names(core: *mut SondeCore, bus: *const c_char) -> *mut c_char {
    guard(move || {
        if core.is_null() {
            return "[]".into();
        }
        let core = unsafe { &*core };
        let bus = unsafe { cstr(bus) };
        let (tx, rx) = mpsc::channel();
        if core.tx.send(Cmd::ListNames { bus, reply: tx }).is_err() {
            return "[]".into();
        }
        match rx.recv_timeout(Duration::from_secs(10)) {
            Ok(Ok(s)) => s,
            _ => "[]".into(),
        }
    })
}

/// 内省某个对象，返回**原始内省 XML**（由 Qt 侧解析成树）。
#[no_mangle]
pub extern "C" fn sonde_introspect(
    core: *mut SondeCore,
    bus: *const c_char,
    dest: *const c_char,
    path: *const c_char,
) -> *mut c_char {
    guard(move || {
        if core.is_null() {
            return String::new();
        }
        let core = unsafe { &*core };
        let (bus, dest, path) = unsafe { (cstr(bus), cstr(dest), cstr(path)) };
        let (tx, rx) = mpsc::channel();
        if core
            .tx
            .send(Cmd::Introspect {
                bus,
                dest,
                path,
                reply: tx,
            })
            .is_err()
        {
            return String::new();
        }
        match rx.recv_timeout(Duration::from_secs(15)) {
            Ok(Ok(s)) => s,
            Ok(Err(e)) => format!("<!-- {e} -->"),
            Err(_) => "<!-- 内省超时 -->".to_string(),
        }
    })
}

/// 发起一次方法调用。结果通过 `cb` 异步回传。
#[no_mangle]
pub extern "C" fn sonde_call(
    core: *mut SondeCore,
    bus: *const c_char,
    dest: *const c_char,
    path: *const c_char,
    iface: *const c_char,
    member: *const c_char,
    args_sig: *const c_char,
    args_json: *const c_char,
    cb: ReplyCb,
    ctx: *mut c_void,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        let core = unsafe { &*core };
        let (bus, dest, path, iface, member, args_sig) = unsafe {
            (
                cstr(bus),
                cstr(dest),
                cstr(path),
                cstr(iface),
                cstr(member),
                cstr(args_sig),
            )
        };
        let raw = unsafe { cstr(args_json) };
        let args: J = serde_json::from_str(&raw).unwrap_or_else(|_| json!([]));
        let _ = core.tx.send(Cmd::Call {
            bus,
            dest,
            path,
            iface,
            member,
            args_sig,
            args,
            cb,
            ctx: Ctx(ctx),
        });
    }));
}

/// 开始监听总线。0 = 成功启动，-1 = 失败。
#[no_mangle]
pub extern "C" fn sonde_monitor_start(
    core: *mut SondeCore,
    bus: *const c_char,
    cb: BatchCb,
    ctx: *mut c_void,
) -> i32 {
    if core.is_null() {
        return -1;
    }
    let core = unsafe { &*core };
    let bus = unsafe { cstr(bus) };
    let stop = core.monitor_stop.clone();
    stop.store(false, Ordering::Relaxed);
    // 先把裸指针包成 Send 的 Ctx，否则闭包无法跨线程。
    let ctx = Ctx(ctx);
    match thread::Builder::new()
        .name("sonde-monitor".into())
        .spawn(move || monitor_loop(bus, cb, ctx, stop))
    {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 请求停止监听。监控线程会在收到下一条消息后自行退出。
#[no_mangle]
pub extern "C" fn sonde_monitor_stop(core: *mut SondeCore) {
    if core.is_null() {
        return;
    }
    let core = unsafe { &*core };
    core.monitor_stop.store(true, Ordering::Relaxed);
}
