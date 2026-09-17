class_name WorkshopDebug
extends Node3D

## Workshop level for Overclocked (Phase 1).
## Provides room geometry, stations container, runtime entities, order pipeline orchestration,
## multiplayer spawn markers, and debug hotkeys.

const DEFAULT_PLAYER_SCENE: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")
const DEFAULT_PHONE_DATA: DeviceData = preload("res://resources/devices/phone.tres")
const DEFAULT_DEVICE_SCENE: PackedScene = preload("res://scenes/devices/Device.tscn")

@export var auto_spawn_player: bool = true
@export var auto_start_round: bool = true
@export var player_scene: PackedScene = DEFAULT_PLAYER_SCENE
@export var default_device_data: DeviceData = DEFAULT_PHONE_DATA

var active_players: Array[PlayerCharacter] = []

@onready var floor_node: CSGBox3D = $Floor
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var stations_container: Node3D = get_node_or_null("Stations") as Node3D
@onready var entities_container: Node3D = get_node_or_null("Entities") as Node3D
@onready var order_manager: OrderManager = get_node_or_null("OrderManager") as OrderManager

# Station references with fallback for flat or nested hierarchy
@onready var reception_desk: ReceptionDesk = (
	get_node_or_null("Stations/ReceptionDesk") as ReceptionDesk
	if has_node("Stations/ReceptionDesk")
	else get_node_or_null("ReceptionDesk") as ReceptionDesk
)
@onready var diagnostic_bench: DiagnosticBench = (
	get_node_or_null("Stations/DiagnosticBench") as DiagnosticBench
	if has_node("Stations/DiagnosticBench")
	else get_node_or_null("DiagnosticBench") as DiagnosticBench
)
@onready var workbench: Node3D = (
	get_node_or_null("Stations/Workbench")
	if has_node("Stations/Workbench")
	else (get_node_or_null("Workbench") if has_node("Workbench") else get_node_or_null("WorkbenchStation"))
)
@onready var parts_shelf: PartsShelf = (
	get_node_or_null("Stations/PartsShelf") as PartsShelf
	if has_node("Stations/PartsShelf")
	else get_node_or_null("PartsShelf") as PartsShelf
)
@onready var software_station: SoftwareStation = (
	get_node_or_null("Stations/SoftwareStation") as SoftwareStation
	if has_node("Stations/SoftwareStation")
	else get_node_or_null("SoftwareStation") as SoftwareStation
)
@onready var delivery_counter: DeliveryCounter = (
	get_node_or_null("Stations/DeliveryCounter") as DeliveryCounter
	if has_node("Stations/DeliveryCounter")
	else get_node_or_null("DeliveryCounter") as DeliveryCounter
)

# Spawn markers
@onready var spawn_point_p1: Marker3D = get_node_or_null("SpawnPoint_P1") as Marker3D
@onready var spawn_point_p2: Marker3D = get_node_or_null("SpawnPoint_P2") as Marker3D
@onready var spawn_point_p3: Marker3D = get_node_or_null("SpawnPoint_P3") as Marker3D
@onready var spawn_point_p4: Marker3D = get_node_or_null("SpawnPoint_P4") as Marker3D


func _ready() -> void:
	_connect_order_pipeline()

	if auto_spawn_player:
		spawn_player(0)

	if auto_start_round:
		start_round()


## Spawns a player character at the designated spawn marker.
func spawn_player(player_index: int = 0) -> PlayerCharacter:
	var scene_to_spawn: PackedScene = player_scene if player_scene != null else DEFAULT_PLAYER_SCENE
	var player: PlayerCharacter = scene_to_spawn.instantiate() as PlayerCharacter
	player.player_index = player_index

	if entities_container:
		entities_container.add_child(player)
	else:
		add_child(player)

	player.global_position = get_spawn_position(player_index)
	active_players.append(player)
	SignalBus.player_joined.emit(player_index)
	return player


## Starts the gameplay round and spawns an initial order
func start_round() -> void:
	SignalBus.round_started.emit()

	if order_manager and not order_manager.has_active_orders():
		var data_to_use := default_device_data if default_device_data != null else DEFAULT_PHONE_DATA
		order_manager.spawn_order(data_to_use)


## Connects OrderManager, ReceptionDesk, and DeliveryCounter into a unified pipeline
func _connect_order_pipeline() -> void:
	if not order_manager:
		return

	if reception_desk:
		order_manager.reception_desk = reception_desk
	if delivery_counter:
		order_manager.delivery_counter = delivery_counter
		delivery_counter.order_manager = order_manager
		if not delivery_counter.device_delivered.is_connected(_on_device_delivered):
			delivery_counter.device_delivered.connect(_on_device_delivered)

	if not order_manager.order_spawned.is_connected(_on_order_spawned):
		order_manager.order_spawned.connect(_on_order_spawned)
	if not order_manager.order_completed.is_connected(_on_order_completed):
		order_manager.order_completed.connect(_on_order_completed)
	if not order_manager.all_orders_complete.is_connected(_on_all_orders_complete):
		order_manager.all_orders_complete.connect(_on_all_orders_complete)


func _on_order_spawned(order: Order) -> void:
	# If device was not already auto-instantiated by order manager, create and place it
	if not order.device_instance and reception_desk:
		var dev_scene := DEFAULT_DEVICE_SCENE
		var dev: Device = dev_scene.instantiate() as Device
		dev.initialize(order.device_data, order.assigned_fault)
		order.device_instance = dev
		reception_desk.spawn_incoming_device(dev)


func _on_device_delivered(device: Carriable) -> void:
	if order_manager and device:
		order_manager.complete_order_for_device(device)


func _on_order_completed(_order: Order, _stars: int, _score: int) -> void:
	pass


func _on_all_orders_complete() -> void:
	var final_score: int = order_manager.total_score if order_manager else 0
	var final_stars: int = order_manager.total_stars if order_manager else 0
	SignalBus.round_ended.emit(final_score, final_stars)


## Returns the active player for single-player, or player at index
func get_player(player_index: int = 0) -> PlayerCharacter:
	for player in active_players:
		if is_instance_valid(player) and player.player_index == player_index:
			return player
	return null


## Returns the 3D spawn position for a given player index.
func get_spawn_position(player_index: int = 0) -> Vector3:
	var marker_name: String = "SpawnPoint_P%d" % (player_index + 1)
	var marker: Marker3D = get_node_or_null(marker_name) as Marker3D
	if marker:
		return marker.global_position

	# Fallbacks based on player index
	match player_index:
		0: return Vector3(1.5, 0.0, 3.0)
		1: return Vector3(2.5, 0.0, 3.0)
		2: return Vector3(1.5, 0.0, 3.8)
		3: return Vector3(2.5, 0.0, 3.8)
		_: return Vector3(1.5, 0.0, 3.0)


## Returns the workshop floor dimensions in meters (X = width, Y = depth).
func get_room_size() -> Vector2:
	if floor_node:
		return Vector2(floor_node.size.x, floor_node.size.z)
	return Constants.DEBUG_ROOM_SIZE


## Returns the global position of the primary workbench.
func get_workbench_position() -> Vector3:
	if workbench:
		return workbench.global_position
	return Vector3(-2.6, 0.0, 0.5)


## Returns a station by its type or name
func get_station(station_type_or_name: String) -> BaseStation:
	var query := station_type_or_name.to_lower().strip_edges()
	for station in get_all_stations():
		if (
			station.station_type.to_lower() == query
			or station.station_name.to_lower() == query
			or station.name.to_lower() == query
		):
			return station
	return null


## Returns all BaseStation nodes present in the workshop
func get_all_stations() -> Array[BaseStation]:
	var stations: Array[BaseStation] = []
	var container: Node = stations_container if stations_container != null else self

	for child in container.get_children():
		if child is BaseStation:
			stations.append(child)

	if container != self:
		for child in get_children():
			if child is BaseStation and not (child in stations):
				stations.append(child)

	return stations


## Returns the bounding box (AABB) of the workshop floor.
func get_room_bounds() -> AABB:
	var size_2d: Vector2 = get_room_size()
	return AABB(
		Vector3(-size_2d.x * 0.5, 0.0, -size_2d.y * 0.5),
		Vector3(size_2d.x, 2.5, size_2d.y)
	)


# Debug tools & hotkeys
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F6:
				_debug_advance_device(RepairState.State.DIAGNOSED)
				get_viewport().set_input_as_handled()
			KEY_F7:
				_debug_give_part()
				get_viewport().set_input_as_handled()
			KEY_F8:
				_debug_complete_order()
				get_viewport().set_input_as_handled()
			KEY_F9:
				_debug_dump_state()
				get_viewport().set_input_as_handled()


func _debug_advance_device(target_state: RepairState.State) -> void:
	var player: PlayerCharacter = get_player(0)
	var dev: Device = null

	if player and player.carry_system and player.carry_system.is_carrying():
		var held := player.carry_system.get_held_item()
		if held is Device:
			dev = held as Device

	if not dev and diagnostic_bench and diagnostic_bench.placed_device is Device:
		dev = diagnostic_bench.placed_device as Device
		if target_state == RepairState.State.DIAGNOSED:
			diagnostic_bench._complete_processing()

	if not dev and workbench and "placed_device" in workbench and workbench.placed_device is Device:
		dev = workbench.placed_device as Device

	if not dev and order_manager and order_manager.has_active_orders():
		var ord: Order = order_manager.get_first_active_order()
		if ord and ord.device_instance:
			dev = ord.device_instance

	if dev:
		if target_state == RepairState.State.DIAGNOSED:
			dev.diagnose()
		else:
			dev.advance_state(target_state)
		print("[Debug F6] Device '%s' advanced to state: %s" % [dev.item_name, dev.get_repair_state()])
	else:
		print("[Debug F6] No active device found to advance.")


func _debug_give_part() -> void:
	var player: PlayerCharacter = get_player(0)
	if not player or not player.carry_system:
		print("[Debug F7] No player found.")
		return

	var comp: ComponentData = null
	if order_manager and order_manager.has_active_orders():
		var ord: Order = order_manager.get_first_active_order()
		if ord and ord.assigned_fault and ord.assigned_fault.broken_component:
			comp = ord.assigned_fault.broken_component

	if not comp:
		comp = load("res://resources/components/screen.tres") as ComponentData

	var part := Carriable.new()
	part.item_name = comp.component_name
	part.item_type = "part"
	part.set_meta("component_data", comp)

	if player.carry_system.is_carrying():
		player.carry_system.drop_item()

	if entities_container:
		entities_container.add_child(part)
	else:
		add_child(part)

	player.carry_system.pick_up(part)
	print("[Debug F7] Gave player replacement component: %s" % comp.component_name)


func _debug_complete_order() -> void:
	if not order_manager or not order_manager.has_active_orders():
		print("[Debug F8] No active orders to complete.")
		return

	var ord: Order = order_manager.get_first_active_order()
	if ord.device_instance:
		ord.device_instance.current_repair_state = RepairState.State.TESTED
		ord.device_instance.deliver()

	order_manager.complete_order(ord)
	print("[Debug F8] Order '%s' completed via debug hotkey." % ord.order_id)


func _debug_dump_state() -> void:
	print("\n================= WORKSHOP STATE DUMP =================")
	print("Active Players: %d" % active_players.size())
	var p: PlayerCharacter = get_player(0)
	if p and p.carry_system:
		var held: Carriable = p.carry_system.get_held_item()
		var held_desc: String = held.item_name if held else "None"
		if held is Device:
			held_desc += " [%s]" % (held as Device).get_repair_state()
		print("  Player 0 Carried Item: %s" % held_desc)

	if order_manager:
		print("OrderManager: Active=%d, Completed=%d, Expired=%d | Score=%d, Stars=%d" % [
			order_manager.get_active_order_count(),
			order_manager.completed_orders.size(),
			order_manager.expired_orders.size(),
			order_manager.total_score,
			order_manager.total_stars
		])
		for ord in order_manager.active_orders:
			var dev_state := ord.device_instance.get_repair_state() if ord.device_instance else "No Device"
			print("  - Order %s: %s [%s] | Time Remaining: %.1fs / %.1fs" % [
				ord.order_id, ord.get_device_name(), dev_state, ord.time_remaining, ord.time_limit
			])

	print("Stations:")
	for st in get_all_stations():
		var placed := st.placed_device.item_name if st.placed_device else "Empty"
		if st.placed_device is Device:
			placed += " [%s]" % (st.placed_device as Device).get_repair_state()
		print("  - %-18s: State=%-10s | Placed: %s" % [st.station_name, BaseStation.StationState.keys()[st.current_state], placed])
	print("=======================================================\n")
