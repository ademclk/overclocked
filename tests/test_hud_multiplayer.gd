extends Node

## Test suite for Phase 2G: HUD Adaptation for Multiplayer
## Tests shared orders, multi-player carried items panel, per-player prompt formatting
## (keyboard split & gamepad), slot visibility, player color coding, dynamic join/leave,
## and shared scoring.

const HUD_SCENE_PATH: String = "res://scenes/ui/HUD.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"
const DIAGNOSTIC_BENCH_PATH: String = "res://scenes/stations/DiagnosticBench.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2G MULTIPLAYER HUD TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_multiplayer_hud_scene_structure()
	failures += test_multiplayer_setup_and_discovery()
	failures += test_slot_color_and_tag_formatting()
	failures += test_multiplayer_carried_items()
	failures += test_per_player_interaction_prompt_formatting()
	failures += test_multiplayer_focus_resolution()
	failures += test_signal_bus_join_and_leave()
	failures += test_shared_orders_and_score()

	print("=========================================================")
	print("--- PHASE 2G MULTIPLAYER HUD TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2G MULTIPLAYER HUD TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2G HUD tests FAILED with %d error(s)." % failures)
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
	if n.is_in_group("players"):
		n.remove_from_group("players")
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.free()


func _create_player(index: int) -> PlayerCharacter:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	player.player_index = index
	add_child(player)
	player.set_player_index(index)
	return player


## 1. Test HUD Scene structure for multiplayer carried items panel
func test_multiplayer_hud_scene_structure() -> int:
	print("\n[1] Testing HUD scene structure for multiplayer carried items panel...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	err += _assert(hud.carried_items_panel != null, "hud.carried_items_panel exists")
	err += _assert(hud.carried_items_panel is HBoxContainer, "carried_items_panel is HBoxContainer")

	for i in range(1, 5):
		var slot_name: String = "P%dCarrySlot" % i
		var slot: Control = hud.carried_items_panel.get_node_or_null(slot_name) as Control
		err += _assert(slot != null, "%s exists in CarriedItemsPanel" % slot_name)
		err += _assert(slot is VBoxContainer, "%s is VBoxContainer" % slot_name)

		var tag: Label = slot.get_node_or_null("PlayerTag") as Label
		var item_name: Label = slot.get_node_or_null("ItemName") as Label
		err += _assert(tag != null, "%s has PlayerTag label" % slot_name)
		err += _assert(item_name != null, "%s has ItemName label" % slot_name)

	_cleanup_node(hud)
	return err


## 2. Test multi-player setup, tracking, and slot visibility
func test_multiplayer_setup_and_discovery() -> int:
	print("\n[2] Testing multi-player setup, tracking, and slot visibility...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p0 := _create_player(0)
	var p1 := _create_player(1)
	var p2 := _create_player(2)
	var p3 := _create_player(3)

	# 2-player setup
	hud.setup_multiplayer([p0, p1])
	err += _assert(hud.get_tracked_players().size() == 2, "2 players tracked via setup_multiplayer")
	var slot1: Control = hud.carried_items_panel.get_node("P1CarrySlot") as Control
	var slot2: Control = hud.carried_items_panel.get_node("P2CarrySlot") as Control
	var slot3: Control = hud.carried_items_panel.get_node("P3CarrySlot") as Control
	var slot4: Control = hud.carried_items_panel.get_node("P4CarrySlot") as Control

	err += _assert(slot1.visible == true, "Slot 1 visible for 2 players")
	err += _assert(slot2.visible == true, "Slot 2 visible for 2 players")
	err += _assert(slot3.visible == false, "Slot 3 hidden for 2 players")
	err += _assert(slot4.visible == false, "Slot 4 hidden for 2 players")

	# Add player 3
	hud.add_tracked_player(p2)
	err += _assert(hud.get_tracked_players().size() == 3, "3 players tracked after add_tracked_player")
	err += _assert(slot3.visible == true, "Slot 3 visible for 3 players")
	err += _assert(slot4.visible == false, "Slot 4 hidden for 3 players")

	# Add player 4
	hud.add_tracked_player(p3)
	err += _assert(hud.get_tracked_players().size() == 4, "4 players tracked")
	err += _assert(slot4.visible == true, "Slot 4 visible for 4 players")

	# Remove player 2
	hud.remove_tracked_player(p1)
	err += _assert(hud.get_tracked_players().size() == 3, "3 players tracked after remove")
	err += _assert(slot4.visible == false, "Slot 4 hidden after remove")

	# Test setup() polymorphic array acceptance
	hud.setup([p0, p1])
	err += _assert(hud.get_tracked_players().size() == 2, "setup([p0, p1]) sets 2 players")

	# Test setup() single player acceptance
	hud.setup(p0)
	err += _assert(hud.get_tracked_players().size() == 1, "setup(p0) sets 1 player")
	err += _assert(slot1.visible == true, "Slot 1 visible for 1 player")
	err += _assert(slot2.visible == false, "Slot 2 hidden for 1 player")

	_cleanup_node(p0)
	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(p3)
	_cleanup_node(hud)
	return err


## 3. Test slot color coding and player tag formatting
func test_slot_color_and_tag_formatting() -> int:
	print("\n[3] Testing slot color coding and player tag formatting...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var players: Array[PlayerCharacter] = []
	for i in range(4):
		players.append(_create_player(i))

	hud.setup_multiplayer(players)

	for i in range(4):
		var slot: Control = hud.carried_items_panel.get_node("P%dCarrySlot" % (i + 1)) as Control
		var tag: Label = slot.get_node("PlayerTag") as Label
		var expected_color: Color = Constants.PLAYER_COLORS[i]

		err += _assert(tag.text.contains("P%d" % (i + 1)), "Player tag text contains 'P%d'" % (i + 1))
		err += _assert(tag.modulate == expected_color, "Player tag %d modulate matches Constants.PLAYER_COLORS[%d]" % [i + 1, i])

	for p in players:
		_cleanup_node(p)
	_cleanup_node(hud)
	return err


## 4. Test multi-player carried items tracking concurrently
func test_multiplayer_carried_items() -> int:
	print("\n[4] Testing multi-player carried items tracking concurrently...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	hud.setup_multiplayer([p1, p2])

	var p1_label: Label = hud.carried_items_panel.get_node("P1CarrySlot/ItemName") as Label
	var p2_label: Label = hud.carried_items_panel.get_node("P2CarrySlot/ItemName") as Label

	# Initial empty state
	hud._update_carried_item()
	err += _assert(p1_label.text == "—", "P1 initial carry slot is '—'")
	err += _assert(p2_label.text == "—", "P2 initial carry slot is '—'")

	# P1 picks up a Phone
	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var fault: FaultData = load(CRACKED_SCREEN_FAULT_PATH)
	dev.initialize(phone_data, fault)
	add_child(dev)

	p1.carry_system.pick_up(dev)
	hud._update_carried_item()

	err += _assert(p1_label.text.contains("Phone"), "P1 carry slot shows 'Phone'")
	err += _assert(p1_label.text.contains("RECEIVED"), "P1 carry slot shows '[RECEIVED]'")
	err += _assert(p2_label.text == "—", "P2 carry slot remains '—'")

	# P2 picks up a Replacement Battery part
	var part := Carriable.new()
	part.item_name = "Replacement Battery"
	part.item_type = "part"
	add_child(part)

	p2.carry_system.pick_up(part)
	hud._update_carried_item()

	err += _assert(p1_label.text.contains("Phone"), "P1 still shows Phone")
	err += _assert(p2_label.text.contains("Replacement Battery"), "P2 carry slot shows 'Replacement Battery'")

	# P1's device is diagnosed
	dev.diagnose()
	hud._update_carried_item()

	err += _assert(p1_label.text.contains("DIAGNOSED"), "P1 carry slot updates to '[DIAGNOSED]'")
	err += _assert(p1_label.text.contains(fault.fault_name), "P1 carry slot shows fault name")
	err += _assert(p2_label.text.contains("Replacement Battery"), "P2 carry slot unchanged")

	# P1 drops item
	p1.carry_system.drop_item()
	hud._update_carried_item()

	err += _assert(p1_label.text == "—", "P1 carry slot resets to '—' after drop")
	err += _assert(p2_label.text.contains("Replacement Battery"), "P2 still carries battery")

	# P2 drops item
	p2.carry_system.drop_item()
	hud._update_carried_item()

	err += _assert(p2_label.text == "—", "P2 carry slot resets to '—' after drop")

	_cleanup_node(part)
	_cleanup_node(dev)
	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(hud)
	return err


## 5. Test per-player interaction prompt formatting
func test_per_player_interaction_prompt_formatting() -> int:
	print("\n[5] Testing per-player interaction prompt formatting (keyboard split & gamepad)...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	hud.setup_multiplayer([p1, p2])

	var bench: DiagnosticBench = load(DIAGNOSTIC_BENCH_PATH).instantiate() as DiagnosticBench
	add_child(bench)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)

	# P1 on keyboard (WASD + E) focuses bench
	p1.carry_system.pick_up(dev)
	bench.interaction_zone.focus_gained.emit(p1)
	p1.interaction_system._current_focus = bench.interaction_zone

	# Ensure device assignment for P1 is keyboard (-1)
	MultiplayerInput.assign_device(0, -1)
	hud._update_interaction_prompt()

	err += _assert(hud.interaction_prompt.visible, "Prompt visible for P1")
	err += _assert(hud.prompt_label.text.contains("[E]"), "P1 prompt contains '[E]' (got: '%s')" % hud.prompt_label.text)
	err += _assert(hud.prompt_label.text.contains("Diagnose Device"), "P1 prompt describes action")

	# P1 clears focus
	bench.interaction_zone.focus_lost.emit(p1)
	p1.interaction_system._current_focus = null
	p1.carry_system.drop_item()

	# P2 on keyboard (Arrows + Num 1) focuses bench
	p2.carry_system.pick_up(dev)
	bench.interaction_zone.focus_gained.emit(p2)
	p2.interaction_system._current_focus = bench.interaction_zone

	# Ensure device assignment for P2 is keyboard (-1)
	MultiplayerInput.assign_device(1, -1)
	hud._update_interaction_prompt()

	err += _assert(hud.interaction_prompt.visible, "Prompt visible for P2")
	err += _assert(hud.prompt_label.text.contains("[Num 1]"), "P2 prompt contains '[Num 1]' for keyboard split (got: '%s')" % hud.prompt_label.text)

	# Now assign P2 to gamepad device 0
	MultiplayerInput.assign_device(1, 0)
	hud._update_interaction_prompt()
	var expected_joy_prompt: String = MultiplayerInput.get_player_action_prompt(1, MultiplayerInput.BASE_INTERACT)
	err += _assert(hud.prompt_label.text.contains(expected_joy_prompt), "P2 prompt updates to gamepad prompt '%s' (got: '%s')" % [expected_joy_prompt, hud.prompt_label.text])

	# Test occupied station prompt
	bench.set_active_user(p1)
	hud._update_interaction_prompt()
	err += _assert(hud.prompt_label.text == "In use by P1", "Occupied prompt shows 'In use by P1' directly")

	# Reset device assignments
	MultiplayerInput.assign_device(0, -1)
	MultiplayerInput.assign_device(1, -1)
	bench.clear_active_user(p1)
	bench.interaction_zone.focus_lost.emit(p2)
	p2.interaction_system._current_focus = null
	p2.carry_system.drop_item()

	_cleanup_node(dev)
	_cleanup_node(bench)
	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(hud)
	return err


## 6. Test multi-player focus resolution (closest player prompt shown)
func test_multiplayer_focus_resolution() -> int:
	print("\n[6] Testing multi-player focus resolution (closest player prompt shown)...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	hud.setup_multiplayer([p1, p2])

	var bench1: DiagnosticBench = load(DIAGNOSTIC_BENCH_PATH).instantiate() as DiagnosticBench
	add_child(bench1)
	bench1.global_position = Vector3(0, 0, 0)

	var bench2: DiagnosticBench = load(DIAGNOSTIC_BENCH_PATH).instantiate() as DiagnosticBench
	add_child(bench2)
	bench2.global_position = Vector3(10, 0, 0)

	var dev1: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev1.initialize(load(PHONE_DATA_PATH))
	add_child(dev1)
	p1.carry_system.pick_up(dev1)

	var dev2: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev2.initialize(load(PHONE_DATA_PATH))
	add_child(dev2)
	p2.carry_system.pick_up(dev2)

	# P1 is at distance 1.0 from bench1
	p1.global_position = Vector3(1, 0, 0)
	bench1.interaction_zone.focus_gained.emit(p1)
	p1.interaction_system._current_focus = bench1.interaction_zone

	# P2 is at distance 3.0 from bench2
	p2.global_position = Vector3(13, 0, 0)
	bench2.interaction_zone.focus_gained.emit(p2)
	p2.interaction_system._current_focus = bench2.interaction_zone

	hud._update_interaction_prompt()
	err += _assert(hud.prompt_label.text.contains("[E]"), "Closest player (P1 at dist 1.0) selected over P2 (dist 3.0)")

	# Now move P2 closer to bench2 (dist 0.2) and move P1 further (dist 5.0)
	p2.global_position = Vector3(10.2, 0, 0)
	p1.global_position = Vector3(5.0, 0, 0)

	hud._update_interaction_prompt()
	err += _assert(hud.prompt_label.text.contains("[Num 1]"), "Closest player (P2 at dist 0.2) selected over P1 (dist 5.0)")

	# P2 loses focus -> P1 prompt shown
	bench2.interaction_zone.focus_lost.emit(p2)
	p2.interaction_system._current_focus = null
	hud._update_interaction_prompt()
	err += _assert(hud.prompt_label.text.contains("[E]"), "P1 prompt shown when P2 focus lost")

	# P1 also loses focus -> prompt hidden
	bench1.interaction_zone.focus_lost.emit(p1)
	p1.interaction_system._current_focus = null
	hud._update_interaction_prompt()
	err += _assert(not hud.interaction_prompt.visible, "Prompt hidden when all players lose focus")

	p1.carry_system.drop_item()
	p2.carry_system.drop_item()
	_cleanup_node(dev1)
	_cleanup_node(dev2)
	_cleanup_node(bench1)
	_cleanup_node(bench2)
	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(hud)
	return err


## 7. Test dynamic player join and leave via SignalBus
func test_signal_bus_join_and_leave() -> int:
	print("\n[7] Testing dynamic player join and leave via SignalBus...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	hud.setup_multiplayer([p1])
	err += _assert(hud.get_tracked_players().size() == 1, "Initially 1 player tracked")

	# Player 2 joins dynamically
	var p2 := _create_player(1)
	SignalBus.player_joined.emit(1)
	err += _assert(hud.get_tracked_players().size() == 2, "HUD auto-discovered and tracked P2 on player_joined")
	var slot2: Control = hud.carried_items_panel.get_node("P2CarrySlot") as Control
	err += _assert(slot2.visible == true, "P2CarrySlot is now visible")

	# Player 2 leaves dynamically
	SignalBus.player_left.emit(1)
	err += _assert(hud.get_tracked_players().size() == 1, "HUD removed P2 on player_left")
	err += _assert(slot2.visible == false, "P2CarrySlot hidden after P2 left")

	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(hud)
	return err


## 8. Test shared orders and shared team scoring
func test_shared_orders_and_score() -> int:
	print("\n[8] Testing shared orders and shared team scoring...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	var mgr := OrderManager.new()
	add_child(hud)
	add_child(mgr)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	hud.setup_multiplayer([p1, p2], mgr)

	# Spawn order
	var order: Order = mgr.spawn_order(load(PHONE_DATA_PATH))
	hud._update_active_orders()
	err += _assert(hud._order_entries.has(order), "Shared order tracked in HUD for both players")

	# Complete order
	mgr.complete_order(order)
	err += _assert(hud.score_label.text.contains("Score: %d" % mgr.total_score), "Shared team score updated on HUD")
	err += _assert(hud.current_stars == mgr.total_stars, "Shared stars updated on HUD")

	if order.device_instance:
		_cleanup_node(order.device_instance)
	_cleanup_node(mgr)
	_cleanup_node(p1)
	_cleanup_node(p2)
	_cleanup_node(hud)
	return err
