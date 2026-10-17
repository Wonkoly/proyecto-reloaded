//! Turns a parsed GML unit into GDScript source that runs on the GM8 runtime in `godot/runtime`.
//!
//! Conventions shared with the runtime (keep both sides in sync):
//! - Every function gets `s` (self instance) and `o` (other instance). `with` rebinds them.
//! - Numbers are always floats. Comparisons/logic produce GDScript bools, converted with
//!   `float()` only when used as a value; conditions on plain values go through `GM.t()`.
//! - Instance variables live in `<inst>.v` (Dictionary); built-in instance variables are real
//!   properties on GMInstance; globals live in `GM.g`; built-in globals are statics on `GM`.
//! - Names that are ever indexed (`a[i]`) anywhere in the game are "array names" and always go
//!   through `GM.vget/vset/aget/aset`, which store a GMArray in the dictionary.
//! - Built-in functions are `G.f_<name>(s, args...)` (G = preloaded gm.gd); scripts are called
//!   through `G.sc(<script id>)`, which loads each generated script lazily on first use.

use crate::Builtins;
use gml_parser::{
    ast::{Expr, AST},
    token::Operator,
};
use std::{
    collections::{HashMap, HashSet},
    fmt::Write,
};

/// Built-in globals that are computed on read, so they become function calls.
const COMPUTED_GLOBALS: &[&str] = &[
    "current_time", "current_year", "current_month", "current_day", "current_weekday", "current_hour",
    "current_minute", "current_second", "instance_count", "room_width", "room_height", "room_persistent",
    "room_caption", "fps", "room_first", "room_last", "temp_directory", "program_directory",
    "keyboard_key", "mouse_button", "mouse_lastbutton", "instance_id",
];

/// Built-in globals whose assignment has side effects.
const SETTER_GLOBALS: &[&str] =
    &["room", "room_persistent", "room_caption", "room_speed", "keyboard_key", "keyboard_lastkey", "keyboard_string"];

/// Built-in variables that are per-instance (everything else in the built-in list is global).
const INSTANCE_VARS: &[&str] = &[
    "x", "y", "xprevious", "yprevious", "xstart", "ystart", "hspeed", "vspeed", "direction", "speed", "friction",
    "gravity", "gravity_direction", "object_index", "id", "alarm", "solid", "visible", "persistent", "depth",
    "bbox_left", "bbox_right", "bbox_top", "bbox_bottom", "sprite_index", "image_index", "image_single",
    "image_number", "sprite_width", "sprite_height", "sprite_xoffset", "sprite_yoffset", "image_xscale",
    "image_yscale", "image_angle", "image_alpha", "image_blend", "image_speed", "mask_index", "path_index",
    "path_position", "path_positionprevious", "path_speed", "path_scale", "path_orientation", "path_endaction",
    "timeline_index", "timeline_position", "timeline_speed", "timeline_running", "timeline_loop",
];

/// Built-in global arrays (indexed by view/background number).
const GLOBAL_ARRAYS: &[&str] = &[
    "view_visible", "view_xview", "view_yview", "view_wview", "view_hview", "view_xport", "view_yport",
    "view_wport", "view_hport", "view_angle", "view_hborder", "view_vborder", "view_hspeed", "view_vspeed",
    "view_object", "background_visible", "background_foreground", "background_index", "background_x",
    "background_y", "background_width", "background_height", "background_htiled", "background_vtiled",
    "background_xscale", "background_yscale", "background_hspeed", "background_vspeed", "background_blend",
    "background_alpha",
];

/// Shared, read-only knowledge about the whole game.
pub struct Ctx<'b> {
    pub builtins: &'b Builtins,
    /// Script name -> number of parameters its generated function declares.
    pub script_arity: HashMap<String, usize>,
    /// Constant / resource name -> numeric value.
    pub constants: HashMap<String, f64>,
    /// Names that are indexed somewhere in the game.
    pub array_names: HashSet<String>,
    pub object_index: HashMap<String, usize>,
    pub script_ids: HashMap<String, usize>,
}

pub enum FnKind<'a> {
    Script,
    /// Object event, with owning object index and event function name (for event_inherited).
    Event { object: usize, event_fn: &'a str },
    /// Room / instance creation code.
    Other,
}

enum Flow {
    /// `while`/`repeat`/`with`: continue is native.
    Loop,
    /// `for`: continue must run the step first.
    For(String),
    /// `do..until`: continue must evaluate the condition first.
    DoUntil(String),
    /// `switch` wrapper loop: continue sets a flag, breaks, and is re-emitted after the wrapper.
    Switch { id: usize, used_continue: bool },
}

struct Gen<'c, 'b> {
    ctx: &'c Ctx<'b>,
    out: String,
    indent: usize,
    tmp: usize,
    locals: HashSet<String>,
    self_v: String,
    other_v: String,
    flow: Vec<Flow>,
    in_script: bool,
    event: Option<(usize, String)>,
    fname: String,
    /// Class-level constants this function needs (switch lookup tables).
    consts: Vec<String>,
}

pub fn ident(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// Our dump decoded GM's Windows-1252 bytes; GM strings are bytes at runtime, so map the few
/// cp1252-only characters back to their byte value (U+0080..U+009F) to keep `ord`/`chr` exact.
fn gd_string(bytes: &[u8]) -> String {
    let s = String::from_utf8_lossy(bytes);
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        let c = match c {
            '€' => '\u{80}', '‚' => '\u{82}', 'ƒ' => '\u{83}', '„' => '\u{84}', '…' => '\u{85}', '†' => '\u{86}',
            '‡' => '\u{87}', 'ˆ' => '\u{88}', '‰' => '\u{89}', 'Š' => '\u{8a}', '‹' => '\u{8b}', 'Œ' => '\u{8c}',
            'Ž' => '\u{8e}', '‘' => '\u{91}', '’' => '\u{92}', '“' => '\u{93}', '”' => '\u{94}', '•' => '\u{95}',
            '–' => '\u{96}', '—' => '\u{97}', '˜' => '\u{98}', '™' => '\u{99}', 'š' => '\u{9a}', '›' => '\u{9b}',
            'œ' => '\u{9c}', 'ž' => '\u{9e}', 'Ÿ' => '\u{9f}',
            c => c,
        };
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (0x7f..0xa0).contains(&(c as u32)) => {
                write!(out, "\\u{:04x}", c as u32).unwrap();
            },
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

pub fn gd_string_pub(b: &[u8]) -> String {
    gd_string(b)
}

pub fn num(f: f64) -> String {
    if f.is_finite() && f == f.trunc() && f.abs() < 1e15 {
        format!("{:.1}", f)
    } else {
        format!("{:?}", f)
    }
}

/// Literal index -> "3"; dynamic -> "GM.ri(expr)".
fn index_expr(g: &mut Gen, e: &Expr) -> String {
    if let Expr::LiteralReal(f) = e {
        return format!("{}", crate::codegen::round_gm(*f));
    }
    format!("G.ri({})", g.value(e))
}

/// GM8's banker's rounding.
pub fn round_gm(f: f64) -> i64 {
    let int = f.floor();
    let diff = f - int;
    if diff < 0.5 {
        int as i64
    } else if diff > 0.5 {
        int as i64 + 1
    } else if (int as i64) % 2 == 0 {
        int as i64
    } else {
        int as i64 + 1
    }
}

/// Expression result: GDScript source plus whether it is a native bool.
struct Ex {
    code: String,
    is_bool: bool,
}

fn ex(code: String) -> Ex {
    Ex { code, is_bool: false }
}

fn bx(code: String) -> Ex {
    Ex { code, is_bool: true }
}

impl<'c, 'b> Gen<'c, 'b> {
    fn line(&mut self, s: &str) {
        for _ in 0..self.indent {
            self.out.push('\t');
        }
        self.out.push_str(s);
        self.out.push('\n');
    }

    fn fresh(&mut self, prefix: &str) -> String {
        self.tmp += 1;
        format!("_{}{}", prefix, self.tmp)
    }

    /// Value context: bools become 1.0/0.0.
    fn value(&mut self, e: &Expr) -> String {
        let x = self.expr(e);
        if x.is_bool { format!("float({})", x.code) } else { x.code }
    }

    /// Condition context: plain values go through GM truthiness (>= 0.5).
    fn cond(&mut self, e: &Expr) -> String {
        let x = self.expr(e);
        if x.is_bool { x.code } else { format!("G.t({})", x.code) }
    }

    fn is_array_name(&self, n: &str) -> bool {
        self.ctx.array_names.contains(n)
    }

    /// Dictionary holding plain variable `n` for the current self.
    fn var_dict(&self) -> String {
        format!("{}.v", self.self_v)
    }

    fn read_ident(&mut self, n: &str) -> Ex {
        if self.locals.contains(n) {
            return if self.is_array_name(n) { ex(format!("G.lget(l_{n})")) } else { ex(format!("l_{n}")) };
        }
        match n {
            "true" => return ex("1.0".into()),
            "false" => return ex("0.0".into()),
            "self" => return ex("-1.0".into()),
            "other" => return ex("-2.0".into()),
            "all" => return ex("-3.0".into()),
            "noone" => return ex("-4.0".into()),
            "global" => return ex("-5.0".into()),
            _ => {},
        }
        if let Some(k) = n.strip_prefix("argument") {
            if let Ok(i) = k.parse::<usize>() {
                return ex(format!("a{i}"));
            }
        }
        if self.ctx.builtins.variables.contains(n) {
            if n == "argument" {
                return ex("argument[0]".into());
            }
            if INSTANCE_VARS.contains(&n) {
                return ex(builtin_read(&self.self_v, n));
            }
            if GLOBAL_ARRAYS.contains(&n) {
                return ex(format!("G.{n}[0]"));
            }
            if COMPUTED_GLOBALS.contains(&n) {
                return ex(format!("G.gv_{n}()"));
            }
            return ex(format!("G.{n}"));
        }
        if let Some(c) = self.ctx.builtins.constants.get(n).or_else(|| self.ctx.constants.get(n)) {
            return ex(num(*c));
        }
        let d = self.var_dict();
        if self.is_array_name(n) { ex(format!("G.vget({d}, \"{n}\")")) } else { ex(format!("{d}.get(\"{n}\", 0.0)")) }
    }

    /// Resolves the left side of `a.b` into (kind, code): an instance expression we can use
    /// directly (self/other/global dict), or a generic target value for GM.fget/fset.
    fn deref_target(&mut self, left: &Expr) -> DerefTarget {
        if let Expr::LiteralIdentifier(id) = left {
            let n = ident(id);
            if !self.locals.contains(&n) {
                match n.as_str() {
                    "self" => return DerefTarget::Inst(self.self_v.clone()),
                    "other" => return DerefTarget::Inst(self.other_v.clone()),
                    "global" => return DerefTarget::Global,
                    _ => {},
                }
            }
        }
        DerefTarget::Value(self.value(left))
    }

    fn expr(&mut self, e: &Expr) -> Ex {
        match e {
            Expr::LiteralReal(f) => ex(num(*f)),
            Expr::LiteralString(s) => ex(gd_string(s)),
            Expr::LiteralIdentifier(id) => self.read_ident(&ident(id)),
            Expr::Group(g) if g.len() == 1 => self.expr(&g[0]),
            Expr::Unary(u) => match u.op {
                Operator::Not => bx(format!("(not {})", self.cond(&u.child))),
                Operator::Subtract => ex(format!("(-{})", self.value(&u.child))),
                Operator::Add => ex(self.value(&u.child)),
                Operator::Complement => ex(format!("G.bnot({})", self.value(&u.child))),
                op => panic!("unary {op:?}"),
            },
            Expr::Binary(b) => self.binary(b.op, &b.left, &b.right),
            Expr::Function(f) => ex(self.call(&ident(f.name), &f.params)),
            other => panic!("unexpected expression {other:?}"),
        }
    }

    fn binary(&mut self, op: Operator, l: &Expr, r: &Expr) -> Ex {
        use Operator::*;
        match op {
            Add | Subtract | Multiply | Divide => {
                let sym = match op {
                    Add => "+",
                    Subtract => "-",
                    Multiply => "*",
                    _ => "/",
                };
                ex(format!("({} {sym} {})", self.value(l), self.value(r)))
            },
            IntDivide => ex(format!("floorf({} / {})", self.value(l), self.value(r))),
            Modulo => ex(format!("fmod({}, {})", self.value(l), self.value(r))),
            BitwiseAnd => ex(format!("G.band({}, {})", self.value(l), self.value(r))),
            BitwiseOr => ex(format!("G.bor({}, {})", self.value(l), self.value(r))),
            BitwiseXor => ex(format!("G.bxor({}, {})", self.value(l), self.value(r))),
            BinaryShiftLeft => ex(format!("G.shl({}, {})", self.value(l), self.value(r))),
            BinaryShiftRight => ex(format!("G.shr({}, {})", self.value(l), self.value(r))),
            And => bx(format!("({} and {})", self.cond(l), self.cond(r))),
            Or => bx(format!("({} or {})", self.cond(l), self.cond(r))),
            Xor => bx(format!("({} != {})", self.cond(l), self.cond(r))),
            Equal | NotEqual | LessThan | LessThanOrEqual | GreaterThan | GreaterThanOrEqual => self.compare(op, l, r),
            Deref => {
                let Expr::LiteralIdentifier(field) = r else { panic!("deref rhs") };
                let field = ident(field);
                ex(self.read_field(l, &field, None))
            },
            Index => {
                let Expr::Group(dims) = r else { panic!("index rhs") };
                ex(self.read_indexed(l, dims))
            },
            Assign => {
                // `=` inside an expression is a comparison in GML.
                self.compare(Equal, l, r)
            },
            op => panic!("binary {op:?}"),
        }
    }

    /// GM8 compares reals with a 1e-13 epsilon; strings exactly. When one side is a numeric
    /// literal we inline the epsilon test, otherwise defer to the runtime helpers.
    fn compare(&mut self, op: Operator, l: &Expr, r: &Expr) -> Ex {
        use Operator::*;
        let strlit = |e: &Expr| matches!(e, Expr::LiteralString(_));
        let any_lit = self.const_value(l).is_some() || self.const_value(r).is_some();
        let (a, b) = (self.value(l), self.value(r));
        if strlit(l) || strlit(r) {
            let sym = match op {
                Equal => "==",
                NotEqual => "!=",
                LessThan => "<",
                LessThanOrEqual => "<=",
                GreaterThan => ">",
                _ => ">=",
            };
            return bx(format!("G.s_cmp({a}, {b}, \"{sym}\")"));
        }
        if any_lit {
            let d = format!("({a} - {b})");
            return bx(match op {
                Equal => format!("(absf{d} < 1e-13)"),
                NotEqual => format!("(absf{d} >= 1e-13)"),
                LessThan => format!("({d} <= -1e-13)"),
                LessThanOrEqual => format!("({d} < 1e-13)"),
                GreaterThan => format!("({d} >= 1e-13)"),
                _ => format!("({d} > -1e-13)"),
            });
        }
        let f = match op {
            Equal => "eq",
            NotEqual => "ne",
            LessThan => "lt",
            LessThanOrEqual => "le",
            GreaterThan => "gt",
            _ => "ge",
        };
        bx(format!("G.{f}({a}, {b})"))
    }

    /// Numeric value of a literal or a known constant identifier (true, c_white, resource names...).
    fn const_value(&self, e: &Expr) -> Option<f64> {
        match e {
            Expr::LiteralReal(f) => Some(*f),
            Expr::LiteralIdentifier(id) => {
                let n = ident(id);
                if self.locals.contains(&n) || self.ctx.builtins.variables.contains(&n) {
                    return None;
                }
                match n.as_str() {
                    "true" => Some(1.0),
                    "false" => Some(0.0),
                    _ => self.ctx.builtins.constants.get(&n).or_else(|| self.ctx.constants.get(&n)).copied(),
                }
            },
            _ => None,
        }
    }

    fn read_field(&mut self, target: &Expr, field: &str, idx: Option<(String, String)>) -> String {
        let t = self.deref_target(target);
        let is_builtin_inst = INSTANCE_VARS.contains(&field);
        match (t, idx) {
            (DerefTarget::Global, None) => self.dict_read("G.g", field),
            (DerefTarget::Global, Some((i, j))) => format!("G.aget(G.g, \"{field}\", {i}, {j})"),
            (DerefTarget::Inst(v), None) if is_builtin_inst => builtin_read(&v, field),
            (DerefTarget::Inst(v), Some((i, _))) if field == "alarm" => format!("{v}.alarm[{i}]"),
            (DerefTarget::Inst(v), None) => self.dict_read(&format!("{v}.v"), field),
            (DerefTarget::Inst(v), Some((i, j))) => format!("G.aget({v}.v, \"{field}\", {i}, {j})"),
            (DerefTarget::Value(t), None) => format!("G.fget({}, {}, {t}, \"{field}\")", self.self_v, self.other_v),
            (DerefTarget::Value(t), Some((i, j))) => {
                format!("G.faget({}, {}, {t}, \"{field}\", {i}, {j})", self.self_v, self.other_v)
            },
        }
    }

    fn dict_read(&self, dict: &str, n: &str) -> String {
        if self.is_array_name(n) { format!("G.vget({dict}, \"{n}\")") } else { format!("{dict}.get(\"{n}\", 0.0)") }
    }

    fn dims(&mut self, dims: &[Expr]) -> (String, String) {
        match dims {
            [i] => (index_expr(self, i), "0".into()),
            [i, j] => (index_expr(self, i), index_expr(self, j)),
            _ => panic!("array with {} dims", dims.len()),
        }
    }

    fn read_indexed(&mut self, base: &Expr, dims: &[Expr]) -> String {
        match base {
            Expr::LiteralIdentifier(id) => {
                let n = ident(id);
                let (i, j) = self.dims(dims);
                if self.locals.contains(&n) {
                    return format!("G.laget(l_{n}, {i}, {j})");
                }
                if n == "argument" {
                    return format!("argument[{i}]");
                }
                if n == "alarm" {
                    return format!("{}.alarm[{i}]", self.self_v);
                }
                if GLOBAL_ARRAYS.contains(&n.as_str()) {
                    return format!("G.{n}[{i}]");
                }
                format!("G.aget({}, \"{n}\", {i}, {j})", self.var_dict())
            },
            Expr::Binary(b) if b.op == Operator::Deref => {
                let Expr::LiteralIdentifier(field) = &b.right else { panic!() };
                let field = ident(field);
                let d = self.dims(dims);
                self.read_field(&b.left, &field, Some(d))
            },
            other => panic!("index on {other:?}"),
        }
    }

    fn call(&mut self, name: &str, params: &[Expr]) -> String {
        // Obfuscated script call that survived in room/instance code: ex(<script id>, ...).
        if name == "ex" {
            if let Some(Expr::LiteralReal(_)) = params.first() {
                panic!("unresolved ex() call; run resolve_ex.py first");
            }
        }
        if let Some(&arity) = self.ctx.script_arity.get(name) {
            let mut args = vec![self.self_v.clone(), self.other_v.clone()];
            for p in params.iter().take(arity) {
                args.push(self.value(p));
            }
            // GM evaluates extra arguments even though the script ignores them.
            let extra: Vec<String> = params.iter().skip(arity).map(|p| self.value(p)).collect();
            let id = self.ctx.script_ids[name];
            let call = format!("G.sc({id}).call({})", args.join(", "));
            return if extra.is_empty() { call } else { format!("G.first({call}, [{}])", extra.join(", ")) };
        }
        match name {
            "event_inherited" => {
                if let Some((obj, ev)) = &self.event {
                    return format!("G.event_inherited({}, {}, {obj}, \"{ev}\")", self.self_v, self.other_v);
                }
                return "0.0".into();
            },
            "floor" => return format!("floorf({})", self.value(&params[0])),
            "ceil" => return format!("ceilf({})", self.value(&params[0])),
            "abs" => return format!("absf({})", self.value(&params[0])),
            _ => {},
        }
        assert!(self.ctx.builtins.functions.contains(name), "unknown function {name}");
        let mut args = vec![self.self_v.clone()];
        for p in params {
            args.push(self.value(p));
        }
        // Variadic built-ins take an array.
        if matches!(name, "choose" | "max" | "min" | "mean" | "median" | "script_execute") {
            let first = if name == "script_execute" { 2 } else { 1 };
            let (head, rest) = args.split_at(first.min(args.len()));
            return format!("G.f_{name}({}, [{}])", head.join(", "), rest.join(", "));
        }
        format!("G.f_{name}({})", args.join(", "))
    }

    // ---------------------------------------------------------------- statements

    fn block(&mut self, e: &Expr) {
        let before = self.out.len();
        self.stmt(e);
        if self.out.len() == before {
            self.line("pass");
        }
    }

    fn stmt(&mut self, e: &Expr) {
        match e {
            Expr::Group(g) => g.iter().for_each(|s| self.stmt(s)),
            Expr::Var(_) | Expr::GlobalVar(_) => {},
            Expr::Binary(b) if is_assign(b.op) => self.assign(b.op, &b.left, &b.right),
            Expr::Function(f) => {
                let c = self.call(&ident(f.name), &f.params);
                self.line(&c);
            },
            Expr::If(i) => {
                let c = self.cond(&i.cond);
                self.line(&format!("if {c}:"));
                self.indent += 1;
                self.block(&i.body);
                self.indent -= 1;
                let mut else_body = i.else_body.as_ref();
                while let Some(eb) = else_body {
                    match eb {
                        Expr::If(i2) => {
                            let c = self.cond(&i2.cond);
                            self.line(&format!("elif {c}:"));
                            self.indent += 1;
                            self.block(&i2.body);
                            self.indent -= 1;
                            else_body = i2.else_body.as_ref();
                        },
                        other => {
                            self.line("else:");
                            self.indent += 1;
                            self.block(other);
                            self.indent -= 1;
                            else_body = None;
                        },
                    }
                }
            },
            Expr::While(w) => {
                let c = self.cond(&w.cond);
                self.line(&format!("while {c}:"));
                self.loop_body(Flow::Loop, &w.body, None);
            },
            Expr::Repeat(r) => {
                let n = self.value(&r.count);
                let v = self.fresh("r");
                self.line(&format!("for {v} in range(G.ri({n})):"));
                self.loop_body(Flow::Loop, &r.body, None);
            },
            Expr::For(f) => {
                self.stmt(&f.start);
                let step = self.capture(|g| g.stmt(&f.step));
                let c = self.cond(&f.cond);
                self.line(&format!("while {c}:"));
                self.loop_body(Flow::For(step.clone()), &f.body, Some(step));
            },
            Expr::DoUntil(d) => {
                let c = self.cond(&d.cond);
                self.line("while true:");
                let tail = format!("if {c}:\n\tbreak\n");
                self.loop_body(Flow::DoUntil(c), &d.body, Some(tail));
            },
            Expr::With(w) => {
                let t = self.value(&w.target);
                let v = self.fresh("w");
                self.line(&format!("for {v} in G.with_iter({}, {}, {t}):", self.self_v, self.other_v));
                let (old_s, old_o) = (self.self_v.clone(), self.other_v.clone());
                self.indent += 1;
                self.line(&format!("if {v}.gone: continue"));
                self.indent -= 1;
                self.other_v = old_s.clone();
                self.self_v = v;
                self.loop_body(Flow::Loop, &w.body, None);
                self.self_v = old_s;
                self.other_v = old_o;
            },
            Expr::Switch(sw) => self.switch(&sw.input, &sw.body),
            Expr::Break => {
                if self.flow.is_empty() {
                    self.line("return 0.0");
                } else {
                    self.line("break");
                }
            },
            Expr::Continue => self.emit_continue(self.flow.len()),
            Expr::Exit => self.line("return 0.0"),
            Expr::Return(r) => {
                let v = self.value(r);
                self.line(&format!("return {v}"));
            },
            // Bare expressions as statements (e.g. `a;`): evaluate for side effects.
            other => {
                let v = self.value(other);
                self.line(&format!("{v}"));
            },
        }
    }

    /// Renders statements into a string at indent 0 so they can be replayed (for-loop step).
    fn capture(&mut self, f: impl FnOnce(&mut Self)) -> String {
        let (out, ind) = (std::mem::take(&mut self.out), self.indent);
        self.indent = 0;
        f(self);
        let s = std::mem::replace(&mut self.out, out);
        self.indent = ind;
        s
    }

    fn replay(&mut self, code: &str) {
        for l in code.lines() {
            self.line(l);
        }
    }

    fn loop_body(&mut self, flow: Flow, body: &Expr, tail: Option<String>) {
        self.flow.push(flow);
        self.indent += 1;
        self.block(body);
        if let Some(t) = tail {
            self.replay(&t);
        }
        self.indent -= 1;
        self.flow.pop();
    }

    /// Emits a `continue` for the flow context at depth `upto` (exclusive top index).
    fn emit_continue(&mut self, upto: usize) {
        let Some(top) = upto.checked_sub(1) else {
            self.line("return 0.0");
            return;
        };
        match &mut self.flow[top] {
            Flow::Loop => self.line("continue"),
            Flow::For(step) => {
                let step = step.clone();
                self.replay(&step);
                self.line("continue");
            },
            Flow::DoUntil(c) => {
                let c = c.clone();
                self.line(&format!("if {c}:"));
                self.line("\tbreak");
                self.line("continue");
            },
            Flow::Switch { id, used_continue } => {
                *used_continue = true;
                let id = *id;
                self.line(&format!("_cc{id} = true"));
                self.line("break");
            },
        }
    }

    fn switch(&mut self, input: &Expr, body: &Expr) {
        let stmts: Vec<&Expr> = match body {
            Expr::Group(g) => g.iter().collect(),
            e => vec![e],
        };
        // Split into labelled segments.
        let mut labels: Vec<Option<&Expr>> = Vec::new(); // None = default
        let mut segs: Vec<Vec<&Expr>> = Vec::new();
        let mut pre: Vec<&Expr> = Vec::new(); // statements before the first label never run
        for s in stmts {
            match s {
                Expr::Case(c) => {
                    labels.push(Some(c));
                    segs.push(vec![]);
                },
                Expr::Default => {
                    labels.push(None);
                    segs.push(vec![]);
                },
                s => match segs.last_mut() {
                    Some(seg) => seg.push(s),
                    None => pre.push(s),
                },
            }
        }
        let id = self.tmp + 1;
        self.tmp += 1;
        let v = self.value(input);
        self.line(&format!("var _sw{id} = {v}"));
        self.line(&format!("var _st{id} := -1"));
        self.line(&format!("var _cc{id} := false"));
        let mut first = true;
        let mut default_idx = labels.iter().position(|l| l.is_none());
        // Constant labels: one dictionary lookup instead of a chain of comparisons.
        let consts: Option<Vec<String>> = labels
            .iter()
            .flatten()
            .map(|c| match c {
                Expr::LiteralString(st) => Some(gd_string(st)),
                c => self.const_value(c).map(num),
            })
            .collect();
        if let Some(keys) = consts.filter(|k| k.len() >= 4) {
            let mut entries = Vec::new();
            let mut seen = HashSet::new();
            let mut k_iter = keys.into_iter();
            for (k, l) in labels.iter().enumerate() {
                if l.is_some() {
                    let key = k_iter.next().unwrap();
                    // First matching label wins, like the comparison chain.
                    if seen.insert(key.clone()) {
                        entries.push(format!("{key}: {k}"));
                    }
                }
            }
            let cname = format!("_SW_{}_{id}", self.fname);
            self.consts.push(format!("const {cname} = {{{}}}", entries.join(", ")));
            let d = default_idx.map_or(-1, |d| d as i64);
            self.line(&format!("_st{id} = G.sw_lookup({cname}, _sw{id}, {d})"));
            default_idx = None;
            first = false;
            labels.clear();
        }
        for (k, l) in labels.iter().enumerate() {
            match l {
                Some(c) => {
                    let cv = self.value(c);
                    let kw = if first { "if" } else { "elif" };
                    first = false;
                    self.line(&format!("{kw} G.eq(_sw{id}, {cv}):"));
                    self.line(&format!("\t_st{id} = {k}"));
                },
                None => default_idx = Some(k),
            }
        }
        if let Some(d) = default_idx.filter(|_| !labels.is_empty() || first) {
            if first {
                self.line(&format!("_st{id} = {d}"));
            } else {
                self.line("else:");
                self.line(&format!("\t_st{id} = {d}"));
            }
        }
        self.line("while true:");
        self.indent += 1;
        self.flow.push(Flow::Switch { id, used_continue: false });
        for (k, seg) in segs.iter().enumerate() {
            if seg.is_empty() {
                continue;
            }
            self.line(&format!("if _st{id} != -1 and _st{id} <= {k}:"));
            self.indent += 1;
            let before = self.out.len();
            for s in seg {
                self.stmt(s);
            }
            if self.out.len() == before {
                self.line("pass");
            }
            self.indent -= 1;
        }
        self.line("break");
        let used = matches!(self.flow.pop(), Some(Flow::Switch { used_continue: true, .. }));
        self.indent -= 1;
        if used {
            self.line(&format!("if _cc{id}:"));
            self.indent += 1;
            let depth = self.flow.len();
            self.emit_continue(depth);
            self.indent -= 1;
        }
    }

    fn assign(&mut self, op: Operator, lhs: &Expr, rhs: &Expr) {
        // Compound assignment: `a op= b` is `a = a op b`, evaluating the target once.
        let bin = match op {
            Operator::Assign => None,
            Operator::AssignAdd => Some(Operator::Add),
            Operator::AssignSubtract => Some(Operator::Subtract),
            Operator::AssignMultiply => Some(Operator::Multiply),
            Operator::AssignDivide => Some(Operator::Divide),
            Operator::AssignBitwiseAnd => Some(Operator::BitwiseAnd),
            Operator::AssignBitwiseOr => Some(Operator::BitwiseOr),
            Operator::AssignBitwiseXor => Some(Operator::BitwiseXor),
            _ => unreachable!(),
        };
        let place = self.place(lhs);
        let rv = self.value(rhs);
        let newv = match bin {
            None => rv,
            Some(b) => {
                let cur = place.read.clone();
                match b {
                    Operator::Add => format!("{cur} + {rv}"),
                    Operator::Subtract => format!("{cur} - {rv}"),
                    Operator::Multiply => format!("{cur} * {rv}"),
                    Operator::Divide => format!("{cur} / {rv}"),
                    Operator::BitwiseAnd => format!("G.band({cur}, {rv})"),
                    Operator::BitwiseOr => format!("G.bor({cur}, {rv})"),
                    _ => format!("G.bxor({cur}, {rv})"),
                }
            },
        };
        let w = place.write.replace("$V", &newv);
        self.line(&w);
    }

    /// An assignable location: how to read it and a write template with `$V` for the value.
    /// Side-effecting parts (deref targets, indices) are hoisted into temporaries.
    fn place(&mut self, lhs: &Expr) -> Place {
        match lhs {
            Expr::LiteralIdentifier(id) => {
                let n = ident(id);
                if self.locals.contains(&n) {
                    if self.is_array_name(&n) {
                        return Place { read: format!("G.lget(l_{n})"), write: format!("l_{n} = G.lset(l_{n}, $V)") };
                    }
                    return Place { read: format!("l_{n}"), write: format!("l_{n} = $V") };
                }
                if let Some(k) = n.strip_prefix("argument") {
                    if let Ok(i) = k.parse::<usize>() {
                        return Place { read: format!("a{i}"), write: format!("a{i} = $V") };
                    }
                }
                if self.ctx.builtins.variables.contains(&n) {
                    if INSTANCE_VARS.contains(&n.as_str()) {
                        return builtin_place(&self.self_v, &n);
                    }
                    if GLOBAL_ARRAYS.contains(&n.as_str()) {
                        return Place { read: format!("G.{n}[0]"), write: format!("G.{n}[0] = $V") };
                    }
                    let read = self.read_ident(&n).code;
                    if SETTER_GLOBALS.contains(&n.as_str()) {
                        return Place { read, write: format!("G.gs_{n}($V)") };
                    }
                    return Place { write: format!("G.{n} = $V"), read };
                }
                let d = self.var_dict();
                self.dict_place(&d, &n)
            },
            Expr::Binary(b) if b.op == Operator::Deref => {
                let Expr::LiteralIdentifier(field) = &b.right else { panic!() };
                let field = ident(field);
                self.field_place(&b.left, &field, None)
            },
            Expr::Binary(b) if b.op == Operator::Index => {
                let Expr::Group(dims) = &b.right else { panic!() };
                let (i, j) = self.dims(dims);
                let (i, j) = (self.hoist(i), self.hoist(j));
                match &b.left {
                    Expr::LiteralIdentifier(id) => {
                        let n = ident(id);
                        if self.locals.contains(&n) {
                            return Place {
                                read: format!("G.laget(l_{n}, {i}, {j})"),
                                write: format!("l_{n} = G.laset(l_{n}, {i}, {j}, $V)"),
                            };
                        }
                        if n == "argument" {
                            return Place { read: format!("argument[{i}]"), write: format!("argument[{i}] = $V") };
                        }
                        if n == "alarm" {
                            let r = format!("{}.alarm[{i}]", self.self_v);
                            return Place { write: format!("{r} = $V"), read: r };
                        }
                        if GLOBAL_ARRAYS.contains(&n.as_str()) {
                            return Place { read: format!("G.{n}[{i}]"), write: format!("G.{n}[{i}] = $V") };
                        }
                        let d = self.var_dict();
                        Place {
                            read: format!("G.aget({d}, \"{n}\", {i}, {j})"),
                            write: format!("G.aset({d}, \"{n}\", {i}, {j}, $V)"),
                        }
                    },
                    Expr::Binary(d) if d.op == Operator::Deref => {
                        let Expr::LiteralIdentifier(field) = &d.right else { panic!() };
                        let field = ident(field);
                        self.field_place(&d.left, &field, Some((i, j)))
                    },
                    other => panic!("index place {other:?}"),
                }
            },
            other => panic!("not assignable: {other:?}"),
        }
    }

    fn dict_place(&self, d: &str, n: &str) -> Place {
        if self.is_array_name(n) {
            Place { read: format!("G.vget({d}, \"{n}\")"), write: format!("G.vset({d}, \"{n}\", $V)") }
        } else {
            Place { read: format!("{d}.get(\"{n}\", 0.0)"), write: format!("{d}[\"{n}\"] = $V") }
        }
    }

    /// Hoists non-trivial index expressions into a temp so compound assignment evaluates once.
    fn hoist(&mut self, code: String) -> String {
        if code.chars().all(|c| c.is_ascii_digit()) {
            return code;
        }
        let t = self.fresh("i");
        self.line(&format!("var {t} = {code}"));
        t
    }

    fn field_place(&mut self, target: &Expr, field: &str, idx: Option<(String, String)>) -> Place {
        let t = self.deref_target(target);
        let builtin = INSTANCE_VARS.contains(&field);
        match (t, idx) {
            (DerefTarget::Global, None) => self.dict_place("G.g", field),
            (DerefTarget::Global, Some((i, j))) => Place {
                read: format!("G.aget(G.g, \"{field}\", {i}, {j})"),
                write: format!("G.aset(G.g, \"{field}\", {i}, {j}, $V)"),
            },
            (DerefTarget::Inst(v), None) if builtin => builtin_place(&v, field),
            (DerefTarget::Inst(v), Some((i, _))) if field == "alarm" => {
                let r = format!("{v}.alarm[{i}]");
                Place { write: format!("{r} = $V"), read: r }
            },
            (DerefTarget::Inst(v), None) => self.dict_place(&format!("{v}.v"), field),
            (DerefTarget::Inst(v), Some((i, j))) => Place {
                read: format!("G.aget({v}.v, \"{field}\", {i}, {j})"),
                write: format!("G.aset({v}.v, \"{field}\", {i}, {j}, $V)"),
            },
            (DerefTarget::Value(t), idx) => {
                let t = if t.chars().all(|c| c.is_ascii_digit() || c == '.' || c == '-') { t } else { self.hoist(t) };
                let (s, o) = (self.self_v.clone(), self.other_v.clone());
                match idx {
                    None => Place {
                        read: format!("G.fget({s}, {o}, {t}, \"{field}\")"),
                        write: format!("G.fset({s}, {o}, {t}, \"{field}\", $V)"),
                    },
                    Some((i, j)) => Place {
                        read: format!("G.faget({s}, {o}, {t}, \"{field}\", {i}, {j})"),
                        write: format!("G.faset({s}, {o}, {t}, \"{field}\", {i}, {j}, $V)"),
                    },
                }
            },
        }
    }
}

/// Built-in instance variables stored as bools on GMInstance.
const BOOL_VARS: &[&str] = &["solid", "visible", "persistent", "timeline_running", "timeline_loop"];

/// Read of a built-in instance variable on instance expression `v`.
fn builtin_read(v: &str, field: &str) -> String {
    if field == "alarm" {
        format!("{v}.alarm[0]")
    } else if BOOL_VARS.contains(&field) {
        format!("float({v}.{field})")
    } else {
        format!("{v}.{field}")
    }
}

/// Assignable place for a built-in instance variable on instance expression `v`.
fn builtin_place(v: &str, field: &str) -> Place {
    if field == "alarm" {
        let r = format!("{v}.alarm[0]");
        Place { write: format!("{r} = $V"), read: r }
    } else if BOOL_VARS.contains(&field) {
        Place { read: format!("float({v}.{field})"), write: format!("{v}.{field} = G.t($V)") }
    } else {
        let r = format!("{v}.{field}");
        Place { write: format!("{r} = $V"), read: r }
    }
}

enum DerefTarget {
    Inst(String),
    Global,
    Value(String),
}

struct Place {
    read: String,
    write: String,
}

fn is_assign(op: Operator) -> bool {
    use Operator::*;
    matches!(
        op,
        Assign | AssignAdd | AssignSubtract | AssignMultiply | AssignDivide | AssignBitwiseAnd | AssignBitwiseOr
            | AssignBitwiseXor
    )
}

/// Collects `var` names and argument usage of a unit.
pub struct UnitInfo {
    pub locals: HashSet<String>,
    pub max_arg: Option<usize>,
    pub uses_argument_array: bool,
}

pub fn unit_info(ast: &AST) -> UnitInfo {
    let mut info = UnitInfo { locals: HashSet::new(), max_arg: None, uses_argument_array: false };
    for line in ast.iter() {
        crate::walk(line, &mut |e| match e {
            Expr::Var(v) => info.locals.extend(v.vars.iter().map(|n| ident(n))),
            Expr::LiteralIdentifier(id) => {
                let n = ident(id);
                if n == "argument" {
                    info.uses_argument_array = true;
                } else if let Some(i) = n.strip_prefix("argument").and_then(|k| k.parse::<usize>().ok()) {
                    info.max_arg = Some(info.max_arg.map_or(i, |m| m.max(i)));
                }
            },
            _ => {},
        });
    }
    info
}

/// Arity a script's generated function declares.
pub fn arity(info: &UnitInfo) -> usize {
    if info.uses_argument_array { 16 } else { info.max_arg.map_or(0, |m| m + 1) }
}

/// Generates the body of one GDScript static function.
pub fn gen_function(ctx: &Ctx, fname: &str, ast: &AST, kind: FnKind) -> String {
    let info = unit_info(ast);
    let mut g = Gen {
        ctx,
        out: String::new(),
        indent: 0,
        tmp: 0,
        locals: info.locals.clone(),
        self_v: "s".into(),
        other_v: "o".into(),
        flow: Vec::new(),
        in_script: matches!(kind, FnKind::Script),
        event: match kind {
            FnKind::Event { object, event_fn } => Some((object, event_fn.to_string())),
            _ => None,
        },
        fname: fname.to_string(),
        consts: Vec::new(),
    };
    let n_args = if g.in_script { arity(&info) } else { 0 };
    let params: Vec<String> = (0..n_args).map(|i| format!("a{i} = 0.0")).collect();
    let sig = if params.is_empty() { String::new() } else { format!(", {}", params.join(", ")) };
    g.line(&format!("static func {fname}(s, o{sig}):"));
    g.indent = 1;
    // Arguments not declared as parameters read as 0 (events, or indices beyond the arity).
    if let Some(m) = info.max_arg {
        for i in n_args..=m {
            g.line(&format!("var a{i} = 0.0"));
        }
    }
    if info.uses_argument_array {
        let all: Vec<String> = (0..16).map(|i| format!("a{i}")).collect();
        let decl = if g.in_script { all.join(", ") } else { vec!["0.0"; 16].join(", ") };
        g.line(&format!("var argument = [{decl}]"));
    }
    let mut locals: Vec<&String> = info.locals.iter().collect();
    locals.sort();
    for l in locals {
        if ctx.array_names.contains(l.as_str()) {
            g.line(&format!("var l_{l} = null"));
        } else {
            g.line(&format!("var l_{l} = 0.0"));
        }
    }
    for line in ast.iter() {
        g.stmt(line);
    }
    g.line("return 0.0");
    if g.consts.is_empty() {
        g.out
    } else {
        format!("{}\n{}", g.consts.join("\n"), g.out)
    }
}
