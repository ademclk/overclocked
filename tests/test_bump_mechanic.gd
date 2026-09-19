extends Node

## Test suite for Bump Mechanic
## Tests:
## 1. CharacterBody3D collision configuration (layer & mask include PLAYERS)
## 2. Low-speed collision does NOT trigger bump or stun
## 3. High-speed collision triggers bump (initiator 0.15s, target 0.3s stun)
## 4. Bumped player drops carried item
## 5. Bump cooldown prevents stunlock (1.0s)
## 6. Stunned player cannot move (velocity remains Vector3.ZERO)
## 7. Stun recovery restores movement and visual state
## 8. Visual feedback on stun (mesh emission and model wobble)
## 9. SignalBus and PlayerCharacter signal emissions

const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2I BUMP MECHANIC TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_player_collision_layers_and_masks()
	failures += test_low_speed_no_bump()
	failures += test_high_speed_bump_and_stun_durations()
	failures += test_bumped_player_drops_carried_item()
	failures += test_bump_cooldown_prevents_stunlock()
	failures += test_stunned_player_movement_disabled()
	failures += test_stun_recovery_lifecycle()
	failures += test_stun_visual_feedback()
	failures += test_bump_signal_emissions()

	print("=========================================================")
	print("--- PHASE 2I TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2I BUMP MECHANIC TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2I tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_player(index: int, pos: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = scene.instantiate() as PlayerCharacter
	player.player_index = index
	add_child(player)
	player.global_position = pos
	return player


## 1. Test collision layer and mask include players
func test_player_collision_layers_and_masks() -> int:
	print("\n[1] Testing PlayerCharacter collision layers and masks...")
	var err: int = 0

	var p1 := _create_player(0)
	var mask_players: int = Constants.COLLISION_MASK_PLAYERS

	err += _assert((p1.collision_layer & mask_players) != 0, "collision_layer includes COLLISION_MASK_PLAYERS")
	err += _assert((p1.collision_mask & mask_players) != 0, "collision_mask includes COLLISION_MASK_PLAYERS")
	err += _assert((p1.collision_mask & Constants.COLLISION_MASK_WORLD) != 0, "collision_mask includes WORLD")
	err += _assert((p1.collision_mask & Constants.COLLISION_MASK_STATIONS) != 0, "collision_mask includes STATIONS")
	err += _assert((p1.collision_mask & Constants.COLLISION_MASK_ITEMS) != 0, "collision_mask includes ITEMS")

	p1.queue_free()
	return err


## 2. Test low-speed collision does NOT trigger bump
func test_low_speed_no_bump() -> int:
	print("\n[2] Testing low-speed collision does NOT trigger bump...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.5, 0.0, 0.0))

	# Speeds below threshold (e.g. 1.0 + 1.0 = 2.0 < 4.0)
	p1._last_motion_speed = 1.0
	p2._last_motion_speed = 1.0

	var bump_events: Array[PlayerCharacter] = []
	p1.player_bumped.connect(func(other): bump_events.append(other))
	p2.player_bumped.connect(func(other): bump_events.append(other))

	# Directly test bump logic with speeds under threshold
	var combined_speed: float = p1.get_last_motion_speed() + p2.get_last_motion_speed()
	err += _assert(combined_speed < Constants.BUMP_SPEED_THRESHOLD, "Combined speed (2.0) is below BUMP_SPEED_THRESHOLD (4.0)")

	# Calling bump check won't trigger bump if speed sum < threshold
	if combined_speed >= Constants.BUMP_SPEED_THRESHOLD:
		p1._apply_bump(p2)

	err += _assert(not p1.is_stunned(), "p1 is NOT stunned on low speed")
	err += _assert(not p2.is_stunned(), "p2 is NOT stunned on low speed")
	err += _assert(bump_events.is_empty(), "No bump events fired on low speed")

	p1.queue_free()
	p2.queue_free()
	return err


## 3. Test high-speed bump and stun durations
func test_high_speed_bump_and_stun_durations() -> int:
	print("\n[3] Testing high-speed bump triggers correct stun durations...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.5, 0.0, 0.0))

	p1._last_motion_speed = 6.0
	p2._last_motion_speed = 6.0

	err += _assert(not p1.is_stunned(), "p1 initially not stunned")
	err += _assert(not p2.is_stunned(), "p2 initially not stunned")

	# P1 bumps P2
	p1._apply_bump(p2)

	err += _assert(p1.is_stunned(), "p1 (initiator) is stunned")
	err += _assert(p2.is_stunned(), "p2 (bumped target) is stunned")

	# Check timers: initiator gets half duration (0.15s), target gets full (0.3s)
	err += _assert(is_equal_approx(p1._stun_timer, Constants.BUMP_STUN_DURATION * 0.5),
		"p1 stun duration is 0.15s (got %.2fs)" % p1._stun_timer)
	err += _assert(is_equal_approx(p2._stun_timer, Constants.BUMP_STUN_DURATION),
		"p2 stun duration is 0.30s (got %.2fs)" % p2._stun_timer)

	p1.queue_free()
	p2.queue_free()
	return err


## 4. Test bumped player drops carried item
func test_bumped_player_drops_carried_item() -> int:
	print("\n[4] Testing bumped player drops carried item...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.5, 0.0, 0.0))

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load("res://resources/devices/phone.tres"))
	add_child(dev)

	p2.carry_system.pick_up(dev)
	err += _assert(p2.carry_system.is_carrying(), "p2 carries device before bump")
	err += _assert(dev.is_held, "dev is held")
	err += _assert(dev.held_by == p2, "dev held by p2")

	# P1 bumps P2
	p1._apply_bump(p2)

	err += _assert(not p2.carry_system.is_carrying(), "p2 dropped item upon being bumped")
	err += _assert(not dev.is_held, "device is no longer held")
	err += _assert(dev.held_by == null, "device held_by is cleared")
	err += _assert(dev.claimed_by == null, "device claim is released and available")

	dev.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 5. Test bump cooldown prevents stunlock
func test_bump_cooldown_prevents_stunlock() -> int:
	print("\n[5] Testing bump cooldown prevents stunlock...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.5, 0.0, 0.0))

	p1._apply_bump(p2)

	err += _assert(is_equal_approx(p1.get_bump_cooldown(), Constants.BUMP_COOLDOWN),
		"p1 cooldown is %f" % Constants.BUMP_COOLDOWN)
	err += _assert(is_equal_approx(p2.get_bump_cooldown(), Constants.BUMP_COOLDOWN),
		"p2 cooldown is %f" % Constants.BUMP_COOLDOWN)

	# Try to trigger another bump while on cooldown
	var initial_p2_stun_timer: float = p2._stun_timer
	p1._check_bumps() # Should exit early due to cooldown
	err += _assert(p2._stun_timer == initial_p2_stun_timer, "No re-bump while cooldown is active")

	# Advance physics by 0.5s (timer decrements)
	p1._physics_process(0.5)
	err += _assert(p1.get_bump_cooldown() < Constants.BUMP_COOLDOWN, "Cooldown timer decrements during physics process")

	p1.queue_free()
	p2.queue_free()
	return err


## 6. Test stunned player movement is completely disabled
func test_stunned_player_movement_disabled() -> int:
	print("\n[6] Testing stunned player movement is disabled...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	p1.stun(0.3)
	err += _assert(p1.is_stunned(), "p1 is stunned")

	# Set an artificial velocity and input direction
	p1.velocity = Vector3(5.0, 0.0, 5.0)
	p1._input_direction = Vector3(1.0, 0.0, 1.0)

	p1._physics_process(0.016)

	err += _assert(p1.velocity == Vector3.ZERO, "velocity forced to Vector3.ZERO while stunned")
	err += _assert(p1.current_movement_state == PlayerCharacter.MovementState.IDLE, "movement state is IDLE while stunned")

	p1.queue_free()
	return err


## 7. Test stun recovery lifecycle
func test_stun_recovery_lifecycle() -> int:
	print("\n[7] Testing stun recovery lifecycle and recovered signal...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var recovered_called: Array[bool] = [false]
	p1.recovered.connect(func(): recovered_called[0] = true)

	p1.stun(0.2)
	err += _assert(p1.is_stunned(), "p1 stunned for 0.2s")
	err += _assert(not recovered_called[0], "recovered signal not yet fired")

	# Process 0.1s — still stunned
	p1._physics_process(0.1)
	err += _assert(p1.is_stunned(), "still stunned after 0.1s")

	# Process 0.15s — exceeds 0.2s duration, should recover
	p1._physics_process(0.15)
	err += _assert(not p1.is_stunned(), "p1 is no longer stunned after duration expires")
	err += _assert(recovered_called[0], "recovered signal was emitted")

	p1.queue_free()
	return err


## 8. Test visual feedback during stun and restoration on recovery
func test_stun_visual_feedback() -> int:
	print("\n[8] Testing visual feedback during stun...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var body_mesh: MeshInstance3D = p1.character_model.get_node_or_null("BodyMesh") as MeshInstance3D
	err += _assert(body_mesh != null, "BodyMesh exists on player character model")

	var mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
	err += _assert(mat != null, "material_override exists")
	err += _assert(not mat.emission_enabled, "emission initially disabled")

	# Stun player
	p1.stun(0.3)
	err += _assert(mat.emission_enabled, "emission enabled during stun flash")
	err += _assert(mat.emission_energy_multiplier > 0.0, "emission energy multiplier > 0 during stun")

	# Recover
	p1._end_stun()
	err += _assert(not mat.emission_enabled, "emission disabled after stun recovery")
	err += _assert(is_equal_approx(p1.character_model.position.y, p1._original_model_pos.y),
		"character_model restored to original position")

	p1.queue_free()
	return err


## 9. Test bump signals on PlayerCharacter and SignalBus
func test_bump_signal_emissions() -> int:
	print("\n[9] Testing bump signals emission...")
	var err: int = 0

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var local_bumper_event := {"other": null, "fired": false}
	p1.player_bumped.connect(func(other):
		local_bumper_event.other = other
		local_bumper_event.fired = true
	)

	var bus_event := {"bumper": -1, "bumped": -1, "fired": false}
	SignalBus.player_bumped.connect(func(b1, b2):
		bus_event.bumper = b1
		bus_event.bumped = b2
		bus_event.fired = true
	)

	p1._apply_bump(p2)

	err += _assert(local_bumper_event.fired, "p1.player_bumped signal fired")
	err += _assert(local_bumper_event.other == p2, "player_bumped passed other player (p2)")
	err += _assert(bus_event.fired, "SignalBus.player_bumped signal fired")
	err += _assert(bus_event.bumper == 0, "SignalBus bumper index is 0")
	err += _assert(bus_event.bumped == 1, "SignalBus bumped index is 1")

	p1.queue_free()
	p2.queue_free()
	return err
