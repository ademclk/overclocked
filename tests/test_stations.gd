extends Node

## Test suite for BaseStation, StationInteractionZone, and the 6 workshop station types.


func _ready() -> void:
	print("--- RUNNING STATIONS TESTS ---")
	var failures: int = 0

	failures += test_station_scenes_and_types()
	failures += test_base_station_lifecycle()
	failures += test_visual_states_and_highlight()
	failures += test_reception_desk_flow()
	failures += test_diagnostic_bench_flow()
	failures += test_workbench_flow()
	failures += test_parts_shelf_flow()
	failures += test_software_station_flow()
	failures += test_delivery_counter_flow()
	failures += test_workshop_debug_integration()

	print("--- STATIONS TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL STATIONS TESTS PASSED SUCCESSFULLY ---")
		get_tree().quit(0)
	else:
		printerr("Stations tests FAILED with %d error(s)." % failures)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_dummy_carriable(item_name: String = "TestDevice", item_type: String = "device") -> Carriable:
	var item := Carriable.new()
	item.name = item_name
	item.item_name = item_name
	item.item_type = item_type
	return item


func _create_test_player() -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	add_child(player)
	return player


func test_station_scenes_and_types() -> int:
	print("Testing station scenes and types...")
	var err: int = 0

	var scenes: Dictionary = {
		"BaseStation": "res://scenes/stations/BaseStation.tscn",
		"ReceptionDesk": "res://scenes/stations/ReceptionDesk.tscn",
		"DiagnosticBench": "res://scenes/stations/DiagnosticBench.tscn",
		"Workbench": "res://scenes/stations/WorkbenchStation.tscn",
		"PartsShelf": "res://scenes/stations/PartsShelf.tscn",
		"SoftwareStation": "res://scenes/stations/SoftwareStation.tscn",
		"DeliveryCounter": "res://scenes/stations/DeliveryCounter.tscn",
	}

	for key: String in scenes:
		var path: String = scenes[key]
		var scene: PackedScene = load(path)
		err += _assert(scene != null, "%s scene loads from %s" % [key, path])
		if scene:
			var instance: Node = scene.instantiate()
			err += _assert(instance is BaseStation, "%s instance is BaseStation" % key)
			err += _assert(instance.has_node("InteractionZone"), "%s has InteractionZone" % key)
			err += _assert(instance.has_node("DeviceSlot"), "%s has DeviceSlot" % key)
			err += _assert(instance.has_node("StationLabel"), "%s has StationLabel" % key)
			instance.queue_free()

	return err


func test_base_station_lifecycle() -> int:
	print("Testing BaseStation lifecycle...")
	var err: int = 0

	var station := BaseStation.new()
	station.station_name = "TestStation"
	station.processing_time = 0.5
	var slot := Marker3D.new()
	slot.name = "DeviceSlot"
	station.add_child(slot)
	add_child(station)

	err += _assert(station.current_state == BaseStation.StationState.IDLE, "Initial state is IDLE")

	var device := _create_dummy_carriable("Phone")
	add_child(device)

	err += _assert(station.can_accept_device(device), "Can accept device when IDLE")

	var accepted := [false]
	station.device_accepted.connect(func(_d): accepted[0] = true)
	station.accept_device(device)

	err += _assert(accepted[0], "device_accepted signal emitted")
	err += _assert(station.current_state == BaseStation.StationState.OCCUPIED, "State is OCCUPIED after accept")
	err += _assert(station.placed_device == device, "placed_device is set to device")
	err += _assert(device.get_parent() == slot, "Device is parented to DeviceSlot")
	err += _assert(not station.can_accept_device(device), "Cannot accept another device while OCCUPIED")

	var started := [false]
	station.processing_started.connect(func(_d): started[0] = true)
	station.start_processing()

	err += _assert(started[0], "processing_started signal emitted")
	err += _assert(station.current_state == BaseStation.StationState.PROCESSING, "State is PROCESSING")

	# Advance physics process
	station._physics_process(0.25)
	err += _assert(absf(station.get_progress() - 0.5) < 0.05, "Progress is ~50% at half time")

	var completed := [false]
	station.processing_completed.connect(func(_d): completed[0] = true)
	station._physics_process(0.3)

	err += _assert(completed[0], "processing_completed signal emitted")
	err += _assert(station.current_state == BaseStation.StationState.COMPLETE, "State is COMPLETE after time")

	var removed := [false]
	station.device_removed.connect(func(_d): removed[0] = true)
	var removed_device: Carriable = station.remove_device()

	err += _assert(removed[0], "device_removed signal emitted")
	err += _assert(removed_device == device, "Removed device matches placed device")
	err += _assert(station.current_state == BaseStation.StationState.IDLE, "State returns to IDLE after remove")
	err += _assert(station.placed_device == null, "placed_device is null after remove")

	station.queue_free()
	device.queue_free()
	return err


func test_visual_states_and_highlight() -> int:
	print("Testing visual states and highlight...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/BaseStation.tscn")
	var station: BaseStation = scene.instantiate()
	add_child(station)

	var label: Label3D = station.get_node("ProgressIndicator/ProgressLabel") as Label3D
	err += _assert(label != null, "ProgressLabel exists")
	err += _assert(not label.visible, "ProgressLabel is hidden when IDLE")

	var device := _create_dummy_carriable("Item")
	add_child(device)
	station.accept_device(device)
	station.start_processing()

	err += _assert(label.visible, "ProgressLabel visible during processing")
	err += _assert(label.text.contains("%"), "ProgressLabel contains percentage during processing")

	station._physics_process(station.processing_time + 0.1)
	err += _assert(label.text.contains("READY"), "ProgressLabel shows READY when COMPLETE")

	# Test focus highlight
	var player := _create_test_player()
	station._on_focus_gained(player)
	err += _assert(
		station._station_material != null and station._station_material.emission_enabled,
		"Station material has emission enabled when focused"
	)

	station._on_focus_lost(player)
	err += _assert(
		station._station_material != null and not station._station_material.emission_enabled,
		"Station material emission disabled when focus lost"
	)

	player.queue_free()
	station.queue_free()
	device.queue_free()
	return err


func test_reception_desk_flow() -> int:
	print("Testing ReceptionDesk flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/ReceptionDesk.tscn")
	var desk: ReceptionDesk = scene.instantiate()
	add_child(desk)

	var player := _create_test_player()
	err += _assert(not desk.can_player_interact(player), "Player cannot interact when desk is empty")

	var device := _create_dummy_carriable("CustomerPhone")
	desk.spawn_incoming_device(device)

	err += _assert(desk.has_device(), "Desk has incoming device")
	err += _assert(desk.can_player_interact(player), "Player can interact when device is on desk")
	err += _assert(desk.get_interaction_prompt(player) == "Pick Up Device", "Prompt is 'Pick Up Device'")

	desk._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up device from reception desk")
	err += _assert(player.carry_system.get_held_item() == device, "Held item is the customer device")
	err += _assert(not desk.has_device(), "Reception desk is empty after pickup")

	player.queue_free()
	desk.queue_free()
	device.queue_free()
	return err


func test_diagnostic_bench_flow() -> int:
	print("Testing DiagnosticBench flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/DiagnosticBench.tscn")
	var bench: DiagnosticBench = scene.instantiate()
	add_child(bench)

	var player := _create_test_player()
	var device := _create_dummy_carriable("PhoneToDiagnose")
	add_child(device)

	player.carry_system.pick_up(device)
	err += _assert(bench.can_player_interact(player), "Player carrying device can interact with empty bench")
	err += _assert(bench.get_interaction_prompt(player) == "Diagnose Device", "Prompt is 'Diagnose Device'")

	bench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Device placed on diagnostic bench")
	err += _assert(bench.placed_device == device, "Device is on diagnostic bench")
	err += _assert(bench.current_state == BaseStation.StationState.PROCESSING, "Bench automatically starts processing")

	# Wait for diagnosis to complete
	bench._physics_process(bench.diagnosis_time + 0.1)
	err += _assert(bench.current_state == BaseStation.StationState.COMPLETE, "Bench reaches COMPLETE state")
	err += _assert(bench.can_player_interact(player), "Player can interact to pick up diagnosed device")
	err += _assert(bench.get_interaction_prompt(player) == "Pick Up Diagnosed Device", "Prompt is 'Pick Up Diagnosed Device'")

	bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picks up diagnosed device")
	err += _assert(bench.placed_device == null, "Bench is empty again")

	player.queue_free()
	bench.queue_free()
	device.queue_free()
	return err


func test_workbench_flow() -> int:
	print("Testing WorkbenchStation flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/WorkbenchStation.tscn")
	var bench: WorkbenchStation = scene.instantiate()
	add_child(bench)

	var player := _create_test_player()
	var device := _create_dummy_carriable("PhoneOnWorkbench")
	add_child(device)

	player.carry_system.pick_up(device)
	err += _assert(bench.can_player_interact(player), "Player can place device on workbench")
	err += _assert(bench.get_interaction_prompt(player) == "Place Device on Workbench", "Prompt is 'Place Device on Workbench'")

	bench._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Device placed on workbench")
	err += _assert(bench.placed_device == device, "Bench has device")

	# Picking device up when device doesn't have custom repair state
	err += _assert(bench.can_player_interact(player), "Player can pick up device from workbench")
	bench._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked device back up")

	player.queue_free()
	bench.queue_free()
	device.queue_free()
	return err


func test_parts_shelf_flow() -> int:
	print("Testing PartsShelf flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/PartsShelf.tscn")
	var shelf: PartsShelf = scene.instantiate()
	add_child(shelf)

	var player := _create_test_player()
	err += _assert(shelf.can_player_interact(player), "Player with empty hands can take part")
	err += _assert(shelf.get_interaction_prompt(player) == "Take Replacement Part", "Prompt is 'Take Replacement Part'")

	shelf._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player picked up part from shelf")
	var part: Carriable = player.carry_system.get_held_item()
	err += _assert(part != null and part.item_type == "part", "Item is of type 'part'")

	err += _assert(not shelf.can_player_interact(player), "Player with full hands cannot take another part")
	err += _assert(shelf.get_interaction_prompt(player) == "Hands Full", "Prompt indicates hands are full")

	part.queue_free()
	player.queue_free()
	shelf.queue_free()
	return err


func test_software_station_flow() -> int:
	print("Testing SoftwareStation flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/SoftwareStation.tscn")
	var sw: SoftwareStation = scene.instantiate()
	add_child(sw)

	var player := _create_test_player()
	var device := _create_dummy_carriable("ReassembledDevice")
	add_child(device)

	player.carry_system.pick_up(device)
	err += _assert(sw.can_player_interact(player), "Can place device on software station")
	err += _assert(sw.get_interaction_prompt(player) == "Install Software", "Prompt is 'Install Software'")

	sw._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Device placed on software station")
	err += _assert(sw.current_state == BaseStation.StationState.PROCESSING, "Software station begins processing")

	sw._physics_process(sw.software_install_time + 0.1)
	err += _assert(sw.current_state == BaseStation.StationState.COMPLETE, "Software station complete")
	err += _assert(sw.can_player_interact(player), "Player can pick up tested device")
	err += _assert(sw.get_interaction_prompt(player) == "Pick Up Tested Device", "Prompt is 'Pick Up Tested Device'")

	sw._on_interacted(player)
	err += _assert(player.carry_system.is_carrying(), "Player retrieved tested device")

	player.queue_free()
	sw.queue_free()
	device.queue_free()
	return err


func test_delivery_counter_flow() -> int:
	print("Testing DeliveryCounter flow...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/stations/DeliveryCounter.tscn")
	var counter: DeliveryCounter = scene.instantiate()
	add_child(counter)

	var player := _create_test_player()
	var device := _create_dummy_carriable("RepairedPhone")
	add_child(device)

	err += _assert(not counter.can_player_interact(player), "Player cannot interact when not carrying device")

	player.carry_system.pick_up(device)
	err += _assert(counter.can_player_interact(player), "Player carrying device can deliver it")
	var prompt: String = counter.get_interaction_prompt(player)
	err += _assert(prompt == "Deliver Repaired Device", "Prompt is 'Deliver Repaired Device'")

	var delivered := [false]
	counter.device_delivered.connect(func(_d): delivered[0] = true)

	var global_signal := [false]
	SignalBus.device_repaired.connect(func(_name): global_signal[0] = true)

	counter._on_interacted(player)
	err += _assert(not player.carry_system.is_carrying(), "Device delivered from player hands")
	err += _assert(delivered[0], "device_delivered signal emitted")
	err += _assert(global_signal[0], "SignalBus.device_repaired signal emitted")
	err += _assert(counter.current_state == BaseStation.StationState.COMPLETE, "Counter state is COMPLETE")

	player.queue_free()
	counter.queue_free()
	device.queue_free()
	return err


func test_workshop_debug_integration() -> int:
	print("Testing WorkshopDebug integration with all stations...")
	var err: int = 0

	var scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn")
	var workshop: WorkshopDebug = scene.instantiate()
	workshop.auto_spawn_player = true
	add_child(workshop)

	err += _assert(workshop.active_players.size() == 1, "Player auto-spawned in workshop")
	var player: PlayerCharacter = workshop.get_player(0)
	err += _assert(player != null, "Active player is accessible")

	var stations: Array[BaseStation] = workshop.get_all_stations()
	err += _assert(stations.size() == 6, "Workshop contains all 6 BaseStations (found %d)" % stations.size())

	err += _assert(workshop.reception_desk != null, "reception_desk reference is wired")
	err += _assert(workshop.diagnostic_bench != null, "diagnostic_bench reference is wired")
	err += _assert(workshop.workbench != null, "workbench reference is wired")
	err += _assert(workshop.parts_shelf != null, "parts_shelf reference is wired")
	err += _assert(workshop.software_station != null, "software_station reference is wired")
	err += _assert(workshop.delivery_counter != null, "delivery_counter reference is wired")

	err += _assert(workshop.get_station("reception") is ReceptionDesk, "get_station('reception') returns ReceptionDesk")
	err += _assert(workshop.get_station("diagnostic") is DiagnosticBench, "get_station('diagnostic') returns DiagnosticBench")
	err += _assert(workshop.get_station("workbench") is WorkbenchStation, "get_station('workbench') returns WorkbenchStation")
	err += _assert(workshop.get_station("shelf") is PartsShelf, "get_station('shelf') returns PartsShelf")
	err += _assert(workshop.get_station("software") is SoftwareStation, "get_station('software') returns SoftwareStation")
	err += _assert(workshop.get_station("delivery") is DeliveryCounter, "get_station('delivery') returns DeliveryCounter")

	workshop.queue_free()
	return err
