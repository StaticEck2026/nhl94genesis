class_name SfxBank
extends Node
## Plays retail sound effects and songs from loose files. Retail sound is YM2612/PSG
## music and effects driven by sfx (L44279) and song (L44297); the port never emulates
## those chips. Each retail id maps to res://assets/audio/sfx/sfx_XX.(ogg|wav) (XX = hex
## id). A missing file is silent, so the game runs before audio exists.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## Ids confirmed from 94 code, with the routine that plays them. 93 equates differ.
const NAMES := {
	0x0E: "puck over the glass (wallcollb2)",
	0x20: "player hits boards (wallcoll)",
	0x28: "puck hits boards 1 (wallcoll)",
	0x29: "puck hits boards 2 (wallcoll)",
	0x2A: "puck hits boards 3 (wallcoll)",
	0x2B: "puck hits boards 4 (wallcoll)",
	0x2C: "puck on ice 1 (updateplayers)",
	0x2D: "puck on ice 2 (updateplayers)",
	0x2E: "puck on ice 3 (updateplayers)",
	0x2F: "puck on ice 4 (updateplayers)",
}
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

func _ready() -> void:
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

func stop_all() -> void:
	for p in _players:
		p.stop()
	_music.stop()

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
