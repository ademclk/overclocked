extends Node

## Test suite for Phase 2B: Multi-Player Spawning.
## Tests multi-player spawning, player indices, designated spawn positions,
## active_players tracking, SignalBus signals, graceful fallbacks, and runtime spawning.

const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2B MULTIPLAYER SPAWNING TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_default_spawning_single_player()
	failures += test_multiplayer_spawning_with_override()
	failures += test_player_joined_and_left_signals()
	failures += test_runtime_additional_player_spawning_f10()
	failures += test_graceful_spawn_point_fallbacks()
	failures += test_active_players_cleanup_on_freed_instances()
	failures += test_gamemanager_registered_player_count()

	print("=========================================================")
	print("--- PHASE 2B TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2B MULTIPLAYER SPAWNING TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2B tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Test single-player default spawning behavior (keyboard fallback)
func test_default_spawning_single_player() -> int:
	print("\n[1] Testing default single-player spawning behavior...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 1, "Exactly 1 player spawned by default")
	err += _assert(workshop.get_active_player_count() == 1, "get_active_player_count() returns 1")

	var p0: PlayerCharacter = workshop.get_player(0)
	err += _assert(p0 != null, "Player 0 exists and is valid")
	err += _assert(p0.player_index == 0, "Player 0 has player_index == 0")
	err += _assert(p0.is_in_group("players"), "Player 0 is in 'players' group")

	var p1_marker: Marker3D = workshop.spawn_point_p1
	err += _assert(p1_marker != null, "SpawnPoint_P1 exists")
	err += _assert(
		p0.global_position.is_equal_approx(p1_marker.global_position),
		"Player 0 spawned at SpawnPoint_P1"
	)

	var label: Label3D = p0.get_node_or_null("PlayerLabel") as Label3D
	err += _assert(label != null and label.text == "P1", "Player 0 label is 'P1'")

	workshop.queue_free()
	return err


## 2. Test 4-player spawning via player_count_override
func test_multiplayer_spawning_with_override() -> int:
	print("\n[2] Testing 4-player spawning via player_count_override...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	workshop.player_count_override = 4
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 4, "All 4 players spawned via override")
	err += _assert(workshop.get_active_player_count() == 4, "get_active_player_count() returns 4")

	var markers: Array[Marker3D] = [
		workshop.spawn_point_p1,
		workshop.spawn_point_p2,
		workshop.spawn_point_p3,
		workshop.spawn_point_p4
	]

	for i in range(4):
		var p: PlayerCharacter = workshop.get_player(i)
		err += _assert(p != null, "Player %d exists" % i)
		if p:
			err += _assert(p.player_index == i, "Player %d has correct player_index (%d)" % [i, p.player_index])
			err += _assert(p.is_in_group("players"), "Player %d is in 'players' group" % i)
			err += _assert(
				p.global_position.is_equal_approx(markers[i].global_position),
				"Player %d spawned at SpawnPoint_P%d" % [i, i + 1]
			)
			var lbl: Label3D = p.get_node_or_null("PlayerLabel") as Label3D
			var expected_lbl := "P%d" % (i + 1)
			err += _assert(lbl != null and lbl.text == expected_lbl, "Player %d label is '%s'" % [i, expected_lbl])

	# Ensure duplicate spawn call returns existing player without creating new one
	var p0_dup: PlayerCharacter = workshop.spawn_player(0)
	err += _assert(p0_dup == workshop.get_player(0), "spawn_player(0) returns existing instance")
	err += _assert(workshop.active_players.size() == 4, "active_players size remains 4")

	workshop.queue_free()
	return err


## 3. Test SignalBus player_joined and player_left emissions
func test_player_joined_and_left_signals() -> int:
	print("\n[3] Testing SignalBus.player_joined and SignalBus.player_left...")
	var err: int = 0

	var joined_events: Array[int] = []
	var left_events: Array[int] = []

	var on_joined := func(pid: int) -> void: joined_events.append(pid)
	var on_left := func(pid: int) -> void: left_events.append(pid)

	SignalBus.player_joined.connect(on_joined)
	SignalBus.player_left.connect(on_left)

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	# Spawn players sequentially
	for i in range(3):
		workshop.spawn_player(i)

	err += _assert(joined_events.size() == 3, "player_joined emitted 3 times")
	err += _assert(joined_events == [0, 1, 2], "player_joined emitted with IDs [0, 1, 2]")

	# Despawn player 1
	var despawn_ok: bool = workshop.despawn_player(1)
	err += _assert(despawn_ok, "despawn_player(1) succeeded")
	err += _assert(left_events.size() == 1 and left_events[0] == 1, "player_left emitted with ID 1")
	err += _assert(workshop.get_player(1) == null, "Player 1 no longer found in workshop")
	err += _assert(workshop.get_active_player_count() == 2, "2 active players remain")

	# Despawn remaining players
	workshop.despawn_all_players()
	err += _assert(workshop.get_active_player_count() == 0, "All players despawned")
	err += _assert(left_events.size() == 3, "player_left emitted for all players")

	SignalBus.player_joined.disconnect(on_joined)
	SignalBus.player_left.disconnect(on_left)
	workshop.queue_free()
	return err


## 4. Test runtime spawning via F10 hotkey
func test_runtime_additional_player_spawning_f10() -> int:
	print("\n[4] Testing runtime player spawning (F10 hotkey)...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.get_active_player_count() == 1, "Initial player count is 1")

	# Simulate F10 key presses
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.echo = false
	key_event.keycode = KEY_F10

	workshop._unhandled_input(key_event)
	err += _assert(workshop.get_active_player_count() == 2, "F10 spawned Player 2 (total 2)")
	err += _assert(workshop.get_player(1) != null, "Player 1 exists")

	workshop._unhandled_input(key_event)
	err += _assert(workshop.get_active_player_count() == 3, "F10 spawned Player 3 (total 3)")
	err += _assert(workshop.get_player(2) != null, "Player 2 exists")

	workshop._unhandled_input(key_event)
	err += _assert(workshop.get_active_player_count() == 4, "F10 spawned Player 4 (total 4)")
	err += _assert(workshop.get_player(3) != null, "Player 3 exists")

	# Fifth press should cap at MAX_PLAYERS
	workshop._unhandled_input(key_event)
	err += _assert(workshop.get_active_player_count() == 4, "F10 capped at MAX_PLAYERS (4)")

	workshop.queue_free()
	return err


## 5. Test graceful spawn point fallbacks when markers are missing
func test_graceful_spawn_point_fallbacks() -> int:
	print("\n[5] Testing graceful spawn point fallbacks...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	# Remove P3 and P4 markers to test fallback
	if workshop.spawn_point_p3:
		workshop.spawn_point_p3.queue_free()
	if workshop.spawn_point_p4:
		workshop.spawn_point_p4.queue_free()

	# Positions should still be generated without overlapping
	var pos0 := workshop.get_spawn_position(0)
	var pos1 := workshop.get_spawn_position(1)
	var pos2 := workshop.get_spawn_position(2)
	var pos3 := workshop.get_spawn_position(3)
	var pos4 := workshop.get_spawn_position(4)

	err += _assert(pos0 != pos1, "Pos 0 and Pos 1 are distinct")
	err += _assert(pos0 != pos2, "Pos 0 and Pos 2 are distinct")
	err += _assert(pos2 != pos3, "Pos 2 and Pos 3 are distinct")
	err += _assert(pos3 != pos4, "Pos 3 and Pos 4 are distinct")
	err += _assert(pos2.z > pos0.z, "Pos 2 is offset behind Pos 0 on Z axis")
	err += _assert(pos3.x > pos2.x, "Pos 3 is offset to right of Pos 2 on X axis")

	workshop.queue_free()
	return err


## 6. Test active_players list cleanup when an instance is freed
func test_active_players_cleanup_on_freed_instances() -> int:
	print("\n[6] Testing active_players safe cleanup on freed instances...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	var p0 := workshop.spawn_player(0)
	var p1 := workshop.spawn_player(1)

	err += _assert(workshop.active_players.size() == 2, "2 active players initially")

	# Free p1 externally
	p1.free()

	# active_players cleanup should handle freed node gracefully
	var active_list := workshop.get_active_players()
	err += _assert(active_list.size() == 1, "get_active_players() pruned invalid instance")
	err += _assert(active_list[0] == p0, "Remaining player is p0")
	err += _assert(workshop.get_player(1) == null, "get_player(1) returns null safely")

	workshop.queue_free()
	return err


## 7. Test GameManager.registered_player_count integration
func test_gamemanager_registered_player_count() -> int:
	print("\n[7] Testing GameManager.registered_player_count integration...")
	var err: int = 0

	GameManager.registered_player_count = 3

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.get_active_player_count() == 3, "Spawns 3 players based on GameManager")

	GameManager.registered_player_count = 0
	workshop.queue_free()
	return err
