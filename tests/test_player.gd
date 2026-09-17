extends Node

## Test suite for PlayerCharacter (Phase 1A verification).


func _ready() -> void:
	print("--- RUNNING PLAYER CHARACTER TESTS ---")

	# 1. Load scene
	print("Checking PlayerCharacter.tscn loading...")
	var scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	assert(scene != null, "Failed to load PlayerCharacter.tscn")

	# 2. Instantiate player
	print("Instantiating PlayerCharacter...")
	var player: PlayerCharacter = scene.instantiate() as PlayerCharacter
	assert(player != null, "PlayerCharacter failed to instantiate")
	add_child(player)

	# 3. Check collision layer and mask
	print("Checking collision layers and masks...")
	assert(
		player.collision_layer == Constants.COLLISION_MASK_PLAYERS,
		"player.collision_layer mismatch"
	)
	var expected_mask: int = (
		Constants.COLLISION_MASK_WORLD
		| Constants.COLLISION_MASK_STATIONS
		| Constants.COLLISION_MASK_ITEMS
	)
	assert(player.collision_mask == expected_mask, "player.collision_mask mismatch")
	assert(player.floor_constant_speed == true, "floor_constant_speed should be true")
	assert(player.floor_stop_on_slope == true, "floor_stop_on_slope should be true")

	# 4. Check child nodes
	print("Checking required child nodes...")
	var col_shape: CollisionShape3D = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert(col_shape != null, "CollisionShape3D missing")
	var capsule_shape: CapsuleShape3D = col_shape.shape as CapsuleShape3D
	assert(capsule_shape != null, "Collision shape is not CapsuleShape3D")
	assert(is_equal_approx(capsule_shape.height, Constants.CHARACTER_HEIGHT), "Height mismatch")
	assert(is_equal_approx(capsule_shape.radius, 0.3), "Radius mismatch")

	var model: Node3D = player.get_node_or_null("CharacterModel") as Node3D
	assert(model != null, "CharacterModel missing")
	var body_mesh: MeshInstance3D = model.get_node_or_null("BodyMesh") as MeshInstance3D
	assert(body_mesh != null, "BodyMesh missing")

	var visor: MeshInstance3D = model.get_node_or_null("Visor") as MeshInstance3D
	assert(visor != null, "Visor missing")

	var carry_pos: Marker3D = player.get_node_or_null("CarryPosition") as Marker3D
	assert(carry_pos != null, "CarryPosition missing")

	var interaction_area: Area3D = player.get_node_or_null("InteractionArea") as Area3D
	assert(interaction_area != null, "InteractionArea missing")
	var expected_interaction_mask: int = (
		Constants.COLLISION_MASK_STATIONS | Constants.COLLISION_MASK_ITEMS
	)
	assert(
		interaction_area.collision_mask == expected_interaction_mask,
		"InteractionArea collision_mask mismatch"
	)

	var p_label: Label3D = player.get_node_or_null("PlayerLabel") as Label3D
	assert(p_label != null, "PlayerLabel missing")
	assert(p_label.text == "P1", "PlayerLabel should default to P1")

	# 5. Check player index change
	print("Checking player index update...")
	player.set_player_index(1)
	assert(player.player_index == 1, "Player index should be 1")
	assert(p_label.text == "P2", "PlayerLabel should update to P2")
	player.set_player_index(0)

	# 6. Test movement states and signals
	print("Testing movement state machine and footstep signals...")
	var state_signals: Array[PlayerCharacter.MovementState] = []
	player.movement_state_changed.connect(
		func(state: PlayerCharacter.MovementState) -> void: state_signals.append(state)
	)

	var footsteps: Array[int] = []
	player.footstep.connect(func(p_idx: int) -> void: footsteps.append(p_idx))

	assert(player.current_movement_state == PlayerCharacter.MovementState.IDLE)
	assert(not player.is_walking())

	# Simulate moving
	player._input_direction = Vector3(1, 0, 0)
	player.velocity = player._input_direction * player.move_speed
	player._update_movement_state(0.1)

	assert(player.current_movement_state == PlayerCharacter.MovementState.WALKING)
	assert(player.is_walking())
	assert(state_signals.size() == 1 and state_signals[0] == PlayerCharacter.MovementState.WALKING)

	# Accumulate footsteps: need >= 1.2 distance. With speed 6.0, 0.2s = 1.2 distance
	player._update_movement_state(0.2)
	assert(footsteps.size() >= 1, "Footstep signal should have fired")
	assert(footsteps[0] == 0, "Footstep player_index mismatch")

	# Return to idle
	player._input_direction = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player._update_movement_state(0.1)
	assert(player.current_movement_state == PlayerCharacter.MovementState.IDLE)
	assert(not player.is_walking())
	assert(state_signals.size() == 2 and state_signals[1] == PlayerCharacter.MovementState.IDLE)

	# 7. Test rotation toward input direction
	print("Testing character rotation toward direction...")
	# Simulate moving right (+X)
	player._input_direction = Vector3(1, 0, 0)
	# Run a few rotation steps to let lerp converge
	for i in range(20):
		player._rotate_toward_direction(0.1)

	var target_angle_right: float = atan2(1.0, 0.0) # PI/2
	assert(
		is_equal_approx(model.rotation.y, target_angle_right),
		"Model rotation should face right (approx PI/2)"
	)
	# 8. Test Workshop spawning integration
	print("Testing WorkshopDebug spawning integration...")
	var workshop_scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn")
	assert(workshop_scene != null, "Failed to load Workshop_Debug.tscn")

	var joined_players: Array[int] = []
	var join_connection: Callable = func(p_id: int) -> void: joined_players.append(p_id)
	SignalBus.player_joined.connect(join_connection)

	var workshop: WorkshopDebug = workshop_scene.instantiate() as WorkshopDebug
	add_child(workshop)

	assert(joined_players.size() == 1, "SignalBus.player_joined should be emitted on workshop spawn")
	assert(joined_players[0] == 0, "Spawned player_index should be 0")

	var spawned_player: PlayerCharacter = workshop.get_player(0)
	assert(spawned_player != null, "workshop.get_player(0) should return active player")
	var expected_spawn_pos: Vector3 = workshop.get_spawn_position(0)
	assert(
		spawned_player.global_position.is_equal_approx(expected_spawn_pos),
		"Spawned player position should match SpawnPoint_P1"
	)

	SignalBus.player_joined.disconnect(join_connection)

	print("--- ALL PLAYER CHARACTER TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)
