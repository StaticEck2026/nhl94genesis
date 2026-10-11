class_name PlayerFSM
extends RefCounted
## Discrete skater states. Nodes read `state` to pick animations.
## Retail drives this through SPA animation ids (SetSPA L43319) and $62/$63 flag bits;
## each transition below names the routine it comes from as it is ported.

enum State { IDLE, SKATING, TURNING, STOPPING, SHOOTING, PASSING, CHECKING, FALLEN, CELEBRATING }

signal state_changed(from: State, to: State)

var state: State = State.IDLE
## Retail frames spent in the current state.
var frames_in_state: float = 0.0

const _ALLOWED := {
	State.IDLE: [State.SKATING, State.SHOOTING, State.PASSING, State.CHECKING, State.FALLEN, State.CELEBRATING],
	State.SKATING: [State.IDLE, State.TURNING, State.STOPPING, State.SHOOTING, State.PASSING, State.CHECKING, State.FALLEN, State.CELEBRATING],
	State.TURNING: [State.SKATING, State.STOPPING, State.FALLEN],
	State.STOPPING: [State.IDLE, State.SKATING, State.FALLEN],
	State.SHOOTING: [State.IDLE, State.SKATING, State.FALLEN],
	State.PASSING: [State.IDLE, State.SKATING, State.FALLEN],
	State.CHECKING: [State.IDLE, State.SKATING, State.FALLEN],
	State.FALLEN: [State.IDLE],
	State.CELEBRATING: [State.IDLE, State.SKATING],
}

func can_enter(to: State) -> bool:
	return to in _ALLOWED[state]

## Returns false and leaves the state alone when the move is not allowed.
func enter(to: State) -> bool:
	if to == state or not can_enter(to):
		return false
	var from := state
	state = to
	frames_in_state = 0.0
	state_changed.emit(from, to)
	return true

func tick(frames: float) -> void:
	frames_in_state += frames
