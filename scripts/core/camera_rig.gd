@tool
class_name CameraRig
extends Node3D

## Camera rig providing top-down isometric framing for the Overclocked workshop.
## Configurable height, distance, angle, and FOV for rapid iteration in the inspector.

@export_group("Camera Settings")
@export_range(1.0, 40.0, 0.5) var camera_height: float = 12.0:
	set(val):
		camera_height = val
		_apply_camera_settings()

@export_range(-89.0, -10.0, 1.0) var camera_angle: float = -55.0:
	set(val):
		camera_angle = val
		_apply_camera_settings()

@export_range(0.0, 40.0, 0.5) var camera_distance: float = 8.0:
	set(val):
		camera_distance = val
		_apply_camera_settings()

@export_range(20.0, 90.0, 1.0) var fov: float = 50.0:
	set(val):
		fov = val
		_apply_camera_settings()

@export var target_offset: Vector3 = Vector3.ZERO:
	set(val):
		target_offset = val
		_apply_camera_settings()

@export_group("Projection")
@export var projection_mode: Camera3D.ProjectionType = Camera3D.PROJECTION_PERSPECTIVE:
	set(val):
		projection_mode = val
		_apply_camera_settings()

@export_range(1.0, 50.0, 0.5) var orthogonal_size: float = 12.0:
	set(val):
		orthogonal_size = val
		_apply_camera_settings()

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply_camera_settings()


## Applies exported properties to the child Camera3D node
func _apply_camera_settings() -> void:
	var cam: Camera3D = camera if camera != null else get_node_or_null("Camera3D") as Camera3D
	if not cam:
		return

	cam.projection = projection_mode
	if projection_mode == Camera3D.PROJECTION_ORTHOGONAL:
		cam.size = orthogonal_size
	else:
		cam.fov = fov

	cam.position = Vector3(0.0, camera_height, camera_distance) + target_offset
	cam.rotation_degrees = Vector3(camera_angle, 0.0, 0.0)


## Returns the active Camera3D child
func get_camera() -> Camera3D:
	if not camera:
		camera = get_node_or_null("Camera3D") as Camera3D
	return camera


## Makes the child Camera3D the current active viewport camera
func make_current() -> void:
	var cam := get_camera()
	if cam:
		cam.make_current()


## Centers camera framing on a specific workshop position
func set_target_offset(new_offset: Vector3) -> void:
	target_offset = new_offset


## Calculates center offset from room bounding box corners
func frame_bounds(min_point: Vector3, max_point: Vector3) -> void:
	var center := (min_point + max_point) * 0.5
	target_offset = Vector3(center.x, 0.0, center.z)
