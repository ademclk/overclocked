extends Node

## Central game state orchestrator (thin manager) for Overclocked.
## Manages high-level game states and delegates gameplay to scenes and systems.

var current_state: GameState.State = GameState.State.MENU
var previous_state: GameState.State = GameState.State.MENU
var registered_player_count: int = 0
var registered_device_assignments: Dictionary = {}


func _ready() -> void:
	# Ensure GameManager continues processing even when the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	MultiplayerInput.setup_device_listener()
	set_initial_state(GameState.State.MENU)


## Sets the initial state without transition validation
func set_initial_state(initial_state: GameState.State) -> void:
	previous_state = initial_state
	current_state = initial_state
	SignalBus.game_state_changed.emit(previous_state, current_state)


## Requests a state change. Returns true if transition was successful.
func change_state(new_state: GameState.State) -> bool:
	if new_state == current_state:
		return false

	if not _is_valid_transition(current_state, new_state):
		push_warning(
			(
				"GameManager: Invalid state transition from %s to %s"
				% [GameState.to_string_name(current_state), GameState.to_string_name(new_state)]
			)
		)
		return false

	previous_state = current_state
	current_state = new_state

	_handle_state_enter(current_state)
	SignalBus.game_state_changed.emit(previous_state, current_state)
	return true


## Checks whether transition from one state to another is allowed
func _is_valid_transition(from_state: GameState.State, to_state: GameState.State) -> bool:
	match from_state:
		GameState.State.MENU:
			return (
				to_state
				in [GameState.State.LOBBY, GameState.State.LOADING, GameState.State.PLAYING]
			)
		GameState.State.LOBBY:
			return (
				to_state in [GameState.State.MENU, GameState.State.LOADING, GameState.State.PLAYING]
			)
		GameState.State.LOADING:
			return to_state in [GameState.State.PLAYING, GameState.State.MENU]
		GameState.State.PLAYING:
			return (
				to_state in [GameState.State.PAUSED, GameState.State.RESULTS, GameState.State.MENU]
			)
		GameState.State.PAUSED:
			return (
				to_state in [GameState.State.PLAYING, GameState.State.MENU, GameState.State.RESULTS]
			)
		GameState.State.RESULTS:
			return (
				to_state in [GameState.State.LOADING, GameState.State.PLAYING, GameState.State.MENU]
			)
		_:
			return false


## Handles state entry side-effects (such as tree pausing)
func _handle_state_enter(state: GameState.State) -> void:
	match state:
		GameState.State.PAUSED:
			get_tree().paused = true
			SignalBus.game_paused.emit(true)
		_:
			if get_tree().paused:
				get_tree().paused = false
				SignalBus.game_paused.emit(false)


## Toggles between PLAYING and PAUSED states
func toggle_pause() -> void:
	if current_state == GameState.State.PLAYING:
		change_state(GameState.State.PAUSED)
	elif current_state == GameState.State.PAUSED:
		change_state(GameState.State.PLAYING)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
