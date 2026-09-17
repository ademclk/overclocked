extends Node

func _ready() -> void:
	print("--- Running Phase 0.2 Verification ---")

	# 1. Test GameState
	print("Checking GameState...")
	assert(GameState.State.MENU == 0)
	assert(GameState.to_string_name(GameState.State.PLAYING) == "PLAYING")

	# 2. Test Constants
	print("Checking Constants...")
	assert(Constants.UNIT_SCALE == 1.0)
	assert(Constants.MAX_PLAYERS == 4)
	assert(Constants.COLLISION_LAYER_WORLD == 1)

	# 3. Test SignalBus Autoload
	print("Checking SignalBus autoload singleton...")
	assert(SignalBus != null)
	assert(SignalBus.has_signal("game_state_changed"))
	assert(SignalBus.has_signal("level_loaded"))
	assert(SignalBus.has_signal("player_joined"))

	# 4. Test GameManager Autoload
	print("Checking GameManager autoload singleton...")
	assert(GameManager != null)
	assert(GameManager.current_state == GameState.State.MENU)

	# Test state transition
	print("Testing state transitions...")
	var transitioned := GameManager.change_state(GameState.State.PLAYING)
	assert(transitioned == true)
	assert(GameManager.current_state == GameState.State.PLAYING)

	# Test invalid transition (PLAYING -> LOBBY is invalid per rules)
	var invalid_transition := GameManager.change_state(GameState.State.LOBBY)
	assert(invalid_transition == false)
	assert(GameManager.current_state == GameState.State.PLAYING)

	# Test pause toggle
	GameManager.toggle_pause()
	assert(GameManager.current_state == GameState.State.PAUSED)
	GameManager.toggle_pause()
	assert(GameManager.current_state == GameState.State.PLAYING)

	print("--- ALL PHASE 0.2 CHECKS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)
