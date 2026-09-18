class_name MultiplayerInput
extends RefCounted

## Manages per-player input device assignment and provides per-player action name lookup.
## Used by PlayerCharacter and its subsystems to route input to the correct player slot.

# Input action prefix per player slot (p0_, p1_, p2_, p3_)
const ACTION_PREFIX: Array[String] = ["p0_", "p1_", "p2_", "p3_"]

# Base action names (without player prefix)
const BASE_MOVE_UP: StringName = &"move_up"
const BASE_MOVE_DOWN: StringName = &"move_down"
const BASE_MOVE_LEFT: StringName = &"move_left"
const BASE_MOVE_RIGHT: StringName = &"move_right"
const BASE_INTERACT: StringName = &"interact"
const BASE_PICK_UP: StringName = &"pick_up"
const BASE_DROP: StringName = &"drop"
const BASE_PAUSE: StringName = &"pause"

## Player device assignments: player_index -> device_id (-1 = keyboard, 0+ = joypad)
static var device_assignments: Dictionary = {}
static var _listener_initialized: bool = false


## Returns the per-player action name, e.g., "p0_interact"
static func action_name(player_index: int, base_action: StringName) -> StringName:
	if player_index < 0 or player_index >= ACTION_PREFIX.size():
		push_warning("MultiplayerInput: Invalid player_index %d" % player_index)
		return base_action
	return StringName(ACTION_PREFIX[player_index] + String(base_action))


## Returns per-player 2D movement vector with analog deadzone handling
static func get_movement_vector(player_index: int, deadzone: float = -1.0) -> Vector2:
	var dz: float = deadzone if deadzone >= 0.0 else Constants.DEFAULT_ANALOG_DEADZONE
	return Input.get_vector(
		action_name(player_index, BASE_MOVE_LEFT),
		action_name(player_index, BASE_MOVE_RIGHT),
		action_name(player_index, BASE_MOVE_UP),
		action_name(player_index, BASE_MOVE_DOWN),
		dz
	)


## Returns per-player movement vector on the XZ ground plane (Y = 0)
static func get_movement_vector_3d(player_index: int, deadzone: float = -1.0) -> Vector3:
	var move_2d: Vector2 = get_movement_vector(player_index, deadzone)
	return Vector3(move_2d.x, 0.0, move_2d.y)


## Returns true if the specified player has active movement input
static func is_moving(player_index: int, deadzone: float = -1.0) -> bool:
	return get_movement_vector(player_index, deadzone).length_squared() > 0.0


## Checks if a per-player action was just pressed
static func is_action_just_pressed(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_just_pressed(action_name(player_index, base_action))


## Checks if a per-player action is currently held
static func is_action_pressed(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_pressed(action_name(player_index, base_action))


## Checks if a per-player action was just released
static func is_action_just_released(player_index: int, base_action: StringName) -> bool:
	return Input.is_action_just_released(action_name(player_index, base_action))


## Assigns a device to a player slot (-1 = keyboard, 0+ = joypad)
static func assign_device(player_index: int, device_id: int) -> void:
	device_assignments[player_index] = device_id


## Returns the assigned device ID for a player slot (-1 = keyboard, 0+ = joypad)
static func get_assigned_device(player_index: int) -> int:
	_ensure_initialized()
	return device_assignments.get(player_index, -1)


## Returns the device type for a player's assigned device (for button prompts)
static func get_player_device_type(player_index: int) -> InputHelper.DeviceType:
	_ensure_initialized()
	var device_id: int = device_assignments.get(player_index, -1)
	if device_id < 0:
		return InputHelper.DeviceType.KEYBOARD
	var detected := InputHelper.detect_device_type(device_id)
	if detected == InputHelper.DeviceType.KEYBOARD:
		return InputHelper.DeviceType.GENERIC_GAMEPAD
	return detected


## Returns the prompt string for a player's action (e.g., "[E]" or "(A)")
static func get_player_action_prompt(player_index: int, base_action: StringName) -> String:
	var device_type := get_player_device_type(player_index)
	if device_type == InputHelper.DeviceType.KEYBOARD:
		match player_index:
			1:
				match base_action:
					BASE_INTERACT:
						return "[Num 1]"
					BASE_PICK_UP:
						return "[Num 2]"
					BASE_DROP:
						return "[Num 3]"
					BASE_PAUSE:
						return "[Esc]"
					BASE_MOVE_UP, BASE_MOVE_DOWN, BASE_MOVE_LEFT, BASE_MOVE_RIGHT:
						return "[Arrows]"
					_:
						return "[%s]" % [base_action]
			_:
				match base_action:
					BASE_INTERACT:
						return "[E]"
					BASE_PICK_UP:
						return "[F]"
					BASE_DROP:
						return "[G]"
					BASE_PAUSE:
						return "[Esc]"
					BASE_MOVE_UP, BASE_MOVE_DOWN, BASE_MOVE_LEFT, BASE_MOVE_RIGHT:
						return "[W/A/S/D]"
					_:
						return "[%s]" % [base_action]
	return InputHelper.get_action_prompt(base_action, device_type)


## Automatically assigns connected joypads sequentially to player slots.
## Unassigned slots default to keyboard (-1).
static func auto_assign_devices() -> void:
	var connected_pads: Array[int] = Input.get_connected_joypads()
	device_assignments.clear()
	for i in range(Constants.MAX_PLAYERS):
		if i < connected_pads.size():
			device_assignments[i] = connected_pads[i]
		else:
			device_assignments[i] = -1


## Sets up listener for gamepad connection and disconnection events.
static func setup_device_listener() -> void:
	if not _listener_initialized and Engine.has_singleton("Input"):
		var callback := Callable(MultiplayerInput, "_on_joy_connection_changed")
		if not Input.joy_connection_changed.is_connected(callback):
			Input.joy_connection_changed.connect(callback)
		_listener_initialized = true
	auto_assign_devices()


## Resets device assignments back to defaults
static func reset_assignments() -> void:
	device_assignments.clear()
	auto_assign_devices()


static func _ensure_initialized() -> void:
	if device_assignments.is_empty():
		auto_assign_devices()
	if not _listener_initialized:
		setup_device_listener()


static func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	auto_assign_devices()
