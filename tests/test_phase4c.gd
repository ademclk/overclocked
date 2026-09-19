extends Node

## Test suite for Phase 4C — Tier 1 Device Roster & High-Tier Prototypes
## Tests Tablet, Laptop, and Desktop PC resources, scenes, multi-fault handling,
## and two-player / solo heavy carry mechanics.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4C DEVICE ROSTER TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_tablet_resources_and_faults()
	failures += test_laptop_resources_and_faults()
	failures += test_desktop_pc_resources_and_faults()
	failures += test_device_scenes_instantiation()
	failures += test_laptop_multi_fault_repair_flow()
	failures += test_desktop_motherboard_multi_fault_flow()
	failures += test_desktop_carry_mechanics()

	print("=========================================================")
	print("--- PHASE 4C TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4C TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4C tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		print("  [FAIL] %s" % test_name)
		return 1


## 1. Test Tablet DeviceData and FaultData resources
func test_tablet_resources_and_faults() -> int:
	print("\n[1] Testing Tablet DeviceData & FaultData resources...")
	var err: int = 0

	var tablet: DeviceData = load("res://resources/devices/tablet.tres") as DeviceData
	err += _assert(tablet != null, "tablet.tres loads successfully")
	if not tablet:
		return err + 1

	err += _assert(tablet.is_valid(), "tablet.tres is_valid() == true")
	err += _assert(tablet.device_id == "tablet", "device_id is 'tablet'")
	err += _assert(tablet.difficulty_tier == 1, "difficulty_tier is 1")
	err += _assert(tablet.base_repair_time == 75.0, "base_repair_time is 75.0")
	err += _assert(tablet.carry_requires_two_players == false, "carry_requires_two_players is false")
	err += _assert(tablet.possible_faults.size() == 3, "possible_faults has 3 entries")

	var expected_faults := {
		"tablet_cracked_screen": {"name": "Cracked Screen", "comp": "tablet_screen", "time": 3.5, "sw": false},
		"tablet_dead_battery": {"name": "Dead Battery", "comp": "tablet_battery", "time": 3.5, "sw": false},
		"tablet_blown_speaker": {"name": "Blown Speaker", "comp": "tablet_speaker", "time": 4.0, "sw": false},
	}

	for f_id in expected_faults.keys():
		var fault: FaultData = tablet.get_fault_by_id(f_id)
		err += _assert(fault != null, "Found fault '%s'" % f_id)
		if fault:
			err += _assert(fault.is_valid(), "Fault '%s' is_valid() == true" % f_id)
			err += _assert(fault.fault_name == expected_faults[f_id]["name"], "Fault name is '%s'" % expected_faults[f_id]["name"])
			err += _assert(fault.repair_time == expected_faults[f_id]["time"], "Repair time is %0.1fs" % expected_faults[f_id]["time"])
			err += _assert(fault.requires_software_reinstall == expected_faults[f_id]["sw"], "requires_software_reinstall is %s" % str(expected_faults[f_id]["sw"]))
			var comps: Array[ComponentData] = fault.get_required_components()
			err += _assert(comps.size() == 1 and comps[0].component_id == expected_faults[f_id]["comp"], "Broken component is '%s'" % expected_faults[f_id]["comp"])

	return err


## 2. Test Laptop DeviceData and FaultData resources
func test_laptop_resources_and_faults() -> int:
	print("\n[2] Testing Laptop DeviceData & FaultData resources...")
	var err: int = 0

	var laptop: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	err += _assert(laptop != null, "laptop.tres loads successfully")
	if not laptop:
		return err + 1

	err += _assert(laptop.is_valid(), "laptop.tres is_valid() == true")
	err += _assert(laptop.device_id == "laptop", "device_id is 'laptop'")
	err += _assert(laptop.difficulty_tier == 2, "difficulty_tier is 2")
	err += _assert(laptop.base_repair_time == 120.0, "base_repair_time is 120.0")
	err += _assert(laptop.carry_requires_two_players == false, "carry_requires_two_players is false")
	err += _assert(laptop.possible_faults.size() == 5, "possible_faults has 5 entries")

	# Check multi-step faults
	var kb_fault: FaultData = laptop.get_fault_by_id("laptop_broken_keyboard")
	err += _assert(kb_fault != null and kb_fault.requires_workbench_step_count == 2, "laptop_broken_keyboard has step count 2")

	var screen_fault: FaultData = laptop.get_fault_by_id("laptop_cracked_screen")
	err += _assert(screen_fault != null and screen_fault.requires_workbench_step_count == 2, "laptop_cracked_screen has step count 2")

	# Check software-requiring hardware faults
	var ram_fault: FaultData = laptop.get_fault_by_id("laptop_dead_ram")
	err += _assert(ram_fault != null and ram_fault.requires_software_reinstall, "laptop_dead_ram requires software reinstall")

	var ssd_fault: FaultData = laptop.get_fault_by_id("laptop_failed_ssd")
	err += _assert(ssd_fault != null and ssd_fault.requires_software_reinstall, "laptop_failed_ssd requires software reinstall")

	# Check multi-fault overheating
	var heat_fault: FaultData = laptop.get_fault_by_id("laptop_overheating")
	err += _assert(heat_fault != null and heat_fault.is_multi_fault, "laptop_overheating is_multi_fault == true")
	if heat_fault:
		var comps: Array[ComponentData] = heat_fault.get_required_components()
		err += _assert(comps.size() == 2, "laptop_overheating requires 2 components")
		var comp_ids: Array[String] = [comps[0].component_id, comps[1].component_id]
		err += _assert("laptop_fan" in comp_ids and "thermal_paste" in comp_ids, "laptop_overheating requires fan and thermal paste")

	return err


## 3. Test Desktop PC DeviceData and FaultData resources
func test_desktop_pc_resources_and_faults() -> int:
	print("\n[3] Testing Desktop PC DeviceData & FaultData resources...")
	var err: int = 0

	var pc: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	err += _assert(pc != null, "desktop_pc.tres loads successfully")
	if not pc:
		return err + 1

	err += _assert(pc.is_valid(), "desktop_pc.tres is_valid() == true")
	err += _assert(pc.device_id == "desktop_pc", "device_id is 'desktop_pc'")
	err += _assert(pc.difficulty_tier == 3, "difficulty_tier is 3")
	err += _assert(pc.base_repair_time == 180.0, "base_repair_time is 180.0")
	err += _assert(pc.carry_requires_two_players == true, "carry_requires_two_players is true")
	err += _assert(pc.possible_faults.size() == 5, "possible_faults has 5 entries")

	# Overheating fault
	var heat_fault: FaultData = pc.get_fault_by_id("desktop_overheating")
	err += _assert(heat_fault != null and heat_fault.is_multi_fault, "desktop_overheating is multi_fault")
	if heat_fault:
		var comps: Array[ComponentData] = heat_fault.get_required_components()
		err += _assert(comps.size() == 2, "desktop_overheating requires 2 components (cpu_cooler, thermal_paste)")

	# Motherboard fault (3 components: mobo, gpu, desktop_ram)
	var mobo_fault: FaultData = pc.get_fault_by_id("desktop_dead_motherboard")
	err += _assert(mobo_fault != null and mobo_fault.is_multi_fault, "desktop_dead_motherboard is multi_fault")
	if mobo_fault:
		err += _assert(mobo_fault.requires_software_reinstall, "desktop_dead_motherboard requires software reinstall")
		var comps: Array[ComponentData] = mobo_fault.get_required_components()
		err += _assert(comps.size() == 3, "desktop_dead_motherboard requires 3 components")
		var ids: Array[String] = [comps[0].component_id, comps[1].component_id, comps[2].component_id]
		err += _assert("motherboard" in ids and "gpu" in ids and "desktop_ram" in ids, "desktop_dead_motherboard requires mobo, gpu, and desktop_ram")

	return err


## 4. Test device scenes instantiation and visual components
func test_device_scenes_instantiation() -> int:
	print("\n[4] Testing device scenes instantiation...")
	var err: int = 0

	var scenes := {
		"Tablet": "res://scenes/devices/Tablet.tscn",
		"Laptop": "res://scenes/devices/Laptop.tscn",
		"DesktopPC": "res://scenes/devices/DesktopPC.tscn",
	}

	for s_name in scenes.keys():
		var path: String = scenes[s_name]
		var scene: PackedScene = load(path) as PackedScene
		err += _assert(scene != null, "%s scene loaded successfully" % s_name)
		if not scene:
			continue

		var inst: Node = scene.instantiate()
		err += _assert(inst is Device, "%s is Device instance" % s_name)
		var dev := inst as Device
		add_child(dev)

		err += _assert(dev.get_node_or_null("DeviceMesh") != null, "%s has DeviceMesh" % s_name)
		err += _assert(dev.get_node_or_null("DeviceLabel") != null, "%s has DeviceLabel" % s_name)
		err += _assert(dev.get_node_or_null("InteractionZone") != null, "%s has InteractionZone" % s_name)

		dev.queue_free()

	return err


## 5. Test Laptop multi-fault repair flow (fan + thermal paste)
func test_laptop_multi_fault_repair_flow() -> int:
	print("\n[5] Testing Laptop multi-fault repair flow...")
	var err: int = 0

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var heat_fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")

	var laptop_scene: PackedScene = load("res://scenes/devices/Laptop.tscn")
	var laptop: Device = laptop_scene.instantiate() as Device
	add_child(laptop)
	laptop.initialize(laptop_data, heat_fault)

	err += _assert(laptop.item_name == "Laptop", "Laptop item_name initialized")
	err += _assert(laptop.assigned_fault == heat_fault, "Laptop assigned_fault is overheating")

	# Progression to DISASSEMBLED
	laptop.diagnose()
	laptop.advance_repair_state()
	err += _assert(laptop.current_repair_state == RepairState.State.DISASSEMBLED, "State is DISASSEMBLED")

	# Check missing components
	var missing: Array[ComponentData] = laptop.get_missing_components()
	err += _assert(missing.size() == 2, "Missing components count is 2 initially")

	# Try installing wrong component
	var wrong_comp: ComponentData = load("res://resources/components/gpu.tres") as ComponentData
	var wrong_res: bool = laptop.try_install_component(wrong_comp)
	err += _assert(not wrong_res, "Wrong component rejected")

	# Install first correct component: fan
	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	var fan_res: bool = laptop.try_install_component(fan)
	err += _assert(fan_res, "Laptop fan accepted")
	err += _assert(laptop.get_missing_components().size() == 1, "Missing components count is 1 after fan installed")

	# Attempt to complete repair with 1 missing component -> should fail
	var partial_install: bool = laptop.install_part()
	err += _assert(not partial_install, "install_part() rejected while components missing")
	err += _assert(laptop.current_repair_state == RepairState.State.DISASSEMBLED, "State remains DISASSEMBLED")

	# Install second component: thermal paste
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	var paste_res: bool = laptop.try_install_component(paste)
	err += _assert(paste_res, "Thermal paste accepted")
	err += _assert(laptop.get_missing_components().is_empty(), "Missing components count is 0 after paste installed")

	# Now install_part() should succeed
	var full_install: bool = laptop.install_part()
	err += _assert(full_install, "install_part() succeeds with all parts installed")
	err += _assert(laptop.current_repair_state == RepairState.State.PART_REPLACED, "State advanced to PART_REPLACED")

	laptop.queue_free()
	return err


## 6. Test Desktop motherboard 3-component multi-fault flow
func test_desktop_motherboard_multi_fault_flow() -> int:
	print("\n[6] Testing Desktop Motherboard 3-component multi-fault flow...")
	var err: int = 0

	var pc_data: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	var mobo_fault: FaultData = pc_data.get_fault_by_id("desktop_dead_motherboard")

	var pc_scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn")
	var pc: Device = pc_scene.instantiate() as Device
	add_child(pc)
	pc.initialize(pc_data, mobo_fault)

	pc.diagnose()
	pc.advance_repair_state()
	err += _assert(pc.current_repair_state == RepairState.State.DISASSEMBLED, "Desktop in DISASSEMBLED")

	var mobo: ComponentData = load("res://resources/components/motherboard.tres") as ComponentData
	var gpu: ComponentData = load("res://resources/components/gpu.tres") as ComponentData
	var ram: ComponentData = load("res://resources/components/desktop_ram.tres") as ComponentData

	err += _assert(pc.get_missing_components().size() == 3, "Initially 3 missing parts")

	pc.try_install_component(mobo)
	err += _assert(pc.get_missing_components().size() == 2, "2 missing parts after motherboard")
	err += _assert(not pc.install_part(), "Cannot advance with 2 missing parts")

	pc.try_install_component(gpu)
	err += _assert(pc.get_missing_components().size() == 1, "1 missing part after gpu")
	err += _assert(not pc.install_part(), "Cannot advance with 1 missing part")

	pc.try_install_component(ram)
	err += _assert(pc.get_missing_components().is_empty(), "0 missing parts after ram")
	err += _assert(pc.install_part(), "install_part() succeeds with all 3 parts")
	err += _assert(pc.current_repair_state == RepairState.State.PART_REPLACED, "Desktop state is PART_REPLACED")

	pc.queue_free()
	return err


## 7. Test Desktop PC carry mechanics (solo heavy carry & two-player co-op carry)
func test_desktop_carry_mechanics() -> int:
	print("\n[7] Testing Desktop PC carry mechanics...")
	var err: int = 0

	var pc_scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn")
	var pc: Device = pc_scene.instantiate() as Device
	add_child(pc)
	var pc_data: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	pc.initialize(pc_data)

	# Single player heavy carry test
	var p1: PlayerCharacter = _create_test_player(0)
	err += _assert(pc.interaction_zone.interaction_prompt == "Requires 2 players to carry!", "Interaction prompt specifies 2 players")

	# In solo scenario (only p1 in tree):
	p1.carry_system.pick_up(pc)
	err += _assert(p1.carry_system.is_carrying(), "Solo player can pick up Desktop PC")
	var expected_solo_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.ONE_PLAYER_HEAVY_CARRY_SPEED
	err += _assert(is_equal_approx(p1.move_speed, expected_solo_speed), "Player move speed reduced to 40%% (%s vs %s)" % [str(p1.move_speed), str(expected_solo_speed)])

	# Drop restores speed
	p1.carry_system.drop_item()
	err += _assert(is_equal_approx(p1.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "Dropping restores player move speed to 100%")

	# Two-player co-op carry test
	var p2: PlayerCharacter = _create_test_player(1)

	# P1 initiates carry request
	p1.carry_system.pick_up(pc)
	err += _assert(pc.carry_request_active, "P1 initiated co-op carry request")
	err += _assert(not p1.carry_system.is_carrying(), "P1 not yet carrying alone in 2-player mode")

	# P2 accepts carry request
	p2.carry_system.pick_up(pc)
	err += _assert(p1.carry_system.is_carrying() and p2.carry_system.is_carrying(), "Both players are now co-carrying")
	var expected_co_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER
	err += _assert(is_equal_approx(p1.move_speed, expected_co_speed), "P1 move speed is 60%% (%s)" % str(p1.move_speed))
	err += _assert(is_equal_approx(p2.move_speed, expected_co_speed), "P2 move speed is 60%% (%s)" % str(p2.move_speed))

	# Drop by P1 releases both players
	p1.carry_system.drop_item()
	err += _assert(not p1.carry_system.is_carrying(), "P1 dropped item")
	err += _assert(not p2.carry_system.is_carrying(), "P2 also released item")
	err += _assert(is_equal_approx(p1.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "P1 speed restored to 100%")
	err += _assert(is_equal_approx(p2.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "P2 speed restored to 100%")

	p1.queue_free()
	p2.queue_free()
	pc.queue_free()
	return err


func _create_test_player(p_idx: int = 0) -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	player.player_index = p_idx
	player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED
	add_child(player)
	player._apply_player_color()
	return player
