class_name PlayerCharacter
extends CharacterBody3D

## Player controller for Overclocked.
## Handles top-down movement, facing direction, state tracking, and provides
## attachment points and interfaces for interaction and carry systems.

signal movement_state_changed(new_state: MovementState)
signal footstep(player_index: int)
signal player_bumped(other_player: PlayerCharacter)
signal stunned(duration: float)
signal recovered
signal dashed()
signal dash_impact()

enum MovementState {
	IDLE,
	WALKING,
}

const FOOTSTEP_INTERVAL_DISTANCE: float = 1.2

@export var move_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED
@export var rotation_speed: float = 10.0
@export var player_index: int = 0

@export_group("Dash / Rush")
@export var dash_speed_multiplier: float = 2.5
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.8

var current_movement_state: MovementState = MovementState.IDLE
var _input_direction: Vector3 = Vector3.ZERO
var _distance_since_last_footstep: float = 0.0

# Dash state
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _shift_was_pressed: bool = false

# Bump mechanic & stun state
var _is_stunned: bool = false
var _stun_timer: float = 0.0
var _bump_cooldown_timer: float = 0.0
var _last_motion_speed: float = 0.0
var _original_model_pos: Vector3 = Vector3.ZERO
var _stun_tween: Tween = null
var _movement_locked: bool = false

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
		| Constants.COLLISION_MASK_PLAYERS
	)
	floor_constant_speed = true
	floor_stop_on_slope = true

	if character_model:
		_original_model_pos = character_model.position

	_apply_player_color()
	_detect_child_systems()


func set_movement_locked(locked: bool) -> void:
	_movement_locked = locked
	if _movement_locked:
		velocity = Vector3.ZERO
		_update_movement_state(0.0)


func is_movement_locked() -> bool:
	return _movement_locked


func is_dashing() -> bool:
	return _is_dashing


func trigger_dash() -> void:
	if _movement_locked or _is_stunned or _is_dashing or _dash_cooldown_timer > 0.0:
		return
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown

	var dir: Vector3 = _input_direction
	if dir.length_squared() < 0.01 and character_model:
		dir = Vector3(sin(character_model.rotation.y), 0.0, cos(character_model.rotation.y))
	if dir.length_squared() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)
	dir.y = 0.0
	_dash_direction = dir.normalized()
	dashed.emit()


func _physics_process(delta: float) -> void:
	_bump_cooldown_timer = maxf(0.0, _bump_cooldown_timer - delta)
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)

	if _movement_locked:
		_is_dashing = false
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if _is_stunned:
		_is_dashing = false
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_end_stun()
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Dash Trigger (Shift or action rush)
	var rush_action := MultiplayerInput.action_name(player_index, &"rush")
	var shift_just_pressed: bool = false
	if player_index == 0:
		var shift_down: bool = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT)
		if shift_down and not _shift_was_pressed:
			shift_just_pressed = true
		_shift_was_pressed = shift_down
	var is_rush_just_pressed: bool = (
		(InputMap.has_action(rush_action) and Input.is_action_just_pressed(rush_action))
		or (InputMap.has_action(&"rush") and Input.is_action_just_pressed(&"rush"))
		or shift_just_pressed
	)
	if is_rush_just_pressed and not _is_dashing and _dash_cooldown_timer <= 0.0:
		trigger_dash()

	if _is_dashing:
		_dash_timer -= delta
		velocity = _dash_direction * (move_speed * dash_speed_multiplier)
		_last_motion_speed = velocity.length()
		move_and_slide()

		# Check for wall / station / obstacle impact
		var impact: bool = false
		var col_count: int = get_slide_collision_count()
		for i in range(col_count):
			var col := get_slide_collision(i)
			var collider := col.get_collider()
			if collider and collider != self:
				impact = true
				break

		if impact:
			_is_dashing = false
			_dash_timer = 0.0
			dash_impact.emit()
			if carry_system and carry_system.is_carrying():
				var held: Carriable = carry_system.get_held_item()
				carry_system.drop_item()
				if held and is_instance_valid(held):
					held.global_position += _dash_direction * 0.6
			stun(0.35)
			return

		if _dash_timer <= 0.0:
			_is_dashing = false

		_rotate_toward_direction(delta)
		_update_movement_state(delta)
		return

	_input_direction = MultiplayerInput.get_movement_vector_3d(player_index)
	velocity = _input_direction * move_speed
	_last_motion_speed = velocity.length()
	move_and_slide()
	_rotate_toward_direction(delta)
	_update_movement_state(delta)
	_check_bumps()




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


## Checks for slide collisions with other players to trigger the bump mechanic
func _check_bumps() -> void:
	if _bump_cooldown_timer > 0.0 or _is_stunned:
		return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is PlayerCharacter and collider != self:
			var other: PlayerCharacter = collider as PlayerCharacter
			if not is_instance_valid(other) or other._is_stunned or other._bump_cooldown_timer > 0.0:
				continue

			var my_speed: float = maxf(_last_motion_speed, _input_direction.length() * move_speed)
			var other_speed: float = maxf(other.get_last_motion_speed(), other._input_direction.length() * other.move_speed)
			if my_speed + other_speed >= Constants.BUMP_SPEED_THRESHOLD:
				_apply_bump(other)
				break


## Applies bump consequences to both colliding players
func _apply_bump(other: PlayerCharacter) -> void:
	# Both players get stunned — initiator gets half duration
	stun(Constants.BUMP_STUN_DURATION * 0.5)
	other.stun(Constants.BUMP_STUN_DURATION)

	# Bumped player drops their carried item
	if other.carry_system and other.carry_system.is_carrying():
		other.carry_system.drop_item()

	player_bumped.emit(other)
	SignalBus.player_bumped.emit(player_index, other.player_index)


## Stuns the player for the given duration, preventing movement
func stun(duration: float) -> void:
	_is_stunned = true
	_stun_timer = duration
	_bump_cooldown_timer = Constants.BUMP_COOLDOWN
	velocity = Vector3.ZERO
	current_movement_state = MovementState.IDLE
	movement_state_changed.emit(MovementState.IDLE)
	_apply_stun_visual(true)
	stunned.emit(duration)


## Restores normal player state upon stun timer completion
func _end_stun() -> void:
	_is_stunned = false
	_stun_timer = 0.0
	_apply_stun_visual(false)
	recovered.emit()


## Toggles visual stun feedback (bright flash and wobble)
func _apply_stun_visual(active: bool) -> void:
	if _stun_tween and _stun_tween.is_valid():
		_stun_tween.kill()

	var body_mesh: MeshInstance3D = null
	if character_model:
		body_mesh = character_model.get_node_or_null("BodyMesh") as MeshInstance3D

	if active:
		if body_mesh and body_mesh.material_override is StandardMaterial3D:
			var mat := body_mesh.material_override as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.95, 0.4)
			mat.emission_energy_multiplier = 2.0

		if character_model:
			_stun_tween = create_tween()
			_stun_tween.tween_property(character_model, "position:y", _original_model_pos.y + 0.15, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_stun_tween.tween_property(character_model, "position:y", _original_model_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		if body_mesh and body_mesh.material_override is StandardMaterial3D:
			var mat := body_mesh.material_override as StandardMaterial3D
			mat.emission_enabled = false
			mat.emission_energy_multiplier = 0.0

		if character_model:
			character_model.position = _original_model_pos


## Returns true if the player is currently stunned
func is_stunned() -> bool:
	return _is_stunned


## Returns speed recorded prior to slide collisions in the current physics frame
func get_last_motion_speed() -> float:
	return _last_motion_speed


## Returns remaining bump cooldown in seconds
func get_bump_cooldown() -> float:
	return _bump_cooldown_timer
