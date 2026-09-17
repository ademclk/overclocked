extends Node

## Test suite for Main.tscn and main.gd (Phase 0.6 verification).


func _ready() -> void:
	print("--- RUNNING MAIN SCENE & ORCHESTRATION TESTS ---")

	# 1. Project settings checks
	print("Checking ProjectSettings configuration...")
	var main_scene_setting: String = ProjectSettings.get_setting("application/run/main_scene")
	assert(main_scene_setting == "res://scenes/main/Main.tscn", "main_scene mismatch")

	var vp_width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	assert(vp_width == 1920, "viewport_width mismatch")

	var vp_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert(vp_height == 1080, "viewport_height mismatch")

	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	assert(msaa == 1, "msaa_3d should be 1 (2x)")

	var physics: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	assert(physics == "Jolt Physics", "physics_engine should be Jolt Physics")
	print("ProjectSettings verified.")

	# 2. Load and instantiate Main.tscn
	print("Instantiating Main.tscn...")
	var main_scene: PackedScene = load("res://scenes/main/Main.tscn")
	assert(main_scene != null, "Failed to load res://scenes/main/Main.tscn")

	var main_node: Main = main_scene.instantiate() as Main
	assert(main_node != null, "Main.tscn root is not Main class")
	add_child(main_node)

	# 3. Check WorldEnvironment
	print("Checking WorldEnvironment...")
	var world_env_node: Node = main_node.get_node_or_null("WorldEnvironment")
	var world_env: WorldEnvironment = world_env_node as WorldEnvironment
	assert(world_env != null, "WorldEnvironment node missing")
	assert(world_env.environment != null, "WorldEnvironment must have an environment resource")
	print("WorldEnvironment verified.")

	# 4. Check CameraRig
	print("Checking CameraRig...")
	var cam_rig: CameraRig = main_node.get_node_or_null("CameraRig") as CameraRig
	assert(cam_rig != null, "CameraRig node missing")
	var cam3d: Camera3D = cam_rig.get_camera()
	assert(cam3d != null, "Camera3D child in CameraRig missing")
	assert(cam3d.current == true, "Camera3D should be active/current")
	print("CameraRig verified.")

	# 5. Check Workshop instance
	print("Checking Workshop child instance...")
	var workshop: WorkshopDebug = main_node.get_node_or_null("Workshop") as WorkshopDebug
	assert(workshop != null, "Workshop instance missing")
	assert(main_node.current_level == workshop, "main_node.current_level should point to Workshop")
	print("Workshop instance verified.")

	# 6. Check UI and DebugLabel
	print("Checking UI CanvasLayer and DebugLabel...")
	var ui: CanvasLayer = main_node.get_node_or_null("UI") as CanvasLayer
	assert(ui != null, "UI CanvasLayer missing")
	var debug_label: Label = ui.get_node_or_null("DebugLabel") as Label
	assert(debug_label != null, "DebugLabel missing from UI")
	assert(debug_label.text.contains("Phase 0 — Overclocked"), "DebugLabel missing title text")
	print("UI and DebugLabel verified.")

	# 7. Check GameState transition
	print("Checking GameManager state transition...")
	var is_playing: bool = GameManager.current_state == GameState.State.PLAYING
	assert(is_playing, "GameManager state should be PLAYING after Main._ready()")
	print("GameManager state PLAYING verified.")

	# 8. Test level reloading and SignalBus emission
	print("Testing level reloading...")
	var signal_results := {
		"level_loaded": false,
		"level_name": "",
		"level_restarted": false,
	}

	SignalBus.level_loaded.connect(
		func(lvl_name: String) -> void:
			signal_results.level_loaded = true
			signal_results.level_name = lvl_name
	)

	SignalBus.level_restarted.connect(func() -> void: signal_results.level_restarted = true)

	main_node.reload_level()
	assert(signal_results.level_loaded == true, "level_loaded signal should be emitted on reload")
	assert(signal_results.level_name == "Workshop", "level_loaded name mismatch")
	assert(
		signal_results.level_restarted == true,
		"level_restarted signal should be emitted on reload_level"
	)
	assert(main_node.current_level != null, "current_level should not be null after reload")
	print("Level reloading and signals verified.")

	print("--- ALL MAIN SCENE TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)
