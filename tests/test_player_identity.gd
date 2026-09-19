extends Node

## Test suite for Player Identity & Visual Differentiation.
## Tests player colors definition, mesh material overrides, PlayerLabel text and modulation,
## floor ring indicators, instance material isolation, and round persistence.

const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2C PLAYER IDENTITY TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_constants_player_colors()
	failures += test_player_character_color_application()
	failures += test_player_index_switching()
	failures += test_material_override_instance_isolation()
	failures += test_workshop_multiplayer_visual_differentiation()
	failures += test_color_persistence_through_round()

	print("=========================================================")
	print("--- PHASE 2C TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2C PLAYER IDENTITY TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2C tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Verify Constants.PLAYER_COLORS contains 4 distinct colors
func test_constants_player_colors() -> int:
	print("\n[1] Testing Constants.PLAYER_COLORS definitions...")
	var err: int = 0

	err += _assert(Constants.PLAYER_COLORS.size() >= 4, "Constants.PLAYER_COLORS has at least 4 colors")

	var expected_colors: Array[Color] = [
		Color(0.2, 0.6, 1.0),   # P1 Blue
		Color(1.0, 0.35, 0.25),  # P2 Red
		Color(0.3, 0.85, 0.35),  # P3 Green
		Color(1.0, 0.75, 0.1),   # P4 Yellow
	]

	for i in range(4):
		var col: Color = Constants.PLAYER_COLORS[i]
		var exp_col: Color = expected_colors[i]
		err += _assert(col.is_equal_approx(exp_col), "P%d color is %s" % [i + 1, exp_col])

	# Check uniqueness
	for i in range(4):
		for j in range(i + 1, 4):
			err += _assert(
				Constants.PLAYER_COLORS[i] != Constants.PLAYER_COLORS[j],
				"Player colors %d and %d are distinct" % [i + 1, j + 1]
			)

	return err


## 2. Test PlayerCharacter visual setup with default player_index 0
func test_player_character_color_application() -> int:
	print("\n[2] Testing PlayerCharacter color application (P1 default)...")
	var err: int = 0

	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player)

	var p1_color: Color = Constants.PLAYER_COLORS[0]
	err += _assert(player.get_player_color() == p1_color, "get_player_color() returns P1 blue")

	var body_mesh: MeshInstance3D = player.character_model.get_node_or_null("BodyMesh") as MeshInstance3D
	err += _assert(body_mesh != null, "BodyMesh exists on CharacterModel")
	err += _assert(body_mesh.material_override != null, "BodyMesh has material_override applied")

	var body_mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
	err += _assert(body_mat != null, "material_override is StandardMaterial3D")
	if body_mat:
		err += _assert(body_mat.albedo_color.is_equal_approx(p1_color), "BodyMesh albedo_color matches P1 blue")

	var label: Label3D = player.player_label
	err += _assert(label != null, "PlayerLabel exists")
	err += _assert(label.text == "P1", "PlayerLabel text is 'P1'")
	err += _assert(label.modulate.is_equal_approx(p1_color), "PlayerLabel modulate matches P1 blue")

	var ring: MeshInstance3D = player.floor_ring
	err += _assert(ring != null, "FloorRing exists on PlayerCharacter")
	if ring:
		err += _assert(ring.material_override != null, "FloorRing has material_override applied")
		var ring_mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
		if ring_mat:
			err += _assert(ring_mat.albedo_color.is_equal_approx(p1_color), "FloorRing albedo_color matches P1 blue")
			err += _assert(ring_mat.emission_enabled, "FloorRing emission is enabled")
			err += _assert(ring_mat.emission.is_equal_approx(p1_color), "FloorRing emission color matches P1 blue")

	player.queue_free()
	return err


## 3. Test changing player_index updates all visual elements
func test_player_index_switching() -> int:
	print("\n[3] Testing dynamic set_player_index() visual updates...")
	var err: int = 0

	var player: PlayerCharacter = load(PLAYER_SCENE_PATH).instantiate() as PlayerCharacter
	add_child(player)

	var body_mesh: MeshInstance3D = player.character_model.get_node("BodyMesh") as MeshInstance3D
	var ring: MeshInstance3D = player.floor_ring

	for i in range(Constants.MAX_PLAYERS):
		player.set_player_index(i)
		var expected_color: Color = Constants.PLAYER_COLORS[i]
		var expected_text: String = "P%d" % (i + 1)

		err += _assert(player.player_index == i, "Player index is %d" % i)
		err += _assert(player.get_player_color() == expected_color, "P%d color is correct" % (i + 1))
		err += _assert(player.player_label.text == expected_text, "Label text is '%s'" % expected_text)
		err += _assert(player.player_label.modulate.is_equal_approx(expected_color), "Label modulate matches P%d color" % (i + 1))

		var body_mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
		err += _assert(body_mat.albedo_color.is_equal_approx(expected_color), "Body mesh albedo matches P%d color" % (i + 1))

		if ring and ring.material_override:
			var ring_mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
			err += _assert(ring_mat.albedo_color.is_equal_approx(expected_color), "Floor ring albedo matches P%d color" % (i + 1))

	player.queue_free()
	return err


## 4. Test that multiple player instances don't share materials (instance isolation)
func test_material_override_instance_isolation() -> int:
	print("\n[4] Testing per-instance material isolation across players...")
	var err: int = 0

	var p0: PlayerCharacter = load(PLAYER_SCENE_PATH).instantiate() as PlayerCharacter
	var p1: PlayerCharacter = load(PLAYER_SCENE_PATH).instantiate() as PlayerCharacter
	add_child(p0)
	add_child(p1)

	p0.set_player_index(0)
	p1.set_player_index(1)

	var p0_body: MeshInstance3D = p0.character_model.get_node("BodyMesh") as MeshInstance3D
	var p1_body: MeshInstance3D = p1.character_model.get_node("BodyMesh") as MeshInstance3D

	err += _assert(p0_body.material_override != p1_body.material_override, "p0 and p1 have distinct material_override instances")
	err += _assert(
		p0_body.material_override.albedo_color.is_equal_approx(Constants.PLAYER_COLORS[0]),
		"p0 body is Blue"
	)
	err += _assert(
		p1_body.material_override.albedo_color.is_equal_approx(Constants.PLAYER_COLORS[1]),
		"p1 body is Red"
	)

	# Modifying p0's material does not change p1's material
	p0_body.material_override.albedo_color = Color.WHITE
	err += _assert(
		p1_body.material_override.albedo_color.is_equal_approx(Constants.PLAYER_COLORS[1]),
		"Modifying p0 does not affect p1"
	)

	p0.queue_free()
	p1.queue_free()
	return err


## 5. Test workshop spawning 4 players with correct visual differentiation
func test_workshop_multiplayer_visual_differentiation() -> int:
	print("\n[5] Testing workshop 4-player visual differentiation...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	workshop.player_count_override = 4
	add_child(workshop)

	err += _assert(workshop.get_active_player_count() == 4, "Workshop spawned 4 players")

	for i in range(4):
		var p: PlayerCharacter = workshop.get_player(i)
		var expected_color: Color = Constants.PLAYER_COLORS[i]
		var expected_text := "P%d" % (i + 1)

		err += _assert(p != null, "Player %d exists" % i)
		err += _assert(p.player_label.text == expected_text, "Player %d label is %s" % [i, expected_text])
		err += _assert(p.player_label.modulate.is_equal_approx(expected_color), "Player %d label modulate is correct" % i)

		var body: MeshInstance3D = p.character_model.get_node("BodyMesh") as MeshInstance3D
		var mat: StandardMaterial3D = body.material_override as StandardMaterial3D
		err += _assert(mat.albedo_color.is_equal_approx(expected_color), "Player %d body color matches P%d" % [i, i + 1])

	workshop.queue_free()
	return err


## 6. Test that colors persist through movement and gameplay actions
func test_color_persistence_through_round() -> int:
	print("\n[6] Testing player color persistence through round actions...")
	var err: int = 0

	var player: PlayerCharacter = load(PLAYER_SCENE_PATH).instantiate() as PlayerCharacter
	player.player_index = 2  # P3 Green
	add_child(player)

	var p3_color: Color = Constants.PLAYER_COLORS[2]
	var body: MeshInstance3D = player.character_model.get_node("BodyMesh") as MeshInstance3D

	# Simulate movement
	player._input_direction = Vector3(1, 0, 0)
	player._physics_process(0.016)

	err += _assert(
		body.material_override.albedo_color.is_equal_approx(p3_color),
		"Color persists after movement"
	)
	err += _assert(player.player_label.text == "P3", "Label persists after movement")
	err += _assert(player.player_label.modulate.is_equal_approx(p3_color), "Label modulate persists after movement")

	player.queue_free()
	return err
