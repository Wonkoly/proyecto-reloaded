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

/// `scenes`: folder of room scenes edited in Godot (godot/rooms); a room that has one takes its
/// creation code from the scene instead of the extracted JSON.
pub fn load(root: &Path, scenes: Option<&Path>) -> Vec<Unit> {
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
        let scene = scenes.map(|d| d.join(format!("{}.tscn", p.file_stem().unwrap().to_string_lossy())));
        let (room_cc, insts) = match scene.filter(|s| s.exists()) {
            Some(s) => scene_codes(&fs::read_to_string(&s).unwrap()),
            None => (
                r["creation_code"].as_str().unwrap_or("").to_string(),
                r["instances"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|i| (i["id"].as_i64().unwrap(), i["creation_code"].as_str().unwrap_or("").to_string()))
                    .collect(),
            ),
        };
        if !room_cc.trim().is_empty() {
            units.push(Unit {
                name: format!("{room}.creation"),
                kind: UnitKind::RoomCreation { room: room.clone() },
                source: room_cc,
            });
        }
        for (id, cc) in insts {
            if !cc.trim().is_empty() {
                units.push(Unit {
                    name: format!("{room}.inst{id}"),
                    kind: UnitKind::InstanceCreation { room: room.clone(), instance_id: id },
                    source: cc,
                });
            }
        }
    }
    units
}

/// Creation code of a room scene (.tscn written by Godot): the root node's `creation_code` and
/// each instance node's (`gm_id`, `creation_code`). Properties left at their default are omitted
/// by Godot, so a missing `creation_code` is empty.
fn scene_codes(text: &str) -> (String, Vec<(i64, String)>) {
    let mut room_cc = String::new();
    let mut insts = Vec::new();
    // Current [node] section: (is root, gm_id, creation_code)
    let mut cur: Option<(bool, Option<i64>, String)> = None;
    let flush = |cur: &mut Option<(bool, Option<i64>, String)>, room_cc: &mut String, insts: &mut Vec<(i64, String)>| {
        if let Some((root, id, cc)) = cur.take() {
            match (root, id) {
                (true, _) => *room_cc = cc,
                (false, Some(id)) => insts.push((id, cc)),
                _ => {},
            }
        }
    };
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let end = text[i..].find('\n').map_or(b.len(), |e| i + e);
        let line = &text[i..end];
        if line.starts_with('[') {
            flush(&mut cur, &mut room_cc, &mut insts);
            if line.starts_with("[node ") {
                cur = Some((!line.contains(" parent="), None, String::new()));
            }
            i = end + 1;
        } else if let Some(v) = line.strip_prefix("gm_id = ") {
            if let Some(c) = cur.as_mut() {
                c.1 = v.trim().parse().ok();
            }
            i = end + 1;
        } else if line.starts_with("creation_code = \"") {
            // A Godot string: may span lines; \\ and \" are escaped.
            let mut j = i + "creation_code = \"".len();
            let mut s = String::new();
            while j < b.len() && b[j] != b'"' {
                if b[j] == b'\\' && j + 1 < b.len() {
                    j += 1;
                    match b[j] {
                        b'n' => s.push('\n'),
                        b't' => s.push('\t'),
                        b'r' => s.push('\r'),
                        c => s.push(c as char),
                    }
                    j += 1;
                } else {
                    let ch = text[j..].chars().next().unwrap();
                    s.push(ch);
                    j += ch.len_utf8();
                }
            }
            if let Some(c) = cur.as_mut() {
                c.2 = s;
            }
            i = text[j..].find('\n').map_or(b.len(), |e| j + e + 1);
        } else {
            i = end + 1;
        }
    }
    flush(&mut cur, &mut room_cc, &mut insts);
    (room_cc, insts)
}
