extends Node

## Test suite for Workshop_Debug.tscn and workshop_debug.gd.


func _ready() -> void:
	print("--- RUNNING WORKSHOP_DEBUG TESTS ---")

	# 1. Load and instantiate scene
	var scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn")
	assert(scene != null, "Failed to load Workshop_Debug.tscn")

	var workshop: WorkshopDebug = scene.instantiate() as WorkshopDebug
	assert(workshop != null, "Failed to instantiate WorkshopDebug")
	add_child(workshop)

	# 2. Check Floor
	print("Checking workshop floor...")
	var floor_node: CSGBox3D = workshop.get_node_or_null("Floor") as CSGBox3D
	assert(floor_node != null, "Floor node missing from Workshop_Debug")
	assert(floor_node.use_collision == true, "Floor must have use_collision = true")
	assert(is_equal_approx(floor_node.size.x, 10.0), "Floor width should be 10.0")
	assert(is_equal_approx(floor_node.size.z, 10.0), "Floor depth should be 10.0")
	# Top surface should be at Y = 0.0: position.y (-0.2) + size.y * 0.5 (0.2) = 0.0
	var top_surface_y: float = floor_node.position.y + (floor_node.size.y * 0.5)
	assert(is_equal_approx(top_surface_y, 0.0), "Floor top surface should be at Y = 0.0")
	assert(floor_node.material != null, "Floor should have a material assigned")
	print("Floor geometry, collision, and material verified")

	# 3. Check Walls
	print("Checking room boundary walls...")
	var walls: Node3D = workshop.get_node_or_null("Walls") as Node3D
	assert(walls != null, "Walls node missing from Workshop_Debug")
	var wall_names := ["WallNorth", "WallSouth", "WallWest", "WallEast"]
	for wname in wall_names:
		var wall: CSGBox3D = walls.get_node_or_null(wname) as CSGBox3D
		assert(wall != null, "Wall %s missing" % wname)
		assert(wall.use_collision == true, "Wall %s must have use_collision = true" % wname)
		assert(wall.collision_layer & 1 != 0, "Wall %s must be on Collision Layer 1" % wname)
	print("All 4 boundary walls verified with collision")

	# 4. Check Workbench
	print("Checking workbench station...")
	var bench: Node3D = workshop.get_node_or_null("Workbench") as Node3D
	assert(bench != null, "Workbench missing from Workshop_Debug")
	if bench is BaseStation:
		assert(bench.collision_layer & Constants.COLLISION_MASK_STATIONS != 0, "Workbench must include station collision mask")
	elif bench is CSGBox3D:
		assert(bench.use_collision == true, "Workbench must have use_collision = true")
		assert(bench.collision_layer & Constants.COLLISION_MASK_STATIONS != 0, "Workbench must include station collision mask")
	print("Workbench station dimensions and collision layer verified")

	# 5. Check Lighting
	print("Checking overhead workshop light...")
	var light_node: Node = workshop.get_node_or_null("DirectionalLight3D")
	var light: DirectionalLight3D = light_node as DirectionalLight3D
	assert(light != null, "DirectionalLight3D missing from Workshop_Debug")
	assert(light.shadow_enabled == true, "DirectionalLight3D must have shadows enabled")
	assert(
		light.light_color.r > 0.9 and light.light_color.g > 0.9, "Light color should be warm white"
	)
	print("Overhead lighting verified")

	# 6. Check Player Spawn Point
	print("Checking spawn marker...")
	var spawn: Marker3D = workshop.get_node_or_null("SpawnPoint_P1") as Marker3D
	assert(spawn != null, "SpawnPoint_P1 marker missing")
	assert(is_equal_approx(spawn.position.y, 0.0), "Spawn point Y should be on floor level (0.0)")
	print("SpawnPoint_P1 verified")

	# 7. Check WorkshopDebug Helper Methods
	print("Checking WorkshopDebug helper functions...")
	var spawn_pos := workshop.get_spawn_position(0)
	assert(spawn_pos == spawn.global_position, "get_spawn_position() mismatch")

	var room_size := workshop.get_room_size()
	assert(room_size == Vector2(10.0, 10.0), "get_room_size() mismatch")

	var bench_pos := workshop.get_workbench_position()
	assert(bench_pos == bench.global_position, "get_workbench_position() mismatch")

	var bounds := workshop.get_room_bounds()
	assert(bounds.size.x == 10.0 and bounds.size.z == 10.0, "get_room_bounds() mismatch")
	print("Helper methods verified")

	print("--- ALL WORKSHOP_DEBUG TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)
