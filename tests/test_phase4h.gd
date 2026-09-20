extends Node

## Test suite for Phase 4H — OrderManager & Device Database Wiring
## Validates device database registration, tier filtering, weighted selection,
## multi-fault initialization, and WorkshopDebug scene configuration.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4H ORDER MANAGER TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_default_device_database_loading()
	failures += test_tier_filtering()
	failures += test_get_devices_by_tier()
	failures += test_device_weight_and_weighted_pick()
	failures += test_spawn_order_multi_fault_device()
	failures += test_spawn_order_all_device_types()
	failures += test_workshop_debug_scene_wiring()

	print("=========================================================")
	print("--- PHASE 4H TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4H TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4H tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


## 1. Test automatic device database population
func test_default_device_database_loading() -> int:
	print("\n[1] Testing default device database loading...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	err += _assert(om.device_database.size() >= 6, "OrderManager populated with at least 6 devices (got %d)" % om.device_database.size())

	var expected_ids := ["phone", "tablet", "laptop", "game_console", "router", "desktop_pc"]
	for dev_id in expected_ids:
		var dev: DeviceData = om.get_device_by_id(dev_id)
		err += _assert(dev != null, "Device '%s' registered in database" % dev_id)
		if dev:
			err += _assert(dev.is_valid(), "Device '%s' is_valid() == true" % dev_id)

	om.queue_free()
	return err


## 2. Test tier filtering
func test_tier_filtering() -> int:
	print("\n[2] Testing tier filtering logic...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	# Tier 1 only: Phone, Tablet
	om.tier_filter = [1]
	var t1_devices: Array[DeviceData] = om.get_available_devices()
	err += _assert(t1_devices.size() == 2, "Tier [1] returns exactly 2 devices (got %d)" % t1_devices.size())
	var t1_ids: Array[String] = []
	for d in t1_devices:
		t1_ids.append(d.device_id)
	err += _assert("phone" in t1_ids and "tablet" in t1_ids, "Tier [1] contains phone and tablet")

	# Tier 2 only: Laptop, Game Console, Router
	om.tier_filter = [2]
	var t2_devices: Array[DeviceData] = om.get_available_devices()
	err += _assert(t2_devices.size() == 3, "Tier [2] returns exactly 3 devices (got %d)" % t2_devices.size())
	var t2_ids: Array[String] = []
	for d in t2_devices:
		t2_ids.append(d.device_id)
	err += _assert("laptop" in t2_ids and "game_console" in t2_ids and "router" in t2_ids, "Tier [2] contains laptop, console, router")

	# Tier 3 only: Desktop PC
	om.tier_filter = [3]
	var t3_devices: Array[DeviceData] = om.get_available_devices()
	err += _assert(t3_devices.size() == 1, "Tier [3] returns exactly 1 device (got %d)" % t3_devices.size())
	if not t3_devices.is_empty():
		err += _assert(t3_devices[0].device_id == "desktop_pc", "Tier [3] device is desktop_pc")

	# Tier [1, 2] (Default for Phase 4 Workshop Debug): All Tier 1 and 2, excludes Desktop PC
	om.tier_filter = [1, 2]
	var t12_devices: Array[DeviceData] = om.get_available_devices()
	err += _assert(t12_devices.size() == 5, "Tier [1, 2] returns 5 devices (got %d)" % t12_devices.size())
	var t12_ids: Array[String] = []
	for d in t12_devices:
		t12_ids.append(d.device_id)
	err += _assert(not ("desktop_pc" in t12_ids), "Tier [1, 2] excludes desktop_pc")

	# Tier [1, 2, 3]: All 6 devices
	om.tier_filter = [1, 2, 3]
	var all_devices: Array[DeviceData] = om.get_available_devices()
	err += _assert(all_devices.size() == 6, "Tier [1, 2, 3] returns all 6 devices (got %d)" % all_devices.size())

	# Empty tier filter: returns all valid registered devices
	om.tier_filter = []
	var empty_filter_devs: Array[DeviceData] = om.get_available_devices()
	err += _assert(empty_filter_devs.size() == 6, "Empty tier filter returns all 6 devices")

	om.queue_free()
	return err


## 3. Test get_devices_by_tier helper
func test_get_devices_by_tier() -> int:
	print("\n[3] Testing get_devices_by_tier()...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	var tier1 := om.get_devices_by_tier(1)
	err += _assert(tier1.size() == 2, "get_devices_by_tier(1) returns 2 devices")

	var tier2 := om.get_devices_by_tier(2)
	err += _assert(tier2.size() == 3, "get_devices_by_tier(2) returns 3 devices")

	var tier3 := om.get_devices_by_tier(3)
	err += _assert(tier3.size() == 1 and tier3[0].device_id == "desktop_pc", "get_devices_by_tier(3) returns desktop_pc")

	var tier99 := om.get_devices_by_tier(99)
	err += _assert(tier99.is_empty(), "get_devices_by_tier(99) returns empty array")

	om.queue_free()
	return err


## 4. Test device_weight and weighted device picking
func test_device_weight_and_weighted_pick() -> int:
	print("\n[4] Testing device_weight and weighted _pick_device()...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	var desktop: DeviceData = om.get_device_by_id("desktop_pc")
	err += _assert(desktop != null, "desktop_pc exists")
	if desktop:
		err += _assert(desktop.device_weight == 0.5, "desktop_pc has device_weight == 0.5 (got %f)" % desktop.device_weight)

	var phone: DeviceData = om.get_device_by_id("phone")
	if phone:
		err += _assert(phone.device_weight == 1.0, "phone has default device_weight == 1.0 (got %f)" % phone.device_weight)

	# Verify _pick_device() respects tier_filter
	om.tier_filter = [3]
	for i in range(10):
		var picked: DeviceData = om._pick_device()
		if picked == null or picked.device_id != "desktop_pc":
			err += _assert(false, "Pick with tier_filter=[3] picked non-desktop: %s" % (picked.device_id if picked else "null"))
			break
	err += _assert(true, "10 consecutive picks with tier_filter=[3] all returned desktop_pc")

	om.tier_filter = [1]
	for i in range(10):
		var picked: DeviceData = om._pick_device()
		if picked == null or (picked.device_id != "phone" and picked.device_id != "tablet"):
			err += _assert(false, "Pick with tier_filter=[1] picked invalid device: %s" % (picked.device_id if picked else "null"))
			break
	err += _assert(true, "10 consecutive picks with tier_filter=[1] all returned tier 1 devices")

	om.queue_free()
	return err


## 5. Test spawning multi-fault device via OrderManager
func test_spawn_order_multi_fault_device() -> int:
	print("\n[5] Testing spawn_order() with multi-fault device...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	var laptop_data: DeviceData = om.get_device_by_id("laptop")
	err += _assert(laptop_data != null, "Loaded laptop DeviceData")
	var overheat_fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	err += _assert(overheat_fault != null and overheat_fault.is_multi_fault, "Loaded laptop_overheating multi-fault")

	var order: Order = om.spawn_order(laptop_data, overheat_fault)
	err += _assert(order != null, "Order spawned successfully")
	if not order:
		om.queue_free()
		return err + 1

	err += _assert(order.device_instance != null, "Order has device_instance attached")
	var dev: Device = order.device_instance
	err += _assert(dev.device_data == laptop_data, "Device instance device_data matches order")
	err += _assert(dev.assigned_fault == overheat_fault, "Device assigned_fault matches order assigned_fault")
	err += _assert(dev.item_name == "Laptop", "Device item_name is Laptop")

	# Verify multi-fault state on device
	err += _assert(dev.assigned_fault.is_multi_fault, "Device assigned fault is_multi_fault == true")
	var missing: Array[ComponentData] = dev.get_missing_components()
	err += _assert(missing.size() == 2, "Device starts with 2 missing components")

	# Diagnose device
	dev.diagnose()
	err += _assert(dev.is_diagnosed, "Device successfully diagnosed")
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "State is DIAGNOSED")

	# Advance to DISASSEMBLED
	dev.advance_state(RepairState.State.DISASSEMBLED)

	# Install first component (Laptop Fan)
	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	var accepted_fan: bool = dev.try_install_component(fan)
	err += _assert(accepted_fan, "Laptop accepted laptop_fan")
	var install_part_early: bool = dev.install_part()
	err += _assert(not install_part_early, "install_part() returns false when components still missing")
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Still DISASSEMBLED after partial install")

	# Install second component (Thermal Paste)
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	var accepted_paste: bool = dev.try_install_component(paste)
	err += _assert(accepted_paste, "Laptop accepted thermal_paste")
	var install_part_complete: bool = dev.install_part()
	err += _assert(install_part_complete, "install_part() returns true when all components installed")
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Advanced to PART_REPLACED")

	dev.queue_free()
	om.queue_free()
	return err


## 6. Test spawning all device types
func test_spawn_order_all_device_types() -> int:
	print("\n[6] Testing spawn_order() across all 6 device types...")
	var err: int = 0

	var om := OrderManager.new()
	add_child(om)

	var dev_ids := ["phone", "tablet", "laptop", "game_console", "router", "desktop_pc"]
	for dev_id in dev_ids:
		var data: DeviceData = om.get_device_by_id(dev_id)
		err += _assert(data != null, "DeviceData exists for %s" % dev_id)
		if not data:
			continue

		var order: Order = om.spawn_order(data)
		err += _assert(order != null, "Spawned order for %s" % dev_id)
		if order and order.device_instance:
			var dev: Device = order.device_instance
			err += _assert(dev.item_name == data.device_name, "%s device_instance item_name matches" % dev_id)
			err += _assert(dev.device_data == data, "%s device_instance device_data matches" % dev_id)
			err += _assert(order.time_limit == data.base_repair_time, "%s time_limit matches base_repair_time (%f)" % [dev_id, data.base_repair_time])
			dev.queue_free()

	om.queue_free()
	return err


## 7. Test Workshop_Debug scene wiring
func test_workshop_debug_scene_wiring() -> int:
	print("\n[7] Testing Workshop_Debug.tscn OrderManager node configuration...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn") as PackedScene
	err += _assert(scene != null, "Loaded Workshop_Debug.tscn")
	if not scene:
		return err + 1

	var workshop: Node = scene.instantiate()
	add_child(workshop)

	var om: OrderManager = workshop.get_node_or_null("OrderManager") as OrderManager
	err += _assert(om != null, "Workshop_Debug has OrderManager node")
	if om:
		err += _assert(om.device_database.size() == 6, "OrderManager.device_database has 6 registered devices (got %d)" % om.device_database.size())
		err += _assert(om.tier_filter == [1, 2], "OrderManager.tier_filter is [1, 2] by default (got %s)" % str(om.tier_filter))

		var available: Array[DeviceData] = om.get_available_devices()
		err += _assert(available.size() == 5, "OrderManager provides 5 available devices under tier_filter [1, 2] (got %d)" % available.size())

		var has_desktop_available: bool = false
		for d in available:
			if d.device_id == "desktop_pc":
				has_desktop_available = true
		err += _assert(not has_desktop_available, "desktop_pc is excluded from available devices under tier_filter [1, 2]")

	workshop.queue_free()
	return err
