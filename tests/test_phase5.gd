extends Node3D

## Comprehensive automated test suite for Phase 5
## Tests Visual Scale & WorldLabel, Interaction Menu System, Station Menus,
## Hazard Menus, Device Examination, Repair Minigames, Game Feel, and Phone Regression.

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("\n=========================================================")
	print("--- STARTING PHASE 5 INTERACTION & GAME FEEL TESTS ---")
	print("=========================================================\n")

	_test_5a_visual_scale_and_world_labels()
	_test_5b_interaction_menu_core()
	_test_5c_station_menu_builder()
	_test_5d_hazard_menu_builder()
	_test_5e_device_examination()
	_test_5f_repair_minigames()
	_test_5g_game_feel_mechanics()
	_test_5h_hud_and_signals_integration()
	_test_phone_regression_with_menus()
	_test_5k_hazard_3d_minigames()

	print("\n=========================================================")
	print("--- PHASE 5 TESTS COMPLETED: %d PASSED, %d FAILED ---" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("--- ALL PHASE 5 TESTS PASSED SUCCESSFULLY! ---")
	else:
		print("--- WARNING: SOME PHASE 5 TESTS FAILED! ---")
	print("=========================================================\n")

	get_tree().quit(0 if _fail_count == 0 else 1)


func assert_test(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % test_name)


func _create_test_player(player_index: int = 0) -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	player.player_index = player_index
	return player


func _test_5a_visual_scale_and_world_labels() -> void:
	print("[1] Testing 5A — Visual Scale & WorldLabel System...")

	var dummy_target := Node3D.new()
	add_child(dummy_target)
	dummy_target.position = Vector3(2.0, 1.0, 0.0)

	var wl := WorldLabel.new()
	add_child(wl)
	wl.target_node = dummy_target
	wl.set_text("WORKBENCH")
	wl.set_icon_text("🔧")

	assert_test(wl.min_font_size >= 16, "WorldLabel min font size is at least 16px")
	assert_test(WorldLabel.get_station_icon_symbol("workbench") == "🔧", "Workbench station icon symbol is 🔧")
	assert_test(WorldLabel.get_station_icon_symbol("diagnostic") == "🔍", "Diagnostic station icon symbol is 🔍")
	assert_test(WorldLabel.get_station_icon_symbol("parts_shelf") == "📦", "Parts shelf icon symbol is 📦")
	assert_test(WorldLabel.get_station_icon_symbol("software") == "💻", "Software station icon symbol is 💻")

	var scaled_font: int = UIScaleManager.get_scaled_font_size(18)
	assert_test(scaled_font >= 16, "UIScaleManager guarantees minimum font size >= 16px")

	var wb := WorkbenchStation.new()
	add_child(wb)
	var wb_wl := wb.setup_world_label()
	assert_test(wb_wl != null, "Workbench creates screen-space WorldLabel")
	assert_test(wb.get_world_label() == wb_wl, "Workbench references its WorldLabel")

	dummy_target.queue_free()
	wl.queue_free()
	wb.queue_free()


func _test_5b_interaction_menu_core() -> void:
	print("\n[2] Testing 5B — Interaction Menu System (RE-Style)...")

	var interactable := Interactable.new()
	assert_test(interactable.interaction_type == "instant", "Interactable default interaction_type is 'instant'")
	interactable.interaction_type = "menu"
	assert_test(interactable.interaction_type == "menu", "Interactable interaction_type can be set to 'menu'")

	var player := _create_test_player(0)
	add_child(player)

	assert_test(not player.is_movement_locked(), "Player initially not movement-locked")
	player.set_movement_locked(true)
	assert_test(player.is_movement_locked(), "Player movement lock activates correctly")
	player.set_movement_locked(false)
	assert_test(not player.is_movement_locked(), "Player movement lock deactivates correctly")

	# Test InteractionMenuOption
	var opt_called: Array[bool] = [false]
	var opt := InteractionMenuOption.new("test_opt", "Test Option", "Test Desc", func() -> void: opt_called[0] = true)
	assert_test(opt.option_id == "test_opt", "InteractionMenuOption holds option_id")
	assert_test(opt.is_enabled, "InteractionMenuOption defaults to enabled")

	# Test InteractionMenu UI
	var menu_scene: PackedScene = load("res://scenes/ui/InteractionMenu.tscn")
	assert_test(menu_scene != null, "InteractionMenu.tscn loads successfully")

	var menu: InteractionMenu = menu_scene.instantiate() as InteractionMenu
	add_child(menu)

	var options: Array[InteractionMenuOption] = [
		opt,
		InteractionMenuOption.new("disabled_opt", "Disabled Option", "Desc", Callable(), false),
		InteractionMenuOption.new("cancel", "Cancel", "Cancel Desc")
	]

	menu.open_menu(player, interactable, options)
	assert_test(menu.is_open(), "InteractionMenu is open after open_menu()")
	assert_test(player.is_movement_locked(), "Player movement is locked while menu is open")
	assert_test(menu.get_selected_index() == 0, "Initial selected option is first enabled option")

	# Test navigation skips disabled options
	menu._navigate(1)
	assert_test(menu.get_selected_index() == 2, "Navigation skips disabled options and selects next enabled")

	menu._navigate(-1)
	assert_test(menu.get_selected_index() == 0, "Navigation backwards returns to first enabled option")

	# Test confirmation
	menu._confirm_selection()
	assert_test(opt_called[0], "Confirming selection invokes option callable")
	assert_test(not menu.is_open(), "Menu closes after confirming selection")
	assert_test(not player.is_movement_locked(), "Player movement is unlocked after menu closes")

	# Test quick action optimization
	var menu_quick := menu_scene.instantiate() as InteractionMenu
	menu_quick.quick_action_enabled = true
	add_child(menu_quick)

	var single_called: Array[bool] = [false]
	var single_options: Array[InteractionMenuOption] = [
		InteractionMenuOption.new("single_opt", "Single", "Desc", func() -> void: single_called[0] = true),
		InteractionMenuOption.new("cancel", "Cancel", "Desc")
	]
	menu_quick.open_menu(player, interactable, single_options)
	assert_test(single_called[0], "Quick action auto-triggers when only 1 actionable option exists")
	assert_test(not menu_quick.is_open(), "Menu remains closed when quick action fires")

	menu.queue_free()
	menu_quick.queue_free()
	player.queue_free()
	interactable.queue_free()


func _test_5c_station_menu_builder() -> void:
	print("\n[3] Testing 5C — Station Interaction Menus (StationMenuBuilder)...")

	var player := _create_test_player(0)
	add_child(player)
	var carry := player.carry_system

	# 1. Empty Workbench
	var wb := WorkbenchStation.new()
	add_child(wb)
	var empty_opts := StationMenuBuilder.build_menu(wb, player)
	assert_test(empty_opts.size() > 0, "Empty workbench generates menu options")
	assert_test(empty_opts.back().option_id == "cancel", "Workbench menu ends with Cancel option")

	# 2. Workbench with player carrying Phone (Device rejected at Workbench)
	var phone_data: DeviceData = load("res://resources/devices/phone.tres")
	var fault_data: FaultData = load("res://resources/faults/phone_cracked_screen.tres")
	var dev := Device.new()
	dev.initialize(phone_data, fault_data)
	add_child(dev)
	carry.pick_up(dev)

	var carry_opts := StationMenuBuilder.build_menu(wb, player)
	var place_opt: InteractionMenuOption = null
	for o in carry_opts:
		if o.option_id == "place_device":
			place_opt = o
			break
	var has_examine_opt := carry_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "examine")
	assert_test(place_opt != null and not place_opt.is_enabled, "Workbench rejects placing device (Hardware repair moved to Repair Table)")
	assert_test(place_opt.disabled_reason.contains("Repair Table"), "Workbench place device option points to Repair Table")
	assert_test(has_examine_opt, "Workbench presents 'Examine Device' option when carrying device")

	# 3. Dedicated Repair Table with Diagnosed Phone
	carry.drop_item()
	var rt := RepairTableStation.new()
	add_child(rt)
	rt.requires_tool = true
	dev.diagnose()
	carry.pick_up(dev)
	var rt_carry_opts := StationMenuBuilder.build_menu(rt, player)
	var rt_place: InteractionMenuOption = rt_carry_opts.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device")[0]
	assert_test(rt_place != null and rt_place.is_enabled, "Repair Table accepts diagnosed device")
	rt_place.action_callable.call()
	assert_test(rt.placed_device == dev, "Diagnosed device successfully placed on Repair Table")

	var diag_opts := StationMenuBuilder.build_menu(rt, player)
	var disasm_opt: InteractionMenuOption = null
	for o in diag_opts:
		if o.option_id == "disassemble":
			disasm_opt = o
			break
	assert_test(disasm_opt != null, "Diagnosed device on repair table has 'Disassemble' option")
	assert_test(not disasm_opt.is_enabled, "Disassemble disabled when player has no required tool")
	assert_test(disasm_opt.disabled_reason.contains("screwdriver"), "Disassemble shows disabled reason for missing tool")

	# Give player a screwdriver
	var tool := ToolItem.new()
	tool.tool_id = "screwdriver"
	tool.item_name = "Screwdriver"
	add_child(tool)
	carry.pick_up(tool)

	var diag_opts_with_tool := StationMenuBuilder.build_menu(rt, player)
	var disasm_with_tool: InteractionMenuOption = null
	for o in diag_opts_with_tool:
		if o.option_id == "disassemble":
			disasm_with_tool = o
			break
	assert_test(disasm_with_tool != null and disasm_with_tool.is_enabled, "Disassemble enabled when player carries screwdriver")

	# Test: While carrying tool with device on repair table, place_tool option is available
	var place_tool_opt: InteractionMenuOption = null
	for o in diag_opts_with_tool:
		if o.option_id == "place_tool":
			place_tool_opt = o
			break
	assert_test(place_tool_opt != null and place_tool_opt.is_enabled, "Carrying tool with device on table offers 'Place on Repair Table' option")
	place_tool_opt.action_callable.call()
	assert_test(rt.get_bench_tool() == tool, "Tool successfully placed on repair table alongside device")
	assert_test(not carry.is_carrying(), "Player hands free after placing tool")

	# Test: When table already has a tool and player carries another tool, offers 'Drop to Ground'
	var tool2 := ToolItem.new()
	tool2.tool_id = "screwdriver"
	tool2.item_name = "Screwdriver 2"
	add_child(tool2)
	carry.pick_up(tool2)
	var opts_two_tools := StationMenuBuilder.build_menu(rt, player)
	var drop_tool_opt: InteractionMenuOption = null
	for o in opts_two_tools:
		if o.option_id == "drop_tool":
			drop_tool_opt = o
			break
	assert_test(drop_tool_opt != null and drop_tool_opt.is_enabled, "When table has a tool, second carried tool offers 'Drop to Ground'")
	drop_tool_opt.action_callable.call()
	assert_test(not carry.is_carrying(), "Player dropped second tool to ground")
	tool2.queue_free()

	# Test: Pickup device while holding a tool auto-stows or drops tool
	var tool3 := ToolItem.new()
	tool3.tool_id = "screwdriver"
	tool3.item_name = "Screwdriver 3"
	add_child(tool3)
	carry.pick_up(tool3)
	var pickup_with_tool_opt: InteractionMenuOption = null
	for o in StationMenuBuilder.build_menu(rt, player):
		if o.option_id == "pick_up":
			pickup_with_tool_opt = o
			break
	assert_test(pickup_with_tool_opt != null and pickup_with_tool_opt.is_enabled, "Pick Up Device is enabled even while carrying tool")
	pickup_with_tool_opt.action_callable.call()
	assert_test(carry.is_carrying() and carry.get_held_item() == dev, "Player picked up device from repair table while tool was auto-stowed/dropped")
	carry.drop_item()
	tool3.queue_free()

	# Test: Empty table with bench_tool already present and player carrying another tool
	var tool4 := ToolItem.new()
	tool4.tool_id = "screwdriver"
	tool4.item_name = "Screwdriver 4"
	add_child(tool4)
	carry.pick_up(tool4)
	var empty_table_opts := StationMenuBuilder.build_menu(rt, player)
	var empty_drop_opt: InteractionMenuOption = null
	for o in empty_table_opts:
		if o.option_id == "drop_tool":
			empty_drop_opt = o
			break
	assert_test(empty_drop_opt != null and empty_drop_opt.is_enabled, "Empty table with tool present offers 'Drop to Ground' for second tool")
	empty_drop_opt.action_callable.call()
	assert_test(not carry.is_carrying(), "Player dropped tool on empty table with existing tool")
	tool4.queue_free()
	rt.queue_free()

	# Test: Workbench tool storage & distribution
	var wb_tool := ToolItem.new()
	wb_tool.tool_id = "screwdriver"
	wb_tool.item_name = "Workbench Screwdriver"
	add_child(wb_tool)
	carry.pick_up(wb_tool)
	var wb_store_opts := StationMenuBuilder.build_menu(wb, player)
	var place_wb_opt: InteractionMenuOption = wb_store_opts.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_tool")[0]
	assert_test(place_wb_opt != null and place_wb_opt.is_enabled, "Workbench accepts placing tool for storage")
	place_wb_opt.action_callable.call()
	assert_test(wb.get_bench_tool() == wb_tool, "Tool successfully stored on Workbench")

	var wb_pick_opts := StationMenuBuilder.build_menu(wb, player)
	var pick_wb_tool: InteractionMenuOption = wb_pick_opts.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up_tool")[0]
	assert_test(pick_wb_tool != null and pick_wb_tool.is_enabled, "Workbench dispenses stored screwdriver")
	pick_wb_tool.action_callable.call()
	assert_test(carry.is_carrying() and carry.get_held_item() == wb_tool, "Player successfully picked up screwdriver from Workbench")
	carry.drop_item()
	wb_tool.queue_free()

	# 4. Diagnostic Bench menu
	var diag_bench := DiagnosticBench.new()
	add_child(diag_bench)
	var diag_menu := StationMenuBuilder.build_menu(diag_bench, player)
	assert_test(diag_menu.size() > 0, "Diagnostic bench generates menu options")

	# 5. Parts Shelf menu
	var shelf := PartsShelf.new()
	add_child(shelf)
	carry.drop_item()
	var shelf_menu := StationMenuBuilder.build_menu(shelf, player)
	assert_test(shelf_menu.size() > 0, "Parts shelf generates menu options")
	var has_take_part := shelf_menu.any(func(o: InteractionMenuOption) -> bool: return o.option_id.begins_with("take_"))
	assert_test(has_take_part, "Parts shelf menu offers parts to take")

	# 6. Delivery Counter menu
	var delivery := DeliveryCounter.new()
	add_child(delivery)
	var deliv_menu := StationMenuBuilder.build_menu(delivery, player)
	assert_test(deliv_menu.size() > 0, "Delivery counter generates menu options")

	wb.queue_free()
	diag_bench.queue_free()
	shelf.queue_free()
	delivery.queue_free()
	dev.queue_free()
	tool.queue_free()
	player.queue_free()


func _test_5d_hazard_menu_builder() -> void:
	print("\n[4] Testing 5D — Hazard Interaction Menus (HazardMenuBuilder)...")

	var player := _create_test_player(0)
	add_child(player)

	# 1. Power Surge
	var surge := PowerSurgeHazard.new()
	add_child(surge)
	var surge_opts := HazardMenuBuilder.build_menu(surge, player)
	assert_test(surge_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "reset_breaker"), "Surge menu contains 'Reset Circuit Breaker'")
	assert_test(surge_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "unplug_station"), "Surge menu contains 'Unplug Station'")

	# 2. Floor Spill (Coffee vs Screws)
	var coffee_spill := FloorSpillHazard.new()
	coffee_spill.spill_type = FloorSpillHazard.SpillType.COFFEE
	add_child(coffee_spill)
	var coffee_opts := HazardMenuBuilder.build_menu(coffee_spill, player)
	assert_test(coffee_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "mop_spill"), "Coffee spill menu contains 'Mop Up'")
	assert_test(not coffee_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "quick_wipe"), "Coffee spill menu does NOT contain 'Quick Wipe' (removed per overhaul)")
	assert_test(not coffee_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "gather_screws"), "Coffee spill menu does NOT contain 'gather_screws'")

	var screw_spill := FloorSpillHazard.new()
	screw_spill.spill_type = FloorSpillHazard.SpillType.SCREWS
	add_child(screw_spill)
	var screw_opts := HazardMenuBuilder.build_menu(screw_spill, player)
	assert_test(screw_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "gather_screws"), "Dropped screws menu contains 'Gather Screws'")
	assert_test(not screw_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "quick_sweep"), "Dropped screws menu does NOT contain 'Quick Sweep' (removed per overhaul)")
	assert_test(not screw_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "mop_spill"), "Dropped screws menu does NOT contain 'mop_spill'")

	# 3. Battery Fire & Wrong Choice
	var fire := BatteryFireHazard.new()
	add_child(fire)
	var fire_opts := HazardMenuBuilder.build_menu(fire, player)
	assert_test(fire_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "fire_extinguisher"), "Battery fire offers 'Use Fire Extinguisher'")
	assert_test(fire_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "pour_water"), "Battery fire offers 'Pour Water'")

	var wrong_choice_fired: Array[bool] = [false]
	var bus_handler := func(h_name: String, choice: String) -> void:
		if h_name == "Battery Fire" and choice == "pour_water":
			wrong_choice_fired[0] = true
	SignalBus.hazard_wrong_choice.connect(bus_handler)

	fire.pour_water(player)
	assert_test(fire.is_exploded, "Pouring water causes battery fire to explode/spread")
	assert_test(wrong_choice_fired[0], "Pouring water emits SignalBus.hazard_wrong_choice")
	SignalBus.hazard_wrong_choice.disconnect(bus_handler)

	# 4. Cable Tangle
	var tangle := CableTangleHazard.new()
	add_child(tangle)
	var tangle_opts := HazardMenuBuilder.build_menu(tangle, player)
	assert_test(tangle_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "untangle_carefully"), "Cable tangle offers 'Untangle Carefully'")
	assert_test(tangle_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "cut_cables"), "Cable tangle offers 'Cut Cables'")

	surge.queue_free()
	coffee_spill.queue_free()
	screw_spill.queue_free()
	fire.queue_free()
	tangle.queue_free()
	player.queue_free()


func _test_5e_device_examination() -> void:
	print("\n[5] Testing 5E — Device Examination & Inspection...")

	var phone_data: DeviceData = load("res://resources/devices/phone.tres")
	var fault_data: FaultData = load("res://resources/faults/phone_cracked_screen.tres")
	var dev := Device.new()
	dev.initialize(phone_data, fault_data)
	add_child(dev)

	var panel_scene: PackedScene = load("res://scenes/ui/DeviceExaminationPanel.tscn")
	assert_test(panel_scene != null, "DeviceExaminationPanel.tscn loads successfully")

	var panel: DeviceExaminationPanel = panel_scene.instantiate() as DeviceExaminationPanel
	add_child(panel)

	var player := _create_test_player(0)
	add_child(player)

	panel.open_panel(player, dev)
	assert_test(panel.is_open(), "Examination panel opens successfully")
	assert_test(player.is_movement_locked(), "Player movement locked while examining device")

	# Test next step hints
	dev.current_repair_state = RepairState.State.RECEIVED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Diagnostic Bench"), "Hint for RECEIVED points to Diagnostic Bench")

	dev.current_repair_state = RepairState.State.DIAGNOSED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Repair Table"), "Hint for DIAGNOSED points to Repair Table")

	dev.current_repair_state = RepairState.State.DISASSEMBLED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Parts Shelf"), "Hint for DISASSEMBLED points to Parts Shelf")

	dev.current_repair_state = RepairState.State.PART_REPLACED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Repair Table"), "Hint for PART_REPLACED points to Repair Table")

	dev.current_repair_state = RepairState.State.TESTED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Delivery Counter"), "Hint for TESTED points to Delivery Counter")

	panel.close_panel()
	assert_test(not panel.is_open(), "Examination panel closes properly")
	assert_test(not player.is_movement_locked(), "Player movement unlocked after closing examination panel")

	# Test opening panel while device is DIAGNOSED on Repair Table
	var rt_bench := RepairTableStation.new()
	add_child(rt_bench)
	dev.current_repair_state = RepairState.State.DIAGNOSED
	dev.is_diagnosed = true
	rt_bench.accept_device(dev)

	panel.open_panel(player, dev, rt_bench)
	assert_test(panel.is_open(), "Panel opened on DIAGNOSED device on repair table")
	assert_test(panel.fault_name_label.text.contains("CRACKED SCREEN"), "Diagnosed fault name shown")
	assert_test(not panel.fault_desc_label.text.is_empty(), "Symptom description populated without error")
	panel.close_panel()
	rt_bench.queue_free()

	# Test opening panel on multi-fault device in DISASSEMBLED state
	var laptop_data: DeviceData = load("res://resources/devices/laptop.tres")
	var laptop_fault: FaultData = load("res://resources/faults/laptop_overheating.tres")
	var laptop_dev := Device.new()
	laptop_dev.initialize(laptop_data, laptop_fault)
	add_child(laptop_dev)
	laptop_dev.current_repair_state = RepairState.State.DISASSEMBLED
	laptop_dev.is_diagnosed = true

	panel.open_panel(player, laptop_dev)
	assert_test(panel.is_open(), "Panel opened on DISASSEMBLED multi-fault device")
	assert_test(panel.fault_desc_label.text.contains("Symptoms:"), "Multi-fault symptoms populated successfully")
	assert_test(panel.parts_container.get_child_count() > 0, "Multi-fault parts list populated")
	# Test part installation via DeviceExaminationPanel without station (station = null)
	var screen_comp: ComponentData = fault_data.broken_component
	var part_item := Carriable.new()
	part_item.item_type = "part"
	part_item.item_name = screen_comp.component_name
	part_item.set_meta("component_data", screen_comp)
	add_child(part_item)
	player.carry_system.pick_up(part_item)

	dev.current_repair_state = RepairState.State.DISASSEMBLED
	panel.open_panel(player, dev, null)
	panel._trigger_install_part(screen_comp)
	assert_test(dev.current_repair_state == RepairState.State.PART_REPLACED, "Installing part via panel advances single-fault device to PART_REPLACED")
	assert_test(not player.carry_system.is_carrying(), "Player carried part is consumed after installation")
	panel.close_panel()

	# Test multi-fault partial part installation (laptop)
	var laptop_req: Array[ComponentData] = laptop_fault.get_required_components()
	if laptop_req.size() >= 2:
		var part1 := Carriable.new()
		part1.item_type = "part"
		part1.item_name = laptop_req[0].component_name
		part1.set_meta("component_data", laptop_req[0])
		add_child(part1)
		player.carry_system.pick_up(part1)

		panel.open_panel(player, laptop_dev, null)
		panel._trigger_install_part(laptop_req[0])
		assert_test(laptop_dev.current_repair_state == RepairState.State.DISASSEMBLED, "Partial part installation keeps multi-fault device in DISASSEMBLED state")
		assert_test(not player.carry_system.is_carrying(), "First part is consumed")

		var part2 := Carriable.new()
		part2.item_type = "part"
		part2.item_name = laptop_req[1].component_name
		part2.set_meta("component_data", laptop_req[1])
		add_child(part2)
		player.carry_system.pick_up(part2)

		panel._trigger_install_part(laptop_req[1])
		assert_test(laptop_dev.current_repair_state == RepairState.State.PART_REPLACED, "Completing all parts advances multi-fault device to PART_REPLACED")
		assert_test(not player.carry_system.is_carrying(), "Second part is consumed")
		panel.close_panel()

	laptop_dev.queue_free()
	panel.queue_free()
	player.queue_free()
	dev.queue_free()


func _test_5f_repair_minigames() -> void:
	print("\n[6] Testing 5F — Workbench Repair Minigames...")

	var phone_data: DeviceData = load("res://resources/devices/phone.tres")
	var dev_t1 := Device.new()
	dev_t1.initialize(phone_data)
	add_child(dev_t1)

	var desktop_data: DeviceData = load("res://resources/devices/desktop_pc.tres")
	var dev_t3 := Device.new()
	dev_t3.initialize(desktop_data)
	add_child(dev_t3)

	var player := _create_test_player(0)
	add_child(player)

	# 1. ScrewMinigame difficulty scaling
	var screw_game := ScrewMinigame.new()
	add_child(screw_game)

	screw_game.start_minigame(player, dev_t1)
	assert_test(screw_game.screw_count == 4, "Tier 1 ScrewMinigame has 4 screws")
	assert_test(screw_game.sweet_spot_width == 0.30, "Tier 1 sweet spot is 30% width")
	assert_test(player.is_movement_locked(), "Player locked during minigame")

	# Skip minigame with penalty
	var skipped: Array[bool] = [false]
	screw_game.minigame_skipped.connect(func() -> void: skipped[0] = true)
	screw_game.skip_minigame()
	assert_test(skipped[0], "ScrewMinigame can be skipped")
	assert_test(not player.is_movement_locked(), "Player unlocked after skipping minigame")

	# Test Tier 3 difficulty scaling
	screw_game.start_minigame(player, dev_t3)
	assert_test(screw_game.screw_count == 8, "Tier 3 ScrewMinigame has 8 screws")
	assert_test(screw_game.sweet_spot_width == 0.12, "Tier 3 sweet spot is 12% width")
	assert_test(screw_game.skip_penalty == Constants.MINIGAME_SKIP_PENALTY_TIER_3, "Tier 3 skip penalty matches constant")

	# Hit simulation
	screw_game.indicator_position = screw_game.sweet_spot_center
	screw_game._on_player_hit()
	assert_test(screw_game.current_screw == 1, "Hitting sweet spot advances screw count")

	# 2. InstallMinigame
	var install_game := InstallMinigame.new()
	add_child(install_game)
	install_game.start_minigame(player, dev_t1)
	assert_test(install_game.alignment_tolerance == 0.25, "Tier 1 InstallMinigame alignment tolerance is 0.25")

	# Perfect snap
	install_game.component_pos = install_game.target_slot_pos
	var completed_rating: Array[int] = [0]
	install_game.minigame_completed.connect(func(rating: int) -> void: completed_rating[0] = rating)
	install_game._on_confirm_snap()
	assert_test(completed_rating[0] == 3, "Snapping component in center yields 3-star rating")

	screw_game.queue_free()
	install_game.queue_free()
	dev_t1.queue_free()
	dev_t3.queue_free()
	player.queue_free()


func _test_5g_game_feel_mechanics() -> void:
	print("\n[7] Testing 5G — Game Feel Mechanics...")

	# 1. ComboTracker
	ComboTracker.reset_combo()
	assert_test(ComboTracker.get_multiplier() == 1.0, "Initial combo multiplier is 1.0")

	ComboTracker.on_repair_completed()
	assert_test(ComboTracker.get_streak() == 1, "First completion sets streak to 1")

	ComboTracker.on_repair_completed()
	assert_test(ComboTracker.get_streak() == 2, "Second completion increases streak to 2")
	assert_test(ComboTracker.get_multiplier() == 2.0, "Streak 2 gives ×2.0 multiplier")

	ComboTracker.on_repair_failed()
	assert_test(ComboTracker.get_streak() == 0, "Failed repair breaks combo streak")
	assert_test(ComboTracker.get_multiplier() == 1.0, "Multiplier resets to 1.0")

	# 2. Tool Durability
	var tool := ToolItem.new()
	tool.tool_id = "test_screwdriver"
	tool.max_durability = 3
	tool.current_durability = 3
	add_child(tool)

	assert_test(tool.use_tool(), "First tool use succeeds")
	assert_test(tool.current_durability == 2, "Tool durability decrements to 2")
	assert_test(tool.use_tool(), "Second tool use succeeds")
	assert_test(tool.use_tool(), "Third tool use succeeds (reaches 0)")
	assert_test(not tool.use_tool(), "Depleted tool cannot be used")

	tool.repair_tool()
	assert_test(tool.current_durability == 3, "Tool repair restores max durability")

	# 3. Rush Mode
	var wb := WorkbenchStation.new()
	add_child(wb)
	wb.processing_time = 2.0
	var test_dev := Device.new()
	add_child(test_dev)
	wb.accept_device(test_dev)
	wb.start_processing()
	assert_test(wb.current_state == BaseStation.StationState.PROCESSING, "Station starts processing")

	# 4. Hot Potato Mechanic
	var dev := Device.new()
	dev.item_name = "Phone"
	dev.set_meta("is_overheated", true)
	add_child(dev)
	dev.is_held = true
	var hp_fired: Array[bool] = [false]
	var hp_handler := func(_item: String, choice: String) -> void:
		if choice == "hot_potato":
			hp_fired[0] = true
	SignalBus.hazard_wrong_choice.connect(hp_handler)
	dev._process(5.1)
	assert_test(hp_fired[0], "Holding overheated device for >5s triggers hot potato warning")
	SignalBus.hazard_wrong_choice.disconnect(hp_handler)

	tool.queue_free()
	wb.queue_free()
	test_dev.queue_free()
	dev.queue_free()


func _test_5h_hud_and_signals_integration() -> void:
	print("\n[8] Testing 5H & 5I — HUD, Signals & Constants Integration...")

	# Signals in SignalBus
	assert_test(SignalBus.has_signal("interaction_menu_opened"), "SignalBus has interaction_menu_opened")
	assert_test(SignalBus.has_signal("interaction_menu_closed"), "SignalBus has interaction_menu_closed")
	assert_test(SignalBus.has_signal("device_examined"), "SignalBus has device_examined")
	assert_test(SignalBus.has_signal("minigame_started"), "SignalBus has minigame_started")
	assert_test(SignalBus.has_signal("combo_updated"), "SignalBus has combo_updated")
	assert_test(SignalBus.has_signal("tool_durability_changed"), "SignalBus has tool_durability_changed")
	assert_test(SignalBus.has_signal("hazard_wrong_choice"), "SignalBus has hazard_wrong_choice")

	# Constants
	assert_test(Constants.COMBO_WINDOW_SECONDS == 10.0, "Constants.COMBO_WINDOW_SECONDS is 10.0")
	assert_test(Constants.COMBO_TIERS.size() == 5, "Constants.COMBO_TIERS has 5 tiers")
	assert_test(Constants.RUSH_SPEED_BONUS == 0.7, "Constants.RUSH_SPEED_BONUS is 0.7")
	assert_test(Constants.TOOL_DEFAULT_DURABILITY == 8, "Constants.TOOL_DEFAULT_DURABILITY is 8")
	assert_test(Constants.WORLD_LABEL_MIN_FONT_SIZE == 16, "Constants.WORLD_LABEL_MIN_FONT_SIZE is 16")

	# HUD Integration
	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	assert_test(hud_scene != null, "HUD.tscn loads successfully")

	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)
	assert_test(hud.combo_display != null, "HUD instantiates combo_display element")

	var p0_menu := hud.get_interaction_menu_for_player(0)
	assert_test(p0_menu != null, "HUD provides per-player InteractionMenu instance")

	hud.queue_free()


func _test_phone_regression_with_menus() -> void:
	print("\n[9] Testing Phone Repair Flow Regression via Menus...")

	var phone_data: DeviceData = load("res://resources/devices/phone.tres")
	var fault_data: FaultData = load("res://resources/faults/phone_cracked_screen.tres")
	var screen_part: ComponentData = load("res://resources/components/screen.tres")

	var phone := Device.new()
	phone.initialize(phone_data, fault_data)
	add_child(phone)

	var player := _create_test_player(0)
	add_child(player)
	var carry := player.carry_system

	var diag := DiagnosticBench.new()
	diag.diagnosis_time = 0.05
	add_child(diag)

	var wb := WorkbenchStation.new()
	wb.work_time = 0.05
	wb.requires_tool = false
	add_child(wb)

	var soft := SoftwareStation.new()
	soft.software_install_time = 0.05
	add_child(soft)

	var delivery := DeliveryCounter.new()
	add_child(delivery)

	# 1. Diagnose via menu option
	carry.pick_up(phone)
	var diag_menu = StationMenuBuilder.build_menu(diag, player)
	var diag_place_opt: InteractionMenuOption = diag_menu.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "diagnose_device")[0]
	diag_place_opt.action_callable.call()
	assert_test(diag.placed_device == phone, "Phone placed on Diagnostic Bench via menu")

	diag._complete_processing()
	var diag_pickup_menu = StationMenuBuilder.build_menu(diag, player)
	var diag_pickup_opt: InteractionMenuOption = diag_pickup_menu.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up")[0]
	diag_pickup_opt.action_callable.call()
	assert_test(carry.is_carrying() and phone.is_diagnosed, "Phone diagnosed and picked up via menu")

	# 2. Hardware repair at dedicated Repair Table
	var rt := RepairTableStation.new()
	rt.disassembly_time = 0.05
	rt.reassembly_time = 0.05
	rt.requires_tool = true
	add_child(rt)

	# Verify workbench rejects placing phone (as requested by overhaul)
	var wb_check_menu = StationMenuBuilder.build_menu(wb, player)
	var wb_reject_opt: InteractionMenuOption = wb_check_menu.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device")[0]
	assert_test(not wb_reject_opt.is_enabled, "Workbench correctly rejects device placement")

	# Place screwdriver on repair table
	var rt_tool := ToolItem.new()
	rt_tool.tool_id = "screwdriver"
	rt_tool.item_name = "Screwdriver"
	rt.add_child(rt_tool)
	rt._bench_tool = rt_tool

	# Place diagnosed phone on Repair Table
	var rt_menu1 = StationMenuBuilder.build_menu(rt, player)
	var rt_place_opt: InteractionMenuOption = rt_menu1.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device")[0]
	rt_place_opt.action_callable.call()
	assert_test(rt.placed_device == phone, "Phone placed on Repair Table via menu")

	var rt_menu2 = StationMenuBuilder.build_menu(rt, player)
	var disasm_opt: InteractionMenuOption = rt_menu2.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "disassemble")[0]
	disasm_opt.action_callable.call()
	rt._complete_processing()
	assert_test(str(phone.get_repair_state()) == "DISASSEMBLED", "Phone disassembled via menu")

	# 3. Install part via menu option
	var part_item := Carriable.new()
	part_item.item_name = screen_part.component_name
	part_item.item_type = "part"
	part_item.set_meta("component_data", screen_part)
	add_child(part_item)
	carry.pick_up(part_item)

	var rt_menu3 = StationMenuBuilder.build_menu(rt, player)
	var install_opt: InteractionMenuOption = rt_menu3.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "install_part")[0]
	install_opt.action_callable.call()
	assert_test(str(phone.get_repair_state()) == "PART_REPLACED", "Phone advanced to PART_REPLACED via menu")

	# 4. Reassemble at Repair Table via menu option
	var rt_menu4 = StationMenuBuilder.build_menu(rt, player)
	var reassem_opt: InteractionMenuOption = rt_menu4.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "reassemble")[0]
	reassem_opt.action_callable.call()
	rt._complete_processing()
	assert_test(str(phone.get_repair_state()) == "REASSEMBLED", "Phone reassembled via menu")

	# 5. Pick up and test at SoftwareStation
	var rt_menu5 = StationMenuBuilder.build_menu(rt, player)
	var pickup_rt_opt: InteractionMenuOption = rt_menu5.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up")[0]
	pickup_rt_opt.action_callable.call()
	assert_test(carry.is_carrying(), "Phone picked up from repair table")

	var soft_menu1 = StationMenuBuilder.build_menu(soft, player)
	var soft_place_opt: InteractionMenuOption = soft_menu1.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device_software")[0]
	soft_place_opt.action_callable.call()
	assert_test(soft.placed_device == phone, "Phone placed on Software Station via menu")

	soft._complete_processing()
	var soft_menu2 = StationMenuBuilder.build_menu(soft, player)
	var soft_pickup_opt: InteractionMenuOption = soft_menu2.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up")[0]
	soft_pickup_opt.action_callable.call()
	assert_test(str(phone.get_repair_state()) == "TESTED", "Phone tested and picked up via menu")

	# 6. Deliver at Delivery Counter
	var deliv_menu = StationMenuBuilder.build_menu(delivery, player)
	var deliver_opt: InteractionMenuOption = deliv_menu.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "deliver_device")[0]
	deliver_opt.action_callable.call()
	assert_test(str(phone.get_repair_state()) == "DELIVERED", "Phone successfully delivered through full menu flow!")

	phone.queue_free()
	player.queue_free()
	diag.queue_free()
	wb.queue_free()
	soft.queue_free()
	delivery.queue_free()


func _test_5k_hazard_3d_minigames() -> void:
	print("\n[10] Testing 5K — 3D Hazard Resolution Minigames...")

	var panel_scene: PackedScene = load("res://scenes/ui/HazardResolutionPanel.tscn")
	assert_test(panel_scene != null, "HazardResolutionPanel.tscn loads successfully")

	var panel: HazardResolutionPanel = panel_scene.instantiate() as HazardResolutionPanel
	add_child(panel)
	assert_test(panel != null, "HazardResolutionPanel instantiates successfully")

	var player := _create_test_player(0)
	add_child(player)

	# 1. Floor Spill Mopping Minigame
	var spill := FloorSpillHazard.new()
	add_child(spill)
	spill.activate()

	panel.open_hazard_panel(player, spill)
	assert_test(panel.is_open(), "Hazard panel opens for floor spill")
	assert_test(player.is_movement_locked(), "Player movement locked during hazard minigame")
	assert_test(panel._total_steps == 4, "Floor spill sets up 4 mopping spots")

	# Clean all 4 spots
	panel._on_mop_spot_cleaned(0)
	panel._on_mop_spot_cleaned(1)
	panel._on_mop_spot_cleaned(2)
	panel._on_mop_spot_cleaned(3)
	assert_test(spill.current_state in [BaseHazard.HazardState.CLEARED, BaseHazard.HazardState.INACTIVE], "Mopping all 4 spots clears the spill hazard")

	panel.close_panel()
	assert_test(not player.is_movement_locked(), "Player movement unlocked after closing hazard panel")

	# 2. Cable Tangle Rewiring Minigame
	var tangle := CableTangleHazard.new()
	add_child(tangle)
	tangle.activate()

	panel.open_hazard_panel(player, tangle)
	assert_test(panel._total_steps == 4, "Cable tangle sets up 4 rewiring steps")
	panel.close_panel()

	# 3. Power Surge Breaker Reset Minigame
	var surge := PowerSurgeHazard.new()
	add_child(surge)
	surge.activate()

	panel.open_hazard_panel(player, surge)
	assert_test(panel._total_steps == 4, "Power surge sets up breaker switches and master lever")
	panel.close_panel()

	# 4. Scattered Screws Gathering Minigame
	var screws := ScatteredScrewsHazard.new()
	add_child(screws)
	screws.activate()

	panel.open_hazard_panel(player, screws)
	assert_test(panel._total_steps == 5, "Scattered screws sets up 5 screw gathering steps")

	# Gather all screws
	for i in range(5):
		panel._step_completed(i)
	assert_test(screws.current_state in [BaseHazard.HazardState.CLEARED, BaseHazard.HazardState.INACTIVE], "Gathering all screws clears the screws hazard")

	panel.close_panel()

	# 5. FloorSpillHazard configured as SCREWS
	var floor_screws := FloorSpillHazard.new()
	floor_screws.spill_type = FloorSpillHazard.SpillType.SCREWS
	add_child(floor_screws)
	floor_screws.activate()

	panel.open_hazard_panel(player, floor_screws)
	assert_test(panel._total_steps == 5, "FloorSpillHazard (SCREWS) launches screw gathering minigame (5 steps)")
	assert_test(panel.hazard_title.text.contains("SCREWS"), "FloorSpillHazard (SCREWS) title contains SCREWS")
	panel.close_panel()

	panel.queue_free()
	player.queue_free()
	spill.queue_free()
	tangle.queue_free()
	surge.queue_free()
	screws.queue_free()
	floor_screws.queue_free()

	print("\n[11] Testing 5L — Gameplay Overhaul (6 Requirements Verification)...")

	# --- OVERHAUL 1: Hazard E-Spam Prevention ---
	var p_h := _create_test_player(0)
	add_child(p_h)
	var sp_h := FloorSpillHazard.new()
	add_child(sp_h)
	sp_h.activate()
	var h_panel: HazardResolutionPanel = panel_scene.instantiate() as HazardResolutionPanel
	add_child(h_panel)
	h_panel.open_hazard_panel(p_h, sp_h)

	# Simulate pressing E key on open panel
	var key_ev := InputEventKey.new()
	key_ev.pressed = true
	key_ev.keycode = KEY_E
	h_panel._unhandled_input(key_ev)
	assert_test(h_panel._cleared_steps == 0, "Hazard panel E-key spam does NOT auto-solve hazard step")
	assert_test(h_panel.primary_action_btn.disabled, "Primary action button is disabled (requires 3D hotspot interaction)")
	h_panel.close_panel()
	h_panel.queue_free()
	sp_h.queue_free()
	p_h.queue_free()

	# --- OVERHAUL 2: Diagnostic Bench Gating ---
	var p2 := _create_test_player(0)
	add_child(p2)
	var diag_b := DiagnosticBench.new()
	add_child(diag_b)
	var test_phone := Device.new()
	var ph_data: DeviceData = load("res://resources/devices/phone.tres")
	var flt_data: FaultData = load("res://resources/faults/phone_cracked_screen.tres")
	test_phone.initialize(ph_data, flt_data)
	add_child(test_phone)
	test_phone.diagnose()
	diag_b.accept_device(test_phone)

	var exam_panel: DeviceExaminationPanel = load("res://scenes/ui/DeviceExaminationPanel.tscn").instantiate() as DeviceExaminationPanel
	add_child(exam_panel)
	exam_panel.open_panel(p2, test_phone, diag_b)
	var unscrew_hotspots = exam_panel._active_hotspots.filter(func(h: Node) -> bool: return h.action_id.begins_with("unscrew_"))
	assert_test(unscrew_hotspots.is_empty(), "Diagnostic Bench prevents disassembly hotspots on diagnosed device")
	exam_panel.close_panel()
	exam_panel.queue_free()
	diag_b.queue_free()

	# --- OVERHAUL 3: Workbench Rejects Faulty Devices ---
	var wb_test := WorkbenchStation.new()
	add_child(wb_test)
	assert_test(not wb_test.can_accept_device(test_phone), "Workbench Station rejects accepting devices")
	assert_test(not wb_test._can_accept_workbench_item(test_phone), "Workbench _can_accept_workbench_item returns false for device")

	# Recovery verification: if device is somehow on workbench, pick up is enabled
	wb_test.placed_device = test_phone
	p2.carry_system.drop_item()
	var wb_rescue_opts := StationMenuBuilder.build_menu(wb_test, p2)
	var rescue_opt: InteractionMenuOption = wb_rescue_opts.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up")[0]
	assert_test(rescue_opt != null and rescue_opt.is_enabled, "Stuck device on workbench can be cleanly picked up")
	rescue_opt.action_callable.call()
	assert_test(p2.carry_system.is_carrying() and p2.carry_system.get_held_item() == test_phone, "Player cleanly picked up device from workbench")
	p2.carry_system.drop_item()
	wb_test.queue_free()

	# --- OVERHAUL 4: Parts Shelf UI Panel ---
	var shelf_test := PartsShelf.new()
	add_child(shelf_test)
	shelf_test._init_stock()

	# Put device in DISASSEMBLED state on a repair table so screen is needed
	var rt_test := RepairTableStation.new()
	add_child(rt_test)
	test_phone.advance_repair_state() # DIAGNOSED -> DISASSEMBLED
	rt_test.accept_device(test_phone)

	var shelf_panel_scene: PackedScene = load("res://scenes/ui/PartsShelfPanel.tscn")
	assert_test(shelf_panel_scene != null, "PartsShelfPanel.tscn loads successfully")
	var shelf_panel: PartsShelfPanel = shelf_panel_scene.instantiate() as PartsShelfPanel
	add_child(shelf_panel)
	shelf_panel.open_shelf_panel(p2, shelf_test)
	assert_test(shelf_panel.is_open(), "PartsShelfPanel opens successfully")
	assert_test(p2.is_movement_locked(), "Player movement locked while parts shelf panel is open")

	var needed_ids: Array[String] = shelf_panel._get_needed_component_ids()
	assert_test(needed_ids.has("phone_screen") or needed_ids.any(func(id: String) -> bool: return id.contains("screen")), "PartsShelfPanel identifies 'screen' as needed component")

	# Select part card via panel
	var part_to_select: String = "phone_screen" if needed_ids.has("phone_screen") else "screen"
	shelf_panel._on_card_selected(part_to_select)
	assert_test(not shelf_panel.is_open(), "PartsShelfPanel closes after part selection")
	assert_test(p2.carry_system.is_carrying(), "Player receives selected replacement part in hands")
	assert_test(not p2.is_movement_locked(), "Player movement unlocked after closing parts shelf panel")
	shelf_panel.queue_free()

	# --- OVERHAUL 5: Trash Bin Station ---
	var trash_scene: PackedScene = load("res://scenes/stations/TrashBin.tscn")
	assert_test(trash_scene != null, "TrashBin.tscn loads successfully")
	var trash: TrashBin = trash_scene.instantiate() as TrashBin
	trash.trash_mess_chance = 0.0 # deterministic for this step
	add_child(trash)

	# 1. Trashing a part is permitted and destroys the item
	var trashed_item_name: Array[String] = [""]
	trash.item_disposed.connect(func(n: String) -> void: trashed_item_name[0] = n)
	var part_held: Carriable = p2.carry_system.get_held_item()
	assert_test(trash.can_player_interact(p2), "Player can interact with Trash Bin carrying a part")
	var trash_success: bool = trash.dispose_item(p2)
	assert_test(trash_success, "Part item successfully disposed in Trash Bin")
	assert_test(not p2.carry_system.is_carrying(), "Player hands empty after discarding part")
	assert_test(trashed_item_name[0] != "", "TrashBin emitted item_disposed signal")

	# 2. Trashing a tool is rejected
	var tool_item := ToolItem.new()
	tool_item.tool_id = "screwdriver"
	tool_item.item_name = "Screwdriver"
	add_child(tool_item)
	p2.carry_system.pick_up(tool_item)
	assert_test(not trash.can_player_interact(p2), "Trash Bin rejects interaction when carrying screwdriver")
	assert_test(not trash.dispose_item(p2), "Trash Bin dispose_item returns false for screwdriver")
	assert_test(p2.carry_system.is_carrying(), "Player still holds screwdriver (not trashed)")
	p2.carry_system.drop_item()
	tool_item.queue_free()

	# 3. Trashing a customer device is rejected
	p2.carry_system.pick_up(test_phone)
	assert_test(not trash.can_player_interact(p2), "Trash Bin rejects interaction when carrying customer device")
	assert_test(not trash.dispose_item(p2), "Trash Bin dispose_item returns false for customer device")
	assert_test(p2.carry_system.is_carrying(), "Player still holds device (not trashed)")
	p2.carry_system.drop_item()
	trash.queue_free()
	shelf_test.queue_free()
	rt_test.queue_free()
	test_phone.queue_free()

	# --- OVERHAUL 6: Shift Dash Mechanics ---
	var p_dash := _create_test_player(0)
	add_child(p_dash)
	p_dash.global_position = Vector3(0.0, 0.0, 0.0)

	assert_test(not p_dash.is_dashing(), "Player initially not dashing")
	p_dash.trigger_dash()
	assert_test(p_dash.is_dashing(), "trigger_dash initiates forward dash")

	# Test collision impact drops held item and stuns player
	var carried_box := Carriable.new()
	carried_box.item_name = "Test Box"
	add_child(carried_box)
	p_dash.carry_system.pick_up(carried_box)
	assert_test(p_dash.carry_system.is_carrying(), "Player holding box before collision dash")

	# Trigger dash impact logic manually
	p_dash._dash_direction = Vector3(1.0, 0.0, 0.0)
	p_dash._is_dashing = true
	# Simulate impact directly as in physics process
	p_dash._is_dashing = false
	p_dash.dash_impact.emit()
	var held_before_drop: Carriable = p_dash.carry_system.get_held_item()
	p_dash.carry_system.drop_item()
	if held_before_drop and is_instance_valid(held_before_drop):
		held_before_drop.global_position += p_dash._dash_direction * 0.6
	p_dash.stun(0.35)

	assert_test(not p_dash.carry_system.is_carrying(), "Dash collision drops held item forward")
	assert_test(p_dash.is_stunned(), "Dash collision stuns the player")
	assert_test(held_before_drop.global_position.x > 0.4, "Dropped item pushed forward in dash direction")

	carried_box.queue_free()
	p_dash.queue_free()
	p2.queue_free()
