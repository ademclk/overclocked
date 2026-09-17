class_name GameState
extends RefCounted

## Game state definitions and helpers for Overclocked

enum State {
	MENU,
	LOBBY,
	LOADING,
	PLAYING,
	PAUSED,
	RESULTS,
}

## Returns human-readable state name
static func to_string_name(state: State) -> String:
	match state:
		State.MENU:
			return "MENU"
		State.LOBBY:
			return "LOBBY"
		State.LOADING:
			return "LOADING"
		State.PLAYING:
			return "PLAYING"
		State.PAUSED:
			return "PAUSED"
		State.RESULTS:
			return "RESULTS"
		_:
			return "UNKNOWN"
