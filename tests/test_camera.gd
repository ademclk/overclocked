extends Node

## Test suite for CameraRig scene and camera_rig.gd script.

func _ready() -> void:
	print("--- RUNNING CAMERA RIG TESTS ---")

	# 1. Instantiate CameraRig scene
	var camera_rig_scene: PackedScene = load("res://scenes/main/CameraRig.tscn")
	assert(camera_rig_scene != null, "Failed to load CameraRig.tscn")

	var rig: CameraRig = camera_rig_scene.instantiate() as CameraRig
	assert(rig != null, "Failed to instantiate CameraRig")
	add_child(rig)

	# 2. Check child Camera3D
	var cam: Camera3D = rig.get_camera()
	assert(cam != null, "CameraRig has no Camera3D child")
	assert(cam.current == true, "Camera3D should be set as current")
	assert(cam.environment != null, "Camera3D should have an Environment assigned")

	# 3. Verify Default Settings
	print("Checking default camera settings...")
	assert(is_equal_approx(rig.camera_height, 12.0), "Default camera_height should be 12.0")
	assert(is_equal_approx(rig.camera_angle, -55.0), "Default camera_angle should be -55.0")
	assert(is_equal_approx(rig.camera_distance, 8.0), "Default camera_distance should be 8.0")
	assert(is_equal_approx(rig.fov, 50.0), "Default fov should be 50.0")

	assert(is_equal_approx(cam.position.x, 0.0), "Camera X position should be 0.0")
	assert(is_equal_approx(cam.position.y, 12.0), "Camera Y position should be 12.0")
	assert(is_equal_approx(cam.position.z, 8.0), "Camera Z position should be 8.0")
	assert(is_equal_approx(cam.rotation_degrees.x, -55.0), "Camera X rotation should be -55.0 deg")
	assert(is_equal_approx(cam.fov, 50.0), "Camera FOV should be 50.0")
	print("Default camera transform and projection verified")

	# 4. Verify Export Property Modifiers
	print("Testing export property adjustments...")
	rig.camera_height = 15.0
	assert(is_equal_approx(cam.position.y, 15.0), "Updating camera_height should update cam.position.y")

	rig.camera_distance = 10.0
	assert(is_equal_approx(cam.position.z, 10.0), "Updating camera_distance should update cam.position.z")

	rig.camera_angle = -60.0
	assert(is_equal_approx(cam.rotation_degrees.x, -60.0), "Updating camera_angle should update cam.rotation_degrees.x")

	rig.fov = 45.0
	assert(is_equal_approx(cam.fov, 45.0), "Updating fov should update cam.fov")
	print("Dynamic inspector property updates verified")

	# 5. Verify Target Offset and Bounds Framing
	print("Testing target offset and room framing...")
	rig.target_offset = Vector3(2.0, 0.0, 3.0)
	assert(is_equal_approx(cam.position.x, 2.0), "Offset should shift camera X")
	assert(is_equal_approx(cam.position.z, 10.0 + 3.0), "Offset should shift camera Z")

	# Frame a 10x8 room from (-5, 0, -4) to (5, 0, 4)
	rig.frame_bounds(Vector3(-5.0, 0.0, -4.0), Vector3(5.0, 0.0, 4.0))
	assert(rig.target_offset == Vector3.ZERO, "Symmetric room center should yield zero offset")

	# Frame an offset room from (0, 0, 0) to (10, 0, 8)
	rig.frame_bounds(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 8.0))
	assert(is_equal_approx(rig.target_offset.x, 5.0), "Target offset X should be center of room (5.0)")
	assert(is_equal_approx(rig.target_offset.z, 4.0), "Target offset Z should be center of room (4.0)")
	print("Room framing calculations verified")

	# 6. Verify Orthogonal Mode Switching
	print("Testing projection mode switching...")
	rig.projection_mode = Camera3D.PROJECTION_ORTHOGONAL
	rig.orthogonal_size = 14.0
	assert(cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "Projection should switch to Orthogonal")
	assert(is_equal_approx(cam.size, 14.0), "Orthogonal size should update to 14.0")

	rig.projection_mode = Camera3D.PROJECTION_PERSPECTIVE
	assert(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "Projection should switch back to Perspective")
	print("Projection mode switching verified")

	print("--- ALL CAMERA RIG TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)
