extends Node

## Test suite for Component Variety & Parts Stock
## Tests PartsShelf stock limits, out-of-stock feedback, stock display,
## wrong part rejection on WorkbenchStation, restocking, and DeliveryBox unpacking.

const PARTS_SHELF_SCENE_PATH: String = "res://scenes/stations/PartsShelf.tscn"
const WORKBENCH_SCENE_PATH: String = "res://scenes/stations/WorkbenchStation.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"
const DEAD_BATTERY_FAULT_PATH: String = "res://resources/faults/phone_dead_battery.tres"
const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"
const DELIVERY_BOX_SCENE_PATH: String = "res://scenes/tools/DeliveryBox.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 3D PARTS STOCK TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_parts_shelf_stock_initialization_and_depletion()
	failures += test_parts_shelf_display_and_cycling()
	failures += test_workbench_wrong_part_rejection()
	failures += test_workbench_correct_part_installation()
	failures += test_parts_shelf_restock_and_delivery_box()
	failures += test_workshop_debug_stock_integration()

	print("=========================================================")
	print("--- PHASE 3D TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 3D TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 3D tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		print("  [FAIL] %s" % test_name)
		return 1


## 1. Test PartsShelf stock initialization and depletion
func test_parts_shelf_stock_initialization_and_depletion() -> int:
	print("\n[1] Testing PartsShelf stock initialization, decrement, and depletion...")
	var err: int = 0

	var shelf_scene: PackedScene = load(PARTS_SHELF_SCENE_PATH)
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	shelf.initial_stock_per_part = 2
	add_child(shelf)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	err += _assert(shelf.stock_tracking_enabled, "Stock tracking is enabled by default")
	err += _assert(shelf.get_stock("screen") == 2, "Screen initial stock is 2")
	err += _assert(shelf.get_stock("battery") == 2, "Battery initial stock is 2")
	err += _assert(shelf.has_stock("screen"), "has_stock('screen') is true")

	# Track signals using Dictionary for mutable closure capture
	var flags: Dictionary = {
		"dispensed_count": 0,
		"out_of_stock_detected": false,
		"bus_dispensed": false,
		"bus_out_of_stock": false
	}

	shelf.stock_changed.connect(func(_id: String, _rem: int) -> void:
		flags["dispensed_count"] += 1
	)
	shelf.stock_depleted.connect(func(id: String) -> void:
		if id == "screen" or id == "phone_screen":
			flags["out_of_stock_detected"] = true
	)
	SignalBus.part_dispensed.connect(func(id: String, _rem: int) -> void:
		if id == "screen" or id == "phone_screen":
			flags["bus_dispensed"] = true
	)
	SignalBus.part_out_of_stock.connect(func(id: String) -> void:
		if id == "screen" or id == "phone_screen":
			flags["bus_out_of_stock"] = true
	)

	# Pick up 1st screen
	shelf.set_selected_part_by_id("screen")
	err += _assert(shelf.can_player_interact(player), "Player can interact to take part")
	shelf._on_interacted(player)

	err += _assert(player.carry_system.is_carrying(), "Player picked up 1st screen")
	err += _assert(shelf.get_stock("screen") == 1, "Screen stock decremented to 1")
	err += _assert(flags["bus_dispensed"], "SignalBus.part_dispensed emitted")

	var item1 := player.carry_system.get_held_item()
	player.carry_system.drop_item()
	if item1:
		item1.queue_free()

	# Pick up 2nd screen (depletes stock to 0)
	shelf._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up 2nd screen")
	err += _assert(shelf.get_stock("screen") == 0, "Screen stock decremented to 0")
	err += _assert(not shelf.has_stock("screen"), "has_stock('screen') is now false")
	err += _assert(flags["out_of_stock_detected"], "shelf.stock_depleted signal fired for screen")
	err += _assert(flags["bus_out_of_stock"], "SignalBus.part_out_of_stock emitted for screen")

	var item2 := player.carry_system.get_held_item()
	player.carry_system.drop_item()
	if item2:
		item2.queue_free()

	# Attempt to pick up 3rd screen (should be rejected)
	var prompt := shelf.get_interaction_prompt(player)
	err += _assert("OUT OF STOCK" in prompt, "Prompt reflects OUT OF STOCK: %s" % prompt)

	shelf._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Player hands remain empty when part is out of stock")
	err += _assert(shelf.get_stock("screen") == 0, "Stock stays at 0")

	# Other parts still in stock
	err += _assert(shelf.get_stock("battery") == 2, "Battery is still in stock (2)")

	shelf.queue_free()
	player.queue_free()
	return err


## 2. Test PartsShelf stock display and cycling
func test_parts_shelf_display_and_cycling() -> int:
	print("\n[2] Testing PartsShelf 3D StockLabel display and part cycling...")
	var err: int = 0

	var shelf_scene: PackedScene = load(PARTS_SHELF_SCENE_PATH)
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	add_child(shelf)

	var label := shelf.stock_display_label
	err += _assert(label != null, "PartsShelf created or has StockLabel")
	if label:
		err += _assert("Screen: 3" in label.text, "StockLabel displays initial Screen count: %s" % label.text)

	# Test cycling parts
	var initial_part := shelf.get_selected_part()
	var next_part := shelf.cycle_next_part()
	err += _assert(next_part != null and next_part != initial_part, "cycle_next_part cycled to next part")

	# Deplete a part and check display string "OUT"
	shelf.restock("screen", -shelf.get_stock("screen"))
	err += _assert(shelf.get_stock("screen") == 0, "Screen forced to 0")
	if label:
		err += _assert("OUT" in label.text, "StockLabel text contains 'OUT' when depleted: %s" % label.text)

	shelf.queue_free()
	return err


## 3. Test Workbench wrong part detection and rejection
func test_workbench_wrong_part_rejection() -> int:
	print("\n[3] Testing WorkbenchStation wrong part detection, rejection, and non-consumption...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	# Set up phone with cracked screen fault (needs SCREEN, NOT battery)
	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	add_child(dev)

	wb.accept_device(dev)
	# Advance to DISASSEMBLED
	dev.advance_state(RepairState.State.DISASSEMBLED)

	# Give player a BATTERY part (WRONG part)
	var battery_comp: ComponentData = load("res://resources/components/battery.tres")
	var wrong_part := Carriable.new()
	wrong_part.item_name = "Battery"
	wrong_part.item_type = "part"
	wrong_part.set_meta("component_data", battery_comp)
	add_child(wrong_part)
	player.carry_system.pick_up(wrong_part)

	err += _assert(not wb._is_valid_replacement_part(dev, wrong_part), "wb._is_valid_replacement_part returns false for wrong part")
	err += _assert(not wb.can_player_interact(player), "Workbench rejects interaction with wrong part")

	var prompt := wb.get_interaction_prompt(player)
	err += _assert(prompt.contains("Wrong Part"), "Prompt indicates Wrong Replacement Part: %s" % prompt)

	# Track hazard signal using Dictionary for mutable closure capture
	var hazard_flags: Dictionary = {"wrong_part_emitted": false}
	var callable = func(h_name: String, h_type: String) -> void:
		if h_name == "Wrong Part" or h_type == "wrong_part":
			hazard_flags["wrong_part_emitted"] = true
	SignalBus.hazard_activated.connect(callable)

	# Attempt to install wrong part
	wb._try_install_part(player)

	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Device repair state remains DISASSEMBLED after wrong part")
	err += _assert(player.carry_system.is_carrying(), "Wrong part was NOT consumed — still held by player")
	err += _assert(player.carry_system.get_held_item() == wrong_part, "Player still holds the battery")
	err += _assert(hazard_flags["wrong_part_emitted"], "SignalBus.hazard_activated emitted for Wrong Part")

	SignalBus.hazard_activated.disconnect(callable)
	wrong_part.queue_free()
	dev.queue_free()
	player.queue_free()
	wb.queue_free()
	return err


## 4. Test Workbench correct part installation
func test_workbench_correct_part_installation() -> int:
	print("\n[4] Testing WorkbenchStation correct part installation...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	add_child(dev)

	wb.accept_device(dev)
	dev.advance_state(RepairState.State.DISASSEMBLED)

	# Give player a SCREEN part (CORRECT part)
	var screen_comp: ComponentData = load("res://resources/components/screen.tres")
	var correct_part := Carriable.new()
	correct_part.item_name = "Screen"
	correct_part.item_type = "part"
	correct_part.set_meta("component_data", screen_comp)
	add_child(correct_part)
	player.carry_system.pick_up(correct_part)

	err += _assert(wb._is_valid_replacement_part(dev, correct_part), "wb._is_valid_replacement_part returns true for correct part")
	err += _assert(wb.get_interaction_prompt(player) == "Install Screen", "Prompt is 'Install Screen'")

	wb._on_interacted(player)

	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Device advanced to PART_REPLACED")
	err += _assert(not player.carry_system.is_carrying(), "Correct part was consumed and removed from player hands")

	dev.queue_free()
	player.queue_free()
	wb.queue_free()
	return err


## 5. Test PartsShelf restocking and DeliveryBox unpacking
func test_parts_shelf_restock_and_delivery_box() -> int:
	print("\n[5] Testing PartsShelf restocking and DeliveryBox unpacking...")
	var err: int = 0

	var shelf_scene: PackedScene = load(PARTS_SHELF_SCENE_PATH)
	var shelf: PartsShelf = shelf_scene.instantiate() as PartsShelf
	add_child(shelf)

	# Deplete screen
	shelf.restock("screen", -shelf.get_stock("screen"))
	err += _assert(shelf.get_stock("screen") == 0, "Screen stock is 0")

	# Manual restock method
	shelf.restock("screen", 4)
	err += _assert(shelf.get_stock("screen") == 4, "shelf.restock('screen', 4) restored stock to 4")

	# restock_all
	shelf.restock_all(5)
	err += _assert(shelf.get_stock("screen") == 5, "restock_all set screen to 5")
	err += _assert(shelf.get_stock("battery") == 5, "restock_all set battery to 5")

	# Test DeliveryBox unpacking
	shelf.restock("screen", -5) # Screen at 0
	err += _assert(shelf.get_stock("screen") == 0, "Screen at 0 before DeliveryBox")

	var box_scene: PackedScene = load(DELIVERY_BOX_SCENE_PATH)
	var box: DeliveryBox = box_scene.instantiate() as DeliveryBox
	box.contained_parts = {"screen": 3, "battery": 2}
	add_child(box)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	player.carry_system.pick_up(box)
	err += _assert(player.carry_system.is_carrying(), "Player carrying DeliveryBox")
	err += _assert(shelf.can_player_interact(player), "Player carrying DeliveryBox can interact with PartsShelf")
	err += _assert("Unpack" in shelf.get_interaction_prompt(player), "Prompt is 'Unpack ...'")

	shelf._on_interacted(player)

	err += _assert(shelf.get_stock("screen") == 3, "DeliveryBox restocked screen to 3")
	err += _assert(shelf.get_stock("battery") == 7, "DeliveryBox restocked battery to 7")
	err += _assert(not player.carry_system.is_carrying(), "Player hands freed after unpacking DeliveryBox")

	shelf.queue_free()
	player.queue_free()
	return err


## 6. Test WorkshopDebug stock integration and Ctrl+F8 hotkey
func test_workshop_debug_stock_integration() -> int:
	print("\n[6] Testing WorkshopDebug parts stock integration and Ctrl+F8 hotkey...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	add_child(workshop)

	workshop.start_round()

	err += _assert(workshop.parts_shelf != null, "Workshop has parts_shelf wired")
	err += _assert(workshop.parts_shelf.stock_tracking_enabled, "Workshop parts_shelf has stock tracking enabled")
	err += _assert(workshop.parts_shelf.get_stock("screen") == Constants.DEFAULT_INITIAL_STOCK_PER_PART, "Initial screen stock is 3")

	# Deplete and use Ctrl+F8 restock
	workshop.parts_shelf.restock("screen", -3)
	err += _assert(workshop.parts_shelf.get_stock("screen") == 0, "Screen depleted to 0")

	workshop._debug_restock_shelf()
	err += _assert(workshop.parts_shelf.get_stock("screen") == 3, "Ctrl+F8 restocked screen to 3")

	# Test delivery box spawning in workshop
	var box := workshop.spawn_delivery_box({"screen": 2})
	err += _assert(box != null and is_instance_valid(box), "spawn_delivery_box returned valid DeliveryBox")
	err += _assert(box.contained_parts.get("screen", 0) == 2, "Spawned box contains 2 screens")

	box.queue_free()
	workshop.queue_free()
	return err
