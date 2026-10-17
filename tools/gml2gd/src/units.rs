//! Loads every piece of GML in the extracted game as a "code unit".

use serde_json::Value;
use std::{fs, path::Path};

pub enum UnitKind {
    Script,
    /// Object event; `event` is the extractor's event key, e.g. "step_normal", "alarm_3".
    Event { object: String, event: String },
    RoomCreation { room: String },
    InstanceCreation { room: String, instance_id: i64 },
}

pub struct Unit {
    pub name: String,
    pub kind: UnitKind,
    pub source: String,
}

pub fn load(root: &Path) -> Vec<Unit> {
    let mut units = Vec::new();

    let mut scripts: Vec<_> = fs::read_dir(root.join("scripts")).unwrap().flatten().map(|e| e.path()).collect();
    scripts.sort();
    for p in scripts {
        if p.extension().is_some_and(|e| e == "gml") {
            units.push(Unit {
                name: p.file_stem().unwrap().to_string_lossy().into_owned(),
                kind: UnitKind::Script,
                source: fs::read_to_string(&p).unwrap(),
            });
        }
    }

    let mut objects: Vec<_> = fs::read_dir(root.join("objects")).unwrap().flatten().map(|e| e.path()).collect();
    objects.sort();
    for p in objects {
        if !p.extension().is_some_and(|e| e == "json") {
            continue;
        }
        let o: Value = serde_json::from_str(&fs::read_to_string(&p).unwrap()).unwrap();
        let object = o["name"].as_str().unwrap().to_string();
        for (event, actions) in o["events"].as_object().unwrap() {
            // Every action in this game is "execute code" applied to self, except a lone
            // action_inherited which we lower to a call to event_inherited().
            let mut src = String::new();
            for a in actions.as_array().unwrap() {
                match (a["lib_id"].as_u64(), a["id"].as_u64()) {
                    (Some(1), Some(603)) => {
                        src.push_str(a["params"][0].as_str().unwrap_or(""));
                        src.push('\n');
                    },
                    (Some(1), Some(604)) => src.push_str("event_inherited();\n"),
                    other => panic!("unsupported D&D action {other:?} in {object}.{event}"),
                }
            }
            units.push(Unit {
                name: format!("{object}.{event}"),
                kind: UnitKind::Event { object: object.clone(), event: event.clone() },
                source: src,
            });
        }
    }

    let mut rooms: Vec<_> = fs::read_dir(root.join("rooms")).unwrap().flatten().map(|e| e.path()).collect();
    rooms.sort();
    for p in rooms {
        let r: Value = serde_json::from_str(&fs::read_to_string(&p).unwrap()).unwrap();
        let room = r["name"].as_str().unwrap().to_string();
        let cc = r["creation_code"].as_str().unwrap_or("");
        if !cc.trim().is_empty() {
            units.push(Unit {
                name: format!("{room}.creation"),
                kind: UnitKind::RoomCreation { room: room.clone() },
                source: cc.to_string(),
            });
        }
        for i in r["instances"].as_array().unwrap() {
            let cc = i["creation_code"].as_str().unwrap_or("");
            if !cc.trim().is_empty() {
                let id = i["id"].as_i64().unwrap();
                units.push(Unit {
                    name: format!("{room}.inst{id}"),
                    kind: UnitKind::InstanceCreation { room: room.clone(), instance_id: id },
                    source: cc.to_string(),
                });
            }
        }
    }
    units
}
