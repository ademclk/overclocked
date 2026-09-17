extends Node

## Test suite for Device, RepairState, DeviceData, FaultData, and ComponentData.


func _ready() -> void:
	print("--- RUNNING DEVICE & FAULT TESTS ---")
	var failures: int = 0

	failures += test_repair_state_machine()
	failures += test_component_resources()
	failures += test_fault_resources()
	failures += test_device_data_resource()
	failures += test_device_scene_instantiation()
	failures += test_device_repair_lifecycle()
	failures += test_device_component_installation()
	failures += test_device_ground_pickup()

	print("--- DEVICE & FAULT TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL DEVICE & FAULT TESTS PASSED SUCCESSFULLY ---")
		get_tree().quit(0)
	else:
		printerr("Device & Fault tests FAILED with %d error(s)." % failures)
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


func test_repair_state_machine() -> int:
	print("Testing RepairState enum and transitions...")
	var err: int = 0

	# Verify legal transitions
	err += _assert(
		RepairState.can_transition(RepairState.State.RECEIVED, RepairState.State.DIAGNOSED),
		"RECEIVED -> DIAGNOSED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.DIAGNOSED, RepairState.State.DISASSEMBLED),
		"DIAGNOSED -> DISASSEMBLED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.DISASSEMBLED, RepairState.State.PART_REPLACED),
		"DISASSEMBLED -> PART_REPLACED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.PART_REPLACED, RepairState.State.REASSEMBLED),
		"PART_REPLACED -> REASSEMBLED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.REASSEMBLED, RepairState.State.SOFTWARE_INSTALLED),
		"REASSEMBLED -> SOFTWARE_INSTALLED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.SOFTWARE_INSTALLED, RepairState.State.TESTED),
		"SOFTWARE_INSTALLED -> TESTED is allowed"
	)
	err += _assert(
		RepairState.can_transition(RepairState.State.TESTED, RepairState.State.DELIVERED),
		"TESTED -> DELIVERED is allowed"
	)

	# Verify illegal transitions
	err += _assert(
		not RepairState.can_transition(RepairState.State.RECEIVED, RepairState.State.REASSEMBLED),
		"RECEIVED -> REASSEMBLED is rejected"
	)
	err += _assert(
		not RepairState.can_transition(RepairState.State.DIAGNOSED, RepairState.State.DELIVERED),
		"DIAGNOSED -> DELIVERED is rejected"
	)
	err += _assert(
		not RepairState.can_transition(RepairState.State.DELIVERED, RepairState.State.RECEIVED),
		"DELIVERED -> RECEIVED is rejected"
	)

	# String conversions
	err += _assert(RepairState.to_string_name(RepairState.State.RECEIVED) == "RECEIVED", "to_string_name RECEIVED")
	err += _assert(RepairState.to_string_name(RepairState.State.TESTED) == "TESTED", "to_string_name TESTED")
	err += _assert(RepairState.from_string_name("DIAGNOSED") == RepairState.State.DIAGNOSED, "from_string_name DIAGNOSED")
	err += _assert(RepairState.from_string_name("software_installed") == RepairState.State.SOFTWARE_INSTALLED, "from_string_name software_installed case-insensitive")

	# Station requirements
	err += _assert(RepairState.get_required_station(RepairState.State.RECEIVED) == "diagnostic_bench", "RECEIVED station")
	err += _assert(RepairState.get_required_station(RepairState.State.DIAGNOSED) == "workbench", "DIAGNOSED station")
	err += _assert(RepairState.get_required_station(RepairState.State.REASSEMBLED) == "software_station", "REASSEMBLED station")
	err += _assert(RepairState.get_required_station(RepairState.State.TESTED) == "delivery_counter", "TESTED station")

	return err


func test_component_resources() -> int:
	print("Testing component data resources...")
	var err: int = 0

	var paths := {
		"screen": "res://resources/components/screen.tres",
		"battery": "res://resources/components/battery.tres",
		"os_installer": "res://resources/components/os_installer.tres",
	}

	for key: String in paths:
		var comp: ComponentData = load(paths[key]) as ComponentData
		err += _assert(comp != null, "Loaded component resource %s" % key)
		if comp:
			err += _assert(comp.is_valid(), "Component %s is valid" % key)
			err += _assert(not comp.component_id.is_empty(), "Component %s has non-empty ID" % key)
			err += _assert(not comp.component_name.is_empty(), "Component %s has non-empty name" % key)

	return err


func test_fault_resources() -> int:
	print("Testing fault data resources...")
	var err: int = 0

	var paths := {
		"cracked_screen": "res://resources/faults/phone_cracked_screen.tres",
		"dead_battery": "res://resources/faults/phone_dead_battery.tres",
		"software_crash": "res://resources/faults/phone_software_crash.tres",
	}

	for key: String in paths:
		var fault: FaultData = load(paths[key]) as FaultData
		err += _assert(fault != null, "Loaded fault resource %s" % key)
		if fault:
			err += _assert(fault.is_valid(), "Fault %s is valid" % key)
			err += _assert(fault.broken_component != null, "Fault %s has assigned broken component" % key)
			err += _assert(fault.broken_component.is_valid(), "Fault %s component is valid" % key)
			err += _assert(not fault.symptom_description.is_empty(), "Fault %s has symptom description" % key)

	var sw_fault: FaultData = load(paths["software_crash"]) as FaultData
	if sw_fault:
		err += _assert(sw_fault.requires_software_reinstall == true, "Software crash fault requires software reinstall")

	return err


func test_device_data_resource() -> int:
	print("Testing Phone DeviceData resource...")
	var err: int = 0

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	err += _assert(phone_data != null, "Loaded phone.tres resource")
	if not phone_data:
		return err + 1

	err += _assert(phone_data.is_valid(), "phone.tres is_valid() returns true")
	err += _assert(phone_data.device_name == "Phone", "Phone device_name is 'Phone'")
	err += _assert(phone_data.device_id == "phone", "Phone device_id is 'phone'")
	err += _assert(phone_data.possible_faults.size() == 3, "Phone has exactly 3 possible faults (found %d)" % phone_data.possible_faults.size())

	var rand_fault: FaultData = phone_data.get_random_fault()
	err += _assert(rand_fault != null, "get_random_fault() returns non-null fault")

	var found_screen: FaultData = phone_data.get_fault_by_id("phone_cracked_screen")
	err += _assert(found_screen != null and found_screen.fault_name == "Cracked Screen", "get_fault_by_id retrieves Cracked Screen")

	return err


func test_device_scene_instantiation() -> int:
	print("Testing Device.tscn scene loading and components...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/devices/Device.tscn")
	err += _assert(scene != null, "Device.tscn loads successfully")
	if not scene:
		return err + 1

	var device: Device = scene.instantiate() as Device
	err += _assert(device != null, "Instantiated node is of type Device")
	err += _assert(device is Carriable, "Device inherits Carriable")

	add_child(device)

	err += _assert(device.has_node("DeviceMesh"), "Device has DeviceMesh child")
	err += _assert(device.has_node("InteractionZone"), "Device has InteractionZone child")
	err += _assert(device.has_node("DeviceLabel"), "Device has DeviceLabel child")
	err += _assert(device.current_repair_state == RepairState.State.RECEIVED, "Initial repair state is RECEIVED")
	err += _assert(device.get_repair_state() == "RECEIVED", "get_repair_state() returns 'RECEIVED'")

	device.queue_free()
	return err


func test_device_repair_lifecycle() -> int:
	print("Testing Device repair progression and signal emissions...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var device: Device = scene.instantiate() as Device
	add_child(device)

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	var fault: FaultData = phone_data.possible_faults[0]
	device.initialize(phone_data, fault)

	err += _assert(device.item_name == "Phone", "item_name initialized to 'Phone'")
	err += _assert(device.assigned_fault == fault, "assigned_fault initialized properly")
	err += _assert(device.current_repair_state == RepairState.State.RECEIVED, "State initialized to RECEIVED")

	# Illegal transition test
	var illegal_res: bool = device.advance_state(RepairState.State.REASSEMBLED)
	err += _assert(not illegal_res, "advance_state rejects illegal transition")
	err += _assert(device.current_repair_state == RepairState.State.RECEIVED, "State unchanged after illegal attempt")

	# Diagnosis
	var diag_emitted := [false]
	device.diagnosed.connect(func(_f): diag_emitted[0] = true)
	device.diagnose()

	err += _assert(diag_emitted[0], "diagnosed signal emitted")
	err += _assert(device.is_diagnosed == true, "is_diagnosed is true")
	err += _assert(device.current_repair_state == RepairState.State.DIAGNOSED, "State is DIAGNOSED")

	# Disassembly
	var advanced: bool = device.advance_repair_state()
	err += _assert(advanced and device.current_repair_state == RepairState.State.DISASSEMBLED, "State advanced to DISASSEMBLED")

	# Part replacement
	var installed: bool = device.install_part()
	err += _assert(installed and device.current_repair_state == RepairState.State.PART_REPLACED, "State advanced to PART_REPLACED")

	# Reassembly
	advanced = device.advance_repair_state()
	err += _assert(advanced and device.current_repair_state == RepairState.State.REASSEMBLED, "State advanced to REASSEMBLED")

	# Software install & test
	var sw_installed: bool = device.install_software()
	err += _assert(sw_installed and device.current_repair_state == RepairState.State.TESTED, "install_software() advances to TESTED")

	# Delivery & completion signal
	var completed := [false]
	device.repair_completed.connect(func(): completed[0] = true)
	var delivered: bool = device.deliver()

	err += _assert(delivered and device.current_repair_state == RepairState.State.DELIVERED, "Device delivered")
	err += _assert(completed[0], "repair_completed signal emitted on delivery")

	device.queue_free()
	return err


func test_device_component_installation() -> int:
	print("Testing try_install_component matching logic...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var device: Device = scene.instantiate() as Device
	add_child(device)

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	var screen_fault: FaultData = phone_data.get_fault_by_id("phone_cracked_screen")
	device.initialize(phone_data, screen_fault)

	var correct_comp: ComponentData = load("res://resources/components/screen.tres") as ComponentData
	var wrong_comp: ComponentData = load("res://resources/components/battery.tres") as ComponentData

	# Wrong component should fail
	var wrong_result: bool = device.try_install_component(wrong_comp)
	err += _assert(not wrong_result, "Installing wrong component returns false")
	err += _assert(device.installed_component == null, "installed_component is null after failure")

	# Correct component should succeed
	var correct_result: bool = device.try_install_component(correct_comp)
	err += _assert(correct_result, "Installing correct component returns true")
	err += _assert(device.installed_component == correct_comp, "installed_component holds installed part")

	device.queue_free()
	return err


func test_device_ground_pickup() -> int:
	print("Testing ground pickup via InteractionZone...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var device: Device = scene.instantiate() as Device
	add_child(device)

	var player := _create_test_player()
	err += _assert(device.interaction_zone != null, "Device has InteractionZone")
	err += _assert(device.interaction_zone.is_interactable == true, "InteractionZone is interactable while on ground")

	# Interact with device on ground
	device.interaction_zone.interact(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up device from the ground")
	err += _assert(player.carry_system.get_held_item() == device, "Held item is the device")
	err += _assert(not device.interaction_zone.is_interactable, "InteractionZone disabled while carried")

	# Drop device back to ground
	player.carry_system.drop_item()
	err += _assert(not player.carry_system.is_carrying(), "Player dropped device")
	err += _assert(device.interaction_zone.is_interactable == true, "InteractionZone re-enabled on drop")

	player.queue_free()
	device.queue_free()
	return err
