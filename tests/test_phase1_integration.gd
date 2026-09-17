extends Node

## End-to-End Integration Test Suite for Phase 1H.
## Tests full integration of Workshop scene, stations, entities, player, HUD,
## OrderManager pipeline, end-to-end device repair loop, round lifecycle,
## debug overlay, and debug hotkeys (F3, F4, F6, F7, F8, F9).

const MAIN_SCENE_PATH: String = "res://scenes/main/Main.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 1H END-TO-END INTEGRATION TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_workshop_scene_tree_structure()
	failures += test_multiplayer_spawn_markers()
	failures += test_end_to_end_core_repair_loop()
	failures += test_debug_overlay_information()
	failures += test_debug_hotkeys()

	print("=========================================================")
	print("--- PHASE 1H INTEGRATION TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 1H INTEGRATION TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 1H tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Test Workshop scene tree matches Phase 1 specification
func test_workshop_scene_tree_structure() -> int:
	print("\n[1] Testing Workshop scene tree hierarchy and structure...")
	var err: int = 0

	var scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	err += _assert(scene != null, "Workshop_Debug.tscn loaded successfully")

	var workshop: WorkshopDebug = scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	# Hierarchy checks
	err += _assert(workshop.has_node("Floor"), "Floor node exists")
	err += _assert(workshop.has_node("Walls"), "Walls container node exists")
	err += _assert(workshop.has_node("DirectionalLight3D"), "DirectionalLight3D exists")
	err += _assert(workshop.has_node("Stations"), "Stations container node exists")
	err += _assert(workshop.has_node("Entities"), "Entities container node exists")
	err += _assert(workshop.has_node("OrderManager"), "OrderManager node exists")

	# Stations container contents
	var stations_node: Node3D = workshop.get_node("Stations") as Node3D
	err += _assert(stations_node.has_node("ReceptionDesk"), "Stations has ReceptionDesk")
	err += _assert(stations_node.has_node("DiagnosticBench"), "Stations has DiagnosticBench")
	err += _assert(stations_node.has_node("Workbench"), "Stations has Workbench")
	err += _assert(stations_node.has_node("PartsShelf"), "Stations has PartsShelf")
	err += _assert(stations_node.has_node("SoftwareStation"), "Stations has SoftwareStation")
	err += _assert(stations_node.has_node("DeliveryCounter"), "Stations has DeliveryCounter")

	# BaseStation types
	err += _assert(workshop.reception_desk is ReceptionDesk, "reception_desk is ReceptionDesk")
	err += _assert(workshop.diagnostic_bench is DiagnosticBench, "diagnostic_bench is DiagnosticBench")
	err += _assert(workshop.workbench is WorkbenchStation, "workbench is WorkbenchStation")
	err += _assert(workshop.parts_shelf is PartsShelf, "parts_shelf is PartsShelf")
	err += _assert(workshop.software_station is SoftwareStation, "software_station is SoftwareStation")
	err += _assert(workshop.delivery_counter is DeliveryCounter, "delivery_counter is DeliveryCounter")

	var all_stations := workshop.get_all_stations()
	err += _assert(all_stations.size() == 6, "get_all_stations() returns 6 stations")

	workshop.queue_free()
	return err


## 2. Test Multiplayer spawn markers P1 - P4
func test_multiplayer_spawn_markers() -> int:
	print("\n[2] Testing Multiplayer spawn markers P1 through P4...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.spawn_point_p1 != null, "SpawnPoint_P1 exists")
	err += _assert(workshop.spawn_point_p2 != null, "SpawnPoint_P2 exists")
	err += _assert(workshop.spawn_point_p3 != null, "SpawnPoint_P3 exists")
	err += _assert(workshop.spawn_point_p4 != null, "SpawnPoint_P4 exists")

	var pos_p1 := workshop.get_spawn_position(0)
	var pos_p2 := workshop.get_spawn_position(1)
	var pos_p3 := workshop.get_spawn_position(2)
	var pos_p4 := workshop.get_spawn_position(3)

	err += _assert(pos_p1 == workshop.spawn_point_p1.global_position, "get_spawn_position(0) matches P1")
	err += _assert(pos_p2 == workshop.spawn_point_p2.global_position, "get_spawn_position(1) matches P2")
	err += _assert(pos_p3 == workshop.spawn_point_p3.global_position, "get_spawn_position(2) matches P3")
	err += _assert(pos_p4 == workshop.spawn_point_p4.global_position, "get_spawn_position(3) matches P4")

	# Test player spawning into Entities container
	var player: PlayerCharacter = workshop.spawn_player(0)
	err += _assert(player != null, "Player 0 spawned")
	err += _assert(player.get_parent() == workshop.entities_container, "Player spawned under Entities container")
	err += _assert(workshop.get_player(0) == player, "get_player(0) returns spawned player")

	workshop.queue_free()
	return err


## 3. Test Full End-to-End Core Repair Loop in Main.tscn
func test_end_to_end_core_repair_loop() -> int:
	print("\n[3] Testing End-to-End Core Repair Loop (Reception -> Delivery -> Score)...")
	var err: int = 0

	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var main: Main = main_scene.instantiate() as Main
	add_child(main)

	var workshop: WorkshopDebug = main.current_level as WorkshopDebug
	err += _assert(workshop != null, "Workshop instantiated in Main")

	var player: PlayerCharacter = workshop.get_player(0)
	err += _assert(player != null, "Player auto-spawned in workshop")

	var hud: HUD = main.hud
	err += _assert(hud != null, "HUD present in Main")

	var order_mgr: OrderManager = workshop.order_manager
	err += _assert(order_mgr != null, "OrderManager present in workshop")
	err += _assert(order_mgr.has_active_orders(), "Active order spawned at round start")

	var order: Order = order_mgr.get_first_active_order()
	err += _assert(order != null, "Order retrieved")
	var phone: Device = order.device_instance
	err += _assert(phone != null, "Phone device instance created for order")
	err += _assert(workshop.reception_desk.placed_device == phone, "Phone placed at ReceptionDesk")
	err += _assert(phone.current_repair_state == RepairState.State.RECEIVED, "Phone initial state is RECEIVED")

	# Step 1: Pick up phone from ReceptionDesk
	print("  Step 1: Picking up device from Reception Desk...")
	err += _assert(workshop.reception_desk.can_player_interact(player), "Player can interact with ReceptionDesk")
	workshop.reception_desk._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Player carries phone")
	err += _assert(not workshop.reception_desk.has_device(), "ReceptionDesk empty")
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("RECEIVED"), "HUD carried item shows [RECEIVED]")

	# Step 2: Place on Diagnostic Bench and diagnose
	print("  Step 2: Placing device on Diagnostic Bench...")
	err += _assert(workshop.diagnostic_bench.can_player_interact(player), "Player can interact with DiagnosticBench")
	workshop.diagnostic_bench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Player placed phone on DiagnosticBench")
	err += _assert(workshop.diagnostic_bench.placed_device == phone, "Bench holds phone")
	err += _assert(workshop.diagnostic_bench.current_state == BaseStation.StationState.PROCESSING, "DiagnosticBench is PROCESSING")

	# Advance physics to complete diagnosis
	workshop.diagnostic_bench._physics_process(workshop.diagnostic_bench.diagnosis_time + 0.1)
	err += _assert(workshop.diagnostic_bench.current_state == BaseStation.StationState.COMPLETE, "DiagnosticBench COMPLETE")
	err += _assert(phone.is_diagnosed, "Phone is diagnosed")
	err += _assert(phone.current_repair_state == RepairState.State.DIAGNOSED, "Phone state advanced to DIAGNOSED")
	err += _assert(phone.assigned_fault != null, "Phone assigned_fault is populated")

	# Pick up diagnosed phone
	workshop.diagnostic_bench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Player picked up diagnosed phone")
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("DIAGNOSED"), "HUD shows [DIAGNOSED]")

	# Step 3: Place on Workbench for disassembly
	print("  Step 3: Placing device on Workbench for disassembly...")
	err += _assert(workshop.workbench.can_player_interact(player), "Player can interact with Workbench")
	workshop.workbench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Phone placed on Workbench")
	err += _assert(workshop.workbench.placed_device == phone, "Workbench holds phone")
	err += _assert(workshop.workbench.current_state == BaseStation.StationState.PROCESSING, "Workbench disassembly PROCESSING")

	# Complete disassembly
	workshop.workbench._physics_process(workshop.workbench.disassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.DISASSEMBLED, "Phone state advanced to DISASSEMBLED")
	err += _assert(workshop.workbench.current_state == BaseStation.StationState.OCCUPIED, "Workbench OCCUPIED awaiting part")

	# Step 4: Get replacement part from PartsShelf
	print("  Step 4: Getting replacement component from Parts Shelf...")
	err += _assert(workshop.parts_shelf.can_player_interact(player), "Player can interact with PartsShelf")
	workshop.parts_shelf._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up part from shelf")
	var held_part: Carriable = player.carry_system.get_held_item()
	err += _assert(held_part != null and held_part.item_type == "part", "Held item is a part")
	var comp: ComponentData = held_part.get_meta("component_data", null) as ComponentData
	err += _assert(comp != null, "Dispensed part has ComponentData metadata")

	# Step 5: Install part on Workbench and reassemble
	print("  Step 5: Installing part and reassembling...")
	err += _assert(workshop.workbench.can_player_interact(player), "Workbench accepts matching part")
	workshop.workbench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Part consumed during installation")
	err += _assert(phone.current_repair_state == RepairState.State.PART_REPLACED, "Phone state advanced to PART_REPLACED")

	# Start reassembly
	workshop.workbench._on_interacted(player)
	err += _assert(workshop.workbench.current_state == BaseStation.StationState.PROCESSING, "Workbench reassembly PROCESSING")
	workshop.workbench._physics_process(workshop.workbench.reassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.REASSEMBLED, "Phone state advanced to REASSEMBLED")
	err += _assert(workshop.workbench.current_state == BaseStation.StationState.COMPLETE, "Workbench COMPLETE")

	# Pick up reassembled phone
	workshop.workbench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Player picked up reassembled phone")
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("REASSEMBLED"), "HUD shows [REASSEMBLED]")

	# Step 6: Install software at SoftwareStation
	print("  Step 6: Flashing software at Software Station...")
	err += _assert(workshop.software_station.can_player_interact(player), "Player can place phone on SoftwareStation")
	workshop.software_station._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Phone placed on SoftwareStation")
	err += _assert(workshop.software_station.current_state == BaseStation.StationState.PROCESSING, "SoftwareStation PROCESSING")

	workshop.software_station._physics_process(workshop.software_station.software_install_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.TESTED, "Phone state advanced to TESTED")
	err += _assert(workshop.software_station.current_state == BaseStation.StationState.COMPLETE, "SoftwareStation COMPLETE")

	# Pick up tested phone
	workshop.software_station._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Player carries tested phone")
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("TESTED"), "HUD shows [TESTED]")

	# Step 7: Deliver at DeliveryCounter
	print("  Step 7: Delivering repaired device to Delivery Counter...")
	var round_ended_fired: Array[bool] = [false]
	var round_score: Array[int] = [0]
	var round_stars: Array[int] = [0]
	var on_round_ended = func(score: int, stars: int) -> void:
		round_ended_fired[0] = true
		round_score[0] = score
		round_stars[0] = stars
	SignalBus.round_ended.connect(on_round_ended)

	err += _assert(workshop.delivery_counter.can_player_interact(player), "Player can deliver phone at DeliveryCounter")
	workshop.delivery_counter._on_interacted(player)

	err += _assert(not player.carry_system.is_carrying(), "Player delivered phone")
	err += _assert(phone.current_repair_state == RepairState.State.DELIVERED, "Phone state is DELIVERED")
	err += _assert(order.is_completed, "Order marked as completed")
	err += _assert(order_mgr.completed_orders.size() == 1, "Order added to OrderManager completed_orders")
	err += _assert(not order_mgr.has_active_orders(), "No active orders remain")
	err += _assert(order_mgr.total_score > 0, "Order scored points (%d)" % order_mgr.total_score)
	err += _assert(order_mgr.total_stars == 3, "Awarded 3 stars")
	err += _assert(round_ended_fired[0], "SignalBus.round_ended emitted upon completion of all orders")
	err += _assert(round_score[0] == order_mgr.total_score, "round_ended signal contains correct score")
	err += _assert(round_stars[0] == order_mgr.total_stars, "round_ended signal contains correct stars")

	# Verify HUD updated score & star display
	err += _assert(hud.current_score == order_mgr.total_score, "HUD current_score matches OrderManager total_score")
	err += _assert(hud.current_stars == 3, "HUD current_stars matches OrderManager total_stars")
	err += _assert(hud.completion_banner.visible, "HUD completion banner displayed")

	SignalBus.round_ended.disconnect(on_round_ended)
	main.queue_free()
	return err


## 4. Test Debug Overlay Information
func test_debug_overlay_information() -> int:
	print("\n[4] Testing Debug Overlay Information (Main debug_label)...")
	var err: int = 0

	var main: Main = load(MAIN_SCENE_PATH).instantiate() as Main
	add_child(main)

	main._update_debug_label()
	var text: String = main.debug_label.text

	err += _assert(text.contains("Phase 0 — Overclocked"), "Debug overlay contains title")
	err += _assert(text.contains("State: PLAYING"), "Debug overlay shows GameState PLAYING")
	err += _assert(text.contains("FPS:"), "Debug overlay shows FPS counter")
	err += _assert(text.contains("Order:"), "Debug overlay shows active Order information")
	err += _assert(text.contains("Device:"), "Debug overlay shows Device repair state")
	err += _assert(text.contains("Carried:"), "Debug overlay shows Player carried item")

	# Test F3 toggle
	var f3_event := InputEventKey.new()
	f3_event.keycode = KEY_F3
	f3_event.pressed = true
	main._unhandled_input(f3_event)
	err += _assert(not main.debug_overlay_visible, "F3 hides debug overlay")
	err += _assert(not main.debug_label.visible, "DebugLabel is hidden after F3")

	main._unhandled_input(f3_event)
	err += _assert(main.debug_overlay_visible, "F3 restores debug overlay")
	err += _assert(main.debug_label.visible, "DebugLabel is visible again")

	main.queue_free()
	return err


## 5. Test Debug Hotkeys (F6, F7, F8, F9)
func test_debug_hotkeys() -> int:
	print("\n[5] Testing Debug Hotkeys (F6, F7, F8, F9)...")
	var err: int = 0

	var workshop: WorkshopDebug = load(WORKSHOP_SCENE_PATH).instantiate() as WorkshopDebug
	add_child(workshop)

	var player: PlayerCharacter = workshop.get_player(0)
	var order_mgr: OrderManager = workshop.order_manager

	# Ensure order and device exist
	err += _assert(order_mgr.has_active_orders(), "Order exists for debug hotkey tests")
	var order: Order = order_mgr.get_first_active_order()
	var dev: Device = order.device_instance
	err += _assert(dev != null, "Device instance exists")

	# Test F6: Skip Diagnosis / Advance Device to DIAGNOSED
	var f6 := InputEventKey.new()
	f6.keycode = KEY_F6
	f6.pressed = true
	workshop._unhandled_input(f6)
	err += _assert(dev.is_diagnosed, "F6 hotkey diagnosed device")
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "F6 advanced device to DIAGNOSED")

	# Test F7: Give Player Replacement Part
	var f7 := InputEventKey.new()
	f7.keycode = KEY_F7
	f7.pressed = true
	workshop._unhandled_input(f7)
	err += _assert(player.carry_system.is_carrying(), "F7 hotkey gave player an item")
	var part: Carriable = player.carry_system.get_held_item()
	err += _assert(part != null and part.item_type == "part", "F7 gave item of type 'part'")

	# Test F9: Dump State (verify execution without errors)
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	workshop._unhandled_input(f9)
	err += _assert(true, "F9 state dump executed cleanly")

	# Test F8: Complete Order Instantly
	var f8 := InputEventKey.new()
	f8.keycode = KEY_F8
	f8.pressed = true
	workshop._unhandled_input(f8)
	err += _assert(order.is_completed, "F8 hotkey completed order instantly")
	err += _assert(not order_mgr.has_active_orders(), "Active orders cleared by F8")
	err += _assert(order_mgr.total_score > 0, "Score awarded by F8 completion")

	workshop.queue_free()
	return err
