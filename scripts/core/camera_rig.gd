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

@export_group("Player Tracking")
@export var tracking_enabled: bool = false:
	set(val):
		tracking_enabled = val
		_apply_camera_settings()
@export var tracking_smoothing: float = 5.0
@export var min_camera_height: float = 8.0
@export var max_camera_height: float = 18.0
@export var player_padding: float = 3.0   # Extra margin around players
@export var zoom_smoothing: float = 3.0

var _tracked_players: Array[Node3D] = []
var _target_position: Vector3 = Vector3.ZERO
var _target_height: float = 12.0
var _room_bounds: AABB = AABB()

# Camera shake variables
var _shake_intensity: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply_camera_settings()
	if not Engine.is_editor_hint():
		if SignalBus:
			if not SignalBus.player_joined.is_connected(_on_signal_player_joined):
				SignalBus.player_joined.connect(_on_signal_player_joined)
			if not SignalBus.player_spawned.is_connected(_on_signal_player_spawned):
				SignalBus.player_spawned.connect(_on_signal_player_spawned)
			if not SignalBus.player_left.is_connected(_on_signal_player_left):
				SignalBus.player_left.connect(_on_signal_player_left)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _shake_time > 0.0:
		_update_shake(delta)

	if not tracking_enabled:
		return

	_update_tracking(delta)


## Sets the array of players to track
func set_tracked_players(players: Array) -> void:
	_tracked_players.clear()
	for p in players:
		if p is Node3D and not _tracked_players.has(p):
			_tracked_players.append(p)
	tracking_enabled = not _tracked_players.is_empty()


## Adds a single player to tracking
func add_tracked_player(player: Node3D) -> void:
	if player and not _tracked_players.has(player):
		_tracked_players.append(player)
		tracking_enabled = true


## Removes a single player from tracking
func remove_tracked_player(player: Node3D) -> void:
	_tracked_players.erase(player)
	if _tracked_players.is_empty():
		tracking_enabled = false


## Clears all tracked players
func clear_tracked_players() -> void:
	_tracked_players.clear()
	tracking_enabled = false


## Returns a copy of currently tracked players
func get_tracked_players() -> Array[Node3D]:
	_clean_tracked_players()
	return _tracked_players.duplicate()


## Sets room bounding box for camera centering and clamping
func set_room_bounds(bounds: AABB) -> void:
	_room_bounds = bounds


## Instantly snaps target_offset and camera_height to current player tracking target
func snap_to_target() -> void:
	_update_tracking(1.0)
	target_offset = _target_position
	camera_height = _target_height
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

	var z_dist: float = camera_distance
	if tracking_enabled:
		var pitch_rad: float = deg_to_rad(absf(camera_angle))
		if pitch_rad > 0.001 and pitch_rad < PI * 0.49:
			z_dist = camera_height / tan(pitch_rad)

	cam.position = Vector3(target_offset.x, camera_height + target_offset.y, target_offset.z + z_dist) + _shake_offset
	cam.rotation_degrees = Vector3(camera_angle, 0.0, 0.0)


## Returns the 3D position on the ground plane (Y=0) where the camera's optical center is pointing
func get_focal_ground_position() -> Vector3:
	var cam := get_camera()
	if not cam:
		return target_offset
	var fwd: Vector3 = -cam.global_transform.basis.z
	if absf(fwd.y) < 0.0001:
		return Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	var t: float = -cam.global_position.y / fwd.y
	return cam.global_position + fwd * t


## Updates dynamic camera tracking to frame all active players
func _update_tracking(delta: float) -> void:
	var min_pos := Vector3(INF, 0.0, INF)
	var max_pos := Vector3(-INF, 0.0, -INF)
	var valid_count: int = 0

	for player in _tracked_players:
		if is_instance_valid(player) and not player.is_queued_for_deletion() and player.is_inside_tree():
			var pos: Vector3 = player.global_position
			min_pos.x = minf(min_pos.x, pos.x)
			min_pos.z = minf(min_pos.z, pos.z)
			max_pos.x = maxf(max_pos.x, pos.x)
			max_pos.z = maxf(max_pos.z, pos.z)
			valid_count += 1

	if valid_count == 0 and is_inside_tree():
		var group_players := get_tree().get_nodes_in_group("players")
		for p in group_players:
			if p is Node3D and is_instance_valid(p) and p.is_inside_tree():
				var pos: Vector3 = (p as Node3D).global_position
				min_pos.x = minf(min_pos.x, pos.x)
				min_pos.z = minf(min_pos.z, pos.z)
				max_pos.x = maxf(max_pos.x, pos.x)
				max_pos.z = maxf(max_pos.z, pos.z)
				valid_count += 1

	if valid_count == 0:
		return

	# Center point of all players
	var center := (min_pos + max_pos) * 0.5
	_target_position = Vector3(center.x, 0.0, center.z)

	# Clamping within workshop boundaries if set
	if _room_bounds.size.length_squared() > 0.0:
		var half_padding := player_padding * 0.5
		var min_x := _room_bounds.position.x + half_padding
		var max_x := _room_bounds.position.x + _room_bounds.size.x - half_padding
		var min_z := _room_bounds.position.z + half_padding
		var max_z := _room_bounds.position.z + _room_bounds.size.z - half_padding
		if min_x < max_x:
			_target_position.x = clampf(_target_position.x, min_x, max_x)
		if min_z < max_z:
			_target_position.z = clampf(_target_position.z, min_z, max_z)

	# Required coverage width/height (with padding)
	var spread_x: float = (max_pos.x - min_pos.x) + player_padding * 2.0
	var spread_z: float = (max_pos.z - min_pos.z) + player_padding * 2.0
	var max_spread: float = maxf(spread_x, spread_z)

	# Map spread to camera height (clamped between min and max camera height)
	var height_ratio: float = clampf(max_spread / 12.0, 0.0, 1.0)
	_target_height = lerpf(min_camera_height, max_camera_height, height_ratio)

	# Smooth interpolation
	if tracking_smoothing > 0.0 and delta > 0.0:
		target_offset = target_offset.lerp(_target_position, clampf(tracking_smoothing * delta, 0.0, 1.0))
	else:
		target_offset = _target_position

	if zoom_smoothing > 0.0 and delta > 0.0:
		camera_height = lerpf(camera_height, _target_height, clampf(zoom_smoothing * delta, 0.0, 1.0))
	else:
		camera_height = _target_height


## Triggers camera shake effect
func apply_shake(intensity: float = 0.5, duration: float = 0.3) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_time = duration


func _update_shake(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		var factor: float = _shake_time / _shake_duration
		var current_intensity: float = _shake_intensity * factor
		_shake_offset = Vector3(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity) * 0.5,
			randf_range(-current_intensity, current_intensity)
		)
		if _shake_time <= 0.0:
			_shake_offset = Vector3.ZERO
		_apply_camera_settings()


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


func _clean_tracked_players() -> void:
	for i in range(_tracked_players.size() - 1, -1, -1):
		var p: Node3D = _tracked_players[i]
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			_tracked_players.remove_at(i)


func _on_signal_player_joined(_player_id: int) -> void:
	if tracking_enabled:
		_sync_players_from_group()


func _on_signal_player_spawned(_player_id: int, player: Node) -> void:
	if player is Node3D and not _tracked_players.has(player):
		add_tracked_player(player as Node3D)
	elif tracking_enabled:
		_sync_players_from_group()



func _on_signal_player_left(_player_id: int) -> void:
	_clean_tracked_players()
	if tracking_enabled:
		_sync_players_from_group()


func _sync_players_from_group() -> void:
	if not is_inside_tree():
		return
	var group_players := get_tree().get_nodes_in_group("players")
	for node in group_players:
		if node is Node3D and not _tracked_players.has(node):
			_tracked_players.append(node)
