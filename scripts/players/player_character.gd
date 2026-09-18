class_name PlayerCharacter
extends CharacterBody3D

## Player controller for Overclocked.
## Handles top-down movement, facing direction, state tracking, and provides
## attachment points and interfaces for interaction and carry systems.

signal movement_state_changed(new_state: MovementState)
signal footstep(player_index: int)

enum MovementState {
	IDLE,
	WALKING,
}

const FOOTSTEP_INTERVAL_DISTANCE: float = 1.2

@export var move_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED
@export var rotation_speed: float = 10.0
@export var player_index: int = 0

var current_movement_state: MovementState = MovementState.IDLE
var _input_direction: Vector3 = Vector3.ZERO
var _distance_since_last_footstep: float = 0.0

# References populated dynamically or wired in 1B
var interaction_system: InteractionSystem = null
var carry_system: CarrySystem = null

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var character_model: Node3D = $CharacterModel
@onready var interaction_area: Area3D = $InteractionArea
@onready var carry_position: Marker3D = $CarryPosition
@onready var player_label: Label3D = $PlayerLabel
@onready var floor_ring: MeshInstance3D = get_node_or_null("FloorRing") as MeshInstance3D


func _ready() -> void:
	add_to_group("players")
	collision_layer = Constants.COLLISION_MASK_PLAYERS
	collision_mask = (
		Constants.COLLISION_MASK_WORLD
		| Constants.COLLISION_MASK_STATIONS
		| Constants.COLLISION_MASK_ITEMS
	)
	floor_constant_speed = true
	floor_stop_on_slope = true

	_apply_player_color()
	_detect_child_systems()


func _physics_process(delta: float) -> void:
	_input_direction = MultiplayerInput.get_movement_vector_3d(player_index)
	velocity = _input_direction * move_speed
	move_and_slide()
	_rotate_toward_direction(delta)
	_update_movement_state(delta)


func _rotate_toward_direction(delta: float) -> void:
	if _input_direction.length_squared() > 0.01:
		var target_angle: float = atan2(_input_direction.x, _input_direction.z)
		character_model.rotation.y = lerp_angle(
			character_model.rotation.y, target_angle, rotation_speed * delta
		)


func _update_movement_state(delta: float) -> void:
	var is_moving: bool = _input_direction.length_squared() > 0.01 or velocity.length_squared() > 0.01
	var new_state: MovementState = MovementState.WALKING if is_moving else MovementState.IDLE

	if new_state != current_movement_state:
		current_movement_state = new_state
		movement_state_changed.emit(current_movement_state)

	if current_movement_state == MovementState.WALKING:
		_distance_since_last_footstep += velocity.length() * delta
		if _distance_since_last_footstep >= FOOTSTEP_INTERVAL_DISTANCE:
			_distance_since_last_footstep = 0.0
			footstep.emit(player_index)


## Returns the player's assigned color based on player_index
func get_player_color() -> Color:
	if player_index >= 0 and player_index < Constants.PLAYER_COLORS.size():
		return Constants.PLAYER_COLORS[player_index]
	return Constants.PLAYER_COLORS[player_index % Constants.PLAYER_COLORS.size()]


## Applies the player's color to the capsule body mesh, floor ring, and overhead label
func _apply_player_color() -> void:
	var color: Color = get_player_color()

	# Color the capsule mesh (using material_override to avoid mutating shared material)
	if character_model:
		var body_mesh: MeshInstance3D = character_model.get_node_or_null("BodyMesh") as MeshInstance3D
		if body_mesh:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.roughness = 0.5
			body_mesh.material_override = mat

	# Color the player label
	_update_player_label()

	# Color the floor indicator ring
	var ring: MeshInstance3D = floor_ring if floor_ring != null else get_node_or_null("FloorRing") as MeshInstance3D
	if ring:
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = color
		ring_mat.emission_enabled = true
		ring_mat.emission = color
		ring_mat.emission_energy_multiplier = 0.6
		ring.material_override = ring_mat


func _update_player_label() -> void:
	if player_label:
		player_label.text = "P%d" % [player_index + 1]
		player_label.modulate = get_player_color()


func _detect_child_systems() -> void:
	if has_node("InteractionSystem"):
		interaction_system = get_node("InteractionSystem")
	if has_node("CarrySystem"):
		carry_system = get_node("CarrySystem")


## Returns current facing direction on the ground plane (normalized Vector3)
func get_facing_direction() -> Vector3:
	if character_model:
		# Since rotation uses atan2(x, z), +Z is the model's forward direction
		return character_model.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


## Alias for get_facing_direction
func get_forward_direction() -> Vector3:
	return get_facing_direction()


## Returns whether the character is currently moving
func is_walking() -> bool:
	return current_movement_state == MovementState.WALKING


## Sets player index and updates UI label and visual identity colors
func set_player_index(index: int) -> void:
	player_index = index
	_apply_player_color()
