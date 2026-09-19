extends Node

## Test suite for Phase 4B — Component Library Expansion
## Verifies that all components exist, are valid ComponentData resources,
## follow the naming conventions, and are registered on the PartsShelf.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4B COMPONENT LIBRARY TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_all_component_resources_valid()
	failures += test_shared_thermal_paste()
	failures += test_parts_shelf_all_components_registered()
	failures += test_parts_shelf_stock_for_new_components()
	failures += test_component_carriable_mesh_colors()

	print("=========================================================")
	print("--- PHASE 4B TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4B TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4B tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		print("  [FAIL] %s" % test_name)
		return 1


## 1. Test all component resources exist, are valid, and follow ID conventions
func test_all_component_resources_valid() -> int:
	print("\n[1] Testing all 22 component resources...")
	var err: int = 0

	var expected_components: Dictionary = {
		# Phone
		"res://resources/components/screen.tres": {"id": "phone_screen", "type": "screen", "cat": "phone"},
		"res://resources/components/battery.tres": {"id": "phone_battery", "type": "battery", "cat": "phone"},
		"res://resources/components/os_installer.tres": {"id": "os_installer", "type": "software", "cat": "shared"},
		# Tablet
		"res://resources/components/tablet_screen.tres": {"id": "tablet_screen", "type": "screen", "cat": "tablet"},
		"res://resources/components/tablet_battery.tres": {"id": "tablet_battery", "type": "battery", "cat": "tablet"},
		"res://resources/components/tablet_speaker.tres": {"id": "tablet_speaker", "type": "audio", "cat": "tablet"},
		# Laptop
		"res://resources/components/laptop_keyboard.tres": {"id": "laptop_keyboard", "type": "keyboard", "cat": "laptop"},
		"res://resources/components/laptop_ram.tres": {"id": "laptop_ram", "type": "memory", "cat": "laptop"},
		"res://resources/components/laptop_ssd.tres": {"id": "laptop_ssd", "type": "storage", "cat": "laptop"},
		"res://resources/components/laptop_screen.tres": {"id": "laptop_screen", "type": "screen", "cat": "laptop"},
		"res://resources/components/laptop_fan.tres": {"id": "laptop_fan", "type": "cooling", "cat": "laptop"},
		"res://resources/components/thermal_paste.tres": {"id": "thermal_paste", "type": "thermal", "cat": "shared"},
		# Desktop PC
		"res://resources/components/gpu.tres": {"id": "gpu", "type": "gpu", "cat": "desktop"},
		"res://resources/components/psu.tres": {"id": "psu", "type": "power", "cat": "desktop"},
		"res://resources/components/motherboard.tres": {"id": "motherboard", "type": "motherboard", "cat": "desktop"},
		"res://resources/components/cpu_cooler.tres": {"id": "cpu_cooler", "type": "cooling", "cat": "desktop"},
		"res://resources/components/desktop_ram.tres": {"id": "desktop_ram", "type": "memory", "cat": "desktop"},
		"res://resources/components/desktop_ssd.tres": {"id": "desktop_ssd", "type": "storage", "cat": "desktop"},
		# Game Console
		"res://resources/components/disc_drive.tres": {"id": "disc_drive", "type": "optical", "cat": "console"},
		"res://resources/components/console_hdmi_port.tres": {"id": "console_hdmi_port", "type": "port", "cat": "console"},
		# Router
		"res://resources/components/router_antenna.tres": {"id": "router_antenna", "type": "antenna", "cat": "router"},
		"res://resources/components/router_firmware.tres": {"id": "router_firmware", "type": "software", "cat": "router"},
	}

	for path: String in expected_components.keys():
		var expected: Dictionary = expected_components[path]
		var file_exists: bool = ResourceLoader.exists(path)
		err += _assert(file_exists, "Component file exists: %s" % path)
		if not file_exists:
			continue

		var res: Resource = load(path)
		err += _assert(res != null and res is ComponentData, "%s is ComponentData" % path)
		if not (res is ComponentData):
			continue

		var comp := res as ComponentData
		err += _assert(comp.is_valid(), "%s is_valid() == true" % comp.component_id)
		err += _assert(comp.component_id == expected["id"], "ID is '%s'" % expected["id"])
		err += _assert(comp.component_type == expected["type"], "Type is '%s'" % expected["type"])
		err += _assert(not comp.component_name.is_empty(), "Name is non-empty ('%s')" % comp.component_name)
		err += _assert(comp.component_shelf_category == expected["cat"], "Shelf category is '%s'" % expected["cat"])

	return err


## 2. Test shared thermal_paste component
func test_shared_thermal_paste() -> int:
	print("\n[2] Testing shared thermal_paste resource...")
	var err: int = 0

	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	err += _assert(paste != null, "thermal_paste.tres loaded")
	err += _assert(paste.component_id == "thermal_paste", "thermal_paste has no device prefix")
	err += _assert(paste.component_shelf_category == "shared", "thermal_paste has shared category")
	return err


## 3. Test PartsShelf registers all components by default
func test_parts_shelf_all_components_registered() -> int:
	print("\n[3] Testing PartsShelf component registration...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn")
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	add_child(shelf)

	err += _assert(shelf.available_parts.size() >= 22, "PartsShelf has at least 22 available parts (got %d)" % shelf.available_parts.size())

	var registered_ids: Array[String] = []
	for comp in shelf.available_parts:
		if comp:
			registered_ids.append(comp.component_id)

	var required_ids: Array[String] = [
		"phone_screen", "phone_battery", "os_installer",
		"tablet_screen", "tablet_battery", "tablet_speaker",
		"laptop_keyboard", "laptop_ram", "laptop_ssd", "laptop_screen", "laptop_fan", "thermal_paste",
		"gpu", "psu", "motherboard", "cpu_cooler", "desktop_ram", "desktop_ssd",
		"disc_drive", "console_hdmi_port",
		"router_antenna", "router_firmware"
	]

	for req_id in required_ids:
		err += _assert(req_id in registered_ids, "PartsShelf registered '%s'" % req_id)

	shelf.queue_free()
	return err


## 4. Test initial stock of 3 per part on PartsShelf
func test_parts_shelf_stock_for_new_components() -> int:
	print("\n[4] Testing stock initialization (3 per part)...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn")
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	shelf.initial_stock_per_part = 3
	add_child(shelf)

	err += _assert(shelf.get_stock("tablet_screen") == 3, "tablet_screen initial stock is 3")
	err += _assert(shelf.get_stock("laptop_keyboard") == 3, "laptop_keyboard initial stock is 3")
	err += _assert(shelf.get_stock("thermal_paste") == 3, "thermal_paste initial stock is 3")
	err += _assert(shelf.get_stock("gpu") == 3, "gpu initial stock is 3")
	err += _assert(shelf.get_stock("disc_drive") == 3, "disc_drive initial stock is 3")
	err += _assert(shelf.get_stock("router_antenna") == 3, "router_antenna initial stock is 3")

	shelf.queue_free()
	return err


## 5. Test Carriable creation and material color
func test_component_carriable_mesh_colors() -> int:
	print("\n[5] Testing component Carriable instance creation and colors...")
	var err: int = 0

	var shelf_scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn")
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	add_child(shelf)

	var test_types: Dictionary = {
		"res://resources/components/tablet_speaker.tres": "audio",
		"res://resources/components/laptop_keyboard.tres": "keyboard",
		"res://resources/components/gpu.tres": "gpu",
		"res://resources/components/thermal_paste.tres": "thermal",
	}

	for path in test_types.keys():
		var comp: ComponentData = load(path) as ComponentData
		var item: Carriable = shelf._create_part_instance(comp)
		err += _assert(item != null, "Carriable created for %s" % comp.component_id)
		err += _assert(item.item_name == comp.component_name, "Item name matches component name: %s" % item.item_name)
		err += _assert(item.has_meta("component_data"), "Item has component_data meta")
		var mesh_inst: MeshInstance3D = item.get_node_or_null("MeshInstance3D") as MeshInstance3D
		err += _assert(mesh_inst != null, "Item has MeshInstance3D")
		err += _assert(mesh_inst.material_override != null, "MeshInstance3D has material_override")
		if item:
			item.queue_free()

	shelf.queue_free()
	return err
