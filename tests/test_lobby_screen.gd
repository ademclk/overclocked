extends Node

## Test suite for Lobby Screen (Player Join / Leave)
## Tests lobby scene structure, device detection (keyboard split & gamepads),
## join/leave flows, visual color coding, ready-up synchronization, minimum player validation,
## device assignment propagation, and controller disconnect handling.

const LOBBY_SCENE_PATH: String = "res://scenes/ui/LobbyScreen.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2H LOBBY SCREEN TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_lobby_scene_structure()
	failures += test_initial_state_empty()
	failures += test_player_join_input()
	failures += test_visual_feedback_and_color_coding()
	failures += test_ready_up_mechanic()
	failures += test_unready_and_leave_mechanic()
	failures += test_minimum_players_requirement()
	failures += test_start_game_and_device_assignment()
	failures += test_joypad_disconnect_releases_slot()
	failures += test_lobby_cancelled_signal()

	print("=========================================================")
	print("--- PHASE 2H LOBBY SCREEN TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2H LOBBY SCREEN TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2H Lobby Screen tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _cleanup_node(n: Node) -> void:
	if not n or not is_instance_valid(n):
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.free()


## 1. Test Lobby scene node hierarchy and required node paths
func test_lobby_scene_structure() -> int:
	print("\n[1] Testing LobbyScreen scene structure and node paths...")
	var err: int = 0

	var lobby_scene: PackedScene = load(LOBBY_SCENE_PATH)
	err += _assert(lobby_scene != null, "Loaded LobbyScreen.tscn successfully")

	var lobby: LobbyScreen = lobby_scene.instantiate() as LobbyScreen
	err += _assert(lobby != null, "LobbyScreen scene root is instance of LobbyScreen")
	add_child(lobby)

	err += _assert(lobby.title_label != null, "lobby.title_label exists")
	err += _assert(lobby.slots_container != null, "lobby.slots_container exists")
	err += _assert(lobby.instruction_label != null, "lobby.instruction_label exists")
	err += _assert(lobby.start_prompt != null, "lobby.start_prompt exists")

	for i in range(1, 5):
		var slot_name: String = "PlayerSlot%d" % i
		var slot: Control = lobby.slots_container.get_node_or_null(slot_name) as Control
		err += _assert(slot != null, "%s exists in SlotsContainer" % slot_name)
		err += _assert(slot.find_child("SlotLabel", true, false) != null, "%s has SlotLabel" % slot_name)
		err += _assert(slot.find_child("DeviceLabel", true, false) != null, "%s has DeviceLabel" % slot_name)
		err += _assert(slot.find_child("ReadyIndicator", true, false) != null, "%s has ReadyIndicator" % slot_name)

	_cleanup_node(lobby)
	return err


## 2. Test initial empty state
func test_initial_state_empty() -> int:
	print("\n[2] Testing initial empty state...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	for i in range(4):
		err += _assert(lobby.is_slot_empty(i) == true, "Slot %d is initially EMPTY" % (i + 1))
		err += _assert(lobby.is_slot_ready(i) == false, "Slot %d is initially NOT ready" % (i + 1))

	err += _assert(lobby.get_joined_count() == 0, "Joined count is initially 0")
	err += _assert(lobby.get_ready_count() == 0, "Ready count is initially 0")
	err += _assert(lobby.are_all_ready() == false, "are_all_ready is initially false")
	err += _assert(lobby.start_prompt.visible == false, "StartPrompt is initially hidden")

	_cleanup_node(lobby)
	return err


## 3. Test player join flow via keyboard and gamepad inputs
func test_player_join_input() -> int:
	print("\n[3] Testing player join flow via keyboard and gamepad inputs...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	var joined_events: Array[Dictionary] = []
	lobby.player_slot_joined.connect(func(slot_idx: int, dev_id: int) -> void:
		joined_events.append({"slot": slot_idx, "device": dev_id})
	)

	# Keyboard P0 (WASD/E) presses key
	var key_event0 := InputEventKey.new()
	key_event0.keycode = KEY_E
	key_event0.pressed = true
	lobby._unhandled_input(key_event0)

	err += _assert(lobby.is_slot_empty(0) == false, "Slot 0 joined by Keyboard P0")
	err += _assert(lobby.get_slot_device(0) == -1, "Slot 0 device is -1 (Keyboard 0)")
	err += _assert(lobby.get_joined_count() == 1, "Joined count is 1")
	err += _assert(joined_events.size() == 1 and joined_events[0].slot == 0, "player_slot_joined emitted for slot 0")

	# Joypad 0 presses A button
	var joy_event0 := InputEventJoypadButton.new()
	joy_event0.device = 0
	joy_event0.button_index = JOY_BUTTON_A
	joy_event0.pressed = true
	lobby._unhandled_input(joy_event0)

	err += _assert(lobby.is_slot_empty(1) == false, "Slot 1 joined by Joypad 0")
	err += _assert(lobby.get_slot_device(1) == 0, "Slot 1 device is 0 (Joypad 0)")
	err += _assert(lobby.get_joined_count() == 2, "Joined count is 2")
	err += _assert(joined_events.size() == 2 and joined_events[1].slot == 1, "player_slot_joined emitted for slot 1")

	# Keyboard P1 (Arrows/Numpad) presses key
	var key_event1 := InputEventKey.new()
	key_event1.keycode = KEY_KP_1
	key_event1.pressed = true
	lobby._unhandled_input(key_event1)

	err += _assert(lobby.is_slot_empty(2) == false, "Slot 2 joined by Keyboard P1 split")
	err += _assert(lobby.get_slot_device(2) == -3, "Slot 2 device is -3 (Keyboard 1 split)")
	err += _assert(lobby.get_joined_count() == 3, "Joined count is 3")

	_cleanup_node(lobby)
	return err


## 4. Test visual feedback and color coding on join
func test_visual_feedback_and_color_coding() -> int:
	print("\n[4] Testing visual feedback and color coding on join...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	lobby.join_player(0, -1) # P1 on Keyboard
	lobby.join_player(1, 0)  # P2 on Gamepad
	lobby.join_player(2, -3) # P3 on Keyboard split
	lobby.join_player(3, 1)  # P4 on Gamepad 2

	for i in range(4):
		var slot_node: Control = lobby.slots_container.get_node("PlayerSlot%d" % (i + 1)) as Control
		var slot_label: Label = slot_node.find_child("SlotLabel", true, false) as Label
		var expected_color: Color = Constants.PLAYER_COLORS[i]

		err += _assert(slot_label.text.contains("PLAYER %d" % (i + 1)), "Slot %d text contains 'PLAYER %d'" % [i + 1, i + 1])
		err += _assert(slot_label.modulate == expected_color, "Slot %d text color matches Constants.PLAYER_COLORS[%d]" % [i + 1, i])

	_cleanup_node(lobby)
	return err


## 5. Test ready-up mechanic and synchronization
func test_ready_up_mechanic() -> int:
	print("\n[5] Testing ready-up mechanic and synchronization...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	lobby.join_player(0, -1) # P1
	lobby.join_player(1, 0)  # P2

	var ready_events: Array[Dictionary] = []
	lobby.player_slot_ready_changed.connect(func(slot_idx: int, is_ready: bool) -> void:
		ready_events.append({"slot": slot_idx, "ready": is_ready})
	)

	# P1 readies up via action key (E)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_E
	key_event.pressed = true
	lobby._unhandled_input(key_event)

	err += _assert(lobby.is_slot_ready(0) == true, "Slot 0 is READY")
	err += _assert(lobby.is_slot_ready(1) == false, "Slot 1 is still NOT ready")
	err += _assert(lobby.get_ready_count() == 1, "Ready count is 1")
	err += _assert(lobby.are_all_ready() == false, "are_all_ready is false while P2 not ready")
	err += _assert(lobby.start_prompt.visible == false, "StartPrompt hidden while not all ready")

	# P2 readies up via Joypad 0 Button A
	var joy_event := InputEventJoypadButton.new()
	joy_event.device = 0
	joy_event.button_index = JOY_BUTTON_A
	joy_event.pressed = true
	lobby._unhandled_input(joy_event)

	err += _assert(lobby.is_slot_ready(1) == true, "Slot 1 is READY")
	err += _assert(lobby.get_ready_count() == 2, "Ready count is 2")
	err += _assert(lobby.are_all_ready() == true, "are_all_ready is TRUE when all joined are ready")
	err += _assert(lobby.start_prompt.visible == true, "StartPrompt visible when all ready")
	err += _assert(ready_events.size() == 2, "player_slot_ready_changed emitted for both players")

	_cleanup_node(lobby)
	return err


## 6. Test unready and leave flow
func test_unready_and_leave_mechanic() -> int:
	print("\n[6] Testing unready and leave mechanic...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	lobby.join_player(0, -1)
	lobby.join_player(1, 0)
	lobby.set_player_ready(0, true)
	lobby.set_player_ready(1, true)
	err += _assert(lobby.are_all_ready() == true, "Initially both players ready")

	var left_events: Array[int] = []
	lobby.player_slot_left.connect(func(slot_idx: int) -> void:
		left_events.append(slot_idx)
	)

	# P2 presses Joypad B (Cancel) -> unreadies
	var joy_cancel := InputEventJoypadButton.new()
	joy_cancel.device = 0
	joy_cancel.button_index = JOY_BUTTON_B
	joy_cancel.pressed = true
	lobby._unhandled_input(joy_cancel)

	err += _assert(lobby.is_slot_ready(1) == false, "P2 unreadied to JOINED")
	err += _assert(lobby.is_slot_empty(1) == false, "P2 is still in slot")
	err += _assert(lobby.are_all_ready() == false, "are_all_ready is false after unready")

	# P2 presses Joypad B again -> leaves slot
	lobby._unhandled_input(joy_cancel)

	err += _assert(lobby.is_slot_empty(1) == true, "P2 left slot (EMPTY)")
	err += _assert(lobby.get_joined_count() == 1, "Joined count dropped to 1")
	err += _assert(left_events.has(1), "player_slot_left emitted for slot 1")
	err += _assert(lobby.are_all_ready() == true, "are_all_ready is TRUE now because only P1 remains and P1 is ready")

	_cleanup_node(lobby)
	return err


## 7. Test minimum players requirement
func test_minimum_players_requirement() -> int:
	print("\n[7] Testing minimum players requirement...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	# 0 players
	err += _assert(lobby.are_all_ready() == false, "0 players cannot start (are_all_ready is false)")

	# 1 player joined & ready
	lobby.join_player(0, -1)
	lobby.set_player_ready(0, true)
	err += _assert(lobby.are_all_ready() == true, "1 player alone can start game if ready")

	_cleanup_node(lobby)
	return err


## 8. Test start game and device assignment propagation
func test_start_game_and_device_assignment() -> int:
	print("\n[8] Testing start game and device assignment propagation...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	lobby.join_player(0, -1) # P1 on keyboard
	lobby.join_player(1, 1)  # P2 on joypad 1
	lobby.set_player_ready(0, true)
	lobby.set_player_ready(1, true)

	var signal_data := {
		"received": false,
		"count": 0,
		"assignments": {}
	}

	lobby.all_players_ready.connect(func(count: int, assignments: Dictionary) -> void:
		signal_data["received"] = true
		signal_data["count"] = count
		signal_data["assignments"] = assignments
	)

	lobby.start_game()

	err += _assert(signal_data["received"] == true, "all_players_ready signal emitted on start_game")
	err += _assert(signal_data["count"] == 2, "Received player count is 2")
	var assignments: Dictionary = signal_data["assignments"]
	err += _assert(assignments.get(0) == -1, "Slot 0 assigned to -1 (Keyboard)")
	err += _assert(assignments.get(1) == 1, "Slot 1 assigned to 1 (Joypad 1)")

	# Verify MultiplayerInput received the assignments
	err += _assert(MultiplayerInput.get_assigned_device(0) == -1, "MultiplayerInput slot 0 is -1")
	err += _assert(MultiplayerInput.get_assigned_device(1) == 1, "MultiplayerInput slot 1 is 1")

	# Verify GameManager received the player count and assignments
	err += _assert(GameManager.registered_player_count == 2, "GameManager registered_player_count updated to 2")
	err += _assert(GameManager.registered_device_assignments.size() == 2, "GameManager registered_device_assignments stored")

	_cleanup_node(lobby)
	return err


## 9. Test joypad disconnect auto-releases slot
func test_joypad_disconnect_releases_slot() -> int:
	print("\n[9] Testing joypad disconnect auto-releases slot...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	lobby.join_player(0, -1) # P1 keyboard
	lobby.join_player(1, 2)  # P2 joypad 2
	lobby.set_player_ready(0, true)
	lobby.set_player_ready(1, true)

	err += _assert(lobby.get_joined_count() == 2, "2 players joined before disconnect")

	# Simulate joypad 2 disconnected
	lobby._on_joy_connection_changed(2, false)

	err += _assert(lobby.is_slot_empty(1) == true, "Slot 1 was automatically cleared when joypad 2 disconnected")
	err += _assert(lobby.get_joined_count() == 1, "Joined count reduced to 1 after disconnect")

	_cleanup_node(lobby)
	return err


## 10. Test lobby cancelled signal on escape with 0 players
func test_lobby_cancelled_signal() -> int:
	print("\n[10] Testing lobby cancelled signal on escape with 0 players...")
	var err: int = 0

	var lobby: LobbyScreen = load(LOBBY_SCENE_PATH).instantiate() as LobbyScreen
	add_child(lobby)

	var cancel_state := {"cancelled": false}
	lobby.lobby_cancelled.connect(func() -> void:
		cancel_state["cancelled"] = true
	)

	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	lobby._unhandled_input(esc_event)

	err += _assert(cancel_state["cancelled"] == true, "lobby_cancelled emitted on Escape with 0 players")

	_cleanup_node(lobby)
	return err
