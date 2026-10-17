## Plays GM sounds on the main thread. One player per sound index (GM8 sounds don't overlap
## with themselves); background-music sounds (kind 1) stop any other background music.
extends Node

var _players: Dictionary = {}   # sound index -> AudioStreamPlayer
var _streams: Dictionary = {}   # path -> AudioStream
var _kinds: Dictionary = {}     # sound index -> kind
var _volume: Dictionary = {}    # sound index -> linear volume
var _global := 1.0
var _fades: Dictionary = {}     # sound index -> [from, to, t, duration]

func command(cmd: Array) -> void:
	match cmd[0]:
		"snd_play":
			_play(cmd[1], cmd[2], cmd[3], cmd[4])
		"snd_stop":
			if _players.has(cmd[1]):
				_players[cmd[1]].stop()
		"snd_stop_all":
			for p in _players.values():
				p.stop()
		"snd_volume":
			_volume[cmd[1]] = clampf(cmd[2], 0.0, 1.0)
			_apply_volume(cmd[1])
		"snd_global_volume":
			_global = clampf(cmd[1], 0.0, 1.0)
			for i in _players:
				_apply_volume(i)
		"snd_fade":
			_fades[cmd[1]] = [_volume.get(cmd[1], 1.0), clampf(cmd[2], 0.0, 1.0), 0.0, maxf(cmd[3], 1.0) / 1000.0]
		"snd_replace":
			if _players.has(cmd[1]):
				_players[cmd[1]].stop()
				_players[cmd[1]].stream = null

func playing_state() -> Dictionary:
	var out := {}
	for i in _players:
		if _players[i].playing:
			out[i] = true
	return out

func _process(delta: float) -> void:
	for i in _fades.keys():
		var f: Array = _fades[i]
		f[2] += delta
		var k := clampf(f[2] / f[3], 0.0, 1.0)
		_volume[i] = lerpf(f[0], f[1], k)
		_apply_volume(i)
		if k >= 1.0:
			_fades.erase(i)

func _apply_volume(i: int) -> void:
	if _players.has(i):
		_players[i].volume_db = linear_to_db(maxf(_volume.get(i, 1.0) * _global, 0.0001))

func _play(i: int, path: String, loop: bool, kind: int) -> void:
	if path == "":
		return
	var stream := _load(path)
	if stream == null:
		return
	if kind == 1:
		for j in _players:
			if j != i and _kinds.get(j, 0) == 1:
				_players[j].stop()
	_kinds[i] = kind
	var p: AudioStreamPlayer = _players.get(i)
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		_players[i] = p
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif "loop" in stream:
		stream.loop = loop
	p.stream = stream
	_apply_volume(i)
	p.play()

func _load(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var ext := path.get_extension().to_lower()
	var s: AudioStream = null
	if ext == "mid" or ext == "midi":
		# MIDI is pre-rendered to OGG next to the original by tools/prepare_gamedata.py.
		var ogg := path.get_basename() + ".ogg"
		if FileAccess.file_exists(ogg):
			s = AudioStreamOggVorbis.load_from_file(ogg)
	elif ext == "ogg":
		s = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "wav":
		s = AudioStreamWAV.load_from_file(path)
	elif ext == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(path)
		s = mp3
	if s == null:
		push_warning("[GM audio] can't load " + path)
	_streams[path] = s
	return s
