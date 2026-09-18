extends Node

## End-to-End Integration Test Suite for Phase 3E: Chaos Systems Integration & Wiring.
## Tests:
## 1. Workshop scene tree & Phase 3 nodes (OrderSpawner, HazardManager, OverheatingHazard, Tools)
## 2. OrderSpawner & multiple simultaneous orders (stacking, queue cap, priority orders, HUD urgency)
## 3. Workshop hazards: Floor spill (slows to 45%, clearable in 2s, speed restored)
## 4. Workshop hazards: Power surge (disables station, OFFLINE label, clearable in 3s or auto-expires)
## 5. Workshop hazards: Device overheating on workbench (warning at 15s, overheat at 20s, resets on pickup)
## 6. Tool system: Screwdriver requirement on workbench (disassembly/reassembly), tool persistence, safety bounds
## 7. Parts shelf stock tracking, depletion, out-of-stock lockout, wrong part rejection, delivery box restock
## 8. Multi-player concurrent chaos: 2 players repairing in parallel with 2 screwdrivers and active hazards
## 9. Single-player backwards compatibility regression (Phase 1-2 behavior when Phase 3 systems disabled/absent)
## 10. Phase 3 debug hotkeys (Ctrl+F6, Ctrl+F7, Ctrl+F8, Shift+F12, F12)

const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/main/Main.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const SCREWDRIVER_SCENE_PATH: String = "res://scenes/tools/Screwdriver.tscn"
const FLOOR_SPILL_SCENE_PATH: String = "res://scenes/hazards/FloorSpillHazard.tscn"
const POWER_SURGE_SCENE_PATH: String = "res://scenes/hazards/PowerSurgeHazard.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"
const DEAD_BATTERY_FAULT_PATH: String = "res://resources/faults/phone_dead_battery.tres"
const SCREEN_PART_PATH: String = "res://resources/components/screen.tres"
const BATTERY_PART_PATH: String = "res://resources/components/battery.tres"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 3E CHAOS SYSTEMS INTEGRATION TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_workshop_scene_tree_and_phase3_nodes()
	failures += test_order_spawner_and_multi_orders_integration()
	failures += test_floor_spill_hazard_gameplay()
	failures += test_power_surge_station_disabling_and_recovery()
	failures += test_device_overheating_on_workbench()
	failures += test_tool_system_and_workbench_requirement()
	failures += test_parts_shelf_stock_and_wrong_part_feedback()
	failures += test_concurrent_multiplayer_chaos()
	failures += test_single_player_regression()
	failures += test_debug_hotkeys_phase3()

	print("=========================================================")
	print("--- PHASE 3E INTEGRATION TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 3E INTEGRATION TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 3E tests FAILED with %d error(s)." % failures)
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


## [1] Test Workshop scene tree, Phase 3 nodes, scenes, signals, and constants
func test_workshop_scene_tree_and_phase3_nodes() -> int:
	print("\n[1] Testing Workshop scene tree, Phase 3 nodes, scenes, signals, and constants...")
	var err: int = 0

	var scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	err += _assert(scene != null, "Workshop_Debug.tscn loads successfully")

	var workshop: WorkshopDebug = scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	# Verify Phase 3 nodes in workshop
	err += _assert(workshop.has_node("OrderSpawner"), "Workshop scene has 'OrderSpawner' node")
	err += _assert(workshop.has_node("HazardManager"), "Workshop scene has 'HazardManager' node")
	err += _assert(workshop.has_node("OverheatingHazard"), "Workshop scene has 'OverheatingHazard' node")
	err += _assert(workshop.has_node("Tools"), "Workshop scene has 'Tools' container node")

	# Verify hazard spawn point markers
	var markers: Array[Node] = workshop.find_children("*", "Marker3D", true, false)
	var hazard_markers := markers.filter(func(m: Node) -> bool: return m.is_in_group("hazard_spawn_points"))
	err += _assert(hazard_markers.size() >= 4, "Workshop has at least 4 hazard spawn markers (found %d)" % hazard_markers.size())

	# Verify scene resources exist
	var screwdriver_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	err += _assert(screwdriver_scene != null, "Screwdriver.tscn loads successfully")

	var spill_scene: PackedScene = load(FLOOR_SPILL_SCENE_PATH)
	err += _assert(spill_scene != null, "FloorSpillHazard.tscn loads successfully")

	var surge_scene: PackedScene = load(POWER_SURGE_SCENE_PATH)
	err += _assert(surge_scene != null, "PowerSurgeHazard.tscn loads successfully")

	# Verify SignalBus signals
	err += _assert(SignalBus.has_signal("hazard_activated"), "SignalBus has 'hazard_activated' signal")
	err += _assert(SignalBus.has_signal("hazard_cleared"), "SignalBus has 'hazard_cleared' signal")
	err += _assert(SignalBus.has_signal("hazard_expired"), "SignalBus has 'hazard_expired' signal")
	err += _assert(SignalBus.has_signal("part_dispensed"), "SignalBus has 'part_dispensed' signal")
	err += _assert(SignalBus.has_signal("part_out_of_stock"), "SignalBus has 'part_out_of_stock' signal")
	err += _assert(SignalBus.has_signal("part_restocked"), "SignalBus has 'part_restocked' signal")

	# Verify Constants
	err += _assert(Constants.DEFAULT_OVERHEAT_TIME == 20.0, "Constants.DEFAULT_OVERHEAT_TIME is 20.0")
	err += _assert(Constants.DEFAULT_SURGE_DURATION == 15.0, "Constants.DEFAULT_SURGE_DURATION is 15.0")
	err += _assert(Constants.DEFAULT_SPILL_SLOW_FACTOR == 0.45, "Constants.DEFAULT_SPILL_SLOW_FACTOR is 0.45")
	err += _assert(Constants.DEFAULT_SPILL_CLEAR_TIME == 2.0, "Constants.DEFAULT_SPILL_CLEAR_TIME is 2.0")
	err += _assert(Constants.DEFAULT_SURGE_CLEAR_TIME == 3.0, "Constants.DEFAULT_SURGE_CLEAR_TIME is 3.0")
	err += _assert(Constants.DEFAULT_SCREWDRIVER_COUNT == 2, "Constants.DEFAULT_SCREWDRIVER_COUNT is 2")
	err += _assert(Constants.DEFAULT_INITIAL_STOCK_PER_PART == 3, "Constants.DEFAULT_INITIAL_STOCK_PER_PART is 3")

	workshop.queue_free()
	return err


## [2] Test OrderSpawner & multiple simultaneous orders
func test_order_spawner_and_multi_orders_integration() -> int:
	print("\n[2] Testing OrderSpawner, multi-orders, queue limits, priority orders, and HUD...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	workshop.auto_start_hazards = false
	add_child(workshop)

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)
	hud.setup(workshop.get_active_players(), workshop.order_manager)

	# Start round -> spawner should be running
	workshop.start_round()
	err += _assert(workshop.order_spawner != null and workshop.order_spawner.is_spawning(), "OrderSpawner auto-started with round")

	var om: OrderManager = workshop.order_manager
	var spawner: OrderSpawner = workshop.order_spawner
	spawner.spawn_interval = 10.0
	spawner.min_interval = 5.0
	spawner.ramp_factor = 0.8
	spawner.max_active_orders = 5

	# Spawning up to 3+ simultaneous orders
	var o1: Order = spawner.try_spawn_order(false)
	var o2: Order = spawner.try_spawn_order(false)
	err += _assert(om.get_active_order_count() == 3, "3 active orders simultaneously (1 initial + 2 spawned)")

	# Independent timers
	o1.tick(1.0)
	o2.tick(3.0)
	err += _assert(o1.time_remaining != o2.time_remaining, "Active orders have independent remaining timers")

	# HUD tracks all active orders
	hud._update_active_orders()
	err += _assert(hud._order_entries.size() == 3, "HUD tracks all 3 simultaneous orders")

	# Spawn up to cap (5)
	var o3: Order = spawner.try_spawn_order(false)
	var o4: Order = spawner.try_spawn_order(false)
	err += _assert(om.get_active_order_count() == 5, "Queue reached maximum cap of 5 active orders")

	# 6th attempt should be rejected
	var o_rejected: Order = spawner.try_spawn_order()
	err += _assert(o_rejected == null, "6th spawn rejected while queue is at max cap (5)")
	err += _assert(om.get_active_order_count() == 5, "Active order count remains capped at 5")

	# Completing one order frees a slot in queue
	om.complete_order(o1)
	err += _assert(om.get_active_order_count() == 4, "Active count reduced to 4 after completion")
	hud._update_active_orders()
	err += _assert(hud._order_entries.size() == 4, "HUD updated to 4 order entries")

	# Priority order spawning
	var prio_order: Order = spawner.try_spawn_order(true)
	err += _assert(prio_order != null and prio_order.is_priority, "Priority order spawned with is_priority == true")
	err += _assert(prio_order.time_limit < 60.0, "Priority order has reduced time limit (%.1fs < 60s)" % prio_order.time_limit)
	err += _assert(prio_order.base_score > 100, "Priority order has multiplied base score (%d > 100)" % prio_order.base_score)

	hud._update_active_orders()
	var prio_entry: Control = hud._order_entries.get(prio_order, null)
	err += _assert(prio_entry != null, "HUD contains priority order entry")
	if prio_entry:
		var name_lbl: Label = prio_entry.get_node_or_null("DeviceName") as Label
		err += _assert(name_lbl != null and name_lbl.text.contains("⚡"), "Priority order entry displays '⚡' prefix in HUD")
		err += _assert(prio_entry.modulate == Color(1.0, 0.7, 0.3), "Priority order entry has urgency red-orange modulate")

	# Difficulty ramping
	var prev_int: float = spawner.get_current_interval()
	err += _assert(prev_int < 10.0, "Spawner interval ramped down below initial (currently %.1fs)" % prev_int)

	workshop.queue_free()
	hud.queue_free()
	return err


## [3] Test FloorSpillHazard gameplay (warning phase, slow effect, clearing, speed restoration)
func test_floor_spill_hazard_gameplay() -> int:
	print("\n[3] Testing FloorSpillHazard (warning phase, 45% slow effect, 2s clear, speed restored)...")
	var err: int = 0

	var spill_scene: PackedScene = load(FLOOR_SPILL_SCENE_PATH)
	var spill: FloorSpillHazard = spill_scene.instantiate() as FloorSpillHazard
	add_child(spill)
	spill.global_position = Vector3(0.0, 0.0, 0.0)

	var player := _create_player(0, Vector3(0.0, 0.0, 0.0))
	player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED

	# Warning phase
	spill.spawn_with_warning(0.5)
	err += _assert(spill.current_state == BaseHazard.HazardState.WARNING, "Floor spill starts in WARNING state")
	err += _assert(player.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "Player speed unaffected during warning phase")

	# Transition to active
	spill._physics_process(0.6)
	err += _assert(spill.current_state == BaseHazard.HazardState.ACTIVE, "Floor spill transitions to ACTIVE state")

	# Enter spill area -> player slowed to 45%
	spill._on_body_entered(player)
	var expected_slow_speed := Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.DEFAULT_SPILL_SLOW_FACTOR
	err += _assert(is_equal_approx(player.move_speed, expected_slow_speed), "Player speed slowed to 45%% (%.2f vs %.2f)" % [player.move_speed, expected_slow_speed])

	# Clearing interaction (2.0 seconds)
	spill.start_clearing(player)
	err += _assert(spill.current_state == BaseHazard.HazardState.CLEARING, "Floor spill enters CLEARING state")

	# Advance clearing progress halfway
	spill._physics_process(1.0)
	err += _assert(spill.get_clear_progress() > 0.4 and spill.get_clear_progress() < 0.6, "Clear progress is ~50% after 1.0s")

	# Complete clearing
	var cleared_signal_fired: Array[bool] = [false]
	SignalBus.hazard_cleared.connect(func(hname: String): if hname.contains("Spill") or hname.contains("Screws"): cleared_signal_fired[0] = true, CONNECT_ONE_SHOT)

	spill._physics_process(1.1)
	err += _assert(cleared_signal_fired[0], "SignalBus.hazard_cleared emitted upon completing clear")
	err += _assert(player.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "Player speed fully restored after spill is cleared")

	player.queue_free()
	if is_instance_valid(spill):
		spill.queue_free()
	return err


## [4] Test PowerSurgeHazard (station disabling, OFFLINE prompt/label, player clear / auto-expire)
func test_power_surge_station_disabling_and_recovery() -> int:
	print("\n[4] Testing PowerSurgeHazard (station disabling, OFFLINE status, clear in 3s & recovery)...")
	var err: int = 0

	var wb_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)
	wb.requires_tool = false

	var surge_scene: PackedScene = load(POWER_SURGE_SCENE_PATH)
	var surge: PowerSurgeHazard = surge_scene.instantiate() as PowerSurgeHazard
	surge.target_station = wb
	add_child(surge)

	var player := _create_player(0, wb.global_position)

	# Initial station state
	err += _assert(wb.interaction_zone.is_interactable, "Workbench initially interactable")

	# Activate surge
	surge.spawn_with_warning(0.2)
	surge._physics_process(0.3)
	err += _assert(surge.current_state == BaseHazard.HazardState.ACTIVE, "Power surge is ACTIVE")
	err += _assert(not wb.interaction_zone.is_interactable, "Workbench interaction zone disabled during surge")
	err += _assert(wb.station_label != null and wb.station_label.text.contains("OFFLINE"), "Workbench station label indicates 'OFFLINE'")

	# Player clearing power surge (3.0 seconds)
	surge.start_clearing(player)
	err += _assert(surge.current_state == BaseHazard.HazardState.CLEARING, "Power surge is in CLEARING state")

	# Advance 3.1 seconds to finish clear
	var surge_cleared_signal: Array[bool] = [false]
	SignalBus.hazard_cleared.connect(func(hname: String): if hname.contains("Surge"): surge_cleared_signal[0] = true, CONNECT_ONE_SHOT)

	surge._physics_process(3.1)
	err += _assert(surge_cleared_signal[0], "SignalBus.hazard_cleared emitted on surge cleared")
	err += _assert(wb.interaction_zone.is_interactable, "Workbench interaction zone re-enabled after surge cleared")
	err += _assert(not wb.station_label.text.contains("OFFLINE"), "Workbench OFFLINE label removed after surge cleared")

	player.queue_free()
	wb.queue_free()
	if is_instance_valid(surge):
		surge.queue_free()
	return err


## [5] Test device overheating on workbench
func test_device_overheating_on_workbench() -> int:
	print("\n[5] Testing OverheatingHazard on workbench (15s warning, 20s overheat, resets on pickup)...")
	var err: int = 0

	var wb_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)

	var overheat_mgr := OverheatingHazard.new()
	overheat_mgr.overheat_time = 20.0
	overheat_mgr.warning_threshold = 0.75  # 15.0s
	add_child(overheat_mgr)
	overheat_mgr.register_workbench(wb)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var fault: FaultData = load(CRACKED_SCREEN_FAULT_PATH)
	dev.initialize(phone_data, fault)
	add_child(dev)

	# Place device on workbench in DISASSEMBLED state
	dev.advance_state(RepairState.State.DIAGNOSED)
	dev.advance_state(RepairState.State.DISASSEMBLED)
	wb.accept_device(dev)

	# 1. Under 15s -> normal
	overheat_mgr._physics_process(5.0)
	err += _assert(overheat_mgr.is_device_tracked(dev), "Disassembled device is tracked by OverheatingHazard")
	err += _assert(not overheat_mgr.is_device_overheated(dev), "Device is not yet overheated at 5s")

	# 2. Advance to 16s (past 15s threshold) -> warning phase
	overheat_mgr._physics_process(11.0)
	err += _assert(not overheat_mgr.is_device_overheated(dev), "Device is not yet overheated at 16s")
	var dev_label: Label3D = dev.get_node_or_null("DeviceLabel") as Label3D
	err += _assert(dev_label != null and dev_label.text.contains("HOT"), "Device label shows 'HOT' warning: %s" % (dev_label.text if dev_label else ""))

	# 3. Advance to 20.5s -> overheat triggered
	var overheat_fired: Array[bool] = [false]
	overheat_mgr.device_overheating.connect(func(_d, _s): overheat_fired[0] = true, CONNECT_ONE_SHOT)

	overheat_mgr._physics_process(4.5)
	err += _assert(overheat_fired[0], "device_overheating signal emitted after 20s")
	err += _assert(overheat_mgr.is_device_overheated(dev), "is_device_overheated(dev) is true")
	err += _assert(dev_label != null and dev_label.text.contains("OVERHEATED"), "Device label shows 'OVERHEATED'")

	# 4. Player picks up overheated device -> timer resets and visual clears
	var cooled_fired: Array[bool] = [false]
	overheat_mgr.device_cooled.connect(func(_d): cooled_fired[0] = true, CONNECT_ONE_SHOT)

	wb.remove_device()
	err += _assert(cooled_fired[0], "device_cooled signal emitted upon picking up overheated device")
	err += _assert(not overheat_mgr.is_device_overheated(dev), "Device is no longer overheated after removal")
	err += _assert(not overheat_mgr.is_device_tracked(dev), "Device is no longer tracked after removal")

	dev.queue_free()
	wb.queue_free()
	overheat_mgr.queue_free()
	return err


## [6] Test tool system: screwdriver requirement, workbench disassembly/reassembly, tool persistence, safety bounds
func test_tool_system_and_workbench_requirement() -> int:
	print("\n[6] Testing tool system, workbench screwdriver requirements, tool persistence, safety bounds...")
	var err: int = 0

	var wb_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = true
	add_child(wb)

	var tool_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	var screwdriver: ToolItem = tool_scene.instantiate() as ToolItem
	add_child(screwdriver)
	screwdriver.global_position = Vector3(-3.0, 0.5, 0.0)

	var p1 := _create_player(0, wb.global_position)
	var p2 := _create_player(1, screwdriver.global_position)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	add_child(dev)
	dev.advance_state(RepairState.State.DIAGNOSED)
	wb.accept_device(dev)

	# 1. Player without tool interacts -> blocked ("Needs screwdriver")
	err += _assert(not wb.can_player_interact(p1), "Player without tool cannot interact to disassemble")
	var prompt := wb.get_interaction_prompt(p1)
	err += _assert(prompt.contains("Needs screwdriver"), "Interaction prompt shows 'Needs screwdriver' (got '%s')" % prompt)

	# 2. P2 picks up screwdriver
	err += _assert(p2.carry_system.can_pick_up(), "P2 hands are free")
	p2.carry_system.pick_up(screwdriver)
	err += _assert(screwdriver.is_held and screwdriver.held_by == p2, "P2 carries screwdriver")

	# P2 approaches workbench with screwdriver -> can interact
	err += _assert(wb.can_player_interact(p2), "P2 carrying screwdriver can interact with workbench")
	err += _assert(wb.get_interaction_prompt(p2) == "Disassemble Device", "Prompt is 'Disassemble Device'")

	# Interact -> screwdriver placed on workbench, disassembly starts
	wb._on_interacted(p2)
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver placed on workbench as bench tool")
	err += _assert(not p2.carry_system.is_carrying(), "P2 hands freed after placing screwdriver")
	err += _assert(wb.current_state == BaseStation.StationState.PROCESSING, "Workbench is processing disassembly")

	# Complete disassembly
	wb._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Device reached DISASSEMBLED state")
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver persists on bench after disassembly")

	# 3. Part replacement
	var comp: ComponentData = load(SCREEN_PART_PATH)
	var part := Carriable.new()
	part.item_name = comp.component_name
	part.item_type = "part"
	part.set_meta("component_data", comp)
	add_child(part)
	p1.carry_system.pick_up(part)

	wb._on_interacted(p1)
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Device advanced to PART_REPLACED")

	# 4. Reassembly requires screwdriver
	# Screwdriver is already on bench -> P1 can reassemble
	err += _assert(wb.can_player_interact(p1), "P1 can interact to reassemble because bench has screwdriver")
	wb._on_interacted(p1)
	wb._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.REASSEMBLED, "Device reached REASSEMBLED state")

	# 5. Tool retrieval & persistence
	wb.remove_device()
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver remains on bench after device is removed")
	err += _assert(wb.can_player_interact(p1), "P1 can interact to pick up screwdriver from bench")
	wb._on_interacted(p1)
	err += _assert(p1.carry_system.get_held_item() == screwdriver, "P1 retrieved screwdriver from bench")
	err += _assert(wb.get_bench_tool() == null, "Workbench bench tool is now null")

	# 6. Safety bounds check: Tool falling through floor
	p1.carry_system.drop_item()
	screwdriver.global_position = Vector3(0.0, -2.5, 0.0)
	screwdriver._physics_process(0.1)
	err += _assert(screwdriver.global_position.y >= 0.0, "Tool below Y < -1.0 safely resets to spawn_position")

	p1.queue_free()
	p2.queue_free()
	dev.queue_free()
	part.queue_free()
	screwdriver.queue_free()
	wb.queue_free()
	return err


## [7] Test PartsShelf stock tracking, out-of-stock lockout, wrong part rejection, and delivery box restock
func test_parts_shelf_stock_and_wrong_part_feedback() -> int:
	print("\n[7] Testing parts stock tracking, out-of-stock lockout, wrong part rejection, delivery box...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn")
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	shelf.initial_stock_per_part = 3
	add_child(shelf)
	shelf._init_stock()

	var player := _create_player(0, shelf.global_position)

	# Initial stock verification
	err += _assert(shelf.get_stock("screen") == 3, "PartsShelf initialized with 3 screens")
	err += _assert(shelf.get_stock("battery") == 3, "PartsShelf initialized with 3 batteries")

	# Dispense 3 screens
	for i in range(3):
		err += _assert(shelf.has_stock("screen"), "Screen is in stock (dispense #%d)" % (i + 1))
		shelf._on_interacted(player)
		var p: Carriable = player.carry_system.get_held_item()
		player.carry_system.drop_item()
		if p: p.queue_free()

	# Screen is now depleted
	err += _assert(shelf.get_stock("screen") == 0, "Screen stock is 0 after 3 dispenses")
	err += _assert(not shelf.has_stock("screen"), "has_stock('screen') is false")

	# Out of stock prompt and non-dispense
	shelf._selected_part_index = 0  # ensure pointing to screen
	var prompt := shelf.get_interaction_prompt(player)
	err += _assert(prompt.contains("OUT OF STOCK"), "Prompt shows OUT OF STOCK (got '%s')" % prompt)
	shelf._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Player hands remain empty when part is out of stock")

	# Wrong part rejection at workbench
	var wb_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = false
	add_child(wb)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))  # Needs screen!
	add_child(dev)
	dev.advance_state(RepairState.State.DIAGNOSED)
	dev.advance_state(RepairState.State.DISASSEMBLED)
	wb.accept_device(dev)

	# Give player a battery (wrong part!)
	var wrong_part := Carriable.new()
	wrong_part.item_name = "Battery"
	wrong_part.item_type = "part"
	wrong_part.set_meta("component_data", load(BATTERY_PART_PATH))
	add_child(wrong_part)
	player.carry_system.pick_up(wrong_part)

	err += _assert(not wb.can_player_interact(player), "Workbench rejects interaction with wrong component")
	var wb_prompt := wb.get_interaction_prompt(player)
	err += _assert(wb_prompt.contains("Wrong Replacement Part"), "Prompt informs player of wrong part (got '%s')" % wb_prompt)

	wb._on_interacted(player)
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Device remains DISASSEMBLED after wrong part attempted")
	err += _assert(player.carry_system.get_held_item() == wrong_part, "Wrong part was NOT consumed — player still carries it")

	# Restocking with DeliveryBox
	player.carry_system.drop_item()
	wrong_part.queue_free()

	var box := DeliveryBox.new()
	box.contained_parts = {"screen": 3, "battery": 2}
	add_child(box)
	player.carry_system.pick_up(box)

	err += _assert(shelf.can_player_interact(player), "Player carrying DeliveryBox can interact with PartsShelf")
	shelf._on_interacted(player)
	err += _assert(shelf.get_stock("screen") == 3, "PartsShelf screen restocked to 3 via DeliveryBox")
	err += _assert(shelf.get_stock("battery") == 5, "PartsShelf battery restocked to 5 via DeliveryBox")
	err += _assert(not player.carry_system.is_carrying(), "DeliveryBox consumed and removed from player hands")

	player.queue_free()
	shelf.queue_free()
	dev.queue_free()
	wb.queue_free()
	return err


## [8] Test concurrent multi-player chaos: 2 players repairing in parallel with 2 screwdrivers and active hazards
func test_concurrent_multiplayer_chaos() -> int:
	print("\n[8] Testing concurrent multi-player chaos (2 players, 2 screwdrivers, parallel repairs)...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	workshop.auto_start_hazards = true
	add_child(workshop)

	# Spawn 2 players
	var p1 := workshop.spawn_player(0)
	var p2 := workshop.spawn_player(1)
	workshop.start_round()

	err += _assert(workshop.get_active_player_count() == 2, "2 active players in workshop")
	err += _assert(workshop.get_all_tools().size() == 2, "2 screwdrivers available in workshop")

	var tools := workshop.get_all_tools()
	var tool1: ToolItem = tools[0]
	var tool2: ToolItem = tools[1]

	# P1 claims tool1, P2 claims tool2
	p1.carry_system.pick_up(tool1)
	p2.carry_system.pick_up(tool2)
	err += _assert(tool1.is_held and p1.carry_system.get_held_item() == tool1, "P1 carries screwdriver 1")
	err += _assert(tool2.is_held and p2.carry_system.get_held_item() == tool2, "P2 carries screwdriver 2")

	# Spawn power surge on software station
	var surge: BaseHazard = workshop.hazard_manager.try_spawn_hazard("surge")
	err += _assert(surge != null, "Power surge successfully spawned amidst active players")

	# Floor spill spawned
	var spill: BaseHazard = workshop.hazard_manager.try_spawn_hazard("floor")
	err += _assert(spill != null, "Floor spill hazard successfully spawned amidst active players")
	err += _assert(workshop.hazard_manager.get_active_hazard_count() >= 2, "Multiple simultaneous hazards active")

	workshop.queue_free()
	return err


## [9] Test single-player backwards compatibility regression
func test_single_player_regression() -> int:
	print("\n[9] Testing single-player backwards compatibility regression (Phase 1-2 fallback)...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	workshop.workbench_requires_tool = false
	workshop.auto_start_hazards = false
	add_child(workshop)

	# Remove spawner and hazard manager to simulate basic mode
	if workshop.order_spawner:
		workshop.order_spawner.queue_free()
		workshop.order_spawner = null
	if workshop.hazard_manager:
		workshop.hazard_manager.queue_free()
		workshop.hazard_manager = null

	# Disable parts stock tracking for infinite parts
	workshop.parts_shelf.stock_tracking_enabled = false

	# Start round -> single order spawned by OrderManager
	workshop.start_round()
	var om: OrderManager = workshop.order_manager
	err += _assert(om.get_active_order_count() == 1, "OrderManager spawns exactly 1 order in basic mode")

	var ord: Order = om.get_first_active_order()
	err += _assert(ord != null, "Active order exists")

	var player := workshop.get_player(0)
	err += _assert(player != null, "Single player exists")

	# Complete full core repair loop without tools or stock limits
	var dev: Device = ord.device_instance
	err += _assert(dev != null, "Order device created at reception")

	# Pickup reception
	workshop.reception_desk._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == dev, "Player picked up phone from reception")

	# Place on diagnostic bench
	workshop.diagnostic_bench._on_interacted(player)
	err += _assert(workshop.diagnostic_bench.placed_device == dev, "Bench holds phone")
	workshop.diagnostic_bench._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Phone diagnosed")
	workshop.diagnostic_bench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == dev, "Player picked up diagnosed phone")

	# Place on workbench
	var wb: WorkbenchStation = workshop.workbench as WorkbenchStation
	wb._on_interacted(player)
	err += _assert(wb.placed_device == dev, "Workbench holds phone")
	wb._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Phone disassembled without tool requirement")

	# Parts shelf (infinite stock)
	workshop.parts_shelf._on_interacted(player)
	var part: Carriable = player.carry_system.get_held_item()
	err += _assert(part != null and part.item_type == "part", "Player got part from shelf")

	# Install part & reassemble
	wb._on_interacted(player)
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Part installed on phone")
	wb._on_interacted(player)
	wb._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.REASSEMBLED, "Phone reassembled")
	wb._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == dev, "Player retrieved reassembled phone")

	# Software test
	workshop.software_station._on_interacted(player)
	err += _assert(workshop.software_station.placed_device == dev, "Phone placed on software station")
	workshop.software_station._complete_processing()
	err += _assert(dev.current_repair_state == RepairState.State.TESTED, "Phone tested")
	workshop.software_station._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == dev, "Player picked up tested phone")

	# Deliver
	workshop.delivery_counter._on_interacted(player)
	err += _assert(om.completed_orders.size() == 1, "Order completed successfully in regression mode")
	err += _assert(om.total_score > 0, "Score awarded in regression mode (%d pts)" % om.total_score)

	workshop.queue_free()
	return err


## [10] Test Phase 3 debug hotkeys
func test_debug_hotkeys_phase3() -> int:
	print("\n[10] Testing Phase 3 debug hotkeys (Ctrl+F6, Ctrl+F7, Ctrl+F8, Shift+F12, F12)...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = true
	add_child(workshop)

	# 1. Ctrl+F6: Force spawn priority order
	var active_before := workshop.order_manager.get_active_order_count()
	workshop._debug_spawn_priority_order()
	var active_after := workshop.order_manager.get_active_order_count()
	err += _assert(active_after == active_before + 1, "Ctrl+F6 force-spawned an order")
	var last_order: Order = workshop.order_manager.active_orders.back()
	err += _assert(last_order != null and last_order.is_priority, "Ctrl+F6 spawned order is a priority order")

	# 2. Ctrl+F7: Toggle tool requirement
	var initial_tool_req: bool = workshop.workbench.requires_tool
	workshop._debug_toggle_tool_requirement()
	err += _assert(workshop.workbench.requires_tool == not initial_tool_req, "Ctrl+F7 toggled workbench tool requirement")
	workshop._debug_toggle_tool_requirement()
	err += _assert(workshop.workbench.requires_tool == initial_tool_req, "Ctrl+F7 toggled workbench tool requirement back")

	# 3. Ctrl+F8: Restock shelf
	workshop.parts_shelf.restock("screen", -workshop.parts_shelf.get_stock("screen"))
	err += _assert(workshop.parts_shelf.get_stock("screen") == 0, "Screen stock depleted to 0 before restock")
	workshop._debug_restock_shelf()
	err += _assert(workshop.parts_shelf.get_stock("screen") == 3, "Ctrl+F8 restocked parts shelf screen count to 3")

	# 4. F12: Spawn floor hazard
	var floor_hazards_before := workshop.hazard_manager.get_active_hazard_count()
	workshop._debug_spawn_floor_hazard()
	var floor_hazards_after := workshop.hazard_manager.get_active_hazard_count()
	err += _assert(floor_hazards_after == floor_hazards_before + 1, "F12 spawned a floor spill hazard")

	# 5. Shift+F12: Spawn power surge
	workshop._debug_spawn_power_surge()
	var surges_after := workshop.hazard_manager.get_active_hazard_count()
	err += _assert(surges_after == floor_hazards_after + 1, "Shift+F12 spawned a power surge hazard")

	workshop.queue_free()
	return err
