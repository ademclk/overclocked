extends Node

## Test suite for Station Occupancy Rules
## Tests:
## 1. BaseStation occupancy API (_active_user, set_active_user, clear_active_user, is_occupied)
## 2. Occupancy enforcement and rejection (can_player_interact, get_interaction_prompt)
## 3. DiagnosticBench occupancy flow and device pickup release
## 4. Auto-release of occupancy on focus loss when not processing
## 5. Processing station occupancy retention and auto-release when completed after focus loss
## 6. Workbench hand-off flow between players (P1 disassembles -> P2 installs part)
## 7. Visual indicator: player color glow on station when occupied
## 8. Multi-player focus tracking on stations
## 9. InteractionSystem and HUD prompt integration for occupied stations
## 10. Reception Desk and Parts Shelf independence (no blocking occupancy)

const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const DIAGNOSTIC_SCENE_PATH: String = "res://scenes/stations/DiagnosticBench.tscn"
const WORKBENCH_SCENE_PATH: String = "res://scenes/stations/WorkbenchStation.tscn"
const SOFTWARE_SCENE_PATH: String = "res://scenes/stations/SoftwareStation.tscn"
const DELIVERY_SCENE_PATH: String = "res://scenes/stations/DeliveryCounter.tscn"
const RECEPTION_SCENE_PATH: String = "res://scenes/stations/ReceptionDesk.tscn"
const PARTS_SHELF_SCENE_PATH: String = "res://scenes/stations/PartsShelf.tscn"
const HUD_SCENE_PATH: String = "res://scenes/ui/HUD.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2F STATION OCCUPANCY TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_base_station_occupancy_api()
	failures += test_station_occupancy_rejection()
	failures += test_diagnostic_bench_occupancy_lifecycle()
	failures += test_occupancy_auto_release_on_focus_loss()
	failures += test_occupancy_during_processing_focus_loss()
	failures += test_workbench_handoff_between_players()
	failures += test_player_color_glow_indicator()
	failures += test_multiplayer_focus_tracking()
	failures += test_interaction_system_and_hud_prompt()
	failures += test_reception_and_parts_shelf_independence()

	print("=========================================================")
	print("--- PHASE 2F TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2F STATION OCCUPANCY TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2F tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_player(index: int) -> PlayerCharacter:
	var scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = scene.instantiate() as PlayerCharacter
	player.player_index = index
	add_child(player)
	return player


func _create_dummy_device(item_name: String = "Phone", r_state: String = "RECEIVED") -> Carriable:
	var item := Carriable.new()
	item.name = item_name
	item.item_name = item_name
	item.item_type = "device"
	item.set_meta("repair_state", r_state)
	return item


## 1. Test BaseStation occupancy API
func test_base_station_occupancy_api() -> int:
	print("\n[1] Testing BaseStation occupancy API...")
	var err: int = 0

	var station := BaseStation.new()
	station.station_name = "TestBench"
	add_child(station)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	err += _assert(station.get_active_user() == null, "Initial active_user is null")
	err += _assert(not station.is_occupied(), "Initial is_occupied is false")
	err += _assert(station.can_player_interact(p1), "p1 can interact when unoccupied")
	err += _assert(station.can_player_interact(p2), "p2 can interact when unoccupied")

	# Track signal emissions
	var user_changed_events: Array[Dictionary] = []
	station.user_changed.connect(func(old_u, new_u):
		user_changed_events.append({"old": old_u, "new": new_u})
	)

	var bus_occupied_events: Array[Dictionary] = []
	SignalBus.station_occupied.connect(func(s_name, pid):
		bus_occupied_events.append({"station": s_name, "player_id": pid})
	)

	var bus_released_events: Array[String] = []
	SignalBus.station_released.connect(func(s_name):
		bus_released_events.append(s_name)
	)

	# Set active user to p1
	station.set_active_user(p1)
	err += _assert(station.get_active_user() == p1, "active_user is p1")
	err += _assert(station.is_occupied(), "is_occupied is true")
	err += _assert(station.can_player_interact(p1), "p1 can interact with their occupied station")
	err += _assert(not station.can_player_interact(p2), "p2 cannot interact with station occupied by p1")
	err += _assert(station.get_interaction_prompt(p2) == "In use by P1", "p2 prompt shows 'In use by P1'")
	err += _assert(user_changed_events.size() == 1, "user_changed signal emitted")
	err += _assert(user_changed_events[0].old == null and user_changed_events[0].new == p1, "user_changed had correct users")
	err += _assert(bus_occupied_events.size() == 1, "SignalBus.station_occupied emitted")
	err += _assert(bus_occupied_events[0].player_id == 0, "SignalBus.station_occupied had player_id 0")

	# Wrong player attempts to clear occupancy
	station.clear_active_user(p2)
	err += _assert(station.get_active_user() == p1, "p2 cannot clear p1's occupancy")
	err += _assert(station.is_occupied(), "station remains occupied")

	# Right player clears occupancy
	station.clear_active_user(p1)
	err += _assert(station.get_active_user() == null, "active_user is now null")
	err += _assert(not station.is_occupied(), "is_occupied is now false")
	err += _assert(station.can_player_interact(p2), "p2 can interact after clearance")
	err += _assert(bus_released_events.size() == 1, "SignalBus.station_released emitted")

	station.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 2. Test occupancy rejection during interaction attempts
func test_station_occupancy_rejection() -> int:
	print("\n[2] Testing station interaction rejection for non-active players...")
	var err: int = 0

	var station := BaseStation.new()
	station.station_name = "BusyBench"
	add_child(station)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	station.set_active_user(p1)

	var interacted_pids: Array[int] = []
	var on_interacted_called: Array[bool] = [false]
	SignalBus.station_interacted.connect(func(_s_name, pid):
		interacted_pids.append(pid)
	)

	# P2 attempts interaction zone interact
	station.can_player_interact(p2)
	err += _assert(not station.can_player_interact(p2), "p2 can_player_interact is false")
	err += _assert(station.get_interaction_prompt(p2) == "In use by P1", "prompt is 'In use by P1'")

	station.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 3. Test DiagnosticBench occupancy lifecycle and device pickup release
func test_diagnostic_bench_occupancy_lifecycle() -> int:
	print("\n[3] Testing DiagnosticBench occupancy lifecycle...")
	var err: int = 0

	var bench: DiagnosticBench = load(DIAGNOSTIC_SCENE_PATH).instantiate() as DiagnosticBench
	add_child(bench)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load("res://resources/devices/phone.tres"))
	add_child(dev)

	p1.carry_system.pick_up(dev)
	err += _assert(bench.can_player_interact(p1), "p1 can interact with empty diagnostic bench")

	# P1 places device
	bench._on_interacted(p1)
	err += _assert(bench.is_occupied(), "bench is occupied after placing device")
	err += _assert(bench.get_active_user() == p1, "bench active_user is p1")
	err += _assert(not bench.can_player_interact(p2), "p2 cannot interact while bench is occupied by p1")
	err += _assert(bench.get_interaction_prompt(p2) == "In use by P1", "p2 prompt shows 'In use by P1'")

	# P2 tries to interact while occupied
	bench._on_interacted(p2)
	err += _assert(not p2.carry_system.is_carrying(), "p2 interaction rejected")

	# Fast-forward diagnosis processing
	bench._physics_process(bench.diagnosis_time + 0.1)
	err += _assert(bench.current_state == BaseStation.StationState.COMPLETE, "diagnosis complete")

	# P1 picks up the diagnosed device
	err += _assert(bench.can_player_interact(p1), "p1 can pick up diagnosed device")
	bench._on_interacted(p1)
	err += _assert(p1.carry_system.is_carrying(), "p1 picked up diagnosed device")
	err += _assert(not bench.is_occupied(), "bench occupancy released on device pickup")
	err += _assert(bench.get_active_user() == null, "bench active_user cleared")
	err += _assert(bench.current_state == BaseStation.StationState.IDLE, "bench is IDLE again")

	p1.carry_system.drop_item()
	dev.queue_free()
	bench.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 4. Test auto-release of occupancy on focus loss when not processing
func test_occupancy_auto_release_on_focus_loss() -> int:
	print("\n[4] Testing auto-release of occupancy on focus loss...")
	var err: int = 0

	var bench: WorkbenchStation = load(WORKBENCH_SCENE_PATH).instantiate() as WorkbenchStation
	add_child(bench)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load("res://resources/devices/phone.tres"))
	dev.diagnose() # diagnosed state
	add_child(dev)

	p1.carry_system.pick_up(dev)
	bench._on_focus_gained(p1)
	bench._on_interacted(p1)

	err += _assert(bench.get_active_user() == p1, "p1 is active user after placing device")

	# Finish disassembly
	bench._physics_process(bench.disassembly_time + 0.1)
	err += _assert(bench.current_state == BaseStation.StationState.OCCUPIED, "bench state is OCCUPIED (waiting for part)")
	err += _assert(not bench._is_processing, "bench is not processing")

	# P1 walks away from bench to fetch part
	bench._on_focus_lost(p1)
	err += _assert(not bench.is_occupied(), "occupancy released when p1 walked away while not processing")
	err += _assert(bench.get_active_user() == null, "active_user cleared on focus loss")

	# Now P2 approaches and can interact
	bench._on_focus_gained(p2)
	err += _assert(bench.can_player_interact(p2) or bench.get_interaction_prompt(p2) != "In use by P1", "bench is no longer locked to P1")

	bench._on_focus_lost(p2)
	dev.queue_free()
	bench.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 5. Test occupancy during processing focus loss and release when complete
func test_occupancy_during_processing_focus_loss() -> int:
	print("\n[5] Testing processing occupancy retention during focus loss...")
	var err: int = 0

	var sw: SoftwareStation = load(SOFTWARE_SCENE_PATH).instantiate() as SoftwareStation
	add_child(sw)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load("res://resources/devices/phone.tres"))
	dev.current_repair_state = RepairState.State.REASSEMBLED
	add_child(dev)

	p1.carry_system.pick_up(dev)
	sw._on_focus_gained(p1)
	sw._on_interacted(p1)

	err += _assert(sw.is_occupied(), "software station is occupied")
	err += _assert(sw.get_active_user() == p1, "active_user is p1")
	err += _assert(sw.current_state == BaseStation.StationState.PROCESSING, "station is processing")

	# P1 walks away mid-process
	sw._on_focus_lost(p1)
	err += _assert(sw.is_occupied(), "station remains occupied by p1 during processing even if focus lost")
	err += _assert(sw.get_active_user() == p1, "active_user is still p1 during processing")
	err += _assert(not sw.can_player_interact(p2), "p2 cannot interact while processing")
	err += _assert(sw.get_interaction_prompt(p2) == "In use by P1", "p2 sees 'In use by P1'")

	# Processing completes
	sw._physics_process(sw.software_install_time + 0.1)
	err += _assert(sw.current_state == BaseStation.StationState.COMPLETE, "processing complete")
	err += _assert(not sw.is_occupied(), "occupancy auto-clears on complete if active user had walked away")
	err += _assert(sw.get_active_user() == null, "active user is now null")
	err += _assert(sw.can_player_interact(p2), "p2 can now interact to retrieve tested device")

	sw._on_interacted(p2)
	err += _assert(p2.carry_system.is_carrying(), "p2 picked up device")

	p2.carry_system.drop_item()
	dev.queue_free()
	sw.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 6. Test Workbench handoff between players
func test_workbench_handoff_between_players() -> int:
	print("\n[6] Testing Workbench collaborative hand-off between players...")
	var err: int = 0

	var bench: WorkbenchStation = load(WORKBENCH_SCENE_PATH).instantiate() as WorkbenchStation
	add_child(bench)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	dev.initialize(load("res://resources/devices/phone.tres"), load("res://resources/faults/phone_cracked_screen.tres"))
	dev.diagnose()
	add_child(dev)

	# P1 places device for disassembly
	p1.carry_system.pick_up(dev)
	bench._on_focus_gained(p1)
	bench._on_interacted(p1)
	err += _assert(bench.get_active_user() == p1, "P1 occupies bench during placement")

	# Disassembly finishes
	bench._physics_process(bench.disassembly_time + 0.1)
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "device disassembled")

	# P1 walks away
	bench._on_focus_lost(p1)
	err += _assert(bench.get_active_user() == null, "occupancy released on P1 departure")

	# P2 arrives with a replacement screen
	var part := Carriable.new()
	part.item_name = "Replacement Screen"
	part.item_type = "part"
	var comp_data: ComponentData = load("res://resources/components/screen.tres")
	part.set_meta("component_data", comp_data)
	add_child(part)
	p2.carry_system.pick_up(part)

	bench._on_focus_gained(p2)
	err += _assert(bench.can_player_interact(p2), "P2 can interact to install replacement part")
	bench._on_interacted(p2)
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "part replaced on device")
	err += _assert(bench.get_active_user() == p2, "bench is now occupied by P2")

	# P2 reassembles device
	bench._on_interacted(p2)
	err += _assert(bench.current_state == BaseStation.StationState.PROCESSING, "reassembly processing started")
	bench._physics_process(bench.reassembly_time + 0.1)
	err += _assert(bench.current_state == BaseStation.StationState.COMPLETE, "reassembly complete")

	# P2 picks up reassembled device
	bench._on_interacted(p2)
	err += _assert(p2.carry_system.is_carrying(), "P2 retrieved reassembled device")
	err += _assert(not bench.is_occupied(), "bench is free after device removal")

	p2.carry_system.drop_item()
	dev.queue_free()
	bench.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 7. Test player color glow visual indicator
func test_player_color_glow_indicator() -> int:
	print("\n[7] Testing player color glow on occupied station...")
	var err: int = 0

	var station: BaseStation = load(DIAGNOSTIC_SCENE_PATH).instantiate() as BaseStation
	add_child(station)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# Initially no emission
	err += _assert(station._station_material != null, "station has material override")
	err += _assert(not station._station_material.emission_enabled, "emission initially disabled")

	# P1 occupies station -> glow matches P1 color
	station.set_active_user(p1)
	err += _assert(station._station_material.emission_enabled, "emission enabled when occupied")
	var expected_p1_color: Color = Constants.PLAYER_COLORS[0] * 0.6
	var c1: Color = station._station_material.emission
	var diff_p1: float = absf(c1.r - expected_p1_color.r) + absf(c1.g - expected_p1_color.g) + absf(c1.b - expected_p1_color.b)
	err += _assert(diff_p1 < 0.05, "emission color matches P1 color")

	# P2 occupies station -> glow matches P2 color
	station.set_active_user(p2)
	var expected_p2_color: Color = Constants.PLAYER_COLORS[1] * 0.6
	var c2: Color = station._station_material.emission
	var diff_p2: float = absf(c2.r - expected_p2_color.r) + absf(c2.g - expected_p2_color.g) + absf(c2.b - expected_p2_color.b)
	err += _assert(diff_p2 < 0.05, "emission color matches P2 color")

	# Clear occupancy
	station.clear_active_user(p2)
	err += _assert(not station._station_material.emission_enabled, "emission disabled when unoccupied and unfocused")

	station.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 8. Test multi-player focus tracking
func test_multiplayer_focus_tracking() -> int:
	print("\n[8] Testing multi-player focus tracking on station...")
	var err: int = 0

	var station: BaseStation = load(DIAGNOSTIC_SCENE_PATH).instantiate() as BaseStation
	add_child(station)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# P1 focuses station
	station._on_focus_gained(p1)
	err += _assert(station._focusing_players.size() == 1, "1 player focusing")
	err += _assert(station._station_material.emission_enabled, "highlight active for P1")

	# P2 also focuses station
	station._on_focus_gained(p2)
	err += _assert(station._focusing_players.size() == 2, "2 players focusing")
	err += _assert(station._station_material.emission_enabled, "highlight active for both")

	# P1 leaves focus
	station._on_focus_lost(p1)
	err += _assert(station._focusing_players.size() == 1, "1 player still focusing")
	err += _assert(station._station_material.emission_enabled, "highlight remains because P2 is still present")

	# P2 leaves focus
	station._on_focus_lost(p2)
	err += _assert(station._focusing_players.is_empty(), "0 players focusing")
	err += _assert(not station._station_material.emission_enabled, "highlight turned off when all leave")

	station.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 9. Test InteractionSystem and HUD prompt integration for occupied station
func test_interaction_system_and_hud_prompt() -> int:
	print("\n[9] Testing InteractionSystem and HUD prompt for occupied stations...")
	var err: int = 0

	var hud: HUD = load(HUD_SCENE_PATH).instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	hud.setup(p2, null) # Track P2 on HUD

	var bench: DiagnosticBench = load(DIAGNOSTIC_SCENE_PATH).instantiate() as DiagnosticBench
	add_child(bench)

	# Benchmark occupied by P1
	bench.set_active_user(p1)

	# P2 approaches bench interaction zone
	bench.interaction_zone.focus_gained.emit(p2)
	p2.interaction_system._current_focus = bench.interaction_zone

	err += _assert(p2.interaction_system.get_current_focus() == bench.interaction_zone, "P2 focuses bench")
	err += _assert(not bench.interaction_zone.can_interact(p2), "zone can_interact is false for P2")
	err += _assert(p2.interaction_system.get_prompt_text() == "In use by P1", "InteractionSystem prompt text is 'In use by P1'")

	hud._update_interaction_prompt()
	err += _assert(hud.interaction_prompt.visible, "HUD prompt is visible for occupied station")
	err += _assert(hud.prompt_label.text == "In use by P1", "HUD prompt displays 'In use by P1' (got: '%s')" % hud.prompt_label.text)

	# P1 clears occupancy
	bench.clear_active_user(p1)
	err += _assert(bench.interaction_zone.can_interact(p2) or bench.interaction_zone.get_prompt_text(p2) != "In use by P1", "Zone prompt updates when occupancy cleared")

	hud.queue_free()
	bench.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 10. Test Reception Desk and Parts Shelf independence
func test_reception_and_parts_shelf_independence() -> int:
	print("\n[10] Testing Reception Desk and Parts Shelf independence...")
	var err: int = 0

	var desk: ReceptionDesk = load(RECEPTION_SCENE_PATH).instantiate() as ReceptionDesk
	var shelf: PartsShelf = load(PARTS_SHELF_SCENE_PATH).instantiate() as PartsShelf
	add_child(desk)
	add_child(shelf)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# Neither has active user set
	err += _assert(desk.get_active_user() == null, "Reception desk has no active user")
	err += _assert(shelf.get_active_user() == null, "Parts shelf has no active user")
	err += _assert(not desk.is_occupied(), "Reception desk is not occupied")
	err += _assert(not shelf.is_occupied(), "Parts shelf is not occupied")

	# Both players can interact with parts shelf simultaneously
	err += _assert(shelf.can_player_interact(p1), "P1 can interact with parts shelf")
	err += _assert(shelf.can_player_interact(p2), "P2 can interact with parts shelf")

	desk.queue_free()
	shelf.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err
