extends Node

## Test suite for Phase 4I — HUD & Diagnosis UI Updates
## Validates multi-fault diagnosis tags, color-coded device icons, difficulty tier stars,
## workbench component slot indicators (✓/○), co-carry prompts, and solo heavy carry HUD warning.

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4I HUD & DIAGNOSIS UI TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_multi_fault_diagnosis_display()
	failures += test_order_panel_device_color_and_tier_stars()
	failures += test_order_panel_multi_fault_tags()
	failures += test_workbench_component_slot_status()
	failures += test_two_player_carry_prompt()
	failures += test_solo_heavy_carry_warning_hud()

	print("=========================================================")
	print("--- PHASE 4I TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4I TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4I tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


## 1. Test multi-fault diagnosis reveal on DiagnosticBench
func test_multi_fault_diagnosis_display() -> int:
	print("\n[1] Testing DiagnosticBench multi-fault diagnosis display...")
	var err: int = 0

	var bench_scene: PackedScene = load("res://scenes/stations/DiagnosticBench.tscn") as PackedScene
	var bench: DiagnosticBench = bench_scene.instantiate() as DiagnosticBench
	add_child(bench)

	var laptop_scene: PackedScene = load("res://scenes/devices/Laptop.tscn") as PackedScene
	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")

	var dev: Device = laptop_scene.instantiate() as Device
	dev.initialize(laptop_data, fault)
	add_child(dev)

	bench.accept_device(dev)
	bench.start_processing()
	bench._on_processing_done()

	err += _assert(bench.progress_label != null, "DiagnosticBench has progress_label")
	if bench.progress_label:
		err += _assert(bench.progress_label.text.contains("fan") and bench.progress_label.text.contains("thermal_paste"),
			"progress_label reveals multi-fault tags: '%s'" % bench.progress_label.text)

	if bench.station_label:
		err += _assert(bench.station_label.text.contains("Needs:"), "station_label shows Needs tags on diagnosis")

	dev.queue_free()
	bench.queue_free()
	return err


## 2. Test HUD order panel device color and difficulty tier stars
func test_order_panel_device_color_and_tier_stars() -> int:
	print("\n[2] Testing HUD order panel device color and tier stars...")
	var err: int = 0

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn") as PackedScene
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)

	var om := OrderManager.new()
	add_child(om)
	hud.setup(null, om)

	# Test Phone (Tier 1)
	var phone_data: DeviceData = om.get_device_by_id("phone")
	var order1: Order = om.spawn_order(phone_data)
	hud._update_active_orders()

	var entry1: HBoxContainer = hud._order_entries.get(order1) as HBoxContainer
	err += _assert(entry1 != null, "HUD created order row for phone")
	if entry1:
		var icon: TextureRect = entry1.get_node_or_null("DeviceIcon") as TextureRect
		err += _assert(icon != null, "Order row has DeviceIcon")
		if icon:
			err += _assert(icon.modulate.is_equal_approx(phone_data.device_color),
				"Phone icon modulate matches phone device_color (%s vs %s)" % [str(icon.modulate), str(phone_data.device_color)])

		var tier_label: Label = entry1.get_node_or_null("TierLabel") as Label
		err += _assert(tier_label != null, "Order row has TierLabel")
		if tier_label:
			err += _assert(tier_label.text == "★", "Phone shows 1 star '★' for Tier 1 (got '%s')" % tier_label.text)

	# Test Laptop (Tier 2)
	var laptop_data: DeviceData = om.get_device_by_id("laptop")
	var order2: Order = om.spawn_order(laptop_data)
	hud._update_active_orders()

	var entry2: HBoxContainer = hud._order_entries.get(order2) as HBoxContainer
	err += _assert(entry2 != null, "HUD created order row for laptop")
	if entry2:
		var icon: TextureRect = entry2.get_node_or_null("DeviceIcon") as TextureRect
		if icon:
			err += _assert(icon.modulate.is_equal_approx(laptop_data.device_color),
				"Laptop icon modulate matches laptop device_color (%s vs %s)" % [str(icon.modulate), str(laptop_data.device_color)])

		var tier_label: Label = entry2.get_node_or_null("TierLabel") as Label
		if tier_label:
			err += _assert(tier_label.text == "★★", "Laptop shows 2 stars '★★' for Tier 2 (got '%s')" % tier_label.text)

	# Test Desktop PC (Tier 3)
	var desktop_data: DeviceData = om.get_device_by_id("desktop_pc")
	var order3: Order = om.spawn_order(desktop_data)
	hud._update_active_orders()

	var entry3: HBoxContainer = hud._order_entries.get(order3) as HBoxContainer
	err += _assert(entry3 != null, "HUD created order row for desktop_pc")
	if entry3:
		var icon: TextureRect = entry3.get_node_or_null("DeviceIcon") as TextureRect
		if icon:
			err += _assert(icon.modulate.is_equal_approx(desktop_data.device_color),
				"Desktop PC icon modulate matches desktop device_color (%s vs %s)" % [str(icon.modulate), str(desktop_data.device_color)])

		var tier_label: Label = entry3.get_node_or_null("TierLabel") as Label
		if tier_label:
			err += _assert(tier_label.text == "★★★", "Desktop PC shows 3 stars '★★★' for Tier 3 (got '%s')" % tier_label.text)

	if order1.device_instance: order1.device_instance.queue_free()
	if order2.device_instance: order2.device_instance.queue_free()
	if order3.device_instance: order3.device_instance.queue_free()
	om.queue_free()
	hud.queue_free()
	return err


## 3. Test order panel multi-fault tags formatting
func test_order_panel_multi_fault_tags() -> int:
	print("\n[3] Testing HUD order panel multi-fault tags...")
	var err: int = 0

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn") as PackedScene
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)

	var om := OrderManager.new()
	add_child(om)
	hud.setup(null, om)

	var laptop_data: DeviceData = om.get_device_by_id("laptop")
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")
	var order: Order = om.spawn_order(laptop_data, fault)

	# Diagnose device instance
	order.device_instance.diagnose()
	hud._update_active_orders()

	var entry: HBoxContainer = hud._order_entries.get(order) as HBoxContainer
	err += _assert(entry != null, "Order entry exists")
	if entry:
		var name_label: Label = entry.get_node_or_null("DeviceName") as Label
		err += _assert(name_label != null, "DeviceName label exists")
		if name_label:
			err += _assert(name_label.text.contains("Needs:"), "DeviceName label reveals 'Needs:' after diagnosis (got '%s')" % name_label.text)
			err += _assert(name_label.text.contains("Fan") and name_label.text.contains("Thermal"),
				"DeviceName label lists required tags Fan + Thermal (got '%s')" % name_label.text)

	if order.device_instance: order.device_instance.queue_free()
	om.queue_free()
	hud.queue_free()
	return err


## 4. Test WorkbenchStation component slot indicators (✓ / ○)
func test_workbench_component_slot_status() -> int:
	print("\n[4] Testing WorkbenchStation component slots (✓/○)...")
	var err: int = 0

	var bench_scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn") as PackedScene
	var bench: WorkbenchStation = bench_scene.instantiate() as WorkbenchStation
	add_child(bench)

	var laptop_scene: PackedScene = load("res://scenes/devices/Laptop.tscn") as PackedScene
	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres") as DeviceData
	var fault: FaultData = laptop_data.get_fault_by_id("laptop_overheating")

	var dev: Device = laptop_scene.instantiate() as Device
	dev.initialize(laptop_data, fault)
	add_child(dev)

	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)

	bench.accept_device(dev)
	bench._update_device_status_label()

	err += _assert(bench.station_label != null, "Workbench has station_label")
	if bench.station_label:
		err += _assert(bench.station_label.text.contains("○"), "Station label shows ○ for uninstalled parts")
		err += _assert(bench.station_label.text.contains("Laptop Fan") and bench.station_label.text.contains("Thermal Paste"),
			"Station label mentions both components")

	# Install one component
	var fan: ComponentData = load("res://resources/components/laptop_fan.tres") as ComponentData
	dev.try_install_component(fan)
	bench._update_device_status_label()

	if bench.station_label:
		err += _assert(bench.station_label.text.contains("✓ Laptop Fan"), "Station label contains '✓ Laptop Fan' after installing fan")
		err += _assert(bench.station_label.text.contains("○ Thermal Paste"), "Station label still shows '○ Thermal Paste'")

	# Install second component
	var paste: ComponentData = load("res://resources/components/thermal_paste.tres") as ComponentData
	dev.try_install_component(paste)
	bench._update_device_status_label()

	if bench.station_label:
		err += _assert(bench.station_label.text.contains("✓ Laptop Fan") and bench.station_label.text.contains("✓ Thermal Paste"),
			"Station label shows '✓' for both parts after full installation")
		err += _assert(not bench.station_label.text.contains("○"), "No remaining ○ in station label")

	dev.queue_free()
	bench.queue_free()
	return err


## 5. Test two-player carry prompt
func test_two_player_carry_prompt() -> int:
	print("\n[5] Testing two-player carry prompt...")
	var err: int = 0

	var desktop_scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn") as PackedScene
	var dev: Device = desktop_scene.instantiate() as Device
	add_child(dev)

	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn") as PackedScene
	var player1: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player1)
	var cs: CarrySystem = player1.carry_system

	cs.request_two_player_carry(dev)

	err += _assert(dev.carry_request_active, "Device carry request is active")
	err += _assert(dev.interaction_zone != null, "Device has interaction zone")
	if dev.interaction_zone:
		err += _assert(dev.interaction_zone.interaction_prompt.contains("Hold [Interact] to help carry"),
			"Prompt says 'Hold [Interact] to help carry' (got '%s')" % dev.interaction_zone.interaction_prompt)

	cs.cancel_two_player_carry_request()
	player1.queue_free()
	dev.queue_free()
	return err


## 6. Test solo heavy carry warning in HUD
func test_solo_heavy_carry_warning_hud() -> int:
	print("\n[6] Testing solo heavy carry HUD warning...")
	var err: int = 0

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn") as PackedScene
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)

	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn") as PackedScene
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player)
	var cs: CarrySystem = player.carry_system

	hud.setup(player, null)

	var desktop_scene: PackedScene = load("res://scenes/devices/DesktopPC.tscn") as PackedScene
	var dev: Device = desktop_scene.instantiate() as Device
	add_child(dev)

	cs.pick_up_solo_heavy(dev)
	err += _assert(cs.is_solo_heavy_carrying(), "Player is solo heavy carrying")

	hud._update_interaction_prompt()
	err += _assert(hud.interaction_prompt.visible, "HUD prompt is visible during solo heavy carry")
	err += _assert(hud.prompt_label.text.contains("Carrying alone — very slow!"),
		"Prompt text contains 'Carrying alone — very slow!' (got '%s')" % hud.prompt_label.text)

	cs.drop_item()
	hud._update_interaction_prompt()
	err += _assert(not hud.interaction_prompt.visible, "HUD prompt hidden after dropping heavy item")
	err += _assert(hud.prompt_label.modulate.is_equal_approx(Color.WHITE), "prompt_label modulate restored to WHITE")

	dev.queue_free()
	player.queue_free()
	hud.queue_free()
	return err
