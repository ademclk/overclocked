class_name InputHelper
extends RefCounted

## Utility helper for input handling, device detection, and button prompts.
## Provides static functions for movement calculation, joypad detection, and UI glyphs.

## Controller / Device categories for UI prompts
enum DeviceType {
	KEYBOARD,
	XBOX,
	PLAYSTATION,
	NINTENDO,
	GENERIC_GAMEPAD,
}

# Action Name Constants
const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_PICK_UP: StringName = &"pick_up"
const ACTION_DROP: StringName = &"drop"
const ACTION_PAUSE: StringName = &"pause"
const ACTION_DEBUG_RELOAD: StringName = &"debug_reload"


## Returns the 2D movement vector using standard input actions with deadzone handling.
## Vector is normalized if length > 1.0.
static func get_movement_vector(deadzone: float = -1.0) -> Vector2:
	var dz: float = deadzone if deadzone >= 0.0 else Constants.DEFAULT_ANALOG_DEADZONE
	return Input.get_vector(
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_UP, ACTION_MOVE_DOWN, dz
	)


## Returns a 3D movement vector mapped to the XZ ground plane (Y = 0).
## Ideal for top-down isometric character controllers.
static func get_movement_vector_3d(deadzone: float = -1.0) -> Vector3:
	var move_2d: Vector2 = get_movement_vector(deadzone)
	return Vector3(move_2d.x, 0.0, move_2d.y)


## Returns true if any movement input is currently active.
static func is_moving(deadzone: float = -1.0) -> bool:
	return get_movement_vector(deadzone).length_squared() > 0.0


## Action state check helpers
static func is_interact_just_pressed() -> bool:
	return Input.is_action_just_pressed(ACTION_INTERACT)


static func is_interact_pressed() -> bool:
	return Input.is_action_pressed(ACTION_INTERACT)


static func is_pick_up_just_pressed() -> bool:
	return Input.is_action_just_pressed(ACTION_PICK_UP)


static func is_drop_just_pressed() -> bool:
	return Input.is_action_just_pressed(ACTION_DROP)


static func is_pause_just_pressed() -> bool:
	return Input.is_action_just_pressed(ACTION_PAUSE)


static func is_debug_reload_just_pressed() -> bool:
	return Input.is_action_just_pressed(ACTION_DEBUG_RELOAD)


## Joypad Detection & Device Type Queries
static func get_connected_joypads() -> Array[int]:
	return Input.get_connected_joypads()


static func has_connected_joypad() -> bool:
	return not Input.get_connected_joypads().is_empty()


static func get_joypad_name(device_id: int = 0) -> String:
	if device_id in Input.get_connected_joypads():
		return Input.get_joy_name(device_id)
	return ""


## Detects the gamepad hardware family from its identification string.
static func detect_device_type(device_id: int = 0) -> DeviceType:
	var joypads: Array[int] = Input.get_connected_joypads()
	if not (device_id in joypads):
		return DeviceType.KEYBOARD

	var joy_name: String = Input.get_joy_name(device_id).to_lower()

	if "xbox" in joy_name or "x-box" in joy_name or "xinput" in joy_name:
		return DeviceType.XBOX
	if (
		"playstation" in joy_name
		or "dualshock" in joy_name
		or "dualsense" in joy_name
		or "sony" in joy_name
		or "ps4" in joy_name
		or "ps5" in joy_name
	):
		return DeviceType.PLAYSTATION
	if (
		"nintendo" in joy_name
		or "switch" in joy_name
		or "joy-con" in joy_name
		or "pro controller" in joy_name
	):
		return DeviceType.NINTENDO

	return DeviceType.GENERIC_GAMEPAD


## Returns human-readable name for a DeviceType
static func get_device_type_name(device_type: DeviceType) -> String:
	match device_type:
		DeviceType.KEYBOARD:
			return "Keyboard & Mouse"
		DeviceType.XBOX:
			return "Xbox Controller"
		DeviceType.PLAYSTATION:
			return "PlayStation Controller"
		DeviceType.NINTENDO:
			return "Nintendo Switch Controller"
		DeviceType.GENERIC_GAMEPAD:
			return "Gamepad"
		_:
			return "Unknown Device"


## Returns user-facing button prompt string for a given action (e.g. "[E]" vs "(A)").
static func get_action_prompt(
	action: StringName, device_type: DeviceType = DeviceType.KEYBOARD
) -> String:
	match action:
		ACTION_INTERACT:
			match device_type:
				DeviceType.KEYBOARD:
					return "[E]"
				DeviceType.XBOX:
					return "(A)"
				DeviceType.PLAYSTATION:
					return "(✕)"
				DeviceType.NINTENDO:
					return "(B)"
				_:
					return "(A)"
		ACTION_PICK_UP:
			match device_type:
				DeviceType.KEYBOARD:
					return "[F]"
				DeviceType.XBOX:
					return "(X)"
				DeviceType.PLAYSTATION:
					return "(□)"
				DeviceType.NINTENDO:
					return "(Y)"
				_:
					return "(X)"
		ACTION_DROP:
			match device_type:
				DeviceType.KEYBOARD:
					return "[G]"
				DeviceType.XBOX:
					return "(B)"
				DeviceType.PLAYSTATION:
					return "(○)"
				DeviceType.NINTENDO:
					return "(A)"
				_:
					return "(B)"
		ACTION_PAUSE:
			match device_type:
				DeviceType.KEYBOARD:
					return "[Esc]"
				_:
					return "[Start]"
		ACTION_DEBUG_RELOAD:
			match device_type:
				DeviceType.KEYBOARD:
					return "[F5]"
				_:
					return ""
		ACTION_MOVE_UP, ACTION_MOVE_DOWN, ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT:
			match device_type:
				DeviceType.KEYBOARD:
					return "[W/A/S/D]"
				_:
					return "[Left Stick / D-Pad]"
		_:
			return "[%s]" % [action]


## Direct joypad polling for specific device ID (prepares Phase 2 multiplayer).
static func get_joy_movement_vector(
	device_id: int, deadzone: float = Constants.DEFAULT_ANALOG_DEADZONE
) -> Vector2:
	var x: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
	var y: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
	var raw_vec := Vector2(x, y)
	var length: float = raw_vec.length()
	if length < deadzone:
		return Vector2.ZERO
	# Rescale smoothly past deadzone
	var adjusted_len: float = clampf((length - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return raw_vec.normalized() * adjusted_len
