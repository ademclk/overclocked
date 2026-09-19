extends Node

## Test suite for Workshop Hazards
## Tests BaseHazard lifecycle, FloorSpillHazard slowing and clearing,
## PowerSurgeHazard station disruption, OverheatingHazard workbench tracking,
## and HazardManager pool limits and difficulty ramping.

const FLOOR_SPILL_SCENE_PATH: String = "res://scenes/hazards/FloorSpillHazard.tscn"
const POWER_SURGE_SCENE_PATH: String = "res://scenes/hazards/PowerSurgeHazard.tscn"
const WORKBENCH_SCENE_PATH: String = "res://scenes/stations/WorkbenchStation.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 3B WORKSHOP HAZARDS TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_base_hazard_lifecycle()
	failures += test_floor_spill_hazard_player_slow_and_clearing()
	failures += test_power_surge_hazard_disables_station()
	failures += test_overheating_hazard_workbench_monitoring()
	failures += test_hazard_manager_spawning_and_limits()
	failures += test_workshop_hazards_integration()

	print("=========================================================")
	print("--- PHASE 3B TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 3B TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 3B tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_test_player() -> PlayerCharacter:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player)
	return player


## 1. Test BaseHazard state transitions, warning countdown, and expiry
func test_base_hazard_lifecycle() -> int:
	print("\n[1] Testing BaseHazard state lifecycle and signals...")
	var err: int = 0

	var hazard := BaseHazard.new()
	hazard.hazard_name = "Test Hazard"
	hazard.hazard_type = "test"
	hazard.warning_duration = 1.0
	hazard.duration = 4.0
	add_child(hazard)

	var activated_emitted: Array[bool] = [false]
	var expired_emitted: Array[bool] = [false]
	hazard.hazard_activated.connect(func(_h: BaseHazard) -> void: activated_emitted[0] = true)
	hazard.hazard_expired.connect(func(_h: BaseHazard) -> void: expired_emitted[0] = true)

	err += _assert(hazard.current_state == BaseHazard.HazardState.INACTIVE, "Initial state is INACTIVE")

	# Start warning phase
	hazard.spawn_with_warning()
	err += _assert(hazard.current_state == BaseHazard.HazardState.WARNING, "State changed to WARNING")
	err += _assert(not hazard.monitoring, "Monitoring disabled during warning phase")

	# Tick halfway through warning: still WARNING
	hazard._physics_process(0.5)
	err += _assert(hazard.current_state == BaseHazard.HazardState.WARNING, "Still WARNING at 0.5s")
	err += _assert(not activated_emitted[0], "hazard_activated not yet emitted")

	# Tick past warning: transitions to ACTIVE
	hazard._physics_process(0.6)
	err += _assert(hazard.current_state == BaseHazard.HazardState.ACTIVE, "State transitioned to ACTIVE")
	err += _assert(hazard.monitoring, "Monitoring enabled when ACTIVE")
	err += _assert(activated_emitted[0], "hazard_activated signal emitted")

	# Tick active duration
	hazard._physics_process(2.0)
	err += _assert(hazard.current_state == BaseHazard.HazardState.ACTIVE, "Still ACTIVE at 2s")

	# Tick past total duration (4.0s) -> auto expires
	hazard._physics_process(2.1)
	err += _assert(expired_emitted[0], "hazard_expired signal emitted after duration")

	return err


## 2. Test FloorSpillHazard slowing players and clearing mechanics
func test_floor_spill_hazard_player_slow_and_clearing() -> int:
	print("\n[2] Testing FloorSpillHazard slowing and clearing...")
	var err: int = 0

	var spill_scene: PackedScene = load(FLOOR_SPILL_SCENE_PATH)
	var spill: FloorSpillHazard = spill_scene.instantiate() as FloorSpillHazard
	var player: PlayerCharacter = _create_test_player()
	add_child(spill)

	spill.activate()
	err += _assert(spill.current_state == BaseHazard.HazardState.ACTIVE, "Spill is ACTIVE")
	err += _assert(player.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "Player initial move speed is normal (6.0)")

	# Player enters spill zone
	spill._on_body_entered(player)
	var expected_slow_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.DEFAULT_SPILL_SLOW_FACTOR
	err += _assert(is_equal_approx(player.move_speed, expected_slow_speed), "Player speed slowed to %.2f (45 percent)" % expected_slow_speed)

	# Player leaves spill zone
	spill._on_body_exited(player)
	err += _assert(player.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "Player speed restored to 6.0 after exiting spill")

	# Player re-enters and starts clearing
	spill._on_body_entered(player)
	err += _assert(is_equal_approx(player.move_speed, expected_slow_speed), "Player slowed again on re-entering")

	spill.start_clearing(player)
	err += _assert(spill.current_state == BaseHazard.HazardState.CLEARING, "Spill entered CLEARING state")
	err += _assert(spill.get_clear_progress() == 0.0, "Initial clear progress is 0.0")

	# Tick half of clear_time (clear_time = 2.0s)
	spill._physics_process(1.0)
	err += _assert(is_equal_approx(spill.get_clear_progress(), 0.5), "Clear progress at 50 percent after 1.0s")

	var cleared_signal_fired: Array[bool] = [false]
	spill.hazard_cleared.connect(func(_h: BaseHazard) -> void: cleared_signal_fired[0] = true)

	# Finish clearing
	spill._physics_process(1.1)
	err += _assert(cleared_signal_fired[0], "hazard_cleared signal emitted after full clear time")
	err += _assert(player.move_speed == Constants.DEFAULT_PLAYER_MOVE_SPEED, "Player speed restored after spill cleared")

	# Test Dropped Screws variant
	var screws: FloorSpillHazard = spill_scene.instantiate() as FloorSpillHazard
	screws.spill_type = FloorSpillHazard.SpillType.SCREWS
	add_child(screws)
	screws.activate()
	err += _assert(screws.hazard_name == "Dropped Screws", "Screws variant hazard_name is Dropped Screws")
	err += _assert(screws.interaction_zone.interaction_prompt == "Sweep Screws", "Screws variant prompt is Sweep Screws")
	err += _assert(screws.hazard_label.text == "🔩 SCREWS", "Screws variant label is 🔩 SCREWS")
	screws.clear()

	player.queue_free()
	return err


## 3. Test PowerSurgeHazard disabling a target station and recovery
func test_power_surge_hazard_disables_station() -> int:
	print("\n[3] Testing PowerSurgeHazard station disabling and recovery...")
	var err: int = 0

	var surge_scene: PackedScene = load(POWER_SURGE_SCENE_PATH)
	var surge: PowerSurgeHazard = surge_scene.instantiate() as PowerSurgeHazard
	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var station: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(station)
	add_child(surge)

	err += _assert(station.interaction_zone.is_interactable, "Station initially interactable")
	err += _assert(station.station_label.text.to_upper().contains("WORKBENCH"), "Station label is WORKBENCH")

	# Link surge to station and activate
	surge.target_station = station
	surge.set_meta("target_station", station)
	surge.activate()

	err += _assert(not station.interaction_zone.is_interactable, "Station interaction zone disabled while surged")
	err += _assert(station.station_label.text.contains("OFFLINE"), "Station label indicates OFFLINE")

	# Clear the surge
	var cleared_fired: Array[bool] = [false]
	surge.hazard_cleared.connect(func(_h: BaseHazard) -> void: cleared_fired[0] = true)
	surge.clear()

	err += _assert(cleared_fired[0], "Surge hazard_cleared signal emitted")
	err += _assert(station.interaction_zone.is_interactable, "Station interaction zone restored after surge cleared")
	err += _assert(station.station_label.text.to_upper().contains("WORKBENCH"), "Station label restored after surge cleared")

	station.queue_free()
	return err


## 4. Test OverheatingHazard tracking vulnerable devices on workbenches
func test_overheating_hazard_workbench_monitoring() -> int:
	print("\n[4] Testing OverheatingHazard device tracking on workbench...")
	var err: int = 0

	var overheat_mgr := OverheatingHazard.new()
	overheat_mgr.overheat_time = 4.0
	overheat_mgr.warning_threshold = 0.5  # Warning at 2.0s
	add_child(overheat_mgr)

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH))
	add_child(dev)

	overheat_mgr.register_workbench(wb)

	# Place device in DIAGNOSED state (not vulnerable to overheat yet)
	dev.current_repair_state = RepairState.State.DIAGNOSED
	wb.accept_device(dev)
	err += _assert(not overheat_mgr.is_device_tracked(dev), "Device in DIAGNOSED state is not tracked for overheat")

	# Advance to DISASSEMBLED state (vulnerable to overheat)
	wb.remove_device()
	dev.current_repair_state = RepairState.State.DISASSEMBLED
	wb.accept_device(dev)
	err += _assert(overheat_mgr.is_device_tracked(dev), "Device in DISASSEMBLED state is tracked for overheat")

	var overheat_signal_fired: Array[bool] = [false]
	var cooled_signal_fired: Array[bool] = [false]
	overheat_mgr.device_overheating.connect(func(_d: Device, _s: BaseStation) -> void: overheat_signal_fired[0] = true)
	overheat_mgr.device_cooled.connect(func(_d: Device) -> void: cooled_signal_fired[0] = true)

	# Tick to 2.5s (past warning threshold 2.0s, before overheat 4.0s)
	overheat_mgr._physics_process(2.5)
	var mesh: MeshInstance3D = dev.get_node_or_null("DeviceMesh") as MeshInstance3D
	err += _assert(mesh != null and mesh.material_override != null, "Device received material override for warning")
	err += _assert(not overheat_mgr.is_device_overheated(dev), "Device not yet overheated at 2.5s")
	err += _assert(not overheat_signal_fired[0], "device_overheating signal not yet fired")

	# Tick past overheat time (4.0s total)
	overheat_mgr._physics_process(2.0)
	err += _assert(overheat_mgr.is_device_overheated(dev), "Device is now overheated at 4.5s")
	err += _assert(overheat_signal_fired[0], "device_overheating signal emitted")

	# Pick up device from workbench to cool it down
	wb.remove_device()
	err += _assert(cooled_signal_fired[0], "device_cooled signal emitted upon removing overheated device")
	err += _assert(not overheat_mgr.is_device_overheated(dev), "Device is no longer overheated after cooling")

	dev.queue_free()
	wb.queue_free()
	overheat_mgr.queue_free()
	return err


## 5. Test HazardManager spawning, pool limits, and difficulty ramping
func test_hazard_manager_spawning_and_limits() -> int:
	print("\n[5] Testing HazardManager pool management and limits...")
	var err: int = 0

	var mgr := HazardManager.new()
	mgr.first_hazard_delay = 5.0
	mgr.spawn_interval = 20.0
	mgr.min_interval = 12.0
	mgr.ramp_factor = 0.8
	mgr.max_active_hazards = 2
	add_child(mgr)

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	add_child(wb)
	mgr.surge_target_stations = [wb]

	mgr.start()
	err += _assert(mgr.is_hazard_active(), "HazardManager is_hazard_active() is true")
	err += _assert(mgr.get_active_hazard_count() == 0, "No active hazards initially")

	# Test initial delay: ticking 3s should not spawn
	mgr._physics_process(3.0)
	err += _assert(mgr.get_active_hazard_count() == 0, "No hazards spawned during first_hazard_delay")

	# Spawn floor hazard directly
	var h1: BaseHazard = mgr.try_spawn_hazard("floor")
	err += _assert(h1 != null, "Successfully spawned first hazard (floor)")
	err += _assert(mgr.get_active_hazard_count() == 1, "Active hazard count is 1")
	err += _assert(is_equal_approx(mgr.get_current_interval(), 16.0), "Difficulty ramp reduced interval to 16.0s (20.0 * 0.8)")

	# Spawn surge hazard directly (reaches max_active_hazards cap of 2)
	var h2: BaseHazard = mgr.try_spawn_hazard("surge")
	err += _assert(h2 != null, "Successfully spawned second hazard (surge)")
	err += _assert(mgr.get_active_hazard_count() == 2, "Active hazard count is at cap (2)")

	# 3rd spawn attempt: should be rejected due to max_active_hazards
	var h3: BaseHazard = mgr.try_spawn_hazard("floor")
	err += _assert(h3 == null, "3rd spawn attempt rejected due to max_active_hazards cap")
	err += _assert(mgr.get_active_hazard_count() == 2, "Active hazard count remains 2")

	# Clear one hazard -> slot opens up
	h1.clear()
	err += _assert(mgr.get_active_hazard_count() == 1, "Active count reduced to 1 after clearing h1")

	var h4: BaseHazard = mgr.try_spawn_hazard("floor")
	err += _assert(h4 != null, "Spawn succeeds after hazard slot freed")
	err += _assert(mgr.get_active_hazard_count() == 2, "Active count back at cap (2)")

	# Stop manager clears all active hazards
	mgr.stop()
	err += _assert(not mgr.is_hazard_active(), "HazardManager is inactive after stop()")
	err += _assert(mgr.get_active_hazard_count() == 0, "All hazards cleared upon stop()")

	wb.queue_free()
	mgr.queue_free()
	return err


## 6. Test WorkshopDebug integration with hazards
func test_workshop_hazards_integration() -> int:
	print("\n[6] Testing Workshop_Debug hazards integration...")
	var err: int = 0

	var workshop_scene: PackedScene = load("res://scenes/workshop/Workshop_Debug.tscn")
	var workshop: WorkshopDebug = workshop_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = false
	workshop.auto_start_round = false
	add_child(workshop)

	err += _assert(workshop.hazard_manager != null, "Workshop has HazardManager child node")
	err += _assert(workshop.overheating_hazard != null, "Workshop has OverheatingHazard child node")

	workshop.start_round()
	err += _assert(workshop.hazard_manager.is_hazard_active(), "HazardManager started on round start")
	err += _assert(workshop.hazard_manager.surge_target_stations.size() == 4, "HazardManager auto-discovered 4 surge target stations (excluding reception/delivery)")
	err += _assert(workshop.hazard_manager.floor_hazard_positions.size() == 5, "HazardManager auto-discovered 5 floor hazard spawn points")

	var surge_h: BaseHazard = workshop.hazard_manager.try_spawn_hazard("surge")
	err += _assert(surge_h != null, "Power surge successfully spawned on target station in workshop")
	err += _assert(surge_h is PowerSurgeHazard, "Spawned hazard is PowerSurgeHazard instance")

	# Stop round clears hazards
	workshop.hazard_manager.stop()
	err += _assert(not workshop.hazard_manager.is_hazard_active(), "HazardManager stopped cleanly")
	err += _assert(workshop.hazard_manager.get_active_hazard_count() == 0, "All workshop hazards cleared on stop")

	workshop.queue_free()
	return err
