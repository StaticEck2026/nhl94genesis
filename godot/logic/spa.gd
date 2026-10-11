class_name Spa
extends RefCounted
## Retail sprite animation (SPA) ids, as SetSPA (L43319) takes them. Animation timing
## and frames come with the SPAList port (Phase 9). Names follow the 93 source.

const GLIDE := 0x50C
const GLIDE_BACK := 0xA60
const STOP := 0x6C6
const TURN_RIGHT := 0x694
const TURN_LEFT := 0x662
const SKATE := 0x5D0
const SKATE_BACK := 0xA92
const SKATE_INJURED := 0x11E6
const SKATE_PUCK := 0x53E
## goalieacc sets this on goalies that are moving (L43699).
const GOALIE_SKATE := 0x3D8

const NAMES := {
	GLIDE: "glide", GLIDE_BACK: "glide back", STOP: "stop", TURN_RIGHT: "turn right",
	TURN_LEFT: "turn left", SKATE: "skate", SKATE_BACK: "skate back",
	SKATE_INJURED: "skate injured", SKATE_PUCK: "skate with puck", GOALIE_SKATE: "goalie skate",
}

static func name_of(id: int) -> String:
	return NAMES.get(id, "spa $%X" % id)
