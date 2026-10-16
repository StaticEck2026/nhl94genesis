class_name SfxBank
extends Node
## Plays retail sound effects and songs from loose files rendered offline from the
## retail sound driver (tools/extract/audio.py, docs/specs/audio.md). sfx (L44279) and
## song (L44297) map each retail id to res://assets/audio/sfx/sfx_XX.wav or
## res://assets/audio/music/song_XX.ogg (XX = hex id). A missing file is silent.
## The mixer follows the driver's rules (spec section 6):
## - an id >= $30 started with song() replaces the music; a song() id below $30 (the crowd
##   cheer, boo, "oooh" and the home-leads bed) is an effect and leaves the music alone;
## - the whistle and the horn stop the music first (sub_1A304 before sfx 3 / sfx 4);
## - one DAC voice: a sampled effect sounds only if the DAC is idle or its instrument
##   number is higher than the one playing (loc_1A74E), so a second pass, shot or check
##   right after the first is silent, as in retail;
## - FM effects take a voice from a small pool.
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const META := "res://assets/audio/audio.json"
## The retail ids (docs/specs/audio.md section 9).
const NAMES := {
	0x00: "siren after a goal (checkgoal)",
	0x01: "breakaway ding; penalty time tick",
	0x02: "penalty over; one minute left",
	0x03: "whistle (Stop4Pen)",
	0x04: "horn (clockcont)",
	0x05: "shot wiff; puck contact",
	0x06: "stick deflection (puckstick)",
	0x07: "no call site",
	0x08: "puck hits the net frame, play live",
	0x09: "punch, high (fight patch)", 0x0A: "punch, low (fight patch)",
	0x0B: "crowd cheer", 0x0C: "crowd boo",
	0x0D: "crowd oooh: injury (setInjuryType), away goalie save",
	0x0E: "puck over the glass (wallcollb2)",
	0x0F: "crowd bed, home leads after the game",
	0x10: "pass, soft", 0x11: "pass", 0x12: "pass", 0x13: "pass, hard",
	0x14: "backhand shot 0", 0x15: "backhand shot 1", 0x16: "backhand shot 2", 0x17: "backhand shot 3",
	0x18: "forehand shot 0", 0x19: "forehand shot 1", 0x1A: "forehand shot 2", 0x1B: "forehand shot 3",
	0x1C: "body check 0", 0x1D: "body check 1", 0x1E: "body check 2", 0x1F: "body check 3",
	0x20: "player hits boards (wallcoll)", 0x21: "boards variant", 0x22: "boards variant",
	0x23: "boards variant",
	0x24: "puck hits a body or goalie",
	0x25: "puck hits the net frame, clock stopped",
	0x28: "puck hits boards 1", 0x29: "puck hits boards 2", 0x2A: "puck hits boards 3", 0x2B: "puck hits boards 4",
	0x2C: "puck on ice 1", 0x2D: "puck on ice 2", 0x2E: "puck on ice 3",
	0x2F: "puck on ice 4; puck drop (Endfaceoff)",
}
## Songs: $78 title / game over, $79 period over, $7A after the setup; $30-$77 are the
## organ tunes ChooseSong picks.
const SONG_NAMES := {0x78: "title / game over", 0x79: "period over", 0x7A: "after setup"}
const FIRST_SONG := 0x30
## The whistle and the horn (sub_1A304 stops the music before them).
const STOPS_MUSIC: Array[int] = [0x03, 0x04]
## Crowd samples, mixed on the Crowd bus.
const CROWD_IDS: Array[int] = [0x0B, 0x0C, 0x0D, 0x0F]
## FM effect voices.
const VOICES := 5

var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _dac: AudioStreamPlayer
var _cache := {}
var _next := 0
## Per id: [DAC instrument (-1 FM only), DAC busy seconds], and the songs' loop starts.
var _dac_info := {}
var _loop_start := {}
var _rate := 44100
## The DAC voice: the instrument holding it and until when (seconds of physics time).
var _dac_prio := 0
var _dac_until := 0.0
## lastsfx: retail remembers the last effect played.
var last_sfx: int = -1

## The crowd: PSG white noise whose attenuation follows the crowd level (updatesound).
var _crowd: AudioStreamPlayer

func _init() -> void:
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = &"Crowd"
	_crowd.stream = _noise_loop()
	_crowd.volume_db = -80.0
	add_child(_crowd)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"Sfx"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	_dac = AudioStreamPlayer.new()
	_dac.bus = &"Sfx"
	add_child(_dac)
	_load_meta()

func _load_meta() -> void:
	if not FileAccess.file_exists(META):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	if not d is Dictionary:
		return
	_rate = int(d.get("format", {}).get("rate", 44100))
	for k in d.get("ids", {}):
		var e: Dictionary = d["ids"][k]
		var id: int = String(k).hex_to_int()
		if e.get("dac_priority") != null:
			_dac_info[id] = [String(e["dac_priority"]).hex_to_int(), float(e["dac_busy_seconds"])]
		if e.get("loops", false):
			_loop_start[id] = int(e["loop_start"])

## sfx: negative ids are ignored, as in retail.
func play(id: int) -> void:
	if id < 0:
		return
	last_sfx = id
	if id in STOPS_MUSIC:
		_music.stop()
	var stream := _load(SFX_DIR, "sfx_%02x" % id)
	if stream == null:
		return
	var bus := &"Crowd" if id in CROWD_IDS else &"Sfx"
	if _dac_info.has(id):
		_play_dac(_dac_info[id][0], _dac_info[id][1], stream, bus)
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.bus = bus
	p.stream = stream
	_start(p)

## The DAC voice (loc_1A74E): taken only when idle or by a higher instrument number.
func _play_dac(prio: int, busy: float, stream: AudioStream, bus: StringName) -> void:
	var now := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	if now < _dac_until and prio <= _dac_prio:
		return
	_dac_prio = prio
	_dac_until = now + busy
	_dac.bus = bus
	_dac.stream = stream
	_start(_dac)

## song: an id from $30 replaces the music (the three long songs loop); below $30 it is
## a crowd effect.
func play_song(id: int) -> void:
	if id < 0:
		return
	if id < FIRST_SONG:
		play(id)
		return
	_music.stop()
	var stream := _load(MUSIC_DIR, "song_%02x" % id)
	if stream == null:
		return
	if _loop_start.has(id):
		if stream is AudioStreamOggVorbis:
			stream.loop = true
			stream.loop_offset = _loop_start[id] / float(_rate)
	elif stream is AudioStreamOggVorbis:
		stream.loop = false
	_music.stream = stream
	_start(_music)

## Outside the scene tree (headless tests) the streams are set but nothing plays.
static func _start(p: AudioStreamPlayer) -> void:
	if p.is_inside_tree():
		p.play()

## sub_1A304: the music stops.
func stop_music() -> void:
	_music.stop()

## updatesound's PSG noise attenuation (0 loudest .. 15 off), 2 dB a step.
func set_crowd_attenuation(att: int) -> void:
	if not _crowd.playing:
		_crowd.play()
	_crowd.volume_db = -80.0 if att >= 15 else -2.0 * att

## One second of white noise, looped (the PSG noise channel clocked by tone 2).
static func _noise_loop() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate)
	var lfsr := 0x4000
	for i in rate:
		var bit := (lfsr ^ (lfsr >> 1)) & 1
		lfsr = (lfsr >> 1) | (bit << 14)
		data[i] = 0xC0 if lfsr & 1 else 0x40
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = rate
	return w

func stop_all() -> void:
	for p in _players:
		p.stop()
	_dac.stop()
	_dac_until = 0.0
	_music.stop()
	_crowd.stop()

func _load(dir: String, base: String) -> AudioStream:
	var key := dir + base
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(key + ext):
			stream = load(key + ext)
			break
	_cache[key] = stream
	return stream
