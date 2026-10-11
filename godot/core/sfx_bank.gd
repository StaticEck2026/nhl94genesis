class_name SfxBank
extends Node
## Plays retail sound effects and songs from loose files. Retail sound is YM2612/PSG
## music and effects driven by sfx (L44279) and song (L44297); the port never emulates
## those chips. Each retail id maps to res://assets/audio/sfx/sfx_XX.(ogg|wav) (XX = hex
## id). A missing file is silent, so the game runs before audio exists.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## Ids confirmed from 94 call sites (docs/specs/animation_assets.md section 5.2); the
## 93 equates in ram94.asm differ.
const NAMES := {
	0x00: "after a goal (checkgoal)",
	0x01: "breakaway ding; penalty time tick",
	0x02: "penalty over; one minute left",
	0x03: "whistle (Stop4Pen)",
	0x04: "horn (clockcont)",
	0x05: "shot wiff; puck contact",
	0x06: "stick deflection (puckstick)",
	0x08: "puck hits the net frame, play live",
	0x0D: "injury (setInjuryType)",
	0x0E: "puck over the glass (wallcollb2)",
	0x10: "pass, soft", 0x11: "pass", 0x12: "pass", 0x13: "pass, hard",
	0x14: "backhand shot 0", 0x15: "backhand shot 1", 0x16: "backhand shot 2", 0x17: "backhand shot 3",
	0x18: "forehand shot 0", 0x19: "forehand shot 1", 0x1A: "forehand shot 2", 0x1B: "forehand shot 3",
	0x1C: "body check 0", 0x1D: "body check 1", 0x1E: "body check 2", 0x1F: "body check 3",
	0x20: "player hits boards (wallcoll)",
	0x24: "puck hits a body or goalie",
	0x25: "puck hits the net frame, clock stopped",
	0x28: "puck hits boards 1", 0x29: "puck hits boards 2", 0x2A: "puck hits boards 3", 0x2B: "puck hits boards 4",
	0x2C: "puck on ice 1", 0x2D: "puck on ice 2", 0x2E: "puck on ice 3",
	0x2F: "puck on ice 4; puck drop (Endfaceoff)",
}
## Songs (song L44297): $B crowd cheer, $C crowd boo, $D away song, $78 title / game
## over, $79 period over, $7A after setup; others are the organ tunes (ChooseSong).
const SONG_NAMES := {0x0B: "crowd cheer", 0x0C: "crowd boo", 0x0D: "away song",
	0x78: "title / game over", 0x79: "period over", 0x7A: "after setup"}
## Ids that belong on the Crowd bus instead of Sfx.
const CROWD_IDS: Array[int] = []
## Simultaneous effects.
const VOICES := 8

var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _cache := {}
var _next := 0
## lastsfx: retail remembers the last effect played.
var last_sfx: int = -1

## The crowd: PSG white noise whose attenuation follows the crowd level (updatesound).
var _crowd: AudioStreamPlayer

func _ready() -> void:
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

## sfx: negative ids are ignored, as in retail.
func play(id: int) -> void:
	if id < 0:
		return
	last_sfx = id
	var stream := _load(SFX_DIR, "sfx_%02x" % id)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.bus = &"Crowd" if id in CROWD_IDS else &"Sfx"
	p.stream = stream
	p.play()

## song: retail songs 0 end of period, 1 title, 3 end of game, 4 playoffs (93 numbering).
func play_song(id: int) -> void:
	if id < 0:
		return
	var stream := _load(MUSIC_DIR, "song_%02x" % id)
	if stream:
		_music.stream = stream
		_music.play()

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
