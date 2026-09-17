extends Node

## Test suite for Phase 1E: Repair Pipeline
## Tests end-to-end device state progression across all stations,
## workbench multi-step logic, wrong-station prevention,
## fault-based part dispensing, and processing feedback.

const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT: String = "res://resources/faults/phone_cracked_screen.tres"
const DEAD_BATTERY_FAULT: String = "res://resources/faults/phone_dead_battery.tres"
const SOFTWARE_CRASH_FAULT: String = "res://resources/faults/phone_software_crash.tres"
const SCREEN_COMP_PATH: String = "res://resources/components/screen.tres"
const BATTERY_COMP_PATH: String = "res://resources/components/battery.tres"
const OS_INSTALLER_PATH: String = "res://resources/components/os_installer.tres"


func _ready() -> void:
	print("--- RUNNING REPAIR PIPELINE TESTS (PHASE 1E) ---")
	var failures: int = 0

	failures += test_full_pipeline_walkthrough()
	failures += test_wrong_station_prevention()
	failures += test_workbench_multi_step_and_part_matching()
	failures += test_parts_shelf_fault_matching()
	failures += test_processing_times_and_visual_wobble()

	print("--- REPAIR PIPELINE TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL REPAIR PIPELINE TESTS PASSED SUCCESSFULLY ---")
		get_tree().quit(0)
	else:
		printerr("Repair pipeline tests FAILED with %d error(s)." % failures)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_test_player() -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	add_child(player)
	return player


func _create_phone_device(fault_path: String = CRACKED_SCREEN_FAULT) -> Device:
	var dev_scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var dev: Device = dev_scene.instantiate()
	var dev_data: DeviceData = load(PHONE_DATA_PATH)
	var fault: FaultData = load(fault_path)
	dev.initialize(dev_data, fault)
	add_child(dev)
	return dev


## Step 1 to 11 full pipeline walkthrough
func test_full_pipeline_walkthrough() -> int:
	print("Testing Full Pipeline Walkthrough (RECEIVED -> DELIVERED)...")
	var err: int = 0

	var reception: ReceptionDesk = load("res://scenes/stations/ReceptionDesk.tscn").instantiate()
	var diagnostic: DiagnosticBench = load("res://scenes/stations/DiagnosticBench.tscn").instantiate()
	var workbench: WorkbenchStation = load("res://scenes/stations/WorkbenchStation.tscn").instantiate()
	var shelf: PartsShelf = load("res://scenes/stations/PartsShelf.tscn").instantiate()
	var software: SoftwareStation = load("res://scenes/stations/SoftwareStation.tscn").instantiate()
	var delivery: DeliveryCounter = load("res://scenes/stations/DeliveryCounter.tscn").instantiate()

	add_child(reception)
	add_child(diagnostic)
	add_child(workbench)
	add_child(shelf)
	add_child(software)
	add_child(delivery)

	var player := _create_test_player()
	var phone := _create_phone_device(CRACKED_SCREEN_FAULT)

	# Step 1: Order spawns device on ReceptionDesk (state: RECEIVED)
	reception.spawn_incoming_device(phone)
	err += _assert(phone.current_repair_state == RepairState.State.RECEIVED, "Step 1: Phone on ReceptionDesk in RECEIVED state")
	err += _assert(reception.has_device(), "Step 1: ReceptionDesk has device")

	# Step 2: Player picks up device from ReceptionDesk
	err += _assert(reception.can_player_interact(player), "Step 2: Player can interact with ReceptionDesk")
	err += _assert(reception.get_interaction_prompt(player) == "Pick Up Device", "Step 2: Prompt is 'Pick Up Device'")
	reception._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Step 2: Player carries RECEIVED phone")
	err += _assert(not reception.has_device(), "Step 2: ReceptionDesk is now empty")

	# Step 3: Player carries to Diagnostic Bench and places it
	err += _assert(diagnostic.can_player_interact(player), "Step 3: Player can place phone on Diagnostic Bench")
	err += _assert(diagnostic.get_interaction_prompt(player) == "Diagnose Device", "Step 3: Prompt is 'Diagnose Device'")
	diagnostic._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Step 3: Player placed phone on bench")
	err += _assert(diagnostic.placed_device == phone, "Step 3: Bench holds phone")
	err += _assert(diagnostic.current_state == BaseStation.StationState.PROCESSING, "Step 3: Diagnostic bench starts processing")

	# Step 4: Diagnosis completes (2s)
	diagnostic._physics_process(diagnostic.diagnosis_time + 0.1)
	err += _assert(diagnostic.current_state == BaseStation.StationState.COMPLETE, "Step 4: Diagnostic bench processing COMPLETE")
	err += _assert(phone.is_diagnosed, "Step 4: Phone is diagnosed")
	err += _assert(phone.current_repair_state == RepairState.State.DIAGNOSED, "Step 4: Phone state advanced to DIAGNOSED")
	err += _assert(phone.assigned_fault.fault_id == "phone_cracked_screen", "Step 4: Fault revealed: phone_cracked_screen")

	# Step 5: Player picks up diagnosed phone from Diagnostic Bench
	err += _assert(diagnostic.can_player_interact(player), "Step 5: Player can pick up diagnosed phone")
	err += _assert(diagnostic.get_interaction_prompt(player) == "Pick Up Diagnosed Device", "Step 5: Prompt is 'Pick Up Diagnosed Device'")
	diagnostic._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Step 5: Player is carrying diagnosed phone")
	err += _assert(diagnostic.placed_device == null, "Step 5: Diagnostic bench is empty")

	# Step 6: Player places diagnosed phone on Workbench -> auto-starts disassembly
	err += _assert(workbench.can_player_interact(player), "Step 6: Player can place phone on Workbench")
	err += _assert(workbench.get_interaction_prompt(player) == "Place Device on Workbench", "Step 6: Prompt is 'Place Device on Workbench'")
	workbench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Step 6: Phone placed on workbench")
	err += _assert(workbench.placed_device == phone, "Step 6: Workbench holds phone")
	err += _assert(workbench.current_state == BaseStation.StationState.PROCESSING, "Step 6: Disassembly processing auto-started")

	# Step 7: Disassembly completes (2s) -> phone is DISASSEMBLED, bench remains OCCUPIED
	workbench._physics_process(workbench.disassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.DISASSEMBLED, "Step 7: Phone state advanced to DISASSEMBLED")
	err += _assert(workbench.current_state == BaseStation.StationState.OCCUPIED, "Step 7: Workbench remains OCCUPIED waiting for part")
	err += _assert(not workbench.can_player_interact(player), "Step 7: Empty-handed player cannot interact with disassembled device")
	err += _assert(workbench.get_interaction_prompt(player) == "Need Replacement Part", "Step 7: Prompt is 'Need Replacement Part'")

	# Step 8: Player goes to Parts Shelf and takes matching part
	err += _assert(shelf.can_player_interact(player), "Step 8: Player can take part from shelf")
	err += _assert(shelf.get_interaction_prompt(player) == "Take Screen", "Step 8: Shelf prompt specifies 'Take Screen'")
	shelf._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Step 8: Player picked up part")
	var part: Carriable = player.carry_system.get_held_item()
	err += _assert(part != null and part.item_type == "part", "Step 8: Held item is a part")
	var comp: ComponentData = part.get_meta("component_data", null) as ComponentData
	err += _assert(comp != null and comp.component_id == "phone_screen", "Step 8: Dispensed part is phone_screen component")

	# Step 9: Player carries Screen part to Workbench -> installs part
	err += _assert(workbench.can_player_interact(player), "Step 9: Player can install screen on workbench")
	err += _assert(workbench.get_interaction_prompt(player) == "Install Screen", "Step 9: Prompt is 'Install Screen'")
	workbench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Step 9: Part consumed from player carry system")
	err += _assert(phone.current_repair_state == RepairState.State.PART_REPLACED, "Step 9: Phone state advanced to PART_REPLACED")
	err += _assert(phone.installed_component == comp, "Step 9: Phone installed_component matches Screen")

	# Step 10: Player interacts with Workbench again to reassemble
	err += _assert(workbench.can_player_interact(player), "Step 10: Player can interact to reassemble")
	err += _assert(workbench.get_interaction_prompt(player) == "Reassemble Device", "Step 10: Prompt is 'Reassemble Device'")
	workbench._on_interacted(player)
	err += _assert(workbench.current_state == BaseStation.StationState.PROCESSING, "Step 10: Reassembly processing started")

	# Step 11: Reassembly completes (2s) -> phone is REASSEMBLED, bench is COMPLETE
	workbench._physics_process(workbench.reassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.REASSEMBLED, "Step 11: Phone state advanced to REASSEMBLED")
	err += _assert(workbench.current_state == BaseStation.StationState.COMPLETE, "Step 11: Workbench reaches COMPLETE state")

	# Step 12: Player picks up reassembled phone from Workbench
	err += _assert(workbench.can_player_interact(player), "Step 12: Player can pick up reassembled phone")
	err += _assert(workbench.get_interaction_prompt(player) == "Pick Up Reassembled Device", "Step 12: Prompt is 'Pick Up Reassembled Device'")
	workbench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Step 12: Player is carrying reassembled phone")
	err += _assert(workbench.placed_device == null, "Step 12: Workbench is empty")

	# Step 13: Player carries to Software Station and places it
	err += _assert(software.can_player_interact(player), "Step 13: Player can place phone on Software Station")
	err += _assert(software.get_interaction_prompt(player) == "Install Software", "Step 13: Prompt is 'Install Software'")
	software._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Step 13: Phone placed on software station")
	err += _assert(software.placed_device == phone, "Step 13: Software station holds phone")
	err += _assert(software.current_state == BaseStation.StationState.PROCESSING, "Step 13: Software installation starts")

	# Step 14: Software completes (2.5s) -> transitions through SOFTWARE_INSTALLED to TESTED
	software._physics_process(software.software_install_time + 0.1)
	err += _assert(software.current_state == BaseStation.StationState.COMPLETE, "Step 14: Software station reaches COMPLETE state")
	err += _assert(phone.current_repair_state == RepairState.State.TESTED, "Step 14: Phone state advanced to TESTED")

	# Step 15: Player picks up tested phone
	err += _assert(software.can_player_interact(player), "Step 15: Player can pick up tested phone")
	err += _assert(software.get_interaction_prompt(player) == "Pick Up Tested Device", "Step 15: Prompt is 'Pick Up Tested Device'")
	software._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Step 15: Player carries tested phone")
	err += _assert(software.placed_device == null, "Step 15: Software station is empty")

	# Step 16: Player carries to Delivery Counter and delivers
	var signal_received: Array[bool] = [false]
	var on_device_repaired = func(_name: String) -> void:
		signal_received[0] = true
	SignalBus.device_repaired.connect(on_device_repaired)

	err += _assert(delivery.can_player_interact(player), "Step 16: Player can deliver tested phone")
	err += _assert(delivery.get_interaction_prompt(player) == "Deliver Repaired Device", "Step 16: Prompt is 'Deliver Repaired Device'")
	delivery._on_interacted(player)

	err += _assert(not player.carry_system.is_carrying(), "Step 16: Phone delivered from player hands")
	err += _assert(phone.current_repair_state == RepairState.State.DELIVERED, "Step 16: Phone state is DELIVERED")
	err += _assert(delivery.current_state == BaseStation.StationState.COMPLETE, "Step 16: DeliveryCounter is COMPLETE")
	err += _assert(signal_received[0], "Step 16: SignalBus.device_repaired emitted")

	SignalBus.device_repaired.disconnect(on_device_repaired)

	player.queue_free()
	phone.queue_free()
	reception.queue_free()
	diagnostic.queue_free()
	workbench.queue_free()
	shelf.queue_free()
	software.queue_free()
	delivery.queue_free()
	return err


## Tests wrong-station prevention across all stations and device states
func test_wrong_station_prevention() -> int:
	print("Testing Wrong-Station Prevention (rejection of invalid device states and items)...")
	var err: int = 0

	var reception: ReceptionDesk = load("res://scenes/stations/ReceptionDesk.tscn").instantiate()
	var diagnostic: DiagnosticBench = load("res://scenes/stations/DiagnosticBench.tscn").instantiate()
	var workbench: WorkbenchStation = load("res://scenes/stations/WorkbenchStation.tscn").instantiate()
	var shelf: PartsShelf = load("res://scenes/stations/PartsShelf.tscn").instantiate()
	var software: SoftwareStation = load("res://scenes/stations/SoftwareStation.tscn").instantiate()
	var delivery: DeliveryCounter = load("res://scenes/stations/DeliveryCounter.tscn").instantiate()

	add_child(reception)
	add_child(diagnostic)
	add_child(workbench)
	add_child(shelf)
	add_child(software)
	add_child(delivery)

	var player := _create_test_player()
	var phone := _create_phone_device(CRACKED_SCREEN_FAULT)

	# 1. Player carrying RECEIVED phone cannot place it on Workbench, Software, or Delivery
	player.carry_system.pick_up(phone)
	err += _assert(not reception.can_accept_device(phone), "ReceptionDesk can_accept_device is false")
	err += _assert(not reception.can_player_interact(player), "ReceptionDesk rejects placing device")
	err += _assert(not workbench.can_accept_device(phone), "Workbench rejects RECEIVED device")
	err += _assert(not workbench.can_player_interact(player), "Workbench can_player_interact is false for RECEIVED device")
	err += _assert(not software.can_accept_device(phone), "Software station rejects RECEIVED device")
	err += _assert(not software.can_player_interact(player), "Software station can_player_interact is false for RECEIVED device")
	err += _assert(not delivery.can_accept_device(phone), "Delivery counter rejects RECEIVED device")
	err += _assert(not delivery.can_player_interact(player), "Delivery counter can_player_interact is false for RECEIVED device")
	err += _assert(not shelf.can_accept_device(phone), "PartsShelf can_accept_device is always false")

	# 2. Advance phone to DIAGNOSED
	phone.current_repair_state = RepairState.State.DIAGNOSED
	err += _assert(not diagnostic.can_accept_device(phone), "Diagnostic bench rejects DIAGNOSED device")
	err += _assert(not diagnostic.can_player_interact(player), "Diagnostic bench can_player_interact is false for DIAGNOSED device")
	err += _assert(not software.can_accept_device(phone), "Software station rejects DIAGNOSED device")
	err += _assert(not delivery.can_accept_device(phone), "Delivery counter rejects DIAGNOSED device")
	err += _assert(workbench.can_accept_device(phone), "Workbench accepts DIAGNOSED device")

	# 3. Advance phone to DISASSEMBLED
	phone.current_repair_state = RepairState.State.DISASSEMBLED
	err += _assert(not diagnostic.can_accept_device(phone), "Diagnostic bench rejects DISASSEMBLED device")
	err += _assert(not software.can_accept_device(phone), "Software station rejects DISASSEMBLED device")
	err += _assert(not delivery.can_accept_device(phone), "Delivery counter rejects DISASSEMBLED device")

	# 4. Advance phone to REASSEMBLED
	phone.current_repair_state = RepairState.State.REASSEMBLED
	err += _assert(not diagnostic.can_accept_device(phone), "Diagnostic bench rejects REASSEMBLED device")
	err += _assert(not workbench.can_accept_device(phone), "Workbench rejects REASSEMBLED device placement")
	err += _assert(not delivery.can_accept_device(phone), "Delivery counter rejects REASSEMBLED device")
	err += _assert(software.can_accept_device(phone), "Software station accepts REASSEMBLED device")

	# 5. Advance phone to TESTED
	phone.current_repair_state = RepairState.State.TESTED
	err += _assert(not diagnostic.can_accept_device(phone), "Diagnostic bench rejects TESTED device")
	err += _assert(not workbench.can_accept_device(phone), "Workbench rejects TESTED device")
	err += _assert(not software.can_accept_device(phone), "Software station rejects TESTED device")
	err += _assert(delivery.can_accept_device(phone), "Delivery counter accepts TESTED device")

	# Drop phone to free player hands
	player.carry_system.drop_item()

	# 6. Test carrying a part
	var part: Carriable = Carriable.new()
	part.item_name = "Screen"
	part.item_type = "part"
	add_child(part)
	player.carry_system.pick_up(part)

	err += _assert(not diagnostic.can_accept_device(part), "Diagnostic bench rejects part")
	err += _assert(not diagnostic.can_player_interact(player), "Diagnostic bench can_player_interact is false for part")
	err += _assert(not workbench.can_accept_device(part), "Empty workbench rejects part placement")
	err += _assert(not workbench.can_player_interact(player), "Empty workbench can_player_interact is false for part")
	err += _assert(not software.can_accept_device(part), "Software station rejects part")
	err += _assert(not delivery.can_accept_device(part), "Delivery counter rejects part")
	err += _assert(not shelf.can_player_interact(player), "Parts shelf rejects player when hands are full")

	player.queue_free()
	phone.queue_free()
	part.queue_free()
	reception.queue_free()
	diagnostic.queue_free()
	workbench.queue_free()
	shelf.queue_free()
	software.queue_free()
	delivery.queue_free()
	return err


## Tests workbench multi-step behavior, part rejection on wrong component, and reassembly
func test_workbench_multi_step_and_part_matching() -> int:
	print("Testing Workbench Multi-Step Logic & Component Matching...")
	var err: int = 0

	var workbench: WorkbenchStation = load("res://scenes/stations/WorkbenchStation.tscn").instantiate()
	add_child(workbench)

	var player := _create_test_player()
	# Phone with cracked screen requires phone_screen component
	var phone := _create_phone_device(CRACKED_SCREEN_FAULT)
	phone.current_repair_state = RepairState.State.DIAGNOSED

	# 1. Place diagnosed phone on workbench
	player.carry_system.pick_up(phone)
	workbench._on_interacted(player)
	err += _assert(workbench.placed_device == phone, "Phone placed on workbench")
	err += _assert(workbench.current_state == BaseStation.StationState.PROCESSING, "Workbench auto-started disassembly")

	# 2. Complete disassembly
	workbench._physics_process(workbench.disassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.DISASSEMBLED, "Phone state is DISASSEMBLED")
	err += _assert(workbench.current_state == BaseStation.StationState.OCCUPIED, "Workbench is OCCUPIED awaiting component")

	# 3. Create wrong part (Battery) and attempt installation
	var wrong_comp: ComponentData = load(BATTERY_COMP_PATH)
	var wrong_part := Carriable.new()
	wrong_part.item_name = wrong_comp.component_name
	wrong_part.item_type = "part"
	wrong_part.set_meta("component_data", wrong_comp)
	add_child(wrong_part)

	player.carry_system.pick_up(wrong_part)
	err += _assert(not workbench.can_player_interact(player), "Workbench rejects installing wrong component")
	err += _assert(workbench.get_interaction_prompt(player) == "Wrong Replacement Part", "Prompt indicates wrong replacement part")

	# Attempt interact with wrong part
	workbench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == wrong_part, "Wrong part was NOT consumed")
	err += _assert(phone.current_repair_state == RepairState.State.DISASSEMBLED, "Phone remains in DISASSEMBLED state")

	# Drop wrong part
	player.carry_system.drop_item()
	wrong_part.queue_free()

	# 4. Create correct part (Screen) and install
	var correct_comp: ComponentData = load(SCREEN_COMP_PATH)
	var correct_part := Carriable.new()
	correct_part.item_name = correct_comp.component_name
	correct_part.item_type = "part"
	correct_part.set_meta("component_data", correct_comp)
	add_child(correct_part)

	player.carry_system.pick_up(correct_part)
	err += _assert(workbench.can_player_interact(player), "Workbench allows installing correct component")
	err += _assert(workbench.get_interaction_prompt(player) == "Install Screen", "Prompt is 'Install Screen'")

	workbench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Correct part was consumed")
	err += _assert(phone.current_repair_state == RepairState.State.PART_REPLACED, "Phone advanced to PART_REPLACED")

	# 5. Reassemble device
	err += _assert(workbench.can_player_interact(player), "Player can start reassembly")
	workbench._on_interacted(player)
	err += _assert(workbench.current_state == BaseStation.StationState.PROCESSING, "Workbench reassembly in progress")

	workbench._physics_process(workbench.reassembly_time + 0.1)
	err += _assert(phone.current_repair_state == RepairState.State.REASSEMBLED, "Phone advanced to REASSEMBLED")
	err += _assert(workbench.current_state == BaseStation.StationState.COMPLETE, "Workbench state is COMPLETE")

	# 6. Pick up reassembled device
	err += _assert(workbench.can_player_interact(player), "Player can pick up reassembled device")
	workbench._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == phone, "Player retrieved reassembled phone")
	err += _assert(workbench.current_state == BaseStation.StationState.IDLE, "Workbench returned to IDLE")

	player.queue_free()
	phone.queue_free()
	workbench.queue_free()
	return err


## Tests PartsShelf auto-dispensing matching components based on diagnosed faults
func test_parts_shelf_fault_matching() -> int:
	print("Testing PartsShelf Auto-Dispensing of Diagnosed Components...")
	var err: int = 0

	var shelf: PartsShelf = load("res://scenes/stations/PartsShelf.tscn").instantiate()
	add_child(shelf)

	var player := _create_test_player()

	# Test 1: Phone with Cracked Screen -> Screen dispensed
	var screen_phone := _create_phone_device(CRACKED_SCREEN_FAULT)
	screen_phone.diagnose()
	shelf._on_interacted(player)
	var screen_part: Carriable = player.carry_system.get_held_item()
	err += _assert(screen_part != null, "Part dispensed for cracked screen")
	var comp1: ComponentData = screen_part.get_meta("component_data", null) as ComponentData
	err += _assert(comp1 != null and comp1.component_id == "phone_screen", "Dispensed component is phone_screen")
	player.carry_system.drop_item()
	screen_part.queue_free()
	screen_phone.queue_free()

	# Test 2: Phone with Dead Battery -> Battery dispensed
	var battery_phone := _create_phone_device(DEAD_BATTERY_FAULT)
	battery_phone.diagnose()
	shelf._on_interacted(player)
	var battery_part: Carriable = player.carry_system.get_held_item()
	err += _assert(battery_part != null, "Part dispensed for dead battery")
	var comp2: ComponentData = battery_part.get_meta("component_data", null) as ComponentData
	err += _assert(comp2 != null and comp2.component_id == "phone_battery", "Dispensed component is phone_battery")
	player.carry_system.drop_item()
	battery_part.queue_free()
	battery_phone.queue_free()

	# Test 3: Phone with Software Crash -> OS Installer dispensed
	var crash_phone := _create_phone_device(SOFTWARE_CRASH_FAULT)
	crash_phone.diagnose()
	shelf._on_interacted(player)
	var crash_part: Carriable = player.carry_system.get_held_item()
	err += _assert(crash_part != null, "Part dispensed for software crash")
	var comp3: ComponentData = crash_part.get_meta("component_data", null) as ComponentData
	err += _assert(comp3 != null and comp3.component_id == "os_installer", "Dispensed component is os_installer")
	player.carry_system.drop_item()
	crash_part.queue_free()
	crash_phone.queue_free()

	player.queue_free()
	shelf.queue_free()
	return err


## Tests station processing times and wobble visual feedback
func test_processing_times_and_visual_wobble() -> int:
	print("Testing Station Processing Times & Visual Wobble Feedback...")
	var err: int = 0

	var diagnostic: DiagnosticBench = load("res://scenes/stations/DiagnosticBench.tscn").instantiate()
	add_child(diagnostic)

	var phone := _create_phone_device(CRACKED_SCREEN_FAULT)
	diagnostic.accept_device(phone)
	diagnostic.start_processing()

	err += _assert(diagnostic.current_state == BaseStation.StationState.PROCESSING, "Station is PROCESSING")

	# Advance physics by 0.5s and check wobble offset
	diagnostic._physics_process(0.5)
	err += _assert(phone.position.y != 0.0, "Placed device wobbles during processing (Y: %f)" % phone.position.y)

	# Complete processing and check wobble reset
	diagnostic._physics_process(diagnostic.diagnosis_time)
	err += _assert(diagnostic.current_state == BaseStation.StationState.COMPLETE, "Station is COMPLETE")
	err += _assert(phone.position == Vector3.ZERO, "Placed device position resets to ZERO on completion")

	phone.queue_free()
	diagnostic.queue_free()
	return err
