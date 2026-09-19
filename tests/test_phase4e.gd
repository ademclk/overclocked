extends Node

## Test suite for Phase 4E — Multi-Fault Devices
## Validates multi-component tracking in Device, partial installations, wrong component rejection,
## workbench component slots (✓/○) visual feedback, diagnostic bench reveal with tags,
## and complete multi-fault repair flows for Laptop and Desktop.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4E MULTI-FAULT TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_multi_fault_schema_and_tracking()
	failures += test_workbench_multi_fault_end_to_end()
	failures += test_desktop_dead_motherboard_3_component_flow()
	failures += test_diagnostic_bench_multi_fault_reveal()
	failures += test_hud_multi_fault_display()
	failures += test_single_fault_regression_on_workbench()

	print("=========================================================")
	print("--- PHASE 4E TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4E TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4E tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


## 1. Test Device multi-component schema, tracking, and validation
func test_multi_fault_schema_and_tracking() -> int:
	print("\n[1] Testing Multi-Fault schema, tracking, and installation validation...")
	var err: int = 0

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	err += _assert(fault != null, "Found laptop_overheating fault")
	if not fault:
		return err + 1

	err += _assert(fault.is_multi_fault, "laptop_overheating is_multi_fault is true")
	err += _assert(fault.fault_display_tags.size() >= 2, "fault_display_tags has at least 2 entries")

	var dev := Device.new()
	add_child(dev)
	dev.initialize(laptop_data, fault)

	err += _assert(dev.installed_components.is_empty(), "installed_components initially empty")
	err += _assert(dev.installed_component == null, "installed_component backward-compat accessor returns null")

	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)

	var missing: Array[ComponentData] = dev.get_missing_components()
	err += _assert(missing.size() == 2, "2 missing components initially")

	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	var wrong: ComponentData = load("res://resources/components/tablet_screen.tres") as ComponentData

	# Wrong component rejection
	var wrong_res: bool = dev.try_install_component(wrong)
	err += _assert(not wrong_res, "Wrong component rejected by try_install_component")
	err += _assert(dev.installed_components.is_empty(), "installed_components still empty after rejected install")

	# Install first part
	var c1_res: bool = dev.try_install_component(fan)
	err += _assert(c1_res, "Laptop fan installed successfully")
	err += _assert(dev.installed_components.size() == 1, "installed_components size is 1")
	err += _assert(dev.installed_component == fan, "installed_component backward-compat returns first component")
	err += _assert(dev.get_missing_components().size() == 1, "1 missing component remaining")

	# Try duplicate install of same component -> must reject
	var dup_res: bool = dev.try_install_component(fan)
	err += _assert(not dup_res, "Duplicate component install rejected")
	err += _assert(dev.installed_components.size() == 1, "installed_components size unchanged after duplicate attempt")

	# install_part() should fail while 1 part is missing
	var early_adv: bool = dev.install_part()
	err += _assert(not early_adv, "install_part() returns false when components still missing")
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "State remains DISASSEMBLED")

	# Install second part
	var c2_res: bool = dev.try_install_component(paste)
	err += _assert(c2_res, "Thermal paste installed successfully")
	err += _assert(dev.installed_components.size() == 2, "installed_components size is 2")
	err += _assert(dev.get_missing_components().is_empty(), "0 missing components remaining")

	# install_part() should now succeed
	var full_adv: bool = dev.install_part()
	err += _assert(full_adv, "install_part() returns true when all components installed")
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "State advanced to PART_REPLACED")

	dev.queue_free()
	return err


## 2. Test Workbench multi-fault end-to-end with visual slots and wrong-part rejection
func test_workbench_multi_fault_end_to_end() -> int:
	print("\n[2] Testing Workbench multi-fault end-to-end flow with slot labels...")
	var err: int = 0

	var bench_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var bench: WorkbenchStation = bench_scene.instantiate() as WorkbenchStation
	add_child(bench)

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	var laptop := Device.new()
	add_child(laptop)
	laptop.initialize(laptop_data, fault)
	laptop.diagnose()

	var player: PlayerCharacter = _create_test_player(0)

	# Place laptop on workbench
	player.carry_system.pick_up(laptop)
	bench._on_interacted(player)
	err += _assert(bench.placed_device == laptop, "Laptop placed on workbench")

	# Disassemble
	bench._start_disassembly()
	bench._complete_processing()
	err += _assert(laptop.current_repair_state == RepairState.State.DISASSEMBLED, "Laptop is DISASSEMBLED")

	# Verify workbench label shows multi-fault component slots (○ for missing)
	err += _assert(bench.station_label != null, "Workbench has station_label")
	if bench.station_label:
		var txt: String = bench.station_label.text
		err += _assert(txt.contains("○"), "Workbench label shows ○ for missing parts initially")
		err += _assert(txt.contains("Laptop Fan"), "Workbench label lists Laptop Fan")
		err += _assert(txt.contains("Thermal Paste"), "Workbench label lists Thermal Paste")

	# Player brings wrong part (GPU)
	var wrong_part: Carriable = _create_component_carriable("gpu", "GPU Card")
	player.carry_system.pick_up(wrong_part)
	var is_valid_wrong: bool = bench._is_valid_replacement_part(laptop, wrong_part)
	err += _assert(not is_valid_wrong, "_is_valid_replacement_part rejects GPU for laptop overheating")

	bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Wrong part was NOT consumed")
	err += _assert(laptop.installed_components.is_empty(), "No parts installed in laptop yet")
	player.carry_system.drop_item()
	wrong_part.queue_free()

	# Player brings first correct part: Laptop Fan
	var fan_part: Carriable = _create_component_carriable("laptop_fan", "Laptop Fan")
	player.carry_system.pick_up(fan_part)
	err += _assert(bench._is_valid_replacement_part(laptop, fan_part), "_is_valid_replacement_part accepts Laptop Fan")
	err += _assert(bench.get_interaction_prompt(player) == "Install Laptop Fan", "Prompt is 'Install Laptop Fan'")

	bench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Cooling fan consumed from player")
	err += _assert(laptop.installed_components.size() == 1, "Cooling fan registered as installed on laptop")
	err += _assert(laptop.current_repair_state == RepairState.State.DISASSEMBLED, "Laptop remains DISASSEMBLED awaiting thermal paste")

	# Check workbench label now shows ✓ for Fan and ○ for Paste
	if bench.station_label:
		var updated_txt: String = bench.station_label.text
		err += _assert(updated_txt.contains("✓ Laptop Fan"), "Workbench label shows '✓ Laptop Fan'")
		err += _assert(updated_txt.contains("○ Thermal Paste"), "Workbench label shows '○ Thermal Paste'")

	# Player brings a second Laptop Fan (duplicate) -> should be rejected!
	var dup_fan_part: Carriable = _create_component_carriable("laptop_fan", "Laptop Fan")
	player.carry_system.pick_up(dup_fan_part)
	var is_dup_valid: bool = bench._is_valid_replacement_part(laptop, dup_fan_part)
	err += _assert(not is_dup_valid, "Workbench rejects already-installed Laptop Fan")
	err += _assert(bench.get_interaction_prompt(player) == "Wrong Replacement Part", "Prompt is 'Wrong Replacement Part' for duplicate part")
	bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Duplicate fan was NOT consumed")
	err += _assert(laptop.installed_components.size() == 1, "Laptop still has exactly 1 installed component (fan preserved)")
	player.carry_system.drop_item()
	dup_fan_part.queue_free()

	# Player empty hands prompt: shows remaining needed part
	var prompt_empty: String = bench.get_interaction_prompt(player)
	err += _assert(prompt_empty == "Needs: Thermal Paste", "Empty hands prompt shows 'Needs: Thermal Paste' (got: '%s')" % prompt_empty)

	# Player brings second correct part: Thermal Paste
	var paste_part: Carriable = _create_component_carriable("thermal_paste", "Thermal Paste")
	player.carry_system.pick_up(paste_part)
	err += _assert(bench._is_valid_replacement_part(laptop, paste_part), "Thermal Paste is accepted")
	err += _assert(bench.get_interaction_prompt(player) == "Install Thermal Paste", "Prompt is 'Install Thermal Paste'")

	bench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Thermal paste consumed from player")
	err += _assert(laptop.installed_components.size() == 2, "Laptop now has 2 installed components")
	err += _assert(laptop.current_repair_state == RepairState.State.PART_REPLACED, "Laptop advanced to PART_REPLACED")

	# Reassemble device on workbench
	bench._try_reassemble(player)
	bench._complete_processing()
	err += _assert(laptop.current_repair_state == RepairState.State.REASSEMBLED, "Laptop reached REASSEMBLED")

	# Remove device from workbench via interaction -> resets label
	bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up reassembled laptop")
	if bench.station_label:
		err += _assert(bench.station_label.text == "WORKBENCH", "Workbench label reset to WORKBENCH on device pickup")

	player.carry_system.drop_item()
	laptop.queue_free()
	player.queue_free()
	bench.queue_free()
	return err


## 3. Test Desktop PC 3-component multi-fault flow (Dead Motherboard)
func test_desktop_dead_motherboard_3_component_flow() -> int:
	print("\n[3] Testing Desktop Dead Motherboard 3-component flow on Workbench...")
	var err: int = 0

	var bench_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var bench: WorkbenchStation = bench_scene.instantiate() as WorkbenchStation
	add_child(bench)

	var pc_data: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	var mobo_fault: FaultData = pc_data.get_fault_by_id("desktop_dead_motherboard")
	var pc := Device.new()
	add_child(pc)
	pc.initialize(pc_data, mobo_fault)
	pc.diagnose()

	var player: PlayerCharacter = _create_test_player(0)

	# Place directly on workbench for pipeline testing
	bench.accept_device(pc)
	bench._start_disassembly()
	bench._complete_processing()
	err += _assert(pc.current_repair_state == RepairState.State.DISASSEMBLED, "Desktop PC disassembled")

	# Install mobo
	var mobo_part: Carriable = _create_component_carriable("motherboard", "Motherboard")
	player.carry_system.pick_up(mobo_part)
	bench._on_interacted(player)
	err += _assert(pc.installed_components.size() == 1, "1 component installed (mobo)")
	err += _assert(pc.current_repair_state == RepairState.State.DISASSEMBLED, "State still DISASSEMBLED after 1/3")

	# Install gpu
	var gpu_part: Carriable = _create_component_carriable("gpu", "GPU")
	player.carry_system.pick_up(gpu_part)
	bench._on_interacted(player)
	err += _assert(pc.installed_components.size() == 2, "2 components installed (mobo + gpu)")
	err += _assert(pc.current_repair_state == RepairState.State.DISASSEMBLED, "State still DISASSEMBLED after 2/3")

	# Install ram
	var ram_part: Carriable = _create_component_carriable("desktop_ram", "RAM")
	player.carry_system.pick_up(ram_part)
	bench._on_interacted(player)
	err += _assert(pc.installed_components.size() == 3, "All 3 components installed")
	err += _assert(pc.current_repair_state == RepairState.State.PART_REPLACED, "Desktop PC advanced to PART_REPLACED")

	bench.queue_free()
	pc.queue_free()
	player.queue_free()
	return err


## 4. Test Diagnostic Bench multi-fault reveal and display tags
func test_diagnostic_bench_multi_fault_reveal() -> int:
	print("\n[4] Testing Diagnostic Bench multi-fault reveal with display tags...")
	var err: int = 0

	var diag_scene: PackedScene = load("res://scenes/stations/DiagnosticBench.tscn")
	var diag_bench: DiagnosticBench = diag_scene.instantiate() as DiagnosticBench
	add_child(diag_bench)

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	var laptop := Device.new()
	add_child(laptop)
	laptop.initialize(laptop_data, fault)

	var player: PlayerCharacter = _create_test_player(0)

	# Place on diagnostic bench
	player.carry_system.pick_up(laptop)
	diag_bench._on_interacted(player)
	err += _assert(diag_bench.placed_device == laptop, "Laptop placed on diagnostic bench")
	err += _assert(diag_bench._is_processing, "Diagnostic bench started processing")

	var bus_revealed := [false, "", ""]
	var on_reveal := func(dev_name: String, f_name: String) -> void:
		bus_revealed[0] = true
		bus_revealed[1] = dev_name
		bus_revealed[2] = f_name
	SignalBus.diagnosis_revealed.connect(on_reveal)

	# Finish diagnosis
	diag_bench._complete_processing()
	err += _assert(laptop.is_diagnosed, "Laptop is marked diagnosed")
	err += _assert(laptop.current_repair_state == RepairState.State.DIAGNOSED, "State is DIAGNOSED")
	err += _assert(bus_revealed[0], "SignalBus.diagnosis_revealed was emitted")
	err += _assert(bus_revealed[1] == "Laptop", "Signal emitted with device name 'Laptop'")

	# Check diagnostic bench visual labels
	if diag_bench.station_label:
		var st_txt: String = diag_bench.station_label.text
		err += _assert(st_txt.contains("Overheating"), "Station label displays fault name")
		err += _assert(st_txt.contains("fan") and st_txt.contains("thermal_paste"), "Station label displays multi-fault tags")

	# Pick up diagnosed laptop -> diagnostic bench label resets
	diag_bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up diagnosed laptop")
	if diag_bench.station_label:
		err += _assert(diag_bench.station_label.text == "DIAGNOSTIC BENCH", "Station label reset to DIAGNOSTIC BENCH")

	SignalBus.diagnosis_revealed.disconnect(on_reveal)
	player.carry_system.drop_item()
	laptop.queue_free()
	player.queue_free()
	diag_bench.queue_free()
	return err


## 5. Test HUD multi-fault display for carried item and order rows
func test_hud_multi_fault_display() -> int:
	print("\n[5] Testing HUD multi-fault display for carried items and order panel...")
	var err: int = 0

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)

	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	var laptop := Device.new()
	add_child(laptop)
	laptop.initialize(laptop_data, fault)
	laptop.diagnose()

	var player: PlayerCharacter = _create_test_player(0)
	hud.setup(player, null)

	player.carry_system.pick_up(laptop)
	hud._update_carried_item()

	err += _assert(hud.carried_item_name != null, "HUD carried_item_name label exists")
	if hud.carried_item_name:
		var txt: String = hud.carried_item_name.text
		err += _assert(txt.contains("Laptop"), "Carried item shows 'Laptop'")
		err += _assert(txt.contains("DIAGNOSED"), "Carried item shows 'DIAGNOSED'")
		err += _assert(txt.contains("Overheating"), "Carried item shows fault name")
		err += _assert(txt.contains("fan") and txt.contains("thermal_paste"), "Carried item shows multi-fault display tags")

	player.carry_system.drop_item()
	laptop.queue_free()
	player.queue_free()
	hud.queue_free()
	return err


## 6. Test Phone single-fault regression on Workbench
func test_single_fault_regression_on_workbench() -> int:
	print("\n[6] Testing Single-Fault Phone regression on updated Workbench...")
	var err: int = 0

	var bench_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var bench: WorkbenchStation = bench_scene.instantiate() as WorkbenchStation
	add_child(bench)

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	var phone_fault: FaultData = load("res://resources/faults/phone_cracked_screen.tres") as FaultData
	var phone := Device.new()
	add_child(phone)
	phone.initialize(phone_data, phone_fault)
	phone.diagnose()

	var player: PlayerCharacter = _create_test_player(0)

	player.carry_system.pick_up(phone)
	bench._on_interacted(player)
	bench._start_disassembly()
	bench._complete_processing()
	err += _assert(phone.current_repair_state == RepairState.State.DISASSEMBLED, "Phone is DISASSEMBLED")

	# Install phone screen (screen.tres)
	var screen_part: Carriable = _create_component_carriable("screen", "Screen")
	player.carry_system.pick_up(screen_part)
	err += _assert(bench._is_valid_replacement_part(phone, screen_part), "Phone screen is valid replacement")
	bench._on_interacted(player)

	err += _assert(phone.installed_components.size() == 1, "Phone has 1 component installed")
	err += _assert(phone.current_repair_state == RepairState.State.PART_REPLACED, "Phone advanced to PART_REPLACED directly on single fault")

	bench._try_reassemble(player)
	bench._complete_processing()
	err += _assert(phone.current_repair_state == RepairState.State.REASSEMBLED, "Phone reassembled")

	bench.queue_free()
	phone.queue_free()
	player.queue_free()
	return err


func _create_test_player(p_idx: int = 0) -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	player.player_index = p_idx
	player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED
	add_child(player)
	player._apply_player_color()
	return player


func _create_component_carriable(comp_id: String, comp_name: String) -> Carriable:
	var item := Carriable.new()
	item.item_type = "part"
	item.item_name = comp_name
	var comp: ComponentData = load("res://resources/components/%s.tres" % comp_id) as ComponentData
	if comp:
		item.set_meta("component_data", comp)
	add_child(item)
	return item
