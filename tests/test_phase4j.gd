extends Node

## Test suite for Phase 4J — Integration & Full Pipeline Testing
## Validates resource schema validity, parts shelf coverage, solo walkthroughs for all 6 devices,
## multi-fault end-to-end, skip-state router firmware, two-player Desktop PC carry,
## phone regression, 4-player session, stock depletion, signals, constants, and debug hotkeys.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4J INTEGRATION & VERIFICATION SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_all_device_and_fault_resources_valid()
	failures += test_parts_shelf_stocks_all_fault_components()
	failures += test_phase4_constants_and_signals()
	failures += test_phone_regression()
	failures += test_solo_walkthrough_all_device_types()
	failures += test_multi_fault_end_to_end()
	failures += test_skip_state_router_firmware_end_to_end()
	failures += test_two_player_carry_desktop_pc()
	failures += test_parts_shelf_stock_depletion_flow()
	failures += test_workshop_debug_hotkeys_and_tier_toggle()
	failures += test_multiplayer_session_simulation()

	print("=========================================================")
	print("--- PHASE 4J TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4J TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4J tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


## 1. Test is_valid() on all 6 DeviceData and their FaultData resources
func test_all_device_and_fault_resources_valid() -> int:
	print("\n[1] Testing is_valid() across all DeviceData and FaultData resources...")
	var err: int = 0

	var device_paths := [
		"res://resources/devices/phone.tres",
		"res://resources/devices/tablet.tres",
		"res://resources/devices/laptop.tres",
		"res://resources/devices/game_console.tres",
		"res://resources/devices/router.tres",
		"res://resources/devices/desktop_pc.tres",
	]

	for path in device_paths:
		var dev: DeviceData = load(path) as DeviceData
		err += _assert(dev != null, "Loaded %s" % path)
		if dev:
			err += _assert(dev.is_valid(), "%s is_valid() == true" % dev.device_name)
			err += _assert(not dev.possible_faults.is_empty(), "%s has possible_faults" % dev.device_name)
			for fault in dev.possible_faults:
				err += _assert(fault != null and fault.is_valid(),
					"%s -> fault '%s' is_valid() == true" % [dev.device_name, fault.fault_name if fault else "null"])

	return err


## 2. Test that PartsShelf stocks all components required by every fault in every device
func test_parts_shelf_stocks_all_fault_components() -> int:
	print("\n[2] Testing PartsShelf component coverage...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn") as PackedScene
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	add_child(shelf)

	var stocked_ids: Array[String] = []
	for comp: ComponentData in shelf.available_parts:
		if comp:
			stocked_ids.append(comp.component_id)

	err += _assert(stocked_ids.size() >= 20, "PartsShelf stocks >= 20 components (got %d)" % stocked_ids.size())

	var device_paths := [
		"res://resources/devices/phone.tres",
		"res://resources/devices/tablet.tres",
		"res://resources/devices/laptop.tres",
		"res://resources/devices/game_console.tres",
		"res://resources/devices/router.tres",
		"res://resources/devices/desktop_pc.tres",
	]

	for path in device_paths:
		var dev: DeviceData = load(path) as DeviceData
		if not dev:
			continue
		for fault: FaultData in dev.possible_faults:
			if not fault:
				continue
			var req: Array[ComponentData] = fault.get_required_components()
			for comp in req:
				if comp:
					var is_stocked: bool = comp.component_id in stocked_ids
					err += _assert(is_stocked, "Fault '%s' part '%s' (%s) is stocked on shelf" % [fault.fault_id, comp.component_name, comp.component_id])

	shelf.queue_free()
	return err


## 3. Test Phase 4 constants and signals existence
func test_phase4_constants_and_signals() -> int:
	print("\n[3] Testing Phase 4 constants and SignalBus signals...")
	var err: int = 0

	# Constants
	err += _assert(Constants.TIER_1_REPAIR_TIME_BASE == 60.0, "TIER_1_REPAIR_TIME_BASE == 60.0")
	err += _assert(Constants.TIER_2_REPAIR_TIME_BASE == 100.0, "TIER_2_REPAIR_TIME_BASE == 100.0")
	err += _assert(Constants.TIER_3_REPAIR_TIME_BASE == 180.0, "TIER_3_REPAIR_TIME_BASE == 180.0")
	err += _assert(Constants.TWO_PLAYER_CARRY_REQUEST_TIMEOUT == 3.0, "TWO_PLAYER_CARRY_REQUEST_TIMEOUT == 3.0")
	err += _assert(Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER == 0.6, "TWO_PLAYER_CARRY_SPEED_MULTIPLIER == 0.6")
	err += _assert(Constants.ONE_PLAYER_HEAVY_CARRY_SPEED == 0.4, "ONE_PLAYER_HEAVY_CARRY_SPEED == 0.4")
	err += _assert(Constants.TWO_PLAYER_CARRY_DISTANCE == 1.5, "TWO_PLAYER_CARRY_DISTANCE == 1.5")
	err += _assert(Constants.DEVICE_COLOR_PHONE != null, "DEVICE_COLOR_PHONE exists")
	err += _assert(Constants.DEVICE_COLOR_TABLET != null, "DEVICE_COLOR_TABLET exists")
	err += _assert(Constants.DEVICE_COLOR_LAPTOP != null, "DEVICE_COLOR_LAPTOP exists")
	err += _assert(Constants.DEVICE_COLOR_DESKTOP != null, "DEVICE_COLOR_DESKTOP exists")
	err += _assert(Constants.DEVICE_COLOR_CONSOLE != null, "DEVICE_COLOR_CONSOLE exists")
	err += _assert(Constants.DEVICE_COLOR_ROUTER != null, "DEVICE_COLOR_ROUTER exists")

	# Signals
	err += _assert(SignalBus.has_signal("multi_fault_detected"), "SignalBus has multi_fault_detected")
	err += _assert(SignalBus.has_signal("multi_fault_component_installed"), "SignalBus has multi_fault_component_installed")
	err += _assert(SignalBus.has_signal("multi_fault_complete"), "SignalBus has multi_fault_complete")
	err += _assert(SignalBus.has_signal("device_carry_requested"), "SignalBus has device_carry_requested")
	err += _assert(SignalBus.has_signal("device_carry_started"), "SignalBus has device_carry_started")
	err += _assert(SignalBus.has_signal("device_tier_unlocked"), "SignalBus has device_tier_unlocked")

	return err


## 4. Test Phone regression: Phase 1-3 behavior unchanged
func test_phone_regression() -> int:
	print("\n[4] Testing Phone regression (Phase 1-3 baseline)...")
	var err: int = 0

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	var fault: FaultData = phone_data.get_fault_by_id("phone_cracked_screen")
	err += _assert(phone_data != null and fault != null, "Loaded phone and cracked screen fault")

	var phone_scene: PackedScene = load("res://scenes/devices/Phone.tscn") as PackedScene
	var dev: Device = phone_scene.instantiate() as Device
	dev.initialize(phone_data, fault)
	add_child(dev)

	err += _assert(dev.current_repair_state == RepairState.State.RECEIVED, "Phone initial state is RECEIVED")
	dev.diagnose()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Phone goes to DIAGNOSED")
	dev.advance_state(RepairState.State.DISASSEMBLED)
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Phone goes to DISASSEMBLED")

	var screen_part: ComponentData = load("res://resources/components/screen.tres") as ComponentData
	var accepted: bool = dev.try_install_component(screen_part)
	err += _assert(accepted, "Phone accepted screen replacement")
	var installed: bool = dev.install_part()
	err += _assert(installed, "Phone install_part advances to PART_REPLACED")
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Phone in PART_REPLACED")

	dev.advance_state(RepairState.State.REASSEMBLED)
	dev.advance_state(RepairState.State.SOFTWARE_INSTALLED)
	dev.advance_state(RepairState.State.TESTED)
	dev.advance_state(RepairState.State.DELIVERED)
	err += _assert(dev.current_repair_state == RepairState.State.DELIVERED, "Phone reached DELIVERED")

	dev.queue_free()
	return err


## 5. Test full solo walkthrough for every device type
func test_solo_walkthrough_all_device_types() -> int:
	print("\n[5] Testing full solo walkthrough for all 6 devices...")
	var err: int = 0

	var device_configs := [
		{"data": "res://resources/devices/phone.tres", "scene": "res://scenes/devices/Phone.tscn"},
		{"data": "res://resources/devices/tablet.tres", "scene": "res://scenes/devices/Tablet.tscn"},
		{"data": "res://resources/devices/laptop.tres", "scene": "res://scenes/devices/Laptop.tscn"},
		{"data": "res://resources/devices/game_console.tres", "scene": "res://scenes/devices/GameConsole.tscn"},
		{"data": "res://resources/devices/router.tres", "scene": "res://scenes/devices/Router.tscn"},
		{"data": "res://resources/devices/desktop_pc.tres", "scene": "res://scenes/devices/DesktopPC.tscn"},
	]

	for cfg in device_configs:
		var data: DeviceData = load(cfg["data"]) as DeviceData
		var scene: PackedScene = load(cfg["scene"]) as PackedScene
		var dev: Device = scene.instantiate() as Device
		var fault: FaultData = data.possible_faults[0]
		dev.initialize(data, fault)
		add_child(dev)

		# 1. Diagnose
		dev.diagnose()
		err += _assert(dev.is_diagnosed, "%s diagnosed" % data.device_name)

		# 2. Advance to disassembly
		if not ("DISASSEMBLED" in fault.skip_states):
			dev.advance_state(RepairState.State.DISASSEMBLED)
			# Install all required components
			var req := fault.get_required_components()
			for comp in req:
				dev.try_install_component(comp)
			dev.install_part()
			err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "%s part replaced" % data.device_name)
			dev.advance_state(RepairState.State.REASSEMBLED)

		# 3. Software reinstall if not yet at SOFTWARE_INSTALLED
		if dev.current_repair_state == RepairState.State.REASSEMBLED:
			dev.advance_state(RepairState.State.SOFTWARE_INSTALLED)
		elif "DISASSEMBLED" in fault.skip_states:
			dev.skip_next_states()

		# 4. Testing & Delivery
		dev.advance_state(RepairState.State.TESTED)
		dev.advance_state(RepairState.State.DELIVERED)
		err += _assert(dev.current_repair_state == RepairState.State.DELIVERED,
			"%s completed full solo repair flow to DELIVERED" % data.device_name)

		dev.queue_free()

	return err


## 6. Test multi-fault end-to-end (Laptop Overheating: Fan + Thermal Paste)
func test_multi_fault_end_to_end() -> int:
	print("\n[6] Testing multi-fault end-to-end (Laptop Overheating)...")
	var err: int = 0

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	var scene: PackedScene = load("res://scenes/devices/Laptop.tscn") as PackedScene
	var dev: Device = scene.instantiate() as Device
	dev.initialize(laptop_data, fault)
	add_child(dev)

	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)

	# Verify missing parts = 2
	var missing: Array[ComponentData] = dev.get_missing_components()
	err += _assert(missing.size() == 2, "2 missing components initially")

	# Try install wrong component
	var wrong_part: ComponentData = load("res://resources/components/gpu.tres") as ComponentData
	var rejected: bool = dev.try_install_component(wrong_part)
	err += _assert(not rejected, "Laptop rejected unrelated component (GPU)")

	# Install first part (Fan)
	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	var accepted_fan: bool = dev.try_install_component(fan)
	err += _assert(accepted_fan, "Laptop accepted laptop_fan")
	err += _assert(not dev.install_part(), "Cannot install_part with 1 component remaining")
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Still DISASSEMBLED")

	# Install second part (Thermal Paste)
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	var accepted_paste: bool = dev.try_install_component(paste)
	err += _assert(accepted_paste, "Laptop accepted thermal_paste")
	err += _assert(dev.install_part(), "install_part succeeded once both parts present")
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "State advanced to PART_REPLACED")

	dev.queue_free()
	return err


## 7. Test skip-state Router Firmware end-to-end
func test_skip_state_router_firmware_end_to_end() -> int:
	print("\n[7] Testing skip-state Router firmware corruption end-to-end...")
	var err: int = 0

	var router_data: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	var fault: FaultData = router_data.get_fault_by_id("router_firmware_corrupt")
	var scene: PackedScene = load("res://scenes/devices/Router.tscn") as PackedScene
	var dev: Device = scene.instantiate() as Device
	dev.initialize(router_data, fault)
	add_child(dev)

	# Router is diagnosed
	dev.diagnose()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Router is DIAGNOSED")

	# Check workbench rejection
	var bench_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn") as PackedScene
	var bench: WorkbenchStation = bench_scene.instantiate() as WorkbenchStation
	add_child(bench)

	var can_accept: bool = bench._can_accept_workbench_item(dev)
	err += _assert(not can_accept, "Workbench rejects router with firmware fault (skips hardware states)")

	# Advance repair state: skips DISASSEMBLED, PART_REPLACED, REASSEMBLED directly to SOFTWARE_INSTALLED
	var advanced: bool = dev.advance_repair_state()
	err += _assert(advanced, "advance_repair_state() succeeded")
	err += _assert(dev.current_repair_state == RepairState.State.SOFTWARE_INSTALLED,
		"Router skipped workbench straight to SOFTWARE_INSTALLED")

	# Software Station accepts it
	var sw_scene: PackedScene = load("res://scenes/stations/SoftwareStation.tscn") as PackedScene
	var sw: SoftwareStation = sw_scene.instantiate() as SoftwareStation
	add_child(sw)
	err += _assert(sw.can_accept_device(dev), "SoftwareStation accepts router in SOFTWARE_INSTALLED state")

	dev.queue_free()
	bench.queue_free()
	sw.queue_free()
	return err


## 8. Test two-player carry Desktop PC co-op movement and speed penalties
func test_two_player_carry_desktop_pc() -> int:
	print("\n[8] Testing two-player carry Desktop PC...")
	var err: int = 0

	var p_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn") as PackedScene
	var p1: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	var p2: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	p1.player_index = 0
	p2.player_index = 1
	add_child(p1)
	add_child(p2)

	var d_scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn") as PackedScene
	var dev: Device = d_scene.instantiate() as Device
	add_child(dev)

	var cs1: CarrySystem = p1.carry_system
	var cs2: CarrySystem = p2.carry_system

	# P1 requests carry
	cs1.request_two_player_carry(dev)
	err += _assert(cs1.is_carry_requested(), "P1 requested carry")

	# P2 joins
	cs2.pick_up(dev)
	err += _assert(cs1.is_co_carrying and cs2.is_co_carrying, "Both players co-carrying")
	err += _assert(p1.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER,
		"P1 speed is 60%% (%f)" % p1.move_speed)
	err += _assert(p2.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER,
		"P2 speed is 60%% (%f)" % p2.move_speed)

	# Drop
	cs1.drop_item()
	err += _assert(not cs1.is_carrying() and not cs2.is_carrying(), "Both players released on drop")
	err += _assert(p1.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "P1 speed restored to 100%%")
	err += _assert(p2.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "P2 speed restored to 100%%")

	dev.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 9. Test PartsShelf stock depletion flow
func test_parts_shelf_stock_depletion_flow() -> int:
	print("\n[9] Testing PartsShelf stock depletion flow...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn") as PackedScene
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	shelf.initial_stock_per_part = 2
	add_child(shelf)

	var p_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn") as PackedScene
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	# Take part twice to deplete
	var part1: Carriable = shelf.dispense_part("laptop_ram")
	err += _assert(part1 != null, "Dispensed first laptop_ram")
	err += _assert(shelf.get_stock("laptop_ram") == 1, "Stock is 1")

	var part2: Carriable = shelf.dispense_part("laptop_ram")
	err += _assert(part2 != null, "Dispensed second laptop_ram")
	err += _assert(shelf.get_stock("laptop_ram") == 0, "Stock is 0 (depleted)")

	var part3: Carriable = shelf.dispense_part("laptop_ram")
	err += _assert(part3 == null, "Cannot dispense depleted laptop_ram")

	# Restock
	shelf.restock("laptop_ram", 3)
	err += _assert(shelf.get_stock("laptop_ram") == 3, "Stock restored to 3 after restock")

	if part1: part1.queue_free()
	if part2: part2.queue_free()
	player.queue_free()
	shelf.queue_free()
	return err


## 10. Test WorkshopDebug debug hotkeys & tier toggle
func test_workshop_debug_hotkeys_and_tier_toggle() -> int:
	print("\n[10] Testing WorkshopDebug spawn helpers and tier toggle...")
	var err: int = 0

	var workshop_scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn") as PackedScene
	var workshop: WorkshopDebug = workshop_scene.instantiate() as WorkshopDebug
	workshop.auto_start_round = false
	workshop.auto_spawn_player = false
	add_child(workshop)

	var om: OrderManager = workshop.order_manager
	err += _assert(om != null, "Found OrderManager in WorkshopDebug")

	# Test spawning specific devices via debug helper
	var tablet_order: Order = workshop._debug_spawn_device("tablet")
	err += _assert(tablet_order != null, "Spawned tablet via _debug_spawn_device")
	if tablet_order and tablet_order.device_instance:
		err += _assert(tablet_order.device_instance.item_name == "Tablet", "Spawned tablet device instance")
		tablet_order.device_instance.queue_free()

	# Test tier toggle
	err += _assert(om.tier_filter == [1, 2], "Initial tier_filter is [1, 2]")
	workshop._toggle_tier_filter()
	err += _assert(om.tier_filter == [1, 2, 3], "After toggle, tier_filter is [1, 2, 3] (Desktop enabled)")
	workshop._toggle_tier_filter()
	err += _assert(om.tier_filter == [1, 2], "After second toggle, tier_filter is [1, 2]")

	workshop.queue_free()
	return err


## 11. Test 4-player session simulation with Tier 1+2 devices
func test_multiplayer_session_simulation() -> int:
	print("\n[11] Testing 4-player session simulation with Tier 1+2 devices...")
	var err: int = 0

	var om := OrderManager.new()
	om.tier_filter = [1, 2]
	add_child(om)

	var players: Array[PlayerCharacter] = []
	var p_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn") as PackedScene
	for i in range(4):
		var p: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
		p.player_index = i
		add_child(p)
		players.append(p)

	# Spawn 4 active orders
	var orders: Array[Order] = []
	for i in range(4):
		var ord: Order = om.spawn_order()
		err += _assert(ord != null, "Spawned order %d for 4-player session" % (i + 1))
		if ord:
			err += _assert(ord.device_data.difficulty_tier in [1, 2], "Order %d is tier 1 or 2" % (i + 1))
			orders.append(ord)

	err += _assert(om.get_active_order_count() == 4, "OrderManager has 4 active orders")

	# Complete all 4 orders
	for ord in orders:
		if ord.device_instance:
			ord.device_instance.current_repair_state = RepairState.State.TESTED
			ord.device_instance.deliver()
			ord.device_instance.queue_free()
		om.complete_order(ord)

	err += _assert(om.get_active_order_count() == 0, "All 4 orders successfully completed")
	err += _assert(om.completed_orders.size() == 4, "OrderManager has 4 completed orders")

	for p in players:
		p.queue_free()
	om.queue_free()
	return err
