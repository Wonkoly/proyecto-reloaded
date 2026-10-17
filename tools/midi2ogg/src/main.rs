//! Pre-renders the game's MIDI music to OGG (GM8 played MIDI through the Windows synth; Godot
//! has no MIDI player). Usage: midi2ogg <soundfont.sf2> <dir>
//! Every `*.mid` under <dir> without one gets a `.ogg` next to it, rendered with rustysynth and encoded by
//! ffmpeg. The render stops exactly at the end of the MIDI so looped music doesn't gain a gap.

use rayon::prelude::*;
use rustysynth::{MidiFile, MidiFileSequencer, SoundFont, Synthesizer, SynthesizerSettings};
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;

const RATE: i32 = 44100;

fn find_midis(dir: &Path, out: &mut Vec<PathBuf>) {
    for e in std::fs::read_dir(dir).expect("read dir").flatten() {
        let p = e.path();
        if p.is_dir() {
            find_midis(&p, out);
        } else if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("mid") || x.eq_ignore_ascii_case("midi")) {
            out.push(p);
        }
    }
}

fn render(sf: &Arc<SoundFont>, mid: &Path) -> Result<(), String> {
    let bytes = std::fs::read(mid).map_err(|e| e.to_string())?;
    // RMID files wrap a standard MIDI file in a RIFF container: parse from the MThd chunk.
    let start = bytes.windows(4).position(|w| w == b"MThd").ok_or("no MThd chunk")?;
    let midi = Arc::new(MidiFile::new(&mut &bytes[start..]).map_err(|e| format!("{e:?}"))?);
    let synth = Synthesizer::new(sf, &SynthesizerSettings::new(RATE)).map_err(|e| format!("{e:?}"))?;
    let mut seq = MidiFileSequencer::new(synth);
    seq.play(&midi, false);
    let total = ((midi.get_length() * RATE as f64).ceil() as usize).max(1);
    let mut pcm = Vec::with_capacity(total * 4);
    let (mut l, mut r) = (vec![0f32; 4096], vec![0f32; 4096]);
    let mut done = 0;
    while done < total {
        let n = (total - done).min(4096);
        seq.render(&mut l[..n], &mut r[..n]);
        for i in 0..n {
            for s in [l[i], r[i]] {
                pcm.extend_from_slice(&((s.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes());
            }
        }
        done += n;
    }
    let out = mid.with_extension("ogg");
    let mut ff = Command::new("ffmpeg")
        .args(["-v", "error", "-y", "-f", "s16le", "-ar", &RATE.to_string(), "-ac", "2", "-i", "-"])
        .args(["-c:a", "libvorbis", "-q:a", "4"])
        .arg(&out)
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("ffmpeg: {e}"))?;
    ff.stdin.take().unwrap().write_all(&pcm).map_err(|e| e.to_string())?;
    let st = ff.wait().map_err(|e| e.to_string())?;
    if !st.success() {
        return Err(format!("ffmpeg failed for {}", out.display()));
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: midi2ogg <soundfont.sf2> <dir>");
        std::process::exit(2);
    }
    let sf = Arc::new(SoundFont::new(&mut File::open(&args[1]).expect("soundfont")).expect("parse soundfont"));
    let mut mids = Vec::new();
    find_midis(Path::new(&args[2]), &mut mids);
    mids.retain(|m| !m.with_extension("ogg").exists());
    let failed: Vec<String> = mids
        .par_iter()
        .filter_map(|m| render(&sf, m).err().map(|e| format!("{}: {e}", m.display())))
        .collect();
    for f in &failed {
        eprintln!("{f}");
    }
    println!("{} MIDI, {} rendered, {} failed", mids.len(), mids.len() - failed.len(), failed.len());
}
