//! Dumps every asset of a GameMaker 8 executable into plain files (GML, JSON, PNG, audio)
//! so the game can be studied and ported to another engine.
//!
//! Usage: gm8dump <game.exe> <output_dir>

use gm8exe::{asset::PascalString, AssetList, GameAssets};
use rayon::prelude::*;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    io::BufWriter,
    path::{Path, PathBuf},
};

/// GM8 strings are Windows-1252, not UTF-8.
fn s(p: &PascalString) -> String {
    const HIGH: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž', '\u{8f}', '\u{90}', '‘',
        '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}', 'ž', 'Ÿ',
    ];
    p.0.iter()
        .map(|&b| match b {
            0x80..=0x9f => HIGH[(b - 0x80) as usize],
            _ => b as char,
        })
        .collect()
}

/// Turns CRLF into LF so the GML reads well in any editor.
fn code(p: &PascalString) -> String {
    s(p).replace("\r\n", "\n")
}

fn file_name(name: &str) -> String {
    name.chars().map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' }).collect()
}

fn names<T>(list: &AssetList<T>, get: impl Fn(&T) -> &PascalString) -> Vec<Option<String>> {
    list.iter().map(|a| a.as_ref().map(|a| s(get(a)))).collect()
}

fn lookup(names: &[Option<String>], id: i32) -> Value {
    if id < 0 {
        return Value::Null;
    }
    names.get(id as usize).cloned().flatten().map(Value::String).unwrap_or(Value::Null)
}

fn write_png(path: &Path, w: u32, h: u32, rgba: &[u8]) {
    let file = fs::File::create(path).expect("create png");
    let mut enc = png::Encoder::new(BufWriter::new(file), w, h);
    enc.set_color(png::ColorType::Rgba);
    enc.set_depth(png::BitDepth::Eight);
    enc.write_header().and_then(|mut w| w.write_image_data(rgba)).expect("write png");
}

/// GM8 stores pixels as BGRA.
fn bgra_to_rgba(data: &[u8]) -> Vec<u8> {
    let mut out = data.to_vec();
    out.chunks_exact_mut(4).for_each(|px| px.swap(0, 2));
    out
}

fn write_json(path: &Path, v: &Value) {
    fs::write(path, serde_json::to_string_pretty(v).unwrap()).expect("write json");
}

const EVENT_TYPES: [&str; 12] = [
    "create", "destroy", "alarm", "step", "collision", "keyboard", "mouse", "other", "draw", "keypress",
    "keyrelease", "trigger",
];

fn event_name(kind: usize, sub: u32, objects: &[Option<String>]) -> String {
    let sub_name = match kind {
        0 | 1 | 8 if sub == 0 => return EVENT_TYPES[kind].to_string(),
        3 => match sub {
            0 => "normal".into(),
            1 => "begin".into(),
            2 => "end".into(),
            _ => sub.to_string(),
        },
        4 => objects.get(sub as usize).cloned().flatten().unwrap_or_else(|| sub.to_string()),
        _ => sub.to_string(),
    };
    format!("{}_{}", EVENT_TYPES.get(kind).unwrap_or(&"unknown"), sub_name)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: {} <game.exe> <output_dir>", args[0]);
        std::process::exit(1);
    }
    let exe = fs::read(&args[1]).expect("read exe");
    let out = PathBuf::from(&args[2]);
    let assets: GameAssets =
        gm8exe::reader::from_exe(exe, Some(|m: &str| eprintln!("{m}")), false, true).expect("parse exe");

    let sprite_names = names(&assets.sprites, |a| &a.name);
    let sound_names = names(&assets.sounds, |a| &a.name);
    let bg_names = names(&assets.backgrounds, |a| &a.name);
    let path_names = names(&assets.paths, |a| &a.name);
    let script_names = names(&assets.scripts, |a| &a.name);
    let font_names = names(&assets.fonts, |a| &a.name);
    let object_names = names(&assets.objects, |a| &a.name);
    let room_names = names(&assets.rooms, |a| &a.name);

    for dir in ["scripts", "objects", "rooms", "sprites", "backgrounds", "sounds", "fonts"] {
        fs::create_dir_all(out.join(dir)).unwrap();
    }

    // Index of every resource id -> name, so GML that refers to numeric ids can be resolved.
    let index = json!({
        "sprites": sprite_names, "sounds": sound_names, "backgrounds": bg_names, "paths": path_names,
        "scripts": script_names, "fonts": font_names, "objects": object_names, "rooms": room_names,
    });
    write_json(&out.join("index.json"), &index);
    write_json(
        &out.join("room_order.json"),
        &json!(assets.room_order.iter().map(|&id| lookup(&room_names, id)).collect::<Vec<_>>()),
    );
    write_json(
        &out.join("constants.json"),
        &json!(assets.constants.iter().map(|c| (s(&c.name), s(&c.expression))).collect::<HashMap<_, _>>()),
    );

    // Original script text, byte-exact (the game's anti-tamper reads it via script_get_text).
    write_json(
        &out.join("scripts_raw.json"),
        &json!(assets.scripts.iter().flatten().map(|sc| (s(&sc.name), s(&sc.source))).collect::<HashMap<_, _>>()),
    );

    // Scripts
    assets.scripts.par_iter().flatten().for_each(|sc| {
        fs::write(out.join("scripts").join(format!("{}.gml", file_name(&s(&sc.name)))), code(&sc.source)).unwrap();
    });

    // Objects: metadata + events as JSON, plus one readable .gml with all event code.
    assets.objects.par_iter().flatten().for_each(|o| {
        let mut events = serde_json::Map::new();
        let mut gml = String::new();
        for (kind, subs) in o.events.iter().enumerate() {
            for (sub, actions) in subs {
                let name = event_name(kind, *sub, &object_names);
                let acts: Vec<Value> = actions
                    .iter()
                    .map(|a| {
                        let params: Vec<String> = a.param_strings[..a.param_count.min(8)].iter().map(code).collect();
                        // lib 1 / action 603 is "Execute code": the GML lives in the first param.
                        let is_code = a.lib_id == 1 && a.id == 603;
                        if is_code {
                            gml.push_str(&format!("/// ==== {name} ====\n"));
                            if a.applies_to != -1 {
                                gml.push_str(&format!("// applies_to: {}\n", a.applies_to));
                            }
                            gml.push_str(params.first().map(String::as_str).unwrap_or(""));
                            gml.push_str("\n\n");
                        } else {
                            gml.push_str(&format!(
                                "/// ==== {name} ==== [D&D lib {} action {} fn '{}' params {:?}]\n\n",
                                a.lib_id,
                                a.id,
                                s(&a.fn_name),
                                params
                            ));
                        }
                        json!({
                            "lib_id": a.lib_id, "id": a.id, "kind": a.action_kind, "exec_type": a.execution_type,
                            "fn_name": s(&a.fn_name), "fn_code": code(&a.fn_code),
                            "applies_to": a.applies_to, "relative": a.is_relative,
                            "is_condition": a.is_condition, "not": a.invert_condition,
                            "param_types": &a.param_types[..a.param_count.min(8)], "params": params,
                        })
                    })
                    .collect();
                events.insert(name, Value::Array(acts));
            }
        }
        let meta = json!({
            "name": s(&o.name), "sprite": lookup(&sprite_names, o.sprite_index), "solid": o.solid,
            "visible": o.visible, "depth": o.depth, "persistent": o.persistent,
            "parent": lookup(&object_names, o.parent_index), "mask": lookup(&sprite_names, o.mask_index),
            "events": events,
        });
        let base = file_name(&s(&o.name));
        write_json(&out.join("objects").join(format!("{base}.json")), &meta);
        fs::write(out.join("objects").join(format!("{base}.gml")), gml).unwrap();
    });

    // Rooms
    assets.rooms.par_iter().flatten().for_each(|r| {
        let v = json!({
            "name": s(&r.name), "caption": s(&r.caption), "width": r.width, "height": r.height,
            "speed": r.speed, "persistent": r.persistent, "bg_colour": r.bg_colour.as_decimal(),
            "clear_screen": r.clear_screen, "creation_code": code(&r.creation_code),
            "backgrounds": r.backgrounds.iter().map(|b| json!({
                "visible": b.visible_on_start, "foreground": b.is_foreground, "bg": lookup(&bg_names, b.source_bg),
                "x": b.xoffset, "y": b.yoffset, "tile_h": b.tile_horz, "tile_v": b.tile_vert,
                "hspeed": b.hspeed, "vspeed": b.vspeed, "stretch": b.stretch,
            })).collect::<Vec<_>>(),
            "views_enabled": r.views_enabled,
            "views": r.views.iter().map(|w| json!({
                "visible": w.visible, "x": w.source_x, "y": w.source_y, "w": w.source_w, "h": w.source_h,
                "port_x": w.port_x, "port_y": w.port_y, "port_w": w.port_w, "port_h": w.port_h,
                "follow": lookup(&object_names, w.following.target),
                "hborder": w.following.hborder, "vborder": w.following.vborder,
                "hspeed": w.following.hspeed, "vspeed": w.following.vspeed,
            })).collect::<Vec<_>>(),
            "instances": r.instances.iter().map(|i| json!({
                "id": i.id, "object": lookup(&object_names, i.object), "x": i.x, "y": i.y,
                "xscale": i.xscale, "yscale": i.yscale, "angle": i.angle, "blend": i.blend,
                "creation_code": code(&i.creation_code),
            })).collect::<Vec<_>>(),
            "tiles": r.tiles.iter().map(|t| json!({
                "id": t.id, "bg": lookup(&bg_names, t.source_bg), "x": t.x, "y": t.y,
                "tx": t.tile_x, "ty": t.tile_y, "w": t.width, "h": t.height, "depth": t.depth,
                "xscale": t.xscale, "yscale": t.yscale, "blend": t.blend,
            })).collect::<Vec<_>>(),
        });
        write_json(&out.join("rooms").join(format!("{}.json", file_name(&s(&r.name)))), &v);
    });

    // Sprites: one folder per sprite with frame PNGs + meta.
    assets.sprites.par_iter().flatten().for_each(|sp| {
        let dir = out.join("sprites").join(file_name(&s(&sp.name)));
        fs::create_dir_all(&dir).unwrap();
        for (i, f) in sp.frames.iter().enumerate() {
            write_png(&dir.join(format!("{i}.png")), f.width, f.height, &bgra_to_rgba(&f.data));
        }
        let bbox = sp.colliders.first().map(|c| {
            json!({"left": c.bbox_left, "right": c.bbox_right, "top": c.bbox_top, "bottom": c.bbox_bottom})
        });
        // Collision masks: "full" masks (solid bbox) need no pixel data; others get a mask PNG.
        let colliders: Vec<Value> = sp
            .colliders
            .iter()
            .enumerate()
            .map(|(i, c)| {
                let full = (c.bbox_top..=c.bbox_bottom.min(c.height.saturating_sub(1))).all(|y| {
                    (c.bbox_left..=c.bbox_right.min(c.width.saturating_sub(1)))
                        .all(|x| c.data.get((y * c.width + x) as usize).copied().unwrap_or(false))
                });
                if !full && c.width > 0 && c.height > 0 {
                    let rgba: Vec<u8> = c.data.iter().flat_map(|&b| if b { [255; 4] } else { [0; 4] }).collect();
                    write_png(&dir.join(format!("mask{i}.png")), c.width, c.height, &rgba);
                }
                json!({"left": c.bbox_left, "right": c.bbox_right, "top": c.bbox_top, "bottom": c.bbox_bottom,
                       "w": c.width, "h": c.height, "full": full})
            })
            .collect();
        write_json(
            &dir.join("meta.json"),
            &json!({
                "name": s(&sp.name), "origin_x": sp.origin_x, "origin_y": sp.origin_y,
                "frames": sp.frames.len(), "width": sp.frames.first().map(|f| f.width),
                "height": sp.frames.first().map(|f| f.height), "bbox": bbox,
                "per_frame_colliders": sp.per_frame_colliders, "colliders": colliders,
            }),
        );
    });

    // Backgrounds / tilesets
    assets.backgrounds.par_iter().flatten().for_each(|b| {
        if let Some(data) = &b.data {
            let p = out.join("backgrounds").join(format!("{}.png", file_name(&s(&b.name))));
            write_png(&p, b.width, b.height, &bgra_to_rgba(data));
        }
    });

    // Sounds (raw files as embedded in the exe)
    let mut sounds_meta = serde_json::Map::new();
    for snd in assets.sounds.iter().flatten() {
        let name = s(&snd.name);
        let ext = s(&snd.extension);
        if let Some(data) = &snd.data {
            fs::write(out.join("sounds").join(format!("{}{}", file_name(&name), ext)), data).unwrap();
        }
        sounds_meta.insert(
            name,
            json!({"file": format!("{}{}", file_name(&s(&snd.name)), ext), "source": s(&snd.source),
                   "kind": snd.kind as u32, "volume": snd.volume, "pan": snd.pan, "has_data": snd.data.is_some()}),
        );
    }
    write_json(&out.join("sounds").join("sounds.json"), &Value::Object(sounds_meta));

    // Fonts: glyph atlas (white + alpha) and the glyph map.
    for f in assets.fonts.iter().flatten() {
        let base = file_name(&s(&f.name));
        let rgba: Vec<u8> = f.pixel_map.iter().flat_map(|&a| [255, 255, 255, a]).collect();
        if f.map_width > 0 && f.map_height > 0 {
            write_png(&out.join("fonts").join(format!("{base}.png")), f.map_width, f.map_height, &rgba);
        }
        let glyphs: Vec<Value> = (f.range_start..=f.range_end.min(255))
            .map(|c| {
                let g = &f.dmap[c as usize * 6..c as usize * 6 + 6];
                json!({"char": c, "x": g[0], "y": g[1], "w": g[2], "h": g[3], "offset": g[4], "advance": g[5]})
            })
            .collect();
        write_json(
            &out.join("fonts").join(format!("{base}.json")),
            &json!({"name": s(&f.name), "sys_name": s(&f.sys_name), "size": f.size, "bold": f.bold,
                    "italic": f.italic, "glyphs": glyphs}),
        );
    }

    // Paths
    write_json(
        &out.join("paths.json"),
        &json!(assets.paths.iter().flatten().map(|p| json!({
            "name": s(&p.name), "closed": p.closed, "precision": p.precision,
            "smooth": p.connection as u32 == 1,
            "points": p.points.iter().map(|pt| [pt.x, pt.y, pt.speed]).collect::<Vec<_>>(),
        })).collect::<Vec<_>>()),
    );

    // Game settings that affect runtime semantics.
    let st = &assets.settings;
    write_json(
        &out.join("settings.json"),
        &json!({
            "fullscreen": st.fullscreen, "scaling": st.scaling, "interpolate_pixels": st.interpolate_pixels,
            "clear_colour": st.clear_colour, "allow_resize": st.allow_resize, "display_cursor": st.display_cursor,
            "vsync": st.vsync, "esc_close_game": st.esc_close_game, "f4_fullscreen_toggle": st.f4_fullscreen_toggle,
            "f5_save_f6_load": st.f5_save_f6_load, "f9_screenshot": st.f9_screenshot,
            "zero_uninitialized_vars": st.zero_uninitialized_vars,
            "error_on_uninitialized_args": st.error_on_uninitialized_args,
            "swap_creation_events": st.swap_creation_events, "freeze_on_lose_focus": st.freeze_on_lose_focus,
            "game_id": assets.game_id, "last_instance_id": assets.last_instance_id, "last_tile_id": assets.last_tile_id,
            "version": format!("{:?}", assets.version),
        }),
    );

    eprintln!("Done -> {}", out.display());
}
