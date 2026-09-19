extends Node

## Test suite for Camera System — Auto-Framing All Players.
## Tests multi-player auto-centering, adaptive zoom spread, min/max bounds clamping,
## smooth lerp interpolation, room bounds clamping, single-player fallback, and camera shake.

const CAMERA_RIG_SCENE_PATH: String = "res://scenes/main/CameraRig.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2D CAMERA TRACKING TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_default_camera_rig_properties()
	failures += test_camera_auto_center_multiplayer()
	failures += test_camera_zoom_spread_adaptive()
	failures += test_camera_min_max_zoom_bounds()
	failures += test_smooth_camera_interpolation()
	failures += test_room_bounds_clamping()
	failures += test_single_player_fallback()
	failures += test_camera_shake_integration()
	failures += test_signalbus_and_group_integration()
	failures += test_diagonal_axis_players_ground_centering()

	print("=========================================================")
	print("--- PHASE 2D TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2D CAMERA TRACKING TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2D tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Verify default properties and backward compatibility
func test_default_camera_rig_properties() -> int:
	print("\n[1] Testing default CameraRig properties & Phase 1 compatibility...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	err += _assert(not rig.tracking_enabled, "tracking_enabled defaults to false")
	err += _assert(is_equal_approx(rig.camera_height, 12.0), "camera_height defaults to 12.0")
	err += _assert(is_equal_approx(rig.camera_distance, 8.0), "camera_distance defaults to 8.0")
	err += _assert(is_equal_approx(rig.camera_angle, -55.0), "camera_angle defaults to -55.0")
	err += _assert(is_equal_approx(rig.min_camera_height, 8.0), "min_camera_height is 8.0")
	err += _assert(is_equal_approx(rig.max_camera_height, 18.0), "max_camera_height is 18.0")
	err += _assert(is_equal_approx(rig.player_padding, 3.0), "player_padding is 3.0")

	# Test frame_bounds still sets target_offset
	rig.frame_bounds(Vector3(-5, 0, -4), Vector3(5, 0, 4))
	err += _assert(rig.target_offset == Vector3.ZERO, "frame_bounds symmetric room gives zero offset")

	rig.queue_free()
	return err


## 2. Test auto-centering on midpoint of multiple players
func test_camera_auto_center_multiplayer() -> int:
	print("\n[2] Testing auto-centering on player midpoint...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	var p1 := Node3D.new()
	var p2 := Node3D.new()
	add_child(p1)
	add_child(p2)

	p1.global_position = Vector3(2.0, 0.0, 1.0)
	p2.global_position = Vector3(6.0, 0.0, 5.0)

	rig.set_tracked_players([p1, p2])
	err += _assert(rig.tracking_enabled, "tracking_enabled automatically set to true")
	err += _assert(rig.get_tracked_players().size() == 2, "2 tracked players registered")

	rig.snap_to_target()

	# Midpoint of (2, 0, 1) and (6, 0, 5) is (4, 0, 3)
	var expected_center := Vector3(4.0, 0.0, 3.0)
	err += _assert(
		rig.target_offset.is_equal_approx(expected_center),
		"target_offset centered on midpoint (4.0, 0.0, 3.0), got %s" % rig.target_offset
	)

	p1.queue_free()
	p2.queue_free()
	rig.queue_free()
	return err


## 3. Test adaptive zoom (zooms out when players spread, zooms in when close)
func test_camera_zoom_spread_adaptive() -> int:
	print("\n[3] Testing adaptive zoom spread...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	var p1 := Node3D.new()
	var p2 := Node3D.new()
	add_child(p1)
	add_child(p2)

	# Close together
	p1.global_position = Vector3(0.0, 0.0, 0.0)
	p2.global_position = Vector3(1.0, 0.0, 1.0)
	rig.set_tracked_players([p1, p2])
	rig.snap_to_target()
	var close_height: float = rig.camera_height

	# Spread far apart
	p1.global_position = Vector3(-6.0, 0.0, -6.0)
	p2.global_position = Vector3(6.0, 0.0, 6.0)
	rig.snap_to_target()
	var spread_height: float = rig.camera_height

	err += _assert(
		spread_height > close_height,
		"Camera height increases when players spread (Close: %.2f, Spread: %.2f)" % [close_height, spread_height]
	)
	err += _assert(close_height >= rig.min_camera_height, "Close height >= min_camera_height (8.0)")
	err += _assert(spread_height <= rig.max_camera_height, "Spread height <= max_camera_height (18.0)")

	p1.queue_free()
	p2.queue_free()
	rig.queue_free()
	return err


## 4. Test strict min and max zoom bounds clamping
func test_camera_min_max_zoom_bounds() -> int:
	print("\n[4] Testing min and max zoom bounds clamping...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	var p1 := Node3D.new()
	var p2 := Node3D.new()
	add_child(p1)
	add_child(p2)

	# Extreme distance (should cap at max_camera_height)
	p1.global_position = Vector3(-500.0, 0.0, 0.0)
	p2.global_position = Vector3(500.0, 0.0, 0.0)
	rig.set_tracked_players([p1, p2])
	rig.snap_to_target()

	err += _assert(
		is_equal_approx(rig.camera_height, rig.max_camera_height),
		"Extreme distance capped at max_camera_height (%.1f)" % rig.max_camera_height
	)

	p1.queue_free()
	p2.queue_free()
	rig.queue_free()
	return err


## 5. Test smooth camera movement (lerp without snapping)
func test_smooth_camera_interpolation() -> int:
	print("\n[5] Testing smooth camera interpolation...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	rig.tracking_smoothing = 5.0
	rig.zoom_smoothing = 3.0
	add_child(rig)

	var p1 := Node3D.new()
	add_child(p1)
	p1.global_position = Vector3(10.0, 0.0, 10.0)

	rig.set_tracked_players([p1])
	rig.target_offset = Vector3.ZERO
	rig.camera_height = 8.0

	# Advance 1 frame with small delta (e.g. 0.05s)
	rig._process(0.05)

	# Should interpolate smoothly, NOT jump immediately to 10.0
	err += _assert(
		rig.target_offset.x > 0.0 and rig.target_offset.x < 10.0,
		"Target offset interpolated partially towards target (got X=%.3f)" % rig.target_offset.x
	)

	var first_x: float = rig.target_offset.x

	# Advance another frame
	rig._process(0.05)
	err += _assert(
		rig.target_offset.x > first_x and rig.target_offset.x <= 10.0,
		"Target offset progressed further on subsequent frame (got X=%.3f)" % rig.target_offset.x
	)

	p1.queue_free()
	rig.queue_free()
	return err


## 6. Test room bounds clamping
func test_room_bounds_clamping() -> int:
	print("\n[6] Testing room bounds clamping...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	# Room bounds from -5 to +5 on X, and -4 to +4 on Z
	var room := AABB(Vector3(-5.0, 0.0, -4.0), Vector3(10.0, 2.0, 8.0))
	rig.set_room_bounds(room)

	var p1 := Node3D.new()
	add_child(p1)
	# Player stands outside room walls
	p1.global_position = Vector3(25.0, 0.0, 20.0)

	rig.set_tracked_players([p1])
	rig.snap_to_target()

	err += _assert(
		rig.target_offset.x <= 5.0,
		"Target offset X clamped within room max (%.2f <= 5.0)" % rig.target_offset.x
	)
	err += _assert(
		rig.target_offset.z <= 4.0,
		"Target offset Z clamped within room max (%.2f <= 4.0)" % rig.target_offset.z
	)

	p1.queue_free()
	rig.queue_free()
	return err


## 7. Test single player fallback behavior
func test_single_player_fallback() -> int:
	print("\n[7] Testing single player fallback behavior...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	var p1 := Node3D.new()
	add_child(p1)
	p1.global_position = Vector3(1.5, 0.0, 3.0)

	rig.set_tracked_players([p1])
	rig.snap_to_target()

	err += _assert(
		rig.target_offset.is_equal_approx(Vector3(1.5, 0.0, 3.0)),
		"Single player centered at player position (1.5, 0.0, 3.0)"
	)
	err += _assert(
		rig.camera_height >= rig.min_camera_height and rig.camera_height <= rig.max_camera_height,
		"Camera height stays within valid bounds for single player (%.2f)" % rig.camera_height
	)

	# When tracking disabled, stays static
	rig.tracking_enabled = false
	rig.target_offset = Vector3.ZERO
	rig.camera_height = 12.0
	rig._process(0.1)
	err += _assert(rig.target_offset == Vector3.ZERO, "Disabled tracking maintains static target_offset")
	err += _assert(is_equal_approx(rig.camera_height, 12.0), "Disabled tracking maintains static camera_height")

	p1.queue_free()
	rig.queue_free()
	return err


## 8. Test camera shake integration point
func test_camera_shake_integration() -> int:
	print("\n[8] Testing camera shake integration point...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	var cam: Camera3D = rig.get_camera()
	var base_pos: Vector3 = cam.position

	# Trigger shake
	rig.apply_shake(1.5, 0.4)
	err += _assert(rig._shake_time > 0.0, "Shake timer started")

	rig._update_shake(0.05)
	err += _assert(cam.position != base_pos, "Camera position displaced by shake offset")

	# Finish shake
	rig._update_shake(0.5)
	err += _assert(rig._shake_time <= 0.0, "Shake timer expired")
	err += _assert(rig._shake_offset == Vector3.ZERO, "Shake offset reset to ZERO")

	rig.queue_free()
	return err


## 9. Test SignalBus player joined/left and group auto-sync
func test_signalbus_and_group_integration() -> int:
	print("\n[9] Testing SignalBus and players group integration...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	rig.tracking_enabled = true
	add_child(rig)

	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var p1: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(p1)

	# When player_joined emits, CameraRig syncs from group "players"
	SignalBus.player_joined.emit(0)
	var tracked := rig.get_tracked_players()
	err += _assert(tracked.has(p1), "PlayerCharacter in 'players' group automatically tracked")

	# Remove player
	p1.queue_free()
	SignalBus.player_left.emit(0)
	var cleaned := rig.get_tracked_players()
	err += _assert(cleaned.is_empty(), "Freed player removed from tracking")

	rig.queue_free()
	return err


## 10. Test optical ground focal point centering for diagonal players (no top lean)
func test_diagonal_axis_players_ground_centering() -> int:
	print("\n[10] Testing diagonal player axis ground centering...")
	var err: int = 0

	var rig: CameraRig = load(CAMERA_RIG_SCENE_PATH).instantiate() as CameraRig
	add_child(rig)

	# Players at diagonal corners of a 16x12 room
	var p1 := Node3D.new()
	var p2 := Node3D.new()
	add_child(p1)
	add_child(p2)

	p1.global_position = Vector3(-7.0, 0.0, -5.0)  # North-West
	p2.global_position = Vector3(7.0, 0.0, 5.0)   # South-East

	rig.set_tracked_players([p1, p2])
	rig.snap_to_target()

	# Midpoint should be (0.0, 0.0, 0.0)
	var focal_pt: Vector3 = rig.get_focal_ground_position()
	err += _assert(
		focal_pt.is_equal_approx(Vector3.ZERO),
		"Optical center points directly at midpoint (0.0, 0.0, 0.0), got %s" % focal_pt
	)

	# Camera height zoomed out due to spread
	err += _assert(
		rig.camera_height > 12.0,
		"Camera zoomed out for diagonal spread (Height: %.2f)" % rig.camera_height
	)

	# Camera Z position matches the exact ground intersection distance
	var pitch_rad: float = deg_to_rad(absf(rig.camera_angle))
	var expected_z: float = rig.camera_height / tan(pitch_rad)
	var cam: Camera3D = rig.get_camera()
	err += _assert(
		is_equal_approx(cam.position.z, expected_z),
		"Camera Z (%.2f) scaled proportionally with height (%.2f) to keep optical center at ground midpoint" % [cam.position.z, rig.camera_height]
	)

	p1.queue_free()
	p2.queue_free()
	rig.queue_free()
	return err
