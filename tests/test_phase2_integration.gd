extends Node

## End-to-End Integration Test Suite for Phase 2J: Multi-Player Integration & Wiring.
## Tests:
## 1. Multi-player spawning & visual identity in Workshop scene
## 2. Input routing & device isolation (keyboard split P0/P1, joypad devices)
## 3. Dynamic camera tracking framing multiple active players
## 4. HUD multi-player carried items and per-player color coding
## 5. Ground item contention resolution (first claims, second rejected, transfer on drop)
## 6. Station occupancy enforcement & "In use by P1" prompts
## 7. Concurrent collaborative repair pipeline (P1 & P2 working in parallel)
## 8. Bump mechanic integration during gameplay (high-speed collision causes item drop)
## 9. Single-player backwards compatibility regression test
## 10. Multi-player debug tools (F10 spawn, F11 cycle focus, F6 advance, F7 give part)

const MAIN_SCENE_PATH: String = "res://scenes/main/Main.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"
const SCREEN_PART_PATH: String = "res://resources/components/screen.tres"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2J MULTI-PLAYER INTEGRATION TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_multiplayer_spawning_and_identity()
	failures += test_input_routing_and_isolation()
	failures += test_camera_dynamic_tracking_integration()
	failures += test_hud_multiplayer_integration()
	failures += test_ground_item_contention_and_transfer()
	failures += test_station_occupancy_integration()
	failures += test_concurrent_collaborative_repair()
	failures += test_bump_mechanic_gameplay_integration()
	failures += test_single_player_regression()
	failures += test_multiplayer_debug_tools()

	print("=========================================================")
	print("--- PHASE 2J INTEGRATION TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2J MULTI-PLAYER INTEGRATION TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2J tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_player(index: int, pos: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = scene.instantiate() as PlayerCharacter
	player.player_index = index
	add_child(player)
	player.global_position = pos
	return player



## 1. Test multi-player spawning and visual identity
func test_multiplayer_spawning_and_identity() -> int:
	print("\n[1] Testing multi-player spawning and visual identity...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 2
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 2, "2 players spawned in workshop")
	var p1: PlayerCharacter = workshop.get_player(0)
	var p2: PlayerCharacter = workshop.get_player(1)

	err += _assert(p1 != null and p2 != null, "Both P1 and P2 exist")
	err += _assert(p1.is_in_group("players"), "P1 is in 'players' group")
	err += _assert(p2.is_in_group("players"), "P2 is in 'players' group")

	# Position checks
	err += _assert(p1.global_position == workshop.spawn_point_p1.global_position, "P1 at SpawnPoint_P1")
	err += _assert(p2.global_position == workshop.spawn_point_p2.global_position, "P2 at SpawnPoint_P2")

	# Visual colors and labels
	err += _assert(p1.get_player_color() == Constants.PLAYER_COLORS[0], "P1 has Blue color")
	err += _assert(p2.get_player_color() == Constants.PLAYER_COLORS[1], "P2 has Red color")
	err += _assert(p1.player_label.text == "P1", "P1 label shows 'P1'")
	err += _assert(p2.player_label.text == "P2", "P2 label shows 'P2'")

	workshop.queue_free()
	return err


## 2. Test input routing and isolation (keyboard split & devices)
func test_input_routing_and_isolation() -> int:
	print("\n[2] Testing input routing and per-player isolation...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 2
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	var p1: PlayerCharacter = workshop.get_player(0)
	var p2: PlayerCharacter = workshop.get_player(1)

	# Simulate P0 move forward (Key W)
	var key_w := InputEventKey.new()
	key_w.physical_keycode = KEY_W
	key_w.pressed = true
	Input.parse_input_event(key_w)
	Input.flush_buffered_events()

	p1._physics_process(0.016)
	p2._physics_process(0.016)

	err += _assert(p1.velocity.length_squared() > 0.0, "Key W moves P1")
	err += _assert(p2.velocity.length_squared() == 0.0, "Key W does NOT move P2")

	var key_w_rel := InputEventKey.new()
	key_w_rel.physical_keycode = KEY_W
	key_w_rel.pressed = false
	Input.parse_input_event(key_w_rel)
	Input.flush_buffered_events()

	# Simulate P1 move forward (Key Up Arrow)
	var key_up := InputEventKey.new()
	key_up.physical_keycode = KEY_UP
	key_up.pressed = true
	Input.parse_input_event(key_up)
	Input.flush_buffered_events()

	p1._physics_process(0.016)
	p2._physics_process(0.016)

	err += _assert(p1.velocity.length_squared() == 0.0, "Key Up does NOT move P1")
	err += _assert(p2.velocity.length_squared() > 0.0, "Key Up moves P2")

	var key_up_rel := InputEventKey.new()
	key_up_rel.physical_keycode = KEY_UP
	key_up_rel.pressed = false
	Input.parse_input_event(key_up_rel)
	Input.flush_buffered_events()

	# Interaction isolation
	var item1 := Carriable.new()
	item1.item_name = "Item1"
	var item2 := Carriable.new()
	item2.item_name = "Item2"
	add_child(item1)
	add_child(item2)

	p1.carry_system.pick_up(item1)
	p2.carry_system.pick_up(item2)

	# P1 drop key (G)
	var key_g := InputEventKey.new()
	key_g.physical_keycode = KEY_G
	key_g.pressed = true
	p1.carry_system._unhandled_input(key_g)
	p2.carry_system._unhandled_input(key_g)

	err += _assert(not p1.carry_system.is_carrying(), "Key G drops P1's item")
	err += _assert(p2.carry_system.is_carrying(), "Key G does NOT drop P2's item")

	# P2 drop key (KP 3)
	var key_kp3 := InputEventKey.new()
	key_kp3.physical_keycode = KEY_KP_3
	key_kp3.pressed = true
	p1.carry_system._unhandled_input(key_kp3)
	p2.carry_system._unhandled_input(key_kp3)

	err += _assert(not p2.carry_system.is_carrying(), "Key KP 3 drops P2's item")

	item1.queue_free()
	item2.queue_free()
	workshop.queue_free()
	return err


## 3. Test camera dynamic tracking integration
func test_camera_dynamic_tracking_integration() -> int:
	print("\n[3] Testing camera tracking integration with multiple players...")
	var err: int = 0

	var main: Main = load(MAIN_SCENE_PATH).instantiate() as Main
	add_child(main)

	var workshop: WorkshopDebug = main.current_level as WorkshopDebug
	workshop.player_count_override = 2
	workshop.despawn_all_players()
	var p1: PlayerCharacter = workshop.spawn_player(0)
	var p2: PlayerCharacter = workshop.spawn_player(1)

	p1.global_position = Vector3(-3.0, 0.0, 0.0)
	p2.global_position = Vector3(3.0, 0.0, 0.0)

	main.camera_rig.set_tracked_players([p1, p2])
	main.camera_rig.tracking_enabled = true
	main.camera_rig.snap_to_target()

	err += _assert(main.camera_rig.tracking_enabled, "Camera tracking is enabled")
	err += _assert(is_equal_approx(main.camera_rig.target_offset.x, 0.0),
		"Camera centered horizontally at midpoint (X=0.0)")

	# Spread players apart to trigger camera zoom out
	p1.global_position = Vector3(-6.0, 0.0, -4.0)
	p2.global_position = Vector3(6.0, 0.0, 4.0)
	main.camera_rig._update_tracking(1.0)

	err += _assert(main.camera_rig.camera_height > main.camera_rig.min_camera_height,
		"Camera height increases when players spread apart (height: %.1f)" % main.camera_rig.camera_height)
	err += _assert(main.camera_rig.camera_height <= main.camera_rig.max_camera_height,
		"Camera height stays within max_camera_height bound")

	main.queue_free()
	return err


## 4. Test HUD multi-player integration
func test_hud_multiplayer_integration() -> int:
	print("\n[4] Testing HUD multi-player carried items and color tags...")
	var err: int = 0

	var main: Main = load(MAIN_SCENE_PATH).instantiate() as Main
	add_child(main)

	var workshop: WorkshopDebug = main.current_level as WorkshopDebug
	workshop.despawn_all_players()
	var p1: PlayerCharacter = workshop.spawn_player(0)
	var p2: PlayerCharacter = workshop.spawn_player(1)

	main._setup_hud()
	var hud: HUD = main.hud

	err += _assert(hud._tracked_players.size() == 2, "HUD tracks both players")

	var slot1: Control = hud.carried_items_panel.get_node("P1CarrySlot") as Control
	var slot2: Control = hud.carried_items_panel.get_node("P2CarrySlot") as Control
	var slot3: Control = hud.carried_items_panel.get_node("P3CarrySlot") as Control
	var slot4: Control = hud.carried_items_panel.get_node("P4CarrySlot") as Control

	err += _assert(slot1.visible, "P1 carry slot is visible")
	err += _assert(slot2.visible, "P2 carry slot is visible")
	err += _assert(not slot3.visible, "P3 carry slot is hidden (2 players)")
	err += _assert(not slot4.visible, "P4 carry slot is hidden (2 players)")

	# Check player color tags
	var tag1: Label = slot1.get_node("PlayerTag") as Label
	var tag2: Label = slot2.get_node("PlayerTag") as Label
	err += _assert(tag1.modulate == Constants.PLAYER_COLORS[0], "P1 tag matches Blue color")
	err += _assert(tag2.modulate == Constants.PLAYER_COLORS[1], "P2 tag matches Red color")

	# P1 picks up phone, P2 picks up screen
	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)
	p1.carry_system.pick_up(dev)

	var part := Carriable.new()
	part.item_name = "Screen"
	add_child(part)
	p2.carry_system.pick_up(part)

	hud._update_carried_item()

	var item1_label: Label = slot1.get_node("ItemName") as Label
	var item2_label: Label = slot2.get_node("ItemName") as Label

	err += _assert(item1_label.text.contains("Phone") and item1_label.text.contains("RECEIVED"),
		"HUD P1 slot displays 'Phone [RECEIVED]' (got '%s')" % item1_label.text)
	err += _assert(item2_label.text == "Screen",
		"HUD P2 slot displays 'Screen' (got '%s')" % item2_label.text)

	p1.carry_system.drop_item()
	p2.carry_system.drop_item()
	dev.queue_free()
	part.queue_free()
	main.queue_free()
	return err


## 5. Test ground item contention and transfer
func test_ground_item_contention_and_transfer() -> int:
	print("\n[5] Testing ground item contention and transfer...")
	var err: int = 0

	var item := Carriable.new()
	item.item_name = "ContestedBattery"
	add_child(item)

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.5, 0.0, 0.0))

	# Both attempt to pick up in same frame
	p1.carry_system.pick_up(item)
	p2.carry_system.pick_up(item)

	err += _assert(p1.carry_system.is_carrying(), "P1 successfully claimed and picked up item")
	err += _assert(not p2.carry_system.is_carrying(), "P2 pick up rejected due to claim locking")
	err += _assert(item.held_by == p1, "Item held by P1")

	# P1 drops item on floor -> claim releases -> P2 picks up
	p1.carry_system.drop_item()
	err += _assert(not item.is_held, "Item dropped on floor")
	err += _assert(item.can_claim(p2), "P2 can now claim dropped item")

	p2.carry_system.pick_up(item)
	err += _assert(p2.carry_system.is_carrying(), "P2 picked up dropped item from floor")
	err += _assert(item.held_by == p2, "Item now held by P2")

	p2.carry_system.drop_item()
	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 6. Test station occupancy integration and prompt display
func test_station_occupancy_integration() -> int:
	print("\n[6] Testing station occupancy and occupied prompts...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 2
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	var p1: PlayerCharacter = workshop.get_player(0)
	var p2: PlayerCharacter = workshop.get_player(1)

	var bench := workshop.diagnostic_bench
	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)

	p1.carry_system.pick_up(dev)
	bench._on_focus_gained(p1)
	bench._on_interacted(p1)

	err += _assert(bench.is_occupied(), "Diagnostic bench is occupied")
	err += _assert(bench.get_active_user() == p1, "Active user is P1")
	err += _assert(not bench.can_player_interact(p2), "P2 cannot interact with bench occupied by P1")
	err += _assert(bench.get_interaction_prompt(p2) == "In use by P1", "P2 prompt is 'In use by P1'")

	# Diagnosis completes
	bench._physics_process(bench.diagnosis_time + 0.1)
	err += _assert(bench.can_player_interact(p1), "P1 can pick up diagnosed device")
	bench._on_interacted(p1)

	err += _assert(not bench.is_occupied(), "Bench occupancy released after device retrieved")
	err += _assert(bench.get_active_user() == null, "Active user cleared")

	# P2 carrying a received device can now interact with the free bench
	var dev2: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev2.initialize(load(PHONE_DATA_PATH))
	add_child(dev2)
	p2.carry_system.pick_up(dev2)
	err += _assert(bench.can_player_interact(p2), "P2 carrying a device can now interact with free bench")

	p1.carry_system.drop_item()
	p2.carry_system.drop_item()
	dev.queue_free()
	dev2.queue_free()
	workshop.queue_free()
	return err


## 7. Test concurrent collaborative repair pipeline
func test_concurrent_collaborative_repair() -> int:
	print("\n[7] Testing concurrent collaborative repair pipeline...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 2
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	var p1: PlayerCharacter = workshop.get_player(0)
	var p2: PlayerCharacter = workshop.get_player(1)

	# Setup Device 1 for P1 (Diagnostic Bench)
	var dev1: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev1.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	add_child(dev1)
	p1.carry_system.pick_up(dev1)

	# Setup Device 2 for P2 (Workbench)
	var dev2: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev2.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev2.diagnose()
	add_child(dev2)
	p2.carry_system.pick_up(dev2)

	# P1 places dev1 on Diagnostic Bench
	workshop.diagnostic_bench._on_interacted(p1)
	err += _assert(workshop.diagnostic_bench.placed_device == dev1, "P1 placed dev1 on DiagnosticBench")

	# P2 places dev2 on Workbench
	workshop.workbench._on_interacted(p2)
	err += _assert(workshop.workbench.placed_device == dev2, "P2 placed dev2 on Workbench")

	# Both stations process simultaneously
	workshop.diagnostic_bench._physics_process(workshop.diagnostic_bench.diagnosis_time + 0.1)
	workshop.workbench._physics_process(workshop.workbench.disassembly_time + 0.1)

	err += _assert(dev1.current_repair_state == RepairState.State.DIAGNOSED, "dev1 diagnosed")
	err += _assert(dev2.current_repair_state == RepairState.State.DISASSEMBLED, "dev2 disassembled")

	# P2 gets replacement part from shelf without blocking P1
	workshop.parts_shelf._on_interacted(p2)
	err += _assert(p2.carry_system.is_carrying(), "P2 got part from shelf")
	var part := p2.carry_system.get_held_item()

	# P2 installs part on workbench
	workshop.workbench._on_interacted(p2)
	err += _assert(dev2.current_repair_state == RepairState.State.PART_REPLACED, "dev2 part replaced")

	# P1 retrieves diagnosed device from bench
	workshop.diagnostic_bench._on_interacted(p1)
	err += _assert(p1.carry_system.get_held_item() == dev1, "P1 retrieved diagnosed device")

	p1.carry_system.drop_item()
	p2.carry_system.drop_item()
	dev1.queue_free()
	dev2.queue_free()
	part.queue_free()
	workshop.queue_free()
	return err



## 8. Test bump mechanic gameplay integration
func test_bump_mechanic_gameplay_integration() -> int:
	print("\n[8] Testing bump mechanic gameplay integration...")
	var err: int = 0

	var p1 := _create_player(0, Vector3(0.0, 0.0, 0.0))
	var p2 := _create_player(1, Vector3(0.6, 0.0, 0.0))

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)

	p2.carry_system.pick_up(dev)
	err += _assert(p2.carry_system.is_carrying(), "P2 is carrying device before bump")

	# High speed collision
	p1._last_motion_speed = 5.0
	p2._last_motion_speed = 3.0
	p1._apply_bump(p2)

	err += _assert(not p2.carry_system.is_carrying(), "P2 dropped device due to bump")
	err += _assert(p2.is_stunned(), "P2 is stunned for 0.3s")
	err += _assert(p1.is_stunned(), "P1 is stunned for 0.15s")
	err += _assert(not dev.is_held, "Dropped device is on floor and claimable")

	# Recover
	p1._end_stun()
	p2._end_stun()
	err += _assert(not p1.is_stunned() and not p2.is_stunned(), "Both players recovered")

	dev.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 9. Test single-player regression (1 player full pipeline unchanged)
func test_single_player_regression() -> int:
	print("\n[9] Testing single-player regression (player_count = 1)...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 1
	workshop.auto_spawn_player = true
	workshop.auto_start_round = true
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 1, "Single player spawned")
	var p1: PlayerCharacter = workshop.get_player(0)
	err += _assert(p1 != null, "P1 exists")

	# Advance device through full repair pipeline
	var ord: Order = workshop.order_manager.get_first_active_order()
	var dev: Device = ord.device_instance
	err += _assert(dev != null, "Order device spawned at reception")

	# Reception -> Diagnostic
	workshop.reception_desk._on_interacted(p1)
	workshop.diagnostic_bench._on_interacted(p1)
	workshop.diagnostic_bench._physics_process(workshop.diagnostic_bench.diagnosis_time + 0.1)
	workshop.diagnostic_bench._on_interacted(p1)

	# Workbench disassemble
	workshop.workbench._on_interacted(p1)
	workshop.workbench._physics_process(workshop.workbench.disassembly_time + 0.1)

	# Parts shelf part
	workshop.parts_shelf._on_interacted(p1)
	workshop.workbench._on_interacted(p1) # install
	workshop.workbench._on_interacted(p1) # reassemble
	workshop.workbench._physics_process(workshop.workbench.reassembly_time + 0.1)
	workshop.workbench._on_interacted(p1) # pickup

	# Software station
	workshop.software_station._on_interacted(p1)
	workshop.software_station._physics_process(workshop.software_station.software_install_time + 0.1)
	workshop.software_station._on_interacted(p1) # pickup

	# Delivery
	workshop.delivery_counter._on_interacted(p1)
	err += _assert(ord.is_completed, "Order completed in single player mode")
	err += _assert(workshop.order_manager.total_score > 0, "Score awarded in single player")
	err += _assert(workshop.order_manager.total_stars == 3, "3 stars awarded")

	workshop.queue_free()
	return err


## 10. Test multi-player debug tools (F10 spawn, F11 cycle, F6 advance, F7 give part)
func test_multiplayer_debug_tools() -> int:
	print("\n[10] Testing multiplayer debug tools (F10, F11, F6, F7)...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.player_count_override = 1
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 1, "Initial player count is 1")

	# F10: Spawn additional player
	var p2: PlayerCharacter = workshop._debug_spawn_additional_player()
	err += _assert(p2 != null, "F10 spawned player 2")
	err += _assert(workshop.active_players.size() == 2, "Active players now 2")
	err += _assert(p2.player_index == 1, "Spawned player has index 1 (P2)")

	# F11: Cycle debug focus to P2
	err += _assert(workshop._debug_focused_player == 0, "Initial debug focus is P1 (0)")
	workshop._cycle_debug_focus()
	err += _assert(workshop._debug_focused_player == 1, "Debug focus cycled to P2 (1)")

	# F7: Give part to focused player (P2)
	workshop._debug_give_part()
	err += _assert(p2.carry_system.is_carrying(), "F7 gave part to focused player (P2)")
	err += _assert(not workshop.get_player(0).carry_system.is_carrying(), "P1 did not receive the part")

	# F6: Advance device held by P2
	var part: Carriable = p2.carry_system.get_held_item()
	p2.carry_system.drop_item()
	part.queue_free()

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)
	p2.carry_system.pick_up(dev)

	workshop._debug_advance_device(RepairState.State.DIAGNOSED)
	err += _assert(dev.is_diagnosed, "F6 advanced device held by focused player P2")

	p2.carry_system.drop_item()
	dev.queue_free()
	workshop.queue_free()
	return err
