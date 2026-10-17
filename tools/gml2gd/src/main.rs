//! GML (GameMaker 8) -> GDScript transpiler for the Proyecto Reloaded port.
//!
//! Usage:
//!   gml2gd analyze <extracted_dir>

mod codegen;
mod units;

use gml_parser::ast::{Expr, AST};
use rayon::prelude::*;
use serde_json::Value;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs,
    path::Path,
};

pub struct Builtins {
    pub constants: HashMap<String, f64>,
    pub variables: HashSet<String>,
    pub functions: HashSet<String>,
}

impl Builtins {
    fn load() -> Self {
        let v: Value = serde_json::from_str(include_str!("../gm_builtins.json")).unwrap();
        Builtins {
            constants: v["constants"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_f64().unwrap())).collect(),
            variables: v["variables"].as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect(),
            functions: v["functions"].as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect(),
        }
    }
}

/// Every resource name -> (kind, index). GML can use resource names as numeric constants.
pub fn load_resources(root: &Path) -> HashMap<String, (String, usize)> {
    let index: Value = serde_json::from_str(&fs::read_to_string(root.join("index.json")).unwrap()).unwrap();
    let mut out = HashMap::new();
    for (kind, list) in index.as_object().unwrap() {
        for (i, n) in list.as_array().unwrap().iter().enumerate() {
            if let Some(n) = n.as_str() {
                out.insert(n.to_string(), (kind.clone(), i));
            }
        }
    }
    out
}

fn walk<'a>(e: &Expr<'a>, f: &mut impl FnMut(&Expr<'a>)) {
    f(e);
    match e {
        Expr::Unary(u) => walk(&u.child, f),
        Expr::Binary(b) => {
            walk(&b.left, f);
            walk(&b.right, f);
        },
        Expr::DoUntil(d) => {
            walk(&d.body, f);
            walk(&d.cond, f);
        },
        Expr::For(x) => {
            walk(&x.start, f);
            walk(&x.cond, f);
            walk(&x.step, f);
            walk(&x.body, f);
        },
        Expr::Function(x) => x.params.iter().for_each(|p| walk(p, f)),
        Expr::Group(g) => g.iter().for_each(|p| walk(p, f)),
        Expr::If(x) => {
            walk(&x.cond, f);
            walk(&x.body, f);
            if let Some(e) = &x.else_body {
                walk(e, f);
            }
        },
        Expr::Repeat(x) => {
            walk(&x.count, f);
            walk(&x.body, f);
        },
        Expr::Switch(x) => {
            walk(&x.input, f);
            walk(&x.body, f);
        },
        Expr::With(x) => {
            walk(&x.target, f);
            walk(&x.body, f);
        },
        Expr::While(x) => {
            walk(&x.cond, f);
            walk(&x.body, f);
        },
        Expr::Case(c) => walk(c, f),
        Expr::Return(r) => walk(r, f),
        _ => {},
    }
}

fn analyze(root: &Path) {
    let b = Builtins::load();
    let res = load_resources(root);
    let units = units::load(root);
    let scripts: HashSet<String> = units
        .iter()
        .filter(|u| matches!(u.kind, units::UnitKind::Script))
        .map(|u| u.name.clone())
        .collect();
    eprintln!("{} code units", units.len());

    #[derive(Default)]
    struct Stats {
        errors: Vec<(String, String)>,
        funcs: BTreeMap<String, usize>,
        unknown_funcs: BTreeMap<String, usize>,
        vars: BTreeMap<String, usize>,
        consts: BTreeMap<String, usize>,
        res_kinds: BTreeMap<String, usize>,
        withs: usize,
        derefs: usize,
    }
    let stats = units
        .par_iter()
        .fold(Stats::default, |mut st, u| {
            match AST::new(u.source.as_bytes()) {
                Err(e) => st.errors.push((u.name.clone(), e.message)),
                Ok(ast) => {
                    for line in ast.iter() {
                        walk(line, &mut |e| match e {
                            Expr::Function(fx) => {
                                let n = String::from_utf8_lossy(fx.name).into_owned();
                                if scripts.contains(&n) {
                                } else if b.functions.contains(&n) {
                                    *st.funcs.entry(n).or_default() += 1;
                                } else {
                                    *st.unknown_funcs.entry(n).or_default() += 1;
                                }
                            },
                            Expr::LiteralIdentifier(id) => {
                                let n = String::from_utf8_lossy(id).into_owned();
                                if b.variables.contains(&n) {
                                    *st.vars.entry(n).or_default() += 1;
                                } else if b.constants.contains_key(&n) {
                                    *st.consts.entry(n).or_default() += 1;
                                } else if let Some((k, _)) = res.get(&n) {
                                    *st.res_kinds.entry(k.clone()).or_default() += 1;
                                }
                            },
                            Expr::With(_) => st.withs += 1,
                            Expr::Binary(bx) if bx.op == gml_parser::token::Operator::Deref => st.derefs += 1,
                            _ => {},
                        });
                    }
                },
            }
            st
        })
        .reduce(Stats::default, |mut a, b| {
            a.errors.extend(b.errors);
            for (dst, src) in [
                (&mut a.funcs, b.funcs),
                (&mut a.unknown_funcs, b.unknown_funcs),
                (&mut a.vars, b.vars),
                (&mut a.consts, b.consts),
                (&mut a.res_kinds, b.res_kinds),
            ] {
                for (k, v) in src {
                    *dst.entry(k).or_default() += v;
                }
            }
            a.withs += b.withs;
            a.derefs += b.derefs;
            a
        });

    let sorted = |m: &BTreeMap<String, usize>| {
        let mut v: Vec<_> = m.iter().map(|(k, v)| (k.clone(), *v)).collect();
        v.sort_by(|a, b| b.1.cmp(&a.1));
        v
    };
    println!("parse errors: {}", stats.errors.len());
    for (n, e) in stats.errors.iter().take(15) {
        println!("  {n}: {e}");
    }
    println!("with blocks: {}, field derefs (a.b): {}", stats.withs, stats.derefs);
    println!("resource names used as values: {:?}", stats.res_kinds);
    println!("\nbuiltin functions used: {}", stats.funcs.len());
    println!("{:?}", sorted(&stats.funcs));
    println!("\nunknown functions: {:?}", sorted(&stats.unknown_funcs));
    println!("\nbuiltin variables used: {:?}", sorted(&stats.vars));
    println!("\nconstants used: {:?}", sorted(&stats.consts));
}

/// Every generated file reaches the runtime through a preloaded constant (cheaper to compile
/// than the global class name) and declares no class_name, so nothing forces eager loading.
const HEADER: &str = "const G = preload(\"res://runtime/gm.gd\")\n\n";

/// Event key from the extractor -> GDScript function name.
fn event_fn(key: &str, objects: &HashMap<String, usize>) -> String {
    if let Some(obj) = key.strip_prefix("collision_") {
        return format!("collision_{}", objects[obj]);
    }
    key.to_string()
}

fn gen(root: &Path, out: &Path) {
    use codegen::*;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    let b = Builtins::load();
    let units = units::load(root);
    let res = load_resources(root);
    let consts: HashMap<String, String> =
        serde_json::from_str(&fs::read_to_string(root.join("constants.json")).unwrap()).unwrap();

    let asts: Vec<_> = units.par_iter().map(|u| AST::new(u.source.as_bytes()).expect(&u.name)).collect();

    let mut constants: HashMap<String, f64> = res.iter().map(|(k, (_, i))| (k.clone(), *i as f64)).collect();
    for (k, v) in &consts {
        constants.insert(k.clone(), v.trim().parse().unwrap_or_else(|_| panic!("constant {k} = {v}")));
    }
    let object_index: HashMap<String, usize> =
        res.iter().filter(|(_, (k, _))| k == "objects").map(|(n, (_, i))| (n.clone(), *i)).collect();

    // Names indexed anywhere in the game.
    let mut array_names = HashSet::new();
    for ast in &asts {
        for line in ast.iter() {
            walk(line, &mut |e| {
                if let Expr::Binary(bx) = e {
                    if bx.op == gml_parser::token::Operator::Index {
                        match &bx.left {
                            Expr::LiteralIdentifier(id) => {
                                let n = codegen::ident(id);
                                if !b.variables.contains(&n) {
                                    array_names.insert(n);
                                }
                            },
                            Expr::Binary(d) if d.op == gml_parser::token::Operator::Deref => {
                                if let Expr::LiteralIdentifier(id) = &d.right {
                                    array_names.insert(codegen::ident(id));
                                }
                            },
                            _ => {},
                        }
                    }
                }
            });
        }
    }

    let mut script_arity = HashMap::new();
    for (u, ast) in units.iter().zip(&asts) {
        if matches!(u.kind, units::UnitKind::Script) {
            script_arity.insert(u.name.clone(), arity(&unit_info(ast)));
        }
    }
    let script_ids: HashMap<String, usize> =
        res.iter().filter(|(_, (k, _))| k == "scripts").map(|(n, (_, i))| (n.clone(), *i)).collect();
    let ctx = Ctx { builtins: &b, script_arity, constants, array_names, object_index: object_index.clone(), script_ids };
    eprintln!("{} array names", ctx.array_names.len());

    for d in ["gen/scripts", "gen/objects"] {
        let _ = fs::remove_dir_all(out.join(d));
        fs::create_dir_all(out.join(d)).unwrap();
    }

    // Generate every function, catching codegen panics so we get a full failure report.
    let results: Vec<Result<String, String>> = units
        .par_iter()
        .zip(&asts)
        .map(|(u, ast)| {
            let kind_fn = match &u.kind {
                units::UnitKind::Script => ("f".to_string(), FnKind::Script),
                units::UnitKind::Event { object, event } => {
                    let ef = event_fn(event, &object_index);
                    (format!("e_{ef}"), FnKind::Event { object: object_index[object], event_fn: "" })
                },
                units::UnitKind::RoomCreation { room } => (format!("r_{room}"), FnKind::Other),
                units::UnitKind::InstanceCreation { instance_id, .. } => (format!("i_{instance_id}"), FnKind::Other),
            };
            let (fname, kind) = kind_fn;
            // FnKind::Event needs the real event name; rebuild it here to keep the borrow simple.
            let ev_name;
            let kind = match (&u.kind, kind) {
                (units::UnitKind::Event { object, event }, _) => {
                    ev_name = event_fn(event, &object_index);
                    FnKind::Event { object: object_index[object], event_fn: &ev_name }
                },
                (_, k) => k,
            };
            catch_unwind(AssertUnwindSafe(|| gen_function(&ctx, &fname, ast, kind)))
                .map_err(|e| e.downcast_ref::<String>().cloned().or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default())
        })
        .collect();

    let mut failures = 0;
    let mut objects: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
    let mut room_code = String::from(HEADER);
    for ((u, r), _) in units.iter().zip(results).zip(&asts) {
        let code = match r {
            Ok(c) => c,
            Err(e) => {
                failures += 1;
                if failures <= 20 {
                    eprintln!("FAIL {}: {}", u.name, e);
                }
                continue;
            },
        };
        match &u.kind {
            units::UnitKind::Script => {
                let src = format!("{HEADER}{code}");
                fs::write(out.join("gen/scripts").join(format!("S_{}.gd", u.name)), src).unwrap();
            },
            units::UnitKind::Event { object, event } => {
                objects.entry(object.clone()).or_default().push((event_fn(event, &object_index), code));
            },
            _ => {
                room_code.push_str(&code);
                room_code.push('\n');
            },
        }
    }
    // Objects without any event still get a file so the runtime can treat all objects alike.
    for name in object_index.keys() {
        objects.entry(name.clone()).or_default();
    }
    let mut events_json = serde_json::Map::new();
    for (name, evs) in &objects {
        let list: Vec<String> = evs.iter().map(|(e, _)| format!("\"{e}\"")).collect();
        let mut src = format!("{HEADER}const EVENTS = [{}]\n\n", list.join(", "));
        events_json.insert(name.clone(), serde_json::json!(evs.iter().map(|(e, _)| e.clone()).collect::<Vec<_>>()));
        for (_, code) in evs {
            src.push_str(code);
            src.push('\n');
        }
        fs::write(out.join("gen/objects").join(format!("O_{name}.gd")), src).unwrap();
    }
    // Code strings passed literally to room_set_code / object_event_add: precompile them and
    // let the runtime find them by exact text (RoomCode.DYNAMIC).
    let mut dyn_codes: Vec<String> = Vec::new();
    for ast in &asts {
        for line in ast.iter() {
            walk(line, &mut |e| {
                if let Expr::Function(f) = e {
                    let n = codegen::ident(f.name);
                    let idx = match n.as_str() {
                        "room_set_code" => 1,
                        "object_event_add" => 3,
                        _ => return,
                    };
                    if let Some(Expr::LiteralString(st)) = f.params.get(idx) {
                        let st = String::from_utf8_lossy(st).into_owned();
                        if !dyn_codes.contains(&st) {
                            dyn_codes.push(st);
                        }
                    }
                }
            });
        }
    }
    let mut dyn_map = Vec::new();
    for (i, code) in dyn_codes.iter().enumerate() {
        let ast = AST::new(code.as_bytes()).unwrap_or_else(|e| panic!("dynamic code {code:?}: {}", e.message));
        room_code.push_str(&gen_function(&ctx, &format!("d_{i}"), &ast, FnKind::Other));
        room_code.push('\n');
        dyn_map.push(format!("{}: \"d_{i}\"", codegen::gd_string_pub(code.as_bytes())));
    }
    room_code.push_str(&format!("const DYNAMIC = {{{}}}\n", dyn_map.join(", ")));
    eprintln!("{} dynamic code strings precompiled", dyn_codes.len());
    fs::write(out.join("gen/RoomCode.gd"), room_code).unwrap();
    fs::write(out.join("gen/events.json"), serde_json::to_string(&events_json).unwrap()).unwrap();
    eprintln!("generated {} units, {} failures", units.len() - failures, failures);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("analyze") => analyze(Path::new(&args[2])),
        Some("gen") => gen(Path::new(&args[2]), Path::new(&args[3])),
        Some("ast") => println!("{:#?}", AST::new(args[2].as_bytes()).map(|a| format!("{:?}", &*a))),
        _ => eprintln!("usage: gml2gd analyze <extracted_dir>"),
    }
}
