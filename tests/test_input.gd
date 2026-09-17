extends Node

## Test suite for Input Map configuration and InputHelper utility.

func _ready() -> void:
	print("--- RUNNING INPUT SYSTEM & INPUT_HELPER TESTS ---")

	# Ensure project settings input map is loaded into engine InputMap
	InputMap.load_from_project_settings()

	# 1. Verify All Required Actions Exist
	var expected_actions: Array[StringName] = [
		InputHelper.ACTION_MOVE_UP,
		InputHelper.ACTION_MOVE_DOWN,
		InputHelper.ACTION_MOVE_LEFT,
		InputHelper.ACTION_MOVE_RIGHT,
		InputHelper.ACTION_INTERACT,
		InputHelper.ACTION_PICK_UP,
		InputHelper.ACTION_DROP,
		InputHelper.ACTION_PAUSE,
		InputHelper.ACTION_DEBUG_RELOAD,
	]

	for action in expected_actions:
		assert(InputMap.has_action(action), "InputMap missing action: %s" % action)
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert(not events.is_empty(), "Action has no events: %s" % action)
		var deadzone: float = InputMap.action_get_deadzone(action)
		assert(is_equal_approx(deadzone, 0.2), "Action %s deadzone is %f, expected 0.2" % [action, deadzone])
		print("  ✓ Action verified: %s (events: %d, deadzone: %.1f)" % [action, events.size(), deadzone])

	# 2. Check Specific Event Mappings for Actions
	_test_action_events()

	# 3. Test InputHelper Movement Methods
	_test_movement_vectors()

	# 4. Test InputHelper Device Detection & Prompts
	_test_device_detection_and_prompts()

	# 5. Test Live Input Event Simulation
	_test_input_simulation()

	print("--- ALL INPUT TESTS PASSED SUCCESSFULLY ---")
	get_tree().quit(0)

func _test_action_events() -> void:
	print("Checking action event bindings...")

	# move_up
	var up_events := InputMap.action_get_events(InputHelper.ACTION_MOVE_UP)
	assert(_has_key(up_events, KEY_W), "move_up missing W key")
	assert(_has_joy_motion(up_events, JOY_AXIS_LEFT_Y, -1.0), "move_up missing Left Stick Up")
	assert(_has_joy_button(up_events, JOY_BUTTON_DPAD_UP), "move_up missing DPad Up")

	# move_down
	var down_events := InputMap.action_get_events(InputHelper.ACTION_MOVE_DOWN)
	assert(_has_key(down_events, KEY_S), "move_down missing S key")
	assert(_has_joy_motion(down_events, JOY_AXIS_LEFT_Y, 1.0), "move_down missing Left Stick Down")
	assert(_has_joy_button(down_events, JOY_BUTTON_DPAD_DOWN), "move_down missing DPad Down")

	# move_left
	var left_events := InputMap.action_get_events(InputHelper.ACTION_MOVE_LEFT)
	assert(_has_key(left_events, KEY_A), "move_left missing A key")
	assert(_has_joy_motion(left_events, JOY_AXIS_LEFT_X, -1.0), "move_left missing Left Stick Left")
	assert(_has_joy_button(left_events, JOY_BUTTON_DPAD_LEFT), "move_left missing DPad Left")

	# move_right
	var right_events := InputMap.action_get_events(InputHelper.ACTION_MOVE_RIGHT)
	assert(_has_key(right_events, KEY_D), "move_right missing D key")
	assert(_has_joy_motion(right_events, JOY_AXIS_LEFT_X, 1.0), "move_right missing Left Stick Right")
	assert(_has_joy_button(right_events, JOY_BUTTON_DPAD_RIGHT), "move_right missing DPad Right")

	# interact
	var interact_events := InputMap.action_get_events(InputHelper.ACTION_INTERACT)
	assert(_has_key(interact_events, KEY_E), "interact missing E key")
	assert(_has_joy_button(interact_events, JOY_BUTTON_A), "interact missing Joypad Button A")

	# pick_up
	var pickup_events := InputMap.action_get_events(InputHelper.ACTION_PICK_UP)
	assert(_has_key(pickup_events, KEY_F), "pick_up missing F key")
	assert(_has_joy_button(pickup_events, JOY_BUTTON_X), "pick_up missing Joypad Button X")

	# drop
	var drop_events := InputMap.action_get_events(InputHelper.ACTION_DROP)
	assert(_has_key(drop_events, KEY_G), "drop missing G key")
	assert(_has_joy_button(drop_events, JOY_BUTTON_B), "drop missing Joypad Button B")

	# pause
	var pause_events := InputMap.action_get_events(InputHelper.ACTION_PAUSE)
	assert(_has_key(pause_events, KEY_ESCAPE), "pause missing Escape key")
	assert(_has_joy_button(pause_events, JOY_BUTTON_START), "pause missing Joypad Button Start")

	# debug_reload
	var reload_events := InputMap.action_get_events(InputHelper.ACTION_DEBUG_RELOAD)
	assert(_has_key(reload_events, KEY_F5), "debug_reload missing F5 key")

	print("  ✓ Event bindings validated")

func _test_movement_vectors() -> void:
	print("Checking InputHelper movement vector calculations...")
	var vec2 := InputHelper.get_movement_vector()
	assert(vec2 == Vector2.ZERO, "Default movement vector should be Vector2.ZERO when idle")

	var vec3 := InputHelper.get_movement_vector_3d()
	assert(vec3 == Vector3.ZERO, "Default 3D movement vector should be Vector3.ZERO when idle")
	assert(vec3.y == 0.0, "3D movement vector Y component must always be 0.0")

	assert(InputHelper.is_moving() == false, "is_moving() should be false when idle")
	print("  ✓ Movement vector helpers validated")

func _test_device_detection_and_prompts() -> void:
	print("Checking InputHelper device detection and UI prompts...")
	assert(InputHelper.get_device_type_name(InputHelper.DeviceType.KEYBOARD) == "Keyboard & Mouse")
	assert(InputHelper.get_device_type_name(InputHelper.DeviceType.XBOX) == "Xbox Controller")
	assert(InputHelper.get_device_type_name(InputHelper.DeviceType.PLAYSTATION) == "PlayStation Controller")
	assert(InputHelper.get_device_type_name(InputHelper.DeviceType.NINTENDO) == "Nintendo Switch Controller")

	# Prompts for interact
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_INTERACT, InputHelper.DeviceType.KEYBOARD) == "[E]")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_INTERACT, InputHelper.DeviceType.XBOX) == "(A)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_INTERACT, InputHelper.DeviceType.PLAYSTATION) == "(✕)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_INTERACT, InputHelper.DeviceType.NINTENDO) == "(B)")

	# Prompts for pick_up
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PICK_UP, InputHelper.DeviceType.KEYBOARD) == "[F]")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PICK_UP, InputHelper.DeviceType.XBOX) == "(X)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PICK_UP, InputHelper.DeviceType.PLAYSTATION) == "(□)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PICK_UP, InputHelper.DeviceType.NINTENDO) == "(Y)")

	# Prompts for drop
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_DROP, InputHelper.DeviceType.KEYBOARD) == "[G]")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_DROP, InputHelper.DeviceType.XBOX) == "(B)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_DROP, InputHelper.DeviceType.PLAYSTATION) == "(○)")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_DROP, InputHelper.DeviceType.NINTENDO) == "(A)")

	# Prompts for pause
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PAUSE, InputHelper.DeviceType.KEYBOARD) == "[Esc]")
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_PAUSE, InputHelper.DeviceType.XBOX) == "[Start]")

	# Prompts for debug_reload
	assert(InputHelper.get_action_prompt(InputHelper.ACTION_DEBUG_RELOAD, InputHelper.DeviceType.KEYBOARD) == "[F5]")

	# Device detection with negative device index should return KEYBOARD
	assert(InputHelper.detect_device_type(-1) == InputHelper.DeviceType.KEYBOARD)

	print("UI prompts and device mapping validated")

func _test_input_simulation() -> void:
	print("Testing live input parsing...")

	# Simulate Keyboard E press
	var key_press := InputEventKey.new()
	key_press.physical_keycode = KEY_E
	key_press.pressed = true
	Input.parse_input_event(key_press)
	Input.flush_buffered_events()

	assert(Input.is_action_pressed(InputHelper.ACTION_INTERACT), "Simulated E key press did not trigger interact")
	assert(InputHelper.is_interact_pressed(), "InputHelper.is_interact_pressed() returned false")

	# Release Keyboard E
	var key_release := InputEventKey.new()
	key_release.physical_keycode = KEY_E
	key_release.pressed = false
	Input.parse_input_event(key_release)
	Input.flush_buffered_events()

	assert(not Input.is_action_pressed(InputHelper.ACTION_INTERACT), "Simulated E key release failed")

	# Simulate Gamepad Start button press
	var joy_press := InputEventJoypadButton.new()
	joy_press.button_index = JOY_BUTTON_START
	joy_press.pressed = true
	joy_press.device = 0
	Input.parse_input_event(joy_press)
	Input.flush_buffered_events()

	assert(Input.is_action_pressed(InputHelper.ACTION_PAUSE), "Simulated Start button did not trigger pause")

	# Release Gamepad Start
	var joy_release := InputEventJoypadButton.new()
	joy_release.button_index = JOY_BUTTON_START
	joy_release.pressed = false
	joy_release.device = 0
	Input.parse_input_event(joy_release)
	Input.flush_buffered_events()

	assert(not Input.is_action_pressed(InputHelper.ACTION_PAUSE), "Simulated Start button release failed")

	print("  ✓ Live input simulation passed")

# Helper checking functions
func _has_key(events: Array[InputEvent], key: Key) -> bool:
	for ev in events:
		if ev is InputEventKey:
			var iek: InputEventKey = ev as InputEventKey
			if iek.physical_keycode == key or iek.keycode == key:
				return true
	return false

func _has_joy_motion(events: Array[InputEvent], axis: JoyAxis, val: float) -> bool:
	for ev in events:
		if ev is InputEventJoypadMotion:
			var iejm: InputEventJoypadMotion = ev as InputEventJoypadMotion
			if iejm.axis == axis and is_equal_approx(iejm.axis_value, val):
				return true
	return false

func _has_joy_button(events: Array[InputEvent], btn: JoyButton) -> bool:
	for ev in events:
		if ev is InputEventJoypadButton:
			var iejb: InputEventJoypadButton = ev as InputEventJoypadButton
			if iejb.button_index == btn:
				return true
	return false
