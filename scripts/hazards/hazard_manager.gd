class_name HazardManager
extends Node

## Manages hazard spawning, tracking, and difficulty-scaled events.
## Added as a child of the workshop scene alongside OrderManager and OrderSpawner.

signal hazard_spawned(hazard: BaseHazard)

@export_group("Timing")
@export var first_hazard_delay: float = 30.0     ## Seconds into round before first hazard
@export var spawn_interval: float = 20.0         ## Seconds between hazard spawn attempts
@export var min_interval: float = 10.0           ## Fastest hazard spawn rate
@export var ramp_factor: float = 0.95            ## Interval multiplier each spawn
@export var max_active_hazards: int = 3          ## Won't spawn if this many are active

@export_group("Hazard Pool")
@export var floor_hazard_scene: PackedScene = null   ## Spill / screws
@export var surge_hazard_scene: PackedScene = null   ## Power surge
@export var fire_hazard_scene: PackedScene = null    ## Battery fire (💡)

@export_group("Spawn Locations")
@export var floor_hazard_positions: Array[Marker3D] = []
@export var surge_target_stations: Array[BaseStation] = []

var _active_hazards: Array[BaseHazard] = []
var _spawn_timer: float = 0.0
var _current_interval: float = 20.0
var _initial_delay_timer: float = 0.0
var _is_active: bool = false


func _ready() -> void:
	add_to_group("hazard_managers")
	_current_interval = spawn_interval
	_load_default_scenes()
	_discover_targets()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	# Handle initial delay
	if _initial_delay_timer > 0.0:
		_initial_delay_timer -= delta
		if _initial_delay_timer > 0.0:
			return

	# Clean up freed hazards
	_active_hazards = _active_hazards.filter(func(h: BaseHazard) -> bool: return is_instance_valid(h))

	_spawn_timer += delta
	if _spawn_timer >= _current_interval:
		_spawn_timer = 0.0
		try_spawn_hazard()


## Starts the hazard system (call when round starts)
func start() -> void:
	_is_active = true
	_spawn_timer = 0.0
	_initial_delay_timer = first_hazard_delay
	_current_interval = spawn_interval
	_discover_targets()


## Stops hazard spawning and clears all active hazards
func stop() -> void:
	_is_active = false
	_spawn_timer = 0.0
	for hazard in _active_hazards:
		if is_instance_valid(hazard):
			hazard.expire()
	_active_hazards.clear()


## Returns whether hazard system is currently active
func is_hazard_active() -> bool:
	return _is_active


## Returns all currently active hazards
func get_active_hazards() -> Array[BaseHazard]:
	_active_hazards = _active_hazards.filter(func(h: BaseHazard) -> bool: return is_instance_valid(h))
	return _active_hazards.duplicate()


## Returns count of active hazards
func get_active_hazard_count() -> int:
	_active_hazards = _active_hazards.filter(func(h: BaseHazard) -> bool: return is_instance_valid(h))
	return _active_hazards.size()


## Returns current spawn interval
func get_current_interval() -> float:
	return _current_interval


## Returns remaining initial delay
func get_initial_delay_remaining() -> float:
	return maxf(0.0, _initial_delay_timer)


## Attempts to spawn a hazard
func try_spawn_hazard(forced_type: String = "") -> BaseHazard:
	_active_hazards = _active_hazards.filter(func(h: BaseHazard) -> bool: return is_instance_valid(h))

	if _active_hazards.size() >= max_active_hazards:
		return null

	var hazard_type: String = forced_type if not forced_type.is_empty() else _pick_hazard_type()
	var spawned: BaseHazard = null

	match hazard_type:
		"floor":
			spawned = _spawn_floor_hazard()
		"surge":
			spawned = _spawn_power_surge()
			if not spawned:
				# If stations are all currently surged or unavailable, fallback to floor
				spawned = _spawn_floor_hazard()
		"fire":
			spawned = _spawn_battery_fire()

	if spawned:
		_current_interval = maxf(min_interval, _current_interval * ramp_factor)

	return spawned


func _pick_hazard_type() -> String:
	if surge_target_stations.is_empty() or floor_hazard_positions.is_empty():
		_discover_targets()
	var options: Array[String] = []
	if floor_hazard_scene:
		options.append("floor")
	if surge_hazard_scene and not surge_target_stations.is_empty():
		options.append("surge")
	if fire_hazard_scene:
		options.append("fire")
	if options.is_empty():
		return "floor"
	return options[randi() % options.size()]


## Spawns a floor spill or screws hazard at a specific world position
func spawn_floor_hazard_at(pos: Vector3) -> BaseHazard:
	return _spawn_floor_hazard(pos)


func _spawn_floor_hazard(target_pos: Variant = null) -> BaseHazard:
	if not floor_hazard_scene:
		return null

	var spawn_pos: Vector3 = Vector3.ZERO
	if target_pos is Vector3:
		spawn_pos = target_pos as Vector3
	elif not floor_hazard_positions.is_empty():
		var valid_markers := floor_hazard_positions.filter(func(m: Marker3D) -> bool: return is_instance_valid(m))
		if not valid_markers.is_empty():
			var marker: Marker3D = valid_markers[randi() % valid_markers.size()]
			spawn_pos = marker.global_position
	else:
		# Dynamic fallback positions between stations
		var fallbacks: Array[Vector3] = [
			Vector3(-2.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 1.5),
			Vector3(2.0, 0.0, 0.0),
			Vector3(-1.0, 0.0, -1.0),
			Vector3(1.0, 0.0, -1.0)
		]
		spawn_pos = fallbacks[randi() % fallbacks.size()]

	var hazard: BaseHazard = floor_hazard_scene.instantiate() as BaseHazard
	if not hazard:
		return null

	if hazard is FloorSpillHazard:
		var fsh := hazard as FloorSpillHazard
		fsh.spill_type = FloorSpillHazard.SpillType.SCREWS if randf() < 0.5 else FloorSpillHazard.SpillType.COFFEE

	var parent_node: Node = get_parent() if get_parent() else self
	parent_node.add_child(hazard)
	hazard.global_position = spawn_pos
	hazard.spawn_with_warning()

	_active_hazards.append(hazard)
	hazard.hazard_cleared.connect(_on_hazard_removed)
	hazard.hazard_expired.connect(_on_hazard_removed)
	hazard_spawned.emit(hazard)
	return hazard


func _spawn_power_surge(station: BaseStation = null) -> BaseHazard:
	if not surge_hazard_scene:
		return null

	var target: BaseStation = station
	if not target:
		var available: Array[BaseStation] = surge_target_stations.filter(
			func(s: BaseStation) -> bool:
				return is_instance_valid(s) and not _is_station_surged(s)
		)
		if available.is_empty():
			return null
		target = available[randi() % available.size()]

	var hazard: BaseHazard = surge_hazard_scene.instantiate() as BaseHazard
	if not hazard:
		return null

	var parent_node: Node = get_parent() if get_parent() else self
	parent_node.add_child(hazard)
	hazard.global_position = target.global_position + Vector3(0.0, 1.2, 0.0)
	hazard.set_meta("target_station", target)
	if "target_station" in hazard:
		hazard.target_station = target
	hazard.spawn_with_warning()

	_active_hazards.append(hazard)
	hazard.hazard_cleared.connect(_on_hazard_removed)
	hazard.hazard_expired.connect(_on_hazard_removed)
	hazard_spawned.emit(hazard)
	return hazard


func _spawn_battery_fire() -> BaseHazard:
	# Stretch goal
	return null


func _is_station_surged(station: BaseStation) -> bool:
	for hazard in _active_hazards:
		if is_instance_valid(hazard):
			if hazard.has_meta("target_station") and hazard.get_meta("target_station") == station:
				return true
			if "target_station" in hazard and hazard.target_station == station:
				return true
	return false


func _on_hazard_removed(hazard: BaseHazard) -> void:
	_active_hazards.erase(hazard)


func _load_default_scenes() -> void:
	if not floor_hazard_scene:
		floor_hazard_scene = load("res://scenes/hazards/FloorSpillHazard.tscn")
	if not surge_hazard_scene:
		surge_hazard_scene = load("res://scenes/hazards/PowerSurgeHazard.tscn")


func _discover_targets() -> void:
	var tree := get_tree()
	if not tree:
		return

	# Refresh floor hazard positions
	floor_hazard_positions = floor_hazard_positions.filter(
		func(m: Marker3D) -> bool: return is_instance_valid(m) and not m.is_queued_for_deletion()
	)
	if floor_hazard_positions.is_empty():
		var parent_node: Node = get_parent()
		if parent_node:
			for node in parent_node.find_children("*", "Marker3D", true, false):
				if node.is_in_group("hazard_spawn_points") and not node.is_queued_for_deletion():
					floor_hazard_positions.append(node as Marker3D)
		if floor_hazard_positions.is_empty():
			for node in tree.get_nodes_in_group("hazard_spawn_points"):
				if node is Marker3D and not node.is_queued_for_deletion():
					floor_hazard_positions.append(node as Marker3D)

	# Refresh surge target stations
	surge_target_stations = surge_target_stations.filter(
		func(s: BaseStation) -> bool: return is_instance_valid(s) and not s.is_queued_for_deletion()
	)
	if surge_target_stations.is_empty():
		var parent_node: Node = get_parent()
		if parent_node:
			for node in parent_node.find_children("*", "", true, false):
				if node is BaseStation and not node.is_queued_for_deletion():
					var st := node as BaseStation
					if st is ReceptionDesk or st is DeliveryCounter or st.station_type == "repair_table" or st.station_type == "trash":
						continue
					if not surge_target_stations.has(st):
						surge_target_stations.append(st)

		if surge_target_stations.is_empty():
			for node in tree.get_nodes_in_group("stations"):
				if node is BaseStation and not node.is_queued_for_deletion():
					var st := node as BaseStation
					if st is ReceptionDesk or st is DeliveryCounter or st.station_type == "repair_table" or st.station_type == "trash":
						continue
					if not surge_target_stations.has(st):
						surge_target_stations.append(st)
