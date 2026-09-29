//! D-Bus 签名 ⇄ 类型树 ⇄ zvariant Value 之间的转换。
//!
//! 这里定义的节点 JSON 是 Rust 核心与 QML 界面之间**唯一**的数据契约，
//! 解码（Value → JSON）和发送（JSON → Value）共用同一套形状：
//!
//! ```json
//! { "sig": "a{sv}", "kind": "dict", "text": "", "items": [ ... ] }
//! ```
//!
//! - `kind`：bool/u8/i16/u16/i32/u32/i64/u64/f64/str/path/sig/fd/
//!   variant/array/dict/struct/maybe
//! - `text`：标量的字面值；variant 节点用它保存"内层签名"
//! - `items`：子节点。array/struct/variant/maybe 为 `{label, node}`；
//!   dict 为 `{label, key, val}`

use serde_json::{json, Value as J};
use std::os::fd::AsRawFd;
// 注意：D-Bus 类型系统里**没有** maybe 类型（`m` 是 GVariant 独有的），
// 所以这里不处理 Maybe，遇到 `m` 会按非法签名报错。
use zvariant::{Array, Dict, ObjectPath, Signature, StructureBuilder, Value};

#[derive(Debug, Clone, PartialEq)]
pub enum Ty {
    Bool,
    U8,
    I16,
    U16,
    I32,
    U32,
    I64,
    U64,
    F64,
    Str,
    Path,
    Sig,
    Fd,
    Variant,
    Array(Box<Ty>),
    Dict(Box<Ty>, Box<Ty>),
    Struct(Vec<Ty>),
}

impl Ty {
    /// 规范签名
    pub fn sig(&self) -> String {
        match self {
            Ty::Bool => "b".into(),
            Ty::U8 => "y".into(),
            Ty::I16 => "n".into(),
            Ty::U16 => "q".into(),
            Ty::I32 => "i".into(),
            Ty::U32 => "u".into(),
            Ty::I64 => "x".into(),
            Ty::U64 => "t".into(),
            Ty::F64 => "d".into(),
            Ty::Str => "s".into(),
            Ty::Path => "o".into(),
            Ty::Sig => "g".into(),
            Ty::Fd => "h".into(),
            Ty::Variant => "v".into(),
            Ty::Array(t) => format!("a{}", t.sig()),
            Ty::Dict(k, v) => format!("a{{{}{}}}", k.sig(), v.sig()),
            Ty::Struct(fs) => {
                let inner: String = fs.iter().map(|f| f.sig()).collect();
                format!("({inner})")
            }
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Ty::Bool => "bool",
            Ty::U8 => "u8",
            Ty::I16 => "i16",
            Ty::U16 => "u16",
            Ty::I32 => "i32",
            Ty::U32 => "u32",
            Ty::I64 => "i64",
            Ty::U64 => "u64",
            Ty::F64 => "f64",
            Ty::Str => "str",
            Ty::Path => "path",
            Ty::Sig => "sig",
            Ty::Fd => "fd",
            Ty::Variant => "variant",
            Ty::Array(_) => "array",
            Ty::Dict(_, _) => "dict",
            Ty::Struct(_) => "struct",
        }
    }
}

/// 解析一段完整签名，例如 `"sa{sv}"` → [Str, Dict(Str, Variant)]
pub fn parse_sig(s: &str) -> Result<Vec<Ty>, String> {
    let b = s.as_bytes();
    let mut i = 0usize;
    let mut out = Vec::new();
    while i < b.len() {
        out.push(parse_one(b, &mut i)?);
    }
    Ok(out)
}

fn parse_one(b: &[u8], i: &mut usize) -> Result<Ty, String> {
    if *i >= b.len() {
        return Err("签名意外结束".into());
    }
    let c = b[*i] as char;
    *i += 1;
    Ok(match c {
        'b' => Ty::Bool,
        'y' => Ty::U8,
        'n' => Ty::I16,
        'q' => Ty::U16,
        'i' => Ty::I32,
        'u' => Ty::U32,
        'x' => Ty::I64,
        't' => Ty::U64,
        'd' => Ty::F64,
        's' => Ty::Str,
        'o' => Ty::Path,
        'g' => Ty::Sig,
        'h' => Ty::Fd,
        'v' => Ty::Variant,
        'a' => {
            if *i < b.len() && b[*i] as char == '{' {
                *i += 1;
                let k = parse_one(b, i)?;
                let v = parse_one(b, i)?;
                if *i >= b.len() || b[*i] as char != '}' {
                    return Err("字典签名缺少 }".into());
                }
                *i += 1;
                Ty::Dict(Box::new(k), Box::new(v))
            } else {
                Ty::Array(Box::new(parse_one(b, i)?))
            }
        }
        '(' => {
            let mut fs = Vec::new();
            while *i < b.len() && b[*i] as char != ')' {
                fs.push(parse_one(b, i)?);
            }
            if *i >= b.len() {
                return Err("结构体签名缺少 )".into());
            }
            *i += 1;
            Ty::Struct(fs)
        }
        other => return Err(format!("未知的签名类型字符 '{other}'")),
    })
}

fn scalar(kind: &str, sig: &str, text: String) -> J {
    json!({ "sig": sig, "kind": kind, "text": text, "items": [] })
}

fn composite(kind: &str, sig: &str) -> J {
    json!({ "sig": sig, "kind": kind, "text": "", "items": [] })
}

/// 由签名生成"空的"类型树，供界面渲染参数表单。
pub fn type_tree(sig: &str) -> Result<J, String> {
    let tys = parse_sig(sig)?;
    let nodes: Vec<J> = tys.iter().map(type_tree_node).collect();
    Ok(J::Array(nodes))
}

fn type_tree_node(t: &Ty) -> J {
    match t {
        Ty::Struct(fs) => {
            let mut n = composite("struct", &t.sig());
            let items: Vec<J> = fs
                .iter()
                .enumerate()
                .map(|(i, f)| json!({ "label": i.to_string(), "node": type_tree_node(f) }))
                .collect();
            n["items"] = J::Array(items);
            n
        }
        Ty::Array(elem) => {
            // 给出元素模板，界面按 "+" 时直接深拷贝一份
            let mut n = composite("array", &t.sig());
            n["elemTemplate"] = type_tree_node(elem);
            n
        }
        Ty::Dict(k, v) => {
            let mut n = composite("dict", &t.sig());
            n["keyTemplate"] = type_tree_node(k);
            n["valTemplate"] = type_tree_node(v);
            n
        }
        Ty::Variant => {
            // 变体的内层类型默认取 str，界面可改；内层签名存在 text 里
            let mut v = composite("variant", "v");
            v["text"] = json!("s");
            v["items"] = json!([{ "label": "value", "node": type_tree_node(&Ty::Str) }]);
            v
        }
        _ => scalar(t.kind(), &t.sig(), String::new()),
    }
}

/// 把一条消息里的 zvariant 值递归转成上面的节点 JSON。
pub fn encode(v: &Value<'_>) -> J {
    match v {
        Value::Bool(x) => scalar("bool", "b", x.to_string()),
        Value::U8(x) => scalar("u8", "y", x.to_string()),
        Value::I16(x) => scalar("i16", "n", x.to_string()),
        Value::U16(x) => scalar("u16", "q", x.to_string()),
        Value::I32(x) => scalar("i32", "i", x.to_string()),
        Value::U32(x) => scalar("u32", "u", x.to_string()),
        Value::I64(x) => scalar("i64", "x", x.to_string()),
        Value::U64(x) => scalar("u64", "t", x.to_string()),
        Value::F64(x) => scalar("f64", "d", x.to_string()),
        Value::Str(x) => scalar("str", "s", x.to_string()),
        Value::ObjectPath(x) => scalar("path", "o", x.to_string()),
        Value::Signature(x) => scalar("sig", "g", x.to_string()),
        Value::Fd(x) => scalar("fd", "h", x.as_raw_fd().to_string()),
        Value::Value(inner) => {
            let mut n = composite("variant", "v");
            n["items"] = json!([{ "label": "value", "node": encode(inner) }]);
            n
        }
        Value::Array(a) => {
            let sig = format!("a{}", a.element_signature());
            let mut n = composite("array", &sig);
            let items: Vec<J> = a
                .inner()
                .iter()
                .enumerate()
                .map(|(i, e)| json!({ "label": format!("[{i}]"), "node": encode(e) }))
                .collect();
            n["items"] = J::Array(items);
            n
        }
        Value::Dict(d) => {
            let mut n = composite("dict", &d.signature().to_string());
            let items: Vec<J> = d
                .iter()
                .map(|(k, val)| {
                    let kn = encode(k);
                    let label = kn
                        .get("text")
                        .and_then(|t| t.as_str())
                        .unwrap_or("?")
                        .to_string();
                    json!({ "label": label, "key": kn, "val": encode(val) })
                })
                .collect();
            n["items"] = J::Array(items);
            n
        }
        Value::Structure(s) => {
            let mut n = composite("struct", &s.signature().to_string());
            let items: Vec<J> = s
                .fields()
                .iter()
                .enumerate()
                .map(|(i, f)| json!({ "label": i.to_string(), "node": encode(f) }))
                .collect();
            n["items"] = J::Array(items);
            n
        }
    }
}

fn txt(node: &J) -> &str {
    node.get("text").and_then(|t| t.as_str()).unwrap_or("")
}

fn child_node(node: &J, idx: usize) -> J {
    node.get("items")
        .and_then(|i| i.as_array())
        .and_then(|a| a.get(idx))
        .and_then(|e| e.get("node"))
        .cloned()
        .unwrap_or_else(|| json!({ "text": "", "items": [] }))
}

fn sig_of(s: &str) -> Result<Signature, String> {
    Signature::try_from(s).map_err(|e| format!("非法签名 '{s}': {e}"))
}

/// 界面表单（节点 JSON）→ 可发送的 zvariant 值。由签名引导类型。
pub fn from_json(node: &J, t: &Ty) -> Result<Value<'static>, String> {
    let text = txt(node);
    Ok(match t {
        Ty::Bool => Value::Bool(match text.trim() {
            "true" | "1" | "yes" | "y" => true,
            "false" | "0" | "no" | "n" | "" => false,
            other => return Err(format!("不是合法布尔值: '{other}'")),
        }),
        Ty::U8 => Value::U8(num(text, "u8")?),
        Ty::I16 => Value::I16(num(text, "i16")?),
        Ty::U16 => Value::U16(num(text, "u16")?),
        Ty::I32 => Value::I32(num(text, "i32")?),
        Ty::U32 => Value::U32(num(text, "u32")?),
        Ty::I64 => Value::I64(num(text, "i64")?),
        Ty::U64 => Value::U64(num(text, "u64")?),
        Ty::F64 => Value::F64(text.trim().parse::<f64>().map_err(|_| format!("不是合法 f64: '{text}'"))?),
        Ty::Str => Value::from(text.to_string()),
        Ty::Path => Value::ObjectPath(
            ObjectPath::try_from(text.to_string()).map_err(|e| format!("非法对象路径: {e}"))?,
        ),
        Ty::Sig => Value::Signature(sig_of(text)?),
        Ty::Fd => return Err("v0.1 暂不支持发送文件描述符 (h)".into()),
        Ty::Variant => {
            let inner_sig = if text.trim().is_empty() { "s" } else { text.trim() };
            let inner_ty = parse_sig(inner_sig)?
                .into_iter()
                .next()
                .ok_or_else(|| "变体的内层类型为空".to_string())?;
            let inner_node = child_node(node, 0);
            Value::Value(Box::new(from_json(&inner_node, &inner_ty)?))
        }
        Ty::Array(elem) => {
            let mut a = Array::new(&sig_of(&elem.sig())?);
            if let Some(items) = node.get("items").and_then(|i| i.as_array()) {
                for it in items {
                    let en = it.get("node").cloned().unwrap_or_else(|| json!({}));
                    a.append(from_json(&en, elem)?).map_err(|e| e.to_string())?;
                }
            }
            Value::Array(a)
        }
        Ty::Dict(k, v) => {
            let mut d = Dict::new(&sig_of(&k.sig())?, &sig_of(&v.sig())?);
            if let Some(items) = node.get("items").and_then(|i| i.as_array()) {
                for it in items {
                    let kn = it.get("key").cloned().unwrap_or_else(|| json!({}));
                    let vn = it.get("val").cloned().unwrap_or_else(|| json!({}));
                    d.append(from_json(&kn, k)?, from_json(&vn, v)?)
                        .map_err(|e| e.to_string())?;
                }
            }
            Value::Dict(d)
        }
        Ty::Struct(fs) => {
            let empty: Vec<J> = Vec::new();
            let items = node
                .get("items")
                .and_then(|i| i.as_array())
                .unwrap_or(&empty);
            let mut b = StructureBuilder::new();
            for (i, f) in fs.iter().enumerate() {
                let fn_ = items
                    .get(i)
                    .and_then(|e| e.get("node"))
                    .cloned()
                    .unwrap_or_else(|| json!({}));
                b = b.append_field(from_json(&fn_, f)?);
            }
            Value::Structure(b.build().map_err(|e| e.to_string())?)
        }
    })
}

fn num<T: std::str::FromStr>(text: &str, what: &str) -> Result<T, String> {
    text.trim()
        .parse::<T>()
        .map_err(|_| format!("不是合法 {what}: '{text}'"))
}

/// 把界面表单（顶层参数数组）转成发送用的值序列。
pub fn from_json_args(sig_str: &str, args: &J) -> Result<Vec<Value<'static>>, String> {
    let tys = parse_sig(sig_str)?;
    let empty: Vec<J> = Vec::new();
    let arr = args.as_array().unwrap_or(&empty);
    if arr.len() != tys.len() {
        return Err(format!(
            "参数个数不符：签名需要 {} 个，表单给出 {} 个",
            tys.len(),
            arr.len()
        ));
    }
    arr.iter()
        .zip(tys.iter())
        .map(|(node, t)| from_json(node, t))
        .collect()
}
