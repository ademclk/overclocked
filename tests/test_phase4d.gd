extends Node

## Test suite for Phase 4D — Tier 2 Device Roster (Game Console & Networking Router)
## Tests Game Console and Router resources, scenes, multi-fault handling on consoles,
## software-only firmware faults, and workbench skip-state pipeline integration.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4D TIER 2 DEVICE ROSTER TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_game_console_resources_and_faults()
	failures += test_router_resources_and_faults()
	failures += test_device_scenes_instantiation()
	failures += test_console_multi_fault_repair_flow()
	failures += test_router_hardware_repair_flow()
	failures += test_router_firmware_skip_states_flow()
	failures += test_order_manager_tier2_integration()

	print("=========================================================")
	print("--- PHASE 4D TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4D TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4D tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		print("  [FAIL] %s" % test_name)
		return 1


## 1. Test Game Console DeviceData & FaultData resources
func test_game_console_resources_and_faults() -> int:
	print("\n[1] Testing Game Console DeviceData & FaultData resources...")
	var err: int = 0

	var console: DeviceData = load("res://resources/devices/game_console.tres") as DeviceData
	err += _assert(console != null, "game_console.tres loads successfully")
	if not console:
		return err + 1

	err += _assert(console.is_valid(), "game_console.tres is_valid() == true")
	err += _assert(console.device_id == "game_console", "device_id is 'game_console'")
	err += _assert(console.difficulty_tier == 2, "difficulty_tier is 2")
	err += _assert(console.base_repair_time == 100.0, "base_repair_time is 100.0")
	err += _assert(console.carry_requires_two_players == false, "carry_requires_two_players is false")
	err += _assert(console.possible_faults.size() == 3, "possible_faults has 3 entries")

	# Fault 1: console_disc_drive
	var f_drive: FaultData = console.get_fault_by_id("console_disc_drive")
	err += _assert(f_drive != null, "Found fault 'console_disc_drive'")
	if f_drive:
		err += _assert(f_drive.is_valid(), "console_disc_drive is_valid()")
		err += _assert(f_drive.fault_name == "Disc Drive Failure", "Name is 'Disc Drive Failure'")
		err += _assert(f_drive.repair_time == 5.0, "Repair time is 5.0s")
		err += _assert(f_drive.is_multi_fault == false, "is_multi_fault is false")
		err += _assert(f_drive.requires_software_reinstall == false, "Software reinstall is false")
		var comps: Array[ComponentData] = f_drive.get_required_components()
		err += _assert(comps.size() == 1 and comps[0].component_id == "disc_drive", "Component is 'disc_drive'")

	# Fault 2: console_hdmi_port
	var f_hdmi: FaultData = console.get_fault_by_id("console_hdmi_port")
	err += _assert(f_hdmi != null, "Found fault 'console_hdmi_port'")
	if f_hdmi:
		err += _assert(f_hdmi.is_valid(), "console_hdmi_port is_valid()")
		err += _assert(f_hdmi.fault_name == "Broken HDMI Port", "Name is 'Broken HDMI Port'")
		err += _assert(f_hdmi.repair_time == 4.5, "Repair time is 4.5s")
		err += _assert(f_hdmi.is_multi_fault == false, "is_multi_fault is false")
		var comps: Array[ComponentData] = f_hdmi.get_required_components()
		err += _assert(comps.size() == 1 and comps[0].component_id == "console_hdmi_port", "Component is 'console_hdmi_port'")

	# Fault 3: console_overheating
	var f_overheat: FaultData = console.get_fault_by_id("console_overheating")
	err += _assert(f_overheat != null, "Found fault 'console_overheating'")
	if f_overheat:
		err += _assert(f_overheat.is_valid(), "console_overheating is_valid()")
		err += _assert(f_overheat.fault_name == "Thermal Shutdown", "Name is 'Thermal Shutdown'")
		err += _assert(f_overheat.repair_time == 6.0, "Repair time is 6.0s")
		err += _assert(f_overheat.is_multi_fault == true, "is_multi_fault is true")
		var comps: Array[ComponentData] = f_overheat.get_required_components()
		err += _assert(comps.size() == 2, "Requires 2 components")
		var ids: Array[String] = [comps[0].component_id, comps[1].component_id]
		err += _assert("cpu_cooler" in ids and "thermal_paste" in ids, "Requires cpu_cooler and thermal_paste")

	return err


## 2. Test Router DeviceData & FaultData resources
func test_router_resources_and_faults() -> int:
	print("\n[2] Testing Router DeviceData & FaultData resources...")
	var err: int = 0

	var router: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	err += _assert(router != null, "router.tres loads successfully")
	if not router:
		return err + 1

	err += _assert(router.is_valid(), "router.tres is_valid() == true")
	err += _assert(router.device_id == "router", "device_id is 'router'")
	err += _assert(router.difficulty_tier == 2, "difficulty_tier is 2")
	err += _assert(router.base_repair_time == 90.0, "base_repair_time is 90.0")
	err += _assert(router.carry_requires_two_players == false, "carry_requires_two_players is false")
	err += _assert(router.possible_faults.size() == 3, "possible_faults has 3 entries")

	# Fault 1: router_antenna_broken
	var f_ant: FaultData = router.get_fault_by_id("router_antenna_broken")
	err += _assert(f_ant != null, "Found fault 'router_antenna_broken'")
	if f_ant:
		err += _assert(f_ant.is_valid(), "router_antenna_broken is_valid()")
		err += _assert(f_ant.fault_name == "Broken Antenna", "Name is 'Broken Antenna'")
		err += _assert(f_ant.repair_time == 3.5, "Repair time is 3.5s")
		err += _assert(f_ant.requires_software_reinstall == false, "requires_software_reinstall is false")
		var comps: Array[ComponentData] = f_ant.get_required_components()
		err += _assert(comps.size() == 1 and comps[0].component_id == "router_antenna", "Component is 'router_antenna'")

	# Fault 2: router_firmware_corrupt (software-only, skip states)
	var f_fw: FaultData = router.get_fault_by_id("router_firmware_corrupt")
	err += _assert(f_fw != null, "Found fault 'router_firmware_corrupt'")
	if f_fw:
		err += _assert(f_fw.is_valid(), "router_firmware_corrupt is_valid()")
		err += _assert(f_fw.fault_name == "Firmware Corruption", "Name is 'Firmware Corruption'")
		err += _assert(f_fw.requires_software_reinstall == true, "requires_software_reinstall is true")
		err += _assert(f_fw.get_required_components().is_empty(), "Requires no physical components (software only)")
		err += _assert(f_fw.skip_states.has("DISASSEMBLED"), "skip_states contains DISASSEMBLED")
		err += _assert(f_fw.skip_states.has("PART_REPLACED"), "skip_states contains PART_REPLACED")
		err += _assert(f_fw.skip_states.has("REASSEMBLED"), "skip_states contains REASSEMBLED")

	# Fault 3: router_dead_port
	var f_port: FaultData = router.get_fault_by_id("router_dead_port")
	err += _assert(f_port != null, "Found fault 'router_dead_port'")
	if f_port:
		err += _assert(f_port.is_valid(), "router_dead_port is_valid()")
		err += _assert(f_port.fault_name == "Dead LAN Port", "Name is 'Dead LAN Port'")
		err += _assert(f_port.repair_time == 4.0, "Repair time is 4.0s")

	return err


## 3. Test GameConsole and Router scenes instantiation
func test_device_scenes_instantiation() -> int:
	print("\n[3] Testing GameConsole and Router scenes instantiation...")
	var err: int = 0

	# GameConsole scene
	var console_scene: PackedScene = load("res://scenes/devices/GameConsole.tscn") as PackedScene
	err += _assert(console_scene != null, "GameConsole.tscn loads successfully")
	if console_scene:
		var console_inst: Node = console_scene.instantiate()
		err += _assert(console_inst is Device, "GameConsole is Device instance")
		err += _assert(console_inst.get_node_or_null("DeviceMesh") != null, "GameConsole has DeviceMesh")
		err += _assert(console_inst.get_node_or_null("DeviceLabel") != null, "GameConsole has DeviceLabel")
		err += _assert(console_inst.get_node_or_null("InteractionZone") != null, "GameConsole has InteractionZone")
		err += _assert(console_inst.get_node_or_null("DeviceMesh/DiscSlotMesh") != null, "GameConsole has DiscSlotMesh")
		err += _assert(console_inst.get_node_or_null("DeviceMesh/PowerLedMesh") != null, "GameConsole has PowerLedMesh")
		console_inst.queue_free()

	# Router scene
	var router_scene: PackedScene = load("res://scenes/devices/Router.tscn") as PackedScene
	err += _assert(router_scene != null, "Router.tscn loads successfully")
	if router_scene:
		var router_inst: Node = router_scene.instantiate()
		err += _assert(router_inst is Device, "Router is Device instance")
		err += _assert(router_inst.get_node_or_null("DeviceMesh") != null, "Router has DeviceMesh")
		err += _assert(router_inst.get_node_or_null("DeviceLabel") != null, "Router has DeviceLabel")
		err += _assert(router_inst.get_node_or_null("InteractionZone") != null, "Router has InteractionZone")
		err += _assert(router_inst.get_node_or_null("DeviceMesh/AntennaLeft") != null, "Router has AntennaLeft")
		err += _assert(router_inst.get_node_or_null("DeviceMesh/AntennaRight") != null, "Router has AntennaRight")
		router_inst.queue_free()

	return err


## 4. Test Game Console Multi-Fault Repair Flow
func test_console_multi_fault_repair_flow() -> int:
	print("\n[4] Testing Game Console multi-fault (Thermal Shutdown) repair flow...")
	var err: int = 0

	var console_data: DeviceData = load("res://resources/devices/game_console.tres") as DeviceData
	var fault: FaultData = console_data.get_fault_by_id("console_overheating")
	var cooler_comp: ComponentData = load("res://resources/components/cpu_cooler.tres") as ComponentData
	var paste_comp: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	var wrong_comp: ComponentData = load("res://resources/components/tablet_screen.tres") as ComponentData

	var dev := Device.new()
	add_child(dev)
	dev.initialize(console_data, fault)

	err += _assert(dev.item_name == "Game Console", "Console initialized with correct name")
	err += _assert(dev.current_repair_state == RepairState.State.RECEIVED, "Initial state is RECEIVED")

	dev.diagnose()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Diagnosed state reached")

	# Advance to DISASSEMBLED
	dev.advance_state(RepairState.State.DISASSEMBLED)
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Disassembled state reached")

	# Check missing parts
	var missing := dev.get_missing_components()
	err += _assert(missing.size() == 2, "Initially 2 missing components")

	# Wrong component should fail
	var wrong_res := dev.try_install_component(wrong_comp)
	err += _assert(wrong_res == false, "Wrong component rejected")

	# Install cooler
	var c1_res := dev.try_install_component(cooler_comp)
	err += _assert(c1_res == true, "Cooler installed successfully")
	err += _assert(dev.get_missing_components().size() == 1, "1 component remaining")

	# Try advance without paste
	var early_ok := dev.install_part()
	err += _assert(early_ok == false, "install_part() fails while paste is missing")
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "State remains DISASSEMBLED")

	# Install paste
	var c2_res := dev.try_install_component(paste_comp)
	err += _assert(c2_res == true, "Thermal paste installed successfully")
	err += _assert(dev.get_missing_components().is_empty(), "0 components remaining")

	# Now install_part should advance to PART_REPLACED
	var adv_ok := dev.install_part()
	err += _assert(adv_ok == true, "install_part() succeeds when all parts installed")
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "State is PART_REPLACED")

	# Reassemble
	dev.advance_state(RepairState.State.REASSEMBLED)
	err += _assert(dev.current_repair_state == RepairState.State.REASSEMBLED, "State is REASSEMBLED")

	# Deliver
	dev.advance_state(RepairState.State.SOFTWARE_INSTALLED)
	dev.advance_state(RepairState.State.TESTED)
	dev.deliver()
	err += _assert(dev.current_repair_state == RepairState.State.DELIVERED, "Console reached DELIVERED")

	dev.queue_free()
	return err


## 5. Test Router Hardware Repair Flow (Broken Antenna)
func test_router_hardware_repair_flow() -> int:
	print("\n[5] Testing Router hardware repair flow (Broken Antenna)...")
	var err: int = 0

	var router_data: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	var fault: FaultData = router_data.get_fault_by_id("router_antenna_broken")
	var antenna_comp: ComponentData = load("res://resources/components/router_antenna.tres") as ComponentData

	var dev := Device.new()
	add_child(dev)
	dev.initialize(router_data, fault)

	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)

	var ok := dev.try_install_component(antenna_comp)
	err += _assert(ok == true, "Router antenna accepted")
	err += _assert(dev.get_missing_components().is_empty(), "No missing components")

	dev.install_part()
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "State is PART_REPLACED")

	dev.queue_free()
	return err


## 6. Test Router Firmware Skip-States Flow (Software Only)
func test_router_firmware_skip_states_flow() -> int:
	print("\n[6] Testing Router Firmware skip-states flow (skips workbench entirely)...")
	var err: int = 0

	var router_data: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	var fw_fault: FaultData = router_data.get_fault_by_id("router_firmware_corrupt")

	var dev := Device.new()
	add_child(dev)
	dev.initialize(router_data, fw_fault)

	# Initial diagnosis
	err += _assert(dev.current_repair_state == RepairState.State.RECEIVED, "Initial state is RECEIVED")
	dev.diagnose()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Diagnosed state reached")

	# Test workbench station checks:
	var bench := WorkbenchStation.new()
	add_child(bench)

	# Workbench should NOT accept diagnosed router with skip_states skipping disassembly
	var bench_accepts := bench.can_accept_device(dev)
	err += _assert(bench_accepts == false, "Workbench can_accept_device() returns false for firmware fault")

	# Player holding device at workbench should see "No hardware repair needed"
	var player: PlayerCharacter = _create_test_player(0)
	player.carry_system.pick_up(dev)

	var prompt := bench.get_interaction_prompt(player)
	err += _assert(prompt == "No hardware repair needed", "Workbench prompt is 'No hardware repair needed' (got: '%s')" % prompt)

	# Test software station interaction:
	var sw_station := SoftwareStation.new()
	add_child(sw_station)

	var sw_accepts := sw_station.can_accept_device(dev)
	err += _assert(sw_accepts == true, "SoftwareStation can_accept_device() returns true for diagnosed router with skip_states")

	var sw_prompt := sw_station.get_interaction_prompt(player)
	err += _assert(sw_prompt == "Install Software", "SoftwareStation prompt is 'Install Software' (got: '%s')" % sw_prompt)

	# Interact with software station: places device and flashes
	sw_station._on_interacted(player)
	err += _assert(player.carry_system.is_carrying() == false, "Player placed router on software station")
	err += _assert(sw_station.placed_device == dev, "Router placed on software station")

	# Simulate software installation completion
	sw_station._on_processing_done()
	err += _assert(dev.current_repair_state == RepairState.State.TESTED, "Router state progressed directly to TESTED (got: %s)" % dev.get_repair_state())

	# Delivery
	var delivered_ok := dev.deliver()
	err += _assert(delivered_ok == true, "Router delivered successfully")
	err += _assert(dev.current_repair_state == RepairState.State.DELIVERED, "Final state is DELIVERED")

	bench.queue_free()
	sw_station.queue_free()
	player.queue_free()
	dev.queue_free()
	return err


## 7. Test OrderManager Integration with Tier 2 Devices
func test_order_manager_tier2_integration() -> int:
	print("\n[7] Testing OrderManager integration with Tier 2 devices...")
	var err: int = 0

	var order_mgr := OrderManager.new()
	add_child(order_mgr)

	# Check devices in database
	var console_data: DeviceData = order_mgr.get_device_by_id("game_console")
	err += _assert(console_data != null, "OrderManager found 'game_console' by id")

	var router_data: DeviceData = order_mgr.get_device_by_id("router")
	err += _assert(router_data != null, "OrderManager found 'router' by id")

	var tier2_devices: Array[DeviceData] = order_mgr.get_devices_by_tier(2)
	err += _assert(tier2_devices.size() >= 3, "Tier 2 has 3+ devices (Laptop, Console, Router)")

	var tier2_ids: Array[String] = []
	for d in tier2_devices:
		tier2_ids.append(d.device_id)
	err += _assert("laptop" in tier2_ids, "Tier 2 contains laptop")
	err += _assert("game_console" in tier2_ids, "Tier 2 contains game_console")
	err += _assert("router" in tier2_ids, "Tier 2 contains router")

	# Test spawning with custom device scene
	order_mgr.tier_filter = [2]
	var order := order_mgr.spawn_order(console_data)
	err += _assert(order != null, "Spawned game_console order")
	err += _assert(order.device_instance != null, "Order has device_instance")
	err += _assert(order.device_instance.item_name == "Game Console", "Device instance is Game Console")
	err += _assert(order.device_instance.scene_file_path.ends_with("GameConsole.tscn"), "Device instantiated from GameConsole.tscn")

	order_mgr.queue_free()
	return err


func _create_test_player(p_idx: int = 0) -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	player.player_index = p_idx
	player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED
	add_child(player)
	player._apply_player_color()
	return player
