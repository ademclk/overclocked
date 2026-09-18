extends Node

## Test suite for Phase 2A: Multiplayer Input Manager & Input Isolation.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2A MULTIPLAYER INPUT TESTS ---")
	print("=========================================================")
	var failures: int = 0

	InputMap.load_from_project_settings()

	failures += test_per_player_actions_registered()
	failures += test_per_player_action_bindings_and_devices()
	failures += test_multiplayer_input_api()
	failures += test_keyboard_split_isolation()
	failures += test_gamepad_device_isolation()
	failures += test_player_controller_input_routing()
	failures += test_interaction_and_carry_isolation()
	failures += test_dynamic_device_assignment()

	print("=========================================================")
	print("--- PHASE 2A TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2A MULTIPLAYER INPUT TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2A tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Verify all 32 per-player input actions exist with proper deadzone
func test_per_player_actions_registered() -> int:
	print("\n[1] Testing registration of 32 per-player actions...")
	var err: int = 0
	var base_actions: Array[StringName] = [
		MultiplayerInput.BASE_MOVE_UP,
		MultiplayerInput.BASE_MOVE_DOWN,
		MultiplayerInput.BASE_MOVE_LEFT,
		MultiplayerInput.BASE_MOVE_RIGHT,
		MultiplayerInput.BASE_INTERACT,
		MultiplayerInput.BASE_PICK_UP,
		MultiplayerInput.BASE_DROP,
		MultiplayerInput.BASE_PAUSE,
	]

	var registered_count: int = 0
	for p in range(Constants.MAX_PLAYERS):
		for base in base_actions:
			var act := MultiplayerInput.action_name(p, base)
			var exists: bool = InputMap.has_action(act)
			if not exists:
				err += _assert(false, "InputMap missing action: %s" % act)
			else:
				registered_count += 1
				var dz: float = InputMap.action_get_deadzone(act)
				if not is_equal_approx(dz, 0.2):
					err += _assert(false, "Action %s deadzone is %f, expected 0.2" % [act, dz])

	err += _assert(registered_count == 32, "All 32 per-player input actions registered (found %d)" % registered_count)
	return err


## 2. Check event bindings and verify device IDs strictly match player slot
func test_per_player_action_bindings_and_devices() -> int:
	print("\n[2] Testing per-player action event device isolation...")
	var err: int = 0

	# P0 keyboard bindings: W, S, A, D, E, F, G, Escape
	err += _assert(_action_has_key("p0_move_up", KEY_W), "p0_move_up has Key W")
	err += _assert(_action_has_key("p0_move_down", KEY_S), "p0_move_down has Key S")
	err += _assert(_action_has_key("p0_move_left", KEY_A), "p0_move_left has Key A")
	err += _assert(_action_has_key("p0_move_right", KEY_D), "p0_move_right has Key D")
	err += _assert(_action_has_key("p0_interact", KEY_E), "p0_interact has Key E")
	err += _assert(_action_has_key("p0_pick_up", KEY_F), "p0_pick_up has Key F")
	err += _assert(_action_has_key("p0_drop", KEY_G), "p0_drop has Key G")
	err += _assert(_action_has_key("p0_pause", KEY_ESCAPE), "p0_pause has Key Escape")

	# P1 keyboard bindings: Arrows + KP 1, 2, 3
	err += _assert(_action_has_key("p1_move_up", KEY_UP), "p1_move_up has Key Up")
	err += _assert(_action_has_key("p1_move_down", KEY_DOWN), "p1_move_down has Key Down")
	err += _assert(_action_has_key("p1_move_left", KEY_LEFT), "p1_move_left has Key Left")
	err += _assert(_action_has_key("p1_move_right", KEY_RIGHT), "p1_move_right has Key Right")
	err += _assert(_action_has_key("p1_interact", KEY_KP_1), "p1_interact has Key KP 1")
	err += _assert(_action_has_key("p1_pick_up", KEY_KP_2), "p1_pick_up has Key KP 2")
	err += _assert(_action_has_key("p1_drop", KEY_KP_3), "p1_drop has Key KP 3")

	# Joypad device IDs: P0 -> device 0, P1 -> device 1, P2 -> device 2, P3 -> device 3
	for p in range(Constants.MAX_PLAYERS):
		var prefix: String = "p%d_" % p
		var joy_device_target: int = p

		var act_interact := StringName(prefix + "interact")
		var act_drop := StringName(prefix + "drop")
		var act_up := StringName(prefix + "move_up")

		err += _assert(_action_has_joy_button_with_device(act_interact, JOY_BUTTON_A, joy_device_target),
			"%s has Joypad Button A with device == %d" % [act_interact, joy_device_target])
		err += _assert(_action_has_joy_button_with_device(act_drop, JOY_BUTTON_B, joy_device_target),
			"%s has Joypad Button B with device == %d" % [act_drop, joy_device_target])
		err += _assert(_action_has_joy_motion_with_device(act_up, JOY_AXIS_LEFT_Y, -1.0, joy_device_target),
			"%s has Joypad Motion Y- with device == %d" % [act_up, joy_device_target])

		# Ensure no joypad event on this action has device != p (and specifically NOT -1)
		for ev in InputMap.action_get_events(act_interact):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				if ev.device != joy_device_target:
					err += _assert(false, "Found joypad event on %s with incorrect device %d (expected %d)" % [act_interact, ev.device, joy_device_target])

	return err


## 3. Test MultiplayerInput API helper methods
func test_multiplayer_input_api() -> int:
	print("\n[3] Testing MultiplayerInput helper API...")
	var err: int = 0

	err += _assert(MultiplayerInput.action_name(0, &"interact") == &"p0_interact", "action_name(0, 'interact') is p0_interact")
	err += _assert(MultiplayerInput.action_name(1, &"drop") == &"p1_drop", "action_name(1, 'drop') is p1_drop")
	err += _assert(MultiplayerInput.action_name(2, &"move_up") == &"p2_move_up", "action_name(2, 'move_up') is p2_move_up")
	err += _assert(MultiplayerInput.action_name(3, &"pause") == &"p3_pause", "action_name(3, 'pause') is p3_pause")

	# Device types and prompts
	MultiplayerInput.assign_device(0, -1)
	err += _assert(MultiplayerInput.get_player_device_type(0) == InputHelper.DeviceType.KEYBOARD, "Device -1 detects as KEYBOARD")
	err += _assert(MultiplayerInput.get_player_action_prompt(0, MultiplayerInput.BASE_INTERACT) == "[E]", "P0 Keyboard prompt is [E]")
	err += _assert(MultiplayerInput.get_player_action_prompt(1, MultiplayerInput.BASE_INTERACT) == "[Num 1]", "P1 Keyboard prompt is [Num 1]")
	err += _assert(MultiplayerInput.get_player_action_prompt(1, MultiplayerInput.BASE_PICK_UP) == "[Num 2]", "P1 Keyboard pickup prompt is [Num 2]")
	err += _assert(MultiplayerInput.get_player_action_prompt(1, MultiplayerInput.BASE_DROP) == "[Num 3]", "P1 Keyboard drop prompt is [Num 3]")

	# Initial movement when idle
	err += _assert(MultiplayerInput.get_movement_vector(0) == Vector2.ZERO, "P0 idle movement is Vector2.ZERO")
	err += _assert(MultiplayerInput.get_movement_vector_3d(0) == Vector3.ZERO, "P0 idle 3D movement is Vector3.ZERO")
	err += _assert(MultiplayerInput.is_moving(0) == false, "P0 is_moving is false")

	return err


## 4. Test keyboard split isolation between P0 (WASD) and P1 (Arrows)
func test_keyboard_split_isolation() -> int:
	print("\n[4] Testing keyboard split isolation (P0 vs P1)...")
	var err: int = 0

	# Simulate pressing W (P0 move_up)
	var key_w_press := InputEventKey.new()
	key_w_press.physical_keycode = KEY_W
	key_w_press.pressed = true
	Input.parse_input_event(key_w_press)
	Input.flush_buffered_events()

	var p0_move := MultiplayerInput.get_movement_vector_3d(0)
	var p1_move := MultiplayerInput.get_movement_vector_3d(1)
	err += _assert(is_equal_approx(p0_move.z, -1.0), "Pressing W causes P0 to move forward (Z = -1.0)")
	err += _assert(p1_move == Vector3.ZERO, "Pressing W does NOT move P1")

	# Release W
	var key_w_release := InputEventKey.new()
	key_w_release.physical_keycode = KEY_W
	key_w_release.pressed = false
	Input.parse_input_event(key_w_release)
	Input.flush_buffered_events()

	# Simulate pressing Up Arrow (P1 move_up)
	var key_up_press := InputEventKey.new()
	key_up_press.physical_keycode = KEY_UP
	key_up_press.pressed = true
	Input.parse_input_event(key_up_press)
	Input.flush_buffered_events()

	p0_move = MultiplayerInput.get_movement_vector_3d(0)
	p1_move = MultiplayerInput.get_movement_vector_3d(1)
	err += _assert(p0_move == Vector3.ZERO, "Pressing Up Arrow does NOT move P0")
	err += _assert(is_equal_approx(p1_move.z, -1.0), "Pressing Up Arrow causes P1 to move forward (Z = -1.0)")

	# Release Up Arrow
	var key_up_release := InputEventKey.new()
	key_up_release.physical_keycode = KEY_UP
	key_up_release.pressed = false
	Input.parse_input_event(key_up_release)
	Input.flush_buffered_events()

	# Test E (P0 interact) vs KP 1 (P1 interact)
	var key_e_press := InputEventKey.new()
	key_e_press.physical_keycode = KEY_E
	key_e_press.pressed = true
	Input.parse_input_event(key_e_press)
	Input.flush_buffered_events()

	err += _assert(MultiplayerInput.is_action_pressed(0, MultiplayerInput.BASE_INTERACT), "Key E activates p0_interact")
	err += _assert(not MultiplayerInput.is_action_pressed(1, MultiplayerInput.BASE_INTERACT), "Key E does NOT activate p1_interact")

	var key_e_release := InputEventKey.new()
	key_e_release.physical_keycode = KEY_E
	key_e_release.pressed = false
	Input.parse_input_event(key_e_release)
	Input.flush_buffered_events()

	var key_kp1_press := InputEventKey.new()
	key_kp1_press.physical_keycode = KEY_KP_1
	key_kp1_press.pressed = true
	Input.parse_input_event(key_kp1_press)
	Input.flush_buffered_events()

	err += _assert(not MultiplayerInput.is_action_pressed(0, MultiplayerInput.BASE_INTERACT), "Key KP 1 does NOT activate p0_interact")
	err += _assert(MultiplayerInput.is_action_pressed(1, MultiplayerInput.BASE_INTERACT), "Key KP 1 activates p1_interact")

	var key_kp1_release := InputEventKey.new()
	key_kp1_release.physical_keycode = KEY_KP_1
	key_kp1_release.pressed = false
	Input.parse_input_event(key_kp1_release)
	Input.flush_buffered_events()

	return err


## 5. Test Gamepad device isolation across all 4 joypad slots (0, 1, 2, 3)
func test_gamepad_device_isolation() -> int:
	print("\n[5] Testing gamepad device isolation across all 4 joypad slots...")
	var err: int = 0

	for dev_id in range(Constants.MAX_PLAYERS):
		var btn_press := InputEventJoypadButton.new()
		btn_press.button_index = JOY_BUTTON_A
		btn_press.device = dev_id
		btn_press.pressed = true
		Input.parse_input_event(btn_press)
		Input.flush_buffered_events()

		for check_slot in range(Constants.MAX_PLAYERS):
			var is_pressed: bool = MultiplayerInput.is_action_pressed(check_slot, MultiplayerInput.BASE_INTERACT)
			if check_slot == dev_id:
				err += _assert(is_pressed, "Joypad %d Button A activates p%d_interact" % [dev_id, check_slot])
			else:
				err += _assert(not is_pressed, "Joypad %d Button A does NOT activate p%d_interact" % [dev_id, check_slot])

		# Release
		var btn_release := InputEventJoypadButton.new()
		btn_release.button_index = JOY_BUTTON_A
		btn_release.device = dev_id
		btn_release.pressed = false
		Input.parse_input_event(btn_release)
		Input.flush_buffered_events()

	return err


## 6. Test PlayerCharacter physics process movement routing per player_index
func test_player_controller_input_routing() -> int:
	print("\n[6] Testing PlayerCharacter movement routing with multiple players...")
	var err: int = 0

	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var p0: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	p0.player_index = 0
	p0.position = Vector3(0, 0, 0)
	add_child(p0)

	var p1: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	p1.player_index = 1
	p1.position = Vector3(10, 0, 0)
	add_child(p1)


	# Simulate W press
	var key_w := InputEventKey.new()
	key_w.physical_keycode = KEY_W
	key_w.pressed = true
	Input.parse_input_event(key_w)
	Input.flush_buffered_events()

	p0._physics_process(0.016)
	p1._physics_process(0.016)

	err += _assert(p0.velocity.length_squared() > 0.0, "P0 moves when W is pressed")
	err += _assert(p1.velocity.length_squared() == 0.0, "P1 stays still when W is pressed")

	# Release W
	var key_w_rel := InputEventKey.new()
	key_w_rel.physical_keycode = KEY_W
	key_w_rel.pressed = false
	Input.parse_input_event(key_w_rel)
	Input.flush_buffered_events()

	# Simulate Up Arrow press
	var key_up := InputEventKey.new()
	key_up.physical_keycode = KEY_UP
	key_up.pressed = true
	Input.parse_input_event(key_up)
	Input.flush_buffered_events()

	p0._physics_process(0.016)
	p1._physics_process(0.016)

	err += _assert(p0.velocity.length_squared() == 0.0, "P0 stays still when Up Arrow is pressed")
	err += _assert(p1.velocity.length_squared() > 0.0, "P1 moves when Up Arrow is pressed")

	# Release Up
	var key_up_rel := InputEventKey.new()
	key_up_rel.physical_keycode = KEY_UP
	key_up_rel.pressed = false
	Input.parse_input_event(key_up_rel)
	Input.flush_buffered_events()

	p0.queue_free()
	p1.queue_free()
	return err


## 7. Test InteractionSystem and CarrySystem per-player isolation
func test_interaction_and_carry_isolation() -> int:
	print("\n[7] Testing InteractionSystem and CarrySystem per-player input isolation...")
	var err: int = 0

	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var p0: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	p0.player_index = 0
	add_child(p0)

	var p1: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	p1.player_index = 1
	add_child(p1)

	# Create two interactables
	var zone0 := Interactable.new()
	var zone1 := Interactable.new()
	add_child(zone0)
	add_child(zone1)

	var interaction_state := {
		"p0": false,
		"p1": false,
	}
	zone0.interacted.connect(func(_p): interaction_state["p0"] = true)
	zone1.interacted.connect(func(_p): interaction_state["p1"] = true)

	p0.interaction_system._on_area_entered(zone0)
	p0.interaction_system._update_focus()
	p1.interaction_system._on_area_entered(zone1)
	p1.interaction_system._update_focus()

	# Press Key E (P0 interact)
	var key_e := InputEventKey.new()
	key_e.physical_keycode = KEY_E
	key_e.pressed = true

	p0.interaction_system._unhandled_input(key_e)
	p1.interaction_system._unhandled_input(key_e)

	err += _assert(interaction_state["p0"] == true, "Key E triggered P0's interaction system")
	err += _assert(interaction_state["p1"] == false, "Key E did NOT trigger P1's interaction system")

	# Press Key KP 1 (P1 interact)
	var key_kp1 := InputEventKey.new()
	key_kp1.physical_keycode = KEY_KP_1
	key_kp1.pressed = true

	p0.interaction_system._unhandled_input(key_kp1)
	p1.interaction_system._unhandled_input(key_kp1)

	err += _assert(interaction_state["p1"] == true, "Key KP 1 triggered P1's interaction system")

	# Test CarrySystem drop isolation
	var item0 := Carriable.new()
	item0.item_name = "Item0"
	var item1 := Carriable.new()
	item1.item_name = "Item1"
	add_child(item0)
	add_child(item1)

	p0.carry_system.pick_up(item0)
	p1.carry_system.pick_up(item1)

	err += _assert(p0.carry_system.is_carrying() == true, "P0 is carrying Item0")
	err += _assert(p1.carry_system.is_carrying() == true, "P1 is carrying Item1")

	# Send p0_drop event (Key G)
	var key_g := InputEventKey.new()
	key_g.physical_keycode = KEY_G
	key_g.pressed = true

	p0.carry_system._unhandled_input(key_g)
	p1.carry_system._unhandled_input(key_g)

	err += _assert(p0.carry_system.is_carrying() == false, "Key G dropped P0's item")
	err += _assert(p1.carry_system.is_carrying() == true, "Key G did NOT drop P1's item")

	# Send p1_drop event (Key KP 3)
	var key_kp3 := InputEventKey.new()
	key_kp3.physical_keycode = KEY_KP_3
	key_kp3.pressed = true

	p0.carry_system._unhandled_input(key_kp3)
	p1.carry_system._unhandled_input(key_kp3)

	err += _assert(p1.carry_system.is_carrying() == false, "Key KP 3 dropped P1's item")

	# Cleanup
	zone0.queue_free()
	zone1.queue_free()
	item0.queue_free()
	item1.queue_free()
	p0.queue_free()
	p1.queue_free()
	return err


## 8. Test dynamic device assignment logic
func test_dynamic_device_assignment() -> int:
	print("\n[8] Testing dynamic controller connection assignment...")
	var err: int = 0

	MultiplayerInput.reset_assignments()
	err += _assert(MultiplayerInput.get_assigned_device(0) == (0 if not Input.get_connected_joypads().is_empty() else -1),
		"Device assignment defaults correctly based on connected joypads")

	# Manual override test
	MultiplayerInput.assign_device(0, 2)
	err += _assert(MultiplayerInput.get_assigned_device(0) == 2, "assign_device overrides slot 0 to joypad 2")

	MultiplayerInput.assign_device(0, -1)
	err += _assert(MultiplayerInput.get_assigned_device(0) == -1, "assign_device resets slot 0 to keyboard (-1)")

	# Reset
	MultiplayerInput.reset_assignments()
	return err


# Helper functions
func _action_has_key(action: StringName, key: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var iek: InputEventKey = ev as InputEventKey
			if iek.physical_keycode == key or iek.keycode == key:
				return true
	return false


func _action_has_joy_button_with_device(action: StringName, btn: JoyButton, device: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			var iejb: InputEventJoypadButton = ev as InputEventJoypadButton
			if iejb.button_index == btn and iejb.device == device:
				return true
	return false


func _action_has_joy_motion_with_device(action: StringName, axis: JoyAxis, val: float, device: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			var iejm: InputEventJoypadMotion = ev as InputEventJoypadMotion
			if iejm.axis == axis and is_equal_approx(iejm.axis_value, val) and iejm.device == device:
				return true
	return false
