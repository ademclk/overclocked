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

	# 2. Workbench with player carrying Phone
	var phone_data: DeviceData = load("res://resources/devices/phone.tres")
	var fault_data: FaultData = load("res://resources/faults/phone_cracked_screen.tres")
	var dev := Device.new()
	dev.initialize(phone_data, fault_data)
	add_child(dev)
	carry.pick_up(dev)

	var carry_opts := StationMenuBuilder.build_menu(wb, player)
	var has_place_opt := carry_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device")
	var has_examine_opt := carry_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "examine")
	assert_test(has_place_opt, "Workbench presents 'Place Device' option when carrying device")
	assert_test(has_examine_opt, "Workbench presents 'Examine Device' option when carrying device")

	# 3. Workbench with Diagnosed Phone on bench
	carry.drop_item()
	wb.accept_device(dev)
	dev.diagnose()
	wb.requires_tool = true
	var diag_opts := StationMenuBuilder.build_menu(wb, player)
	var disasm_opt: InteractionMenuOption = null
	for o in diag_opts:
		if o.option_id == "disassemble":
			disasm_opt = o
			break
	assert_test(disasm_opt != null, "Diagnosed device on workbench has 'Disassemble' option")
	assert_test(not disasm_opt.is_enabled, "Disassemble disabled when player has no required tool")
	assert_test(disasm_opt.disabled_reason.contains("screwdriver"), "Disassemble shows disabled reason for missing tool")

	# Give player a screwdriver
	var tool := ToolItem.new()
	tool.tool_id = "screwdriver"
	tool.item_name = "Screwdriver"
	add_child(tool)
	carry.pick_up(tool)

	var diag_opts_with_tool := StationMenuBuilder.build_menu(wb, player)
	var disasm_with_tool: InteractionMenuOption = null
	for o in diag_opts_with_tool:
		if o.option_id == "disassemble":
			disasm_with_tool = o
			break
	assert_test(disasm_with_tool != null and disasm_with_tool.is_enabled, "Disassemble enabled when player carries screwdriver")

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
	assert_test(coffee_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "quick_wipe"), "Coffee spill menu contains 'Quick Wipe'")
	assert_test(not coffee_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "gather_screws"), "Coffee spill menu does NOT contain 'gather_screws'")

	var screw_spill := FloorSpillHazard.new()
	screw_spill.spill_type = FloorSpillHazard.SpillType.SCREWS
	add_child(screw_spill)
	var screw_opts := HazardMenuBuilder.build_menu(screw_spill, player)
	assert_test(screw_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "gather_screws"), "Dropped screws menu contains 'Gather Screws'")
	assert_test(screw_opts.any(func(o: InteractionMenuOption) -> bool: return o.option_id == "quick_sweep"), "Dropped screws menu contains 'Quick Sweep'")
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
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Workbench"), "Hint for DIAGNOSED points to Workbench")

	dev.current_repair_state = RepairState.State.DISASSEMBLED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Parts Shelf"), "Hint for DISASSEMBLED points to Parts Shelf")

	dev.current_repair_state = RepairState.State.TESTED
	assert_test(DeviceExaminationPanel.get_next_step_hint(dev).contains("Delivery Counter"), "Hint for TESTED points to Delivery Counter")

	panel.close_panel()
	assert_test(not panel.is_open(), "Examination panel closes properly")
	assert_test(not player.is_movement_locked(), "Player movement unlocked after closing examination panel")

	# Test opening panel while device is DIAGNOSED on Workbench
	var wb := WorkbenchStation.new()
	add_child(wb)
	dev.current_repair_state = RepairState.State.DIAGNOSED
	dev.is_diagnosed = true
	wb.accept_device(dev)

	panel.open_panel(player, dev)
	assert_test(panel.is_open(), "Panel opened on DIAGNOSED device on workbench")
	assert_test(panel.fault_name_label.text.contains("CRACKED SCREEN"), "Diagnosed fault name shown")
	assert_test(not panel.fault_desc_label.text.is_empty(), "Symptom description populated without error")
	panel.close_panel()

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
	panel.close_panel()

	wb.queue_free()
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
	wb.disassembly_time = 0.05
	wb.work_time = 0.05
	wb.reassembly_time = 0.05
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

	# 2. Disassemble at Workbench via menu option
	var wb_menu1 = StationMenuBuilder.build_menu(wb, player)
	var wb_place_opt: InteractionMenuOption = wb_menu1.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "place_device")[0]
	wb_place_opt.action_callable.call()
	assert_test(wb.placed_device == phone, "Phone placed on Workbench via menu")

	var wb_menu2 = StationMenuBuilder.build_menu(wb, player)
	var disasm_opt: InteractionMenuOption = wb_menu2.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "disassemble")[0]
	disasm_opt.action_callable.call()
	wb._complete_processing()
	assert_test(str(phone.get_repair_state()) == "DISASSEMBLED", "Phone disassembled via menu")

	# 3. Install part via menu option
	var part_item := Carriable.new()
	part_item.item_name = screen_part.component_name
	part_item.item_type = "part"
	part_item.set_meta("component_data", screen_part)
	add_child(part_item)
	carry.pick_up(part_item)

	var wb_menu3 = StationMenuBuilder.build_menu(wb, player)
	var install_opt: InteractionMenuOption = wb_menu3.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "install_part")[0]
	install_opt.action_callable.call()
	assert_test(str(phone.get_repair_state()) == "PART_REPLACED", "Phone advanced to PART_REPLACED via menu")

	# 4. Reassemble at Workbench via menu option
	var wb_menu4 = StationMenuBuilder.build_menu(wb, player)
	var reassem_opt: InteractionMenuOption = wb_menu4.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "reassemble")[0]
	reassem_opt.action_callable.call()
	wb._complete_processing()
	assert_test(str(phone.get_repair_state()) == "REASSEMBLED", "Phone reassembled via menu")

	# 5. Pick up and test at SoftwareStation
	var wb_menu5 = StationMenuBuilder.build_menu(wb, player)
	var pickup_wb_opt: InteractionMenuOption = wb_menu5.filter(func(o: InteractionMenuOption) -> bool: return o.option_id == "pick_up")[0]
	pickup_wb_opt.action_callable.call()
	assert_test(carry.is_carrying(), "Phone picked up from workbench")

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
