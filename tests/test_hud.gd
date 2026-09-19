extends Node

## Test suite for Basic HUD
## Tests HUD scene structure, carried item indicator, contextual interaction prompts,
## active order timers with color changes, score/star tracking, and visibility toggle.

const HUD_SCENE_PATH: String = "res://scenes/ui/HUD.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"


func _ready() -> void:
	print("--- RUNNING BASIC HUD TESTS (PHASE 1G) ---")
	var failures: int = 0

	failures += test_hud_scene_structure()
	failures += test_hud_carried_item_indicator()
	failures += test_hud_contextual_prompt()
	failures += test_hud_active_orders_and_timers()
	failures += test_hud_scoring_and_stars()
	failures += test_hud_visibility_toggle()

	print("--- BASIC HUD TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL BASIC HUD TESTS PASSED SUCCESSFULLY ---")
		get_tree().quit(0)
	else:
		printerr("HUD tests FAILED with %d error(s)." % failures)
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


## Test HUD scene node hierarchy and required node paths
func test_hud_scene_structure() -> int:
	print("Testing HUD scene structure and node paths...")
	var err: int = 0

	var hud_scene: PackedScene = load(HUD_SCENE_PATH)
	err += _assert(hud_scene != null, "Loaded HUD.tscn successfully")

	var hud: HUD = hud_scene.instantiate() as HUD
	err += _assert(hud != null, "HUD scene root is instance of HUD")
	add_child(hud)

	# Order panel
	err += _assert(hud.order_panel != null, "hud.order_panel exists")
	err += _assert(hud.order_entry_template != null, "hud.order_entry_template exists")
	var icon: TextureRect = hud.order_entry_template.get_node_or_null("DeviceIcon") as TextureRect
	var name_lbl: Label = hud.order_entry_template.get_node_or_null("DeviceName") as Label
	var bar: ProgressBar = hud.order_entry_template.get_node_or_null("TimerBar") as ProgressBar
	err += _assert(icon != null, "OrderEntry has DeviceIcon")
	err += _assert(name_lbl != null, "OrderEntry has DeviceName")
	err += _assert(bar != null, "OrderEntry has TimerBar")

	# Carried item panel
	err += _assert(hud.carried_item_panel != null, "hud.carried_item_panel exists")
	err += _assert(hud.carried_item_icon != null, "hud.carried_item_icon exists")
	err += _assert(hud.carried_item_name != null, "hud.carried_item_name exists")

	# Score panel
	err += _assert(hud.score_panel != null, "hud.score_panel exists")
	err += _assert(hud.star_display != null, "hud.star_display exists")
	err += _assert(hud.score_label != null, "hud.score_label exists")

	# Interaction prompt
	err += _assert(hud.interaction_prompt != null, "hud.interaction_prompt exists")
	err += _assert(hud.prompt_label != null, "hud.prompt_label exists")

	# Repair progress
	err += _assert(hud.repair_progress != null, "hud.repair_progress exists")
	err += _assert(hud.state_label != null, "hud.state_label exists")

	hud.queue_free()
	return err


## Test carried item label and repair state indicators
func test_hud_carried_item_indicator() -> int:
	print("Testing HUD carried item indicator and repair state updates...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	var player: PlayerCharacter = _create_test_player()
	add_child(hud)
	hud.setup(player, null)

	# Initial state: player is not carrying anything
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text == "—", "Empty carried item text is '—'")

	# Pick up a phone
	var dev_scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var device: Device = dev_scene.instantiate() as Device
	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var fault: FaultData = load(CRACKED_SCREEN_FAULT_PATH)
	device.initialize(phone_data, fault)
	add_child(device)

	player.carry_system.pick_up(device)
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("Phone"), "Carried item shows device name 'Phone'")
	err += _assert(hud.carried_item_name.text.contains("RECEIVED"), "Carried item shows repair state 'RECEIVED'")
	err += _assert(hud.state_label.text.contains("RECEIVED"), "Repair pipeline label reflects 'RECEIVED'")

	# Advance repair state to DIAGNOSED
	device.diagnose()
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text.contains("DIAGNOSED"), "Carried item reflects 'DIAGNOSED' state")
	err += _assert(hud.carried_item_name.text.contains(fault.fault_name), "Carried item includes fault name after diagnosis")
	err += _assert(hud.state_label.text.contains("DIAGNOSED"), "Repair pipeline reflects 'DIAGNOSED'")

	# Pick up generic part instead
	player.carry_system.drop_item()
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text == "—", "Carried item returns to '—' after drop")

	var part := Carriable.new()
	part.item_name = "Replacement Screen"
	part.item_type = "part"
	add_child(part)

	player.carry_system.pick_up(part)
	hud._update_carried_item()
	err += _assert(hud.carried_item_name.text == "Replacement Screen", "Carried item shows replacement part name")

	player.carry_system.drop_item()
	part.queue_free()
	device.queue_free()
	player.queue_free()
	hud.queue_free()
	return err


## Test contextual interaction prompt when focusing interactables
func test_hud_contextual_prompt() -> int:
	print("Testing HUD contextual interaction prompt...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	var player: PlayerCharacter = _create_test_player()
	add_child(hud)
	hud.setup(player, null)

	# Initially no focus -> prompt invisible
	hud._update_interaction_prompt()
	err += _assert(not hud.interaction_prompt.visible, "Interaction prompt is hidden when no focus")

	# Simulate DiagnosticBench in range
	var bench: DiagnosticBench = load("res://scenes/stations/DiagnosticBench.tscn").instantiate()
	add_child(bench)

	# Give player a device to diagnose
	var dev: Device = load("res://scenes/devices/Device.tscn").instantiate()
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)
	player.carry_system.pick_up(dev)

	# Simulate interaction system focus
	bench.interaction_zone.focus_gained.emit(player)
	player.interaction_system._current_focus = bench.interaction_zone

	hud._update_interaction_prompt()
	err += _assert(hud.interaction_prompt.visible, "Interaction prompt is visible when focusing bench")
	err += _assert(hud.prompt_label.text.contains("[E]"), "Prompt includes action button [E]")
	err += _assert(hud.prompt_label.text.contains("Diagnose Device"), "Prompt contains action description 'Diagnose Device'")

	# Lose focus
	bench.interaction_zone.focus_lost.emit(player)
	player.interaction_system._current_focus = null
	hud._update_interaction_prompt()
	err += _assert(not hud.interaction_prompt.visible, "Interaction prompt hides when focus lost")

	dev.queue_free()
	bench.queue_free()
	player.queue_free()
	hud.queue_free()
	return err


## Test active orders display, timer bar countdown, and color changes
func test_hud_active_orders_and_timers() -> int:
	print("Testing HUD active orders, countdown timer, and color changes...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	var mgr := OrderManager.new()
	add_child(hud)
	add_child(mgr)

	hud.setup(null, mgr)

	# Spawn an order
	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var order: Order = mgr.spawn_order(phone_data)
	order.time_limit = 100.0
	order.time_remaining = 100.0

	hud._update_active_orders()
	err += _assert(hud._order_entries.has(order), "HUD tracks spawned order entry")
	var entry: HBoxContainer = hud._order_entries[order]
	var bar: ProgressBar = entry.get_node_or_null("TimerBar") as ProgressBar
	var name_lbl: Label = entry.get_node_or_null("DeviceName") as Label

	err += _assert(entry.visible, "OrderEntry is visible")
	err += _assert(name_lbl.text.contains("Phone"), "OrderEntry shows 'Phone'")
	err += _assert(bar.value == 100.0, "TimerBar value is 100.0")

	# Test Healthy timer color (> 50%)
	order.tick(20.0) # 80% remaining
	hud._update_active_orders()
	err += _assert(bar.modulate == HUD.COLOR_TIMER_HEALTHY, "TimerBar is healthy green at 80% time remaining")

	# Test Warning timer color (20% - 50%)
	order.tick(45.0) # 35% remaining
	hud._update_active_orders()
	err += _assert(bar.modulate == HUD.COLOR_TIMER_WARNING, "TimerBar is warning yellow at 35% time remaining")

	# Test Critical timer color (< 20%)
	order.tick(25.0) # 10% remaining
	hud._update_active_orders()
	err += _assert(bar.modulate == HUD.COLOR_TIMER_CRITICAL, "TimerBar is critical red at 10% time remaining")

	if order.device_instance:
		order.device_instance.queue_free()
	mgr.queue_free()
	hud.queue_free()
	return err


## Test score update, star display rating, and completion banner
func test_hud_scoring_and_stars() -> int:
	print("Testing HUD score display, star rating, and completion banner...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	# Initial values
	err += _assert(hud.score_label.text == "Score: 0", "Initial score is Score: 0")

	# Update score and stars directly
	hud._update_score_display(300)
	err += _assert(hud.score_label.text == "Score: 300", "Score updated to Score: 300")

	hud._update_star_display(3)
	var star1: Label = hud.star_display.get_node_or_null("Star1") as Label
	var star2: Label = hud.star_display.get_node_or_null("Star2") as Label
	var star3: Label = hud.star_display.get_node_or_null("Star3") as Label
	err += _assert(star1.modulate == HUD.COLOR_STAR_EARNED, "Star 1 earned")
	err += _assert(star2.modulate == HUD.COLOR_STAR_EARNED, "Star 2 earned")
	err += _assert(star3.modulate == HUD.COLOR_STAR_EARNED, "Star 3 earned")

	# Trigger completion animation
	hud.show_order_completed_animation(3, 300)
	err += _assert(hud.completion_banner != null and hud.completion_banner.visible, "Completion banner is visible")
	err += _assert(hud.banner_label != null and hud.banner_label.text.contains("+300 PTS"), "Banner contains '+300 PTS'")
	err += _assert(hud.banner_label.text.contains("★"), "Banner contains star symbols")

	hud.queue_free()
	return err


## Test F4 key toggles HUD visibility
func test_hud_visibility_toggle() -> int:
	print("Testing F4 key toggles HUD visibility...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	err += _assert(hud.visible == true, "HUD initially visible")

	var f4_event := InputEventKey.new()
	f4_event.keycode = KEY_F4
	f4_event.pressed = true
	hud._unhandled_input(f4_event)
	err += _assert(hud.visible == false, "HUD hidden after F4 press")

	hud._unhandled_input(f4_event)
	err += _assert(hud.visible == true, "HUD visible again after second F4 press")

	hud.queue_free()
	return err
