extends Node

## Test suite for Phase 4G — Device Scenes & Visual Differentiation
## Validates all 6 device scenes (Phone, Tablet, Laptop, Desktop PC, Game Console, Router),
## verifying node structures, meshes, labels, interaction zones, visual differentiation,
## material coloring via device_data.device_color, and multi-fault label updates.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4G DEVICE SCENES TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_phone_scene()
	failures += test_tablet_scene()
	failures += test_laptop_scene()
	failures += test_desktop_pc_scene()
	failures += test_game_console_scene()
	failures += test_router_scene()
	failures += test_device_color_application()
	failures += test_device_label_multi_fault_formatting()

	print("=========================================================")
	print("--- PHASE 4G TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4G TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4G tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


## 1. Test Phone scene
func test_phone_scene() -> int:
	print("\n[1] Testing Phone.tscn...")
	var err: int = 0

	var phone_res: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	err += _assert(phone_res != null, "Loaded phone.tres")
	err += _assert(phone_res.device_scene != null, "phone.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/Phone.tscn") as PackedScene
	err += _assert(scene != null, "Loaded Phone.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Phone is Device instance")
	err += _assert(dev.item_name == "Phone", "item_name is Phone")
	err += _assert(dev.device_mesh != null, "Phone has DeviceMesh")
	err += _assert(dev.device_label != null, "Phone has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Phone has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/ScreenMesh") != null, "Phone has ScreenMesh")

	dev.queue_free()
	return err


## 2. Test Tablet scene
func test_tablet_scene() -> int:
	print("\n[2] Testing Tablet.tscn...")
	var err: int = 0

	var tablet_res: DeviceData = load("res://resources/devices/tablet.tres") as DeviceData
	err += _assert(tablet_res != null, "Loaded tablet.tres")
	err += _assert(tablet_res.device_scene != null, "tablet.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/Tablet.tscn") as PackedScene
	err += _assert(scene != null, "Loaded Tablet.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Tablet is Device instance")
	err += _assert(dev.item_name == "Tablet", "item_name is Tablet")
	err += _assert(dev.device_mesh != null, "Tablet has DeviceMesh")
	err += _assert(dev.device_label != null, "Tablet has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Tablet has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/ScreenMesh") != null, "Tablet has ScreenMesh")

	dev.queue_free()
	return err


## 3. Test Laptop scene
func test_laptop_scene() -> int:
	print("\n[3] Testing Laptop.tscn...")
	var err: int = 0

	var laptop_res: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	err += _assert(laptop_res != null, "Loaded laptop.tres")
	err += _assert(laptop_res.device_scene != null, "laptop.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/Laptop.tscn") as PackedScene
	err += _assert(scene != null, "Loaded Laptop.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Laptop is Device instance")
	err += _assert(dev.item_name == "Laptop", "item_name is Laptop")
	err += _assert(dev.device_mesh != null, "Laptop has DeviceMesh")
	err += _assert(dev.device_label != null, "Laptop has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Laptop has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/KeyboardMesh") != null, "Laptop has KeyboardMesh")
	err += _assert(dev.get_node_or_null("DeviceMesh/LidMesh") != null, "Laptop has LidMesh")
	err += _assert(dev.get_node_or_null("DeviceMesh/LidMesh/LidScreenMesh") != null, "Laptop has LidScreenMesh")

	dev.queue_free()
	return err


## 4. Test Desktop PC scene
func test_desktop_pc_scene() -> int:
	print("\n[4] Testing DesktopPC.tscn...")
	var err: int = 0

	var desktop_res: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	err += _assert(desktop_res != null, "Loaded desktop_pc.tres")
	err += _assert(desktop_res.device_scene != null, "desktop_pc.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn") as PackedScene
	err += _assert(scene != null, "Loaded DesktopPC.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Desktop PC is Device instance")
	err += _assert(dev.item_name == "Desktop PC", "item_name is Desktop PC")
	err += _assert(dev.device_mesh != null, "Desktop PC has DeviceMesh")
	err += _assert(dev.device_label != null, "Desktop PC has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Desktop PC has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/SidePanel") != null, "Desktop PC has SidePanel")
	err += _assert(dev.get_node_or_null("DeviceMesh/FrontLED") != null, "Desktop PC has FrontLED")

	# Check enlarged interaction pickup zone for 2-player desktop
	var col_shape: CollisionShape3D = dev.interaction_zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	err += _assert(col_shape != null, "InteractionZone has CollisionShape3D")
	if col_shape and col_shape.shape is BoxShape3D:
		var box := col_shape.shape as BoxShape3D
		err += _assert(box.size.x >= 1.2 and box.size.z >= 1.2, "Desktop PC has enlarged 2x pickup zone (>= 1.2)")

	dev.queue_free()
	return err


## 5. Test Game Console scene
func test_game_console_scene() -> int:
	print("\n[5] Testing GameConsole.tscn...")
	var err: int = 0

	var console_res: DeviceData = load("res://resources/devices/game_console.tres") as DeviceData
	err += _assert(console_res != null, "Loaded game_console.tres")
	err += _assert(console_res.device_scene != null, "game_console.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/GameConsole.tscn") as PackedScene
	err += _assert(scene != null, "Loaded GameConsole.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Game Console is Device instance")
	err += _assert(dev.item_name == "Game Console", "item_name is Game Console")
	err += _assert(dev.device_mesh != null, "Game Console has DeviceMesh")
	err += _assert(dev.device_label != null, "Game Console has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Game Console has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/DiscSlotMesh") != null, "Game Console has DiscSlotMesh")
	err += _assert(dev.get_node_or_null("DeviceMesh/PowerLedMesh") != null, "Game Console has PowerLedMesh")

	dev.queue_free()
	return err


## 6. Test Router scene
func test_router_scene() -> int:
	print("\n[6] Testing Router.tscn...")
	var err: int = 0

	var router_res: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	err += _assert(router_res != null, "Loaded router.tres")
	err += _assert(router_res.device_scene != null, "router.tres has device_scene assigned")

	var scene: PackedScene = load("res://scenes/devices/Router.tscn") as PackedScene
	err += _assert(scene != null, "Loaded Router.tscn")
	if not scene:
		return err + 1

	var dev: Device = scene.instantiate() as Device
	add_child(dev)

	err += _assert(dev != null, "Router is Device instance")
	err += _assert(dev.item_name == "Router", "item_name is Router")
	err += _assert(dev.device_mesh != null, "Router has DeviceMesh")
	err += _assert(dev.device_label != null, "Router has DeviceLabel")
	err += _assert(dev.interaction_zone != null, "Router has InteractionZone")
	err += _assert(dev.get_node_or_null("DeviceMesh/AntennaLeft") != null, "Router has AntennaLeft")
	err += _assert(dev.get_node_or_null("DeviceMesh/AntennaRight") != null, "Router has AntennaRight")
	err += _assert(dev.get_node_or_null("DeviceMesh/StatusLed1") != null, "Router has StatusLed1")

	dev.queue_free()
	return err


## 7. Test device_color material application
func test_device_color_application() -> int:
	print("\n[7] Testing _apply_device_color() across all device types...")
	var err: int = 0

	var device_configs := [
		{"res": "res://resources/devices/phone.tres", "scene": "res://scenes/devices/Phone.tscn", "color": Constants.DEVICE_COLOR_PHONE},
		{"res": "res://resources/devices/tablet.tres", "scene": "res://scenes/devices/Tablet.tscn", "color": Constants.DEVICE_COLOR_TABLET},
		{"res": "res://resources/devices/laptop.tres", "scene": "res://scenes/devices/Laptop.tscn", "color": Constants.DEVICE_COLOR_LAPTOP},
		{"res": "res://resources/devices/desktop_pc.tres", "scene": "res://scenes/devices/DesktopPC.tscn", "color": Constants.DEVICE_COLOR_DESKTOP},
		{"res": "res://resources/devices/game_console.tres", "scene": "res://scenes/devices/GameConsole.tscn", "color": Constants.DEVICE_COLOR_CONSOLE},
		{"res": "res://resources/devices/router.tres", "scene": "res://scenes/devices/Router.tscn", "color": Constants.DEVICE_COLOR_ROUTER},
	]

	for cfg in device_configs:
		var data: DeviceData = load(cfg["res"]) as DeviceData
		var scene: PackedScene = load(cfg["scene"]) as PackedScene
		var dev: Device = scene.instantiate() as Device
		add_child(dev)

		# Check that material_override was applied with matching albedo_color
		err += _assert(dev.device_mesh.material_override != null, "%s has material_override" % data.device_name)
		if dev.device_mesh.material_override is StandardMaterial3D:
			var mat := dev.device_mesh.material_override as StandardMaterial3D
			var expected: Color = cfg["color"]
			err += _assert(mat.albedo_color.is_equal_approx(expected),
				"%s material albedo matches device_color (%s vs %s)" % [data.device_name, str(mat.albedo_color), str(expected)])

		dev.queue_free()

	return err


## 8. Test DeviceLabel multi-fault component slot formatting
func test_device_label_multi_fault_formatting() -> int:
	print("\n[8] Testing DeviceLabel multi-fault component slots [✓ / ○]...")
	var err: int = 0

	var laptop_scene: PackedScene = load("res://scenes/devices/Laptop.tscn") as PackedScene
	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	err += _assert(fault != null and fault.is_multi_fault, "Found laptop_overheating multi-fault")

	var dev: Device = laptop_scene.instantiate() as Device
	add_child(dev)
	dev.initialize(laptop_data, fault)

	# Before diagnosis, label only shows item_name and [RECEIVED]
	err += _assert(dev.device_label.text.contains("Laptop"), "Label contains Laptop")
	err += _assert(dev.device_label.text.contains("[RECEIVED]"), "Label contains [RECEIVED]")
	err += _assert(not dev.device_label.text.contains("○"), "Label does not reveal missing components before diagnosis")

	# Diagnose device
	dev.diagnose()
	err += _assert(dev.device_label.text.contains("Overheating"), "Label contains fault name after diagnosis")
	err += _assert(dev.device_label.text.contains("○"), "Label shows ○ for missing components after diagnosis")
	err += _assert(dev.device_label.text.contains("Laptop Fan"), "Label mentions Laptop Fan")
	err += _assert(dev.device_label.text.contains("Thermal Paste"), "Label mentions Thermal Paste")

	# Install one component
	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	dev.try_install_component(fan)

	err += _assert(dev.device_label.text.contains("✓"), "Label now contains ✓ after first component installed")
	err += _assert(dev.device_label.text.contains("○"), "Label still contains ○ for second component")

	# Install second component
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	dev.try_install_component(paste)

	err += _assert(not dev.device_label.text.contains("○"), "Label has 0 ○ remaining after both components installed")

	dev.queue_free()
	return err
