class_name OrderManager
extends Node

## Manages customer repair orders during gameplay.
## Spawns orders, links them to physical devices placed at the ReceptionDesk,
## ticks order timers in physics process, scores completions, and tracks session totals.

signal order_spawned(order: Order)
signal order_completed(order: Order, stars: int, score: int)
signal order_expired(order: Order)
signal all_orders_complete

const DEFAULT_DEVICE_SCENE: PackedScene = preload("res://scenes/devices/Device.tscn")
const DEFAULT_PHONE_DATA: DeviceData = preload("res://resources/devices/phone.tres")

@export var device_scene: PackedScene = DEFAULT_DEVICE_SCENE
@export var device_database: Array[DeviceData] = []
@export var tier_filter: Array[int] = [1, 2]  ## Which difficulty tiers to spawn
@export var reception_desk: ReceptionDesk = null
@export var delivery_counter: DeliveryCounter = null
@export var auto_spawn_first_order: bool = false

var active_orders: Array[Order] = []
var completed_orders: Array[Order] = []
var expired_orders: Array[Order] = []

var total_score: int = 0
var total_stars: int = 0

var order_spawner: Node = null
var _order_counter: int = 0


func _ready() -> void:
	add_to_group("order_managers")

	if device_database.is_empty():
		_load_default_devices()
	if device_database.is_empty() and DEFAULT_PHONE_DATA:
		device_database.append(DEFAULT_PHONE_DATA)

	_discover_stations()

	if auto_spawn_first_order:
		spawn_order()


func _physics_process(delta: float) -> void:
	for order: Order in active_orders.duplicate():
		order.tick(delta)


## Returns all registered devices matching the current tier filter
func get_available_devices() -> Array[DeviceData]:
	if tier_filter.is_empty():
		return device_database.filter(func(d: DeviceData) -> bool: return d != null and d.is_valid())
	return device_database.filter(
		func(d: DeviceData) -> bool:
			return d != null and d.difficulty_tier in tier_filter and d.is_valid()
	)


## Selects a random device from the filtered pool, or falls back to device_database
func _pick_device() -> DeviceData:
	var pool: Array[DeviceData] = get_available_devices()
	if not pool.is_empty():
		return pool[randi() % pool.size()]
	if not device_database.is_empty():
		return device_database[randi() % device_database.size()]
	return null


## Loads default devices from resources if device_database is not set
func _load_default_devices() -> void:
	var paths: Array[String] = [
		"res://resources/devices/phone.tres",
		"res://resources/devices/tablet.tres",
		"res://resources/devices/laptop.tres",
		"res://resources/devices/game_console.tres",
		"res://resources/devices/router.tres",
		"res://resources/devices/desktop_pc.tres",
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is DeviceData and (res as DeviceData).is_valid():
				device_database.append(res as DeviceData)


## Spawns a new order from given DeviceData, or randomly picks from device_database
func spawn_order(dev_data: DeviceData = null, fault: FaultData = null, target_desk: ReceptionDesk = null) -> Order:
	if not dev_data:
		dev_data = _pick_device()
	if not dev_data and not device_database.is_empty():
		dev_data = device_database[randi() % device_database.size()]
	if not dev_data:
		dev_data = DEFAULT_PHONE_DATA
	if not dev_data:
		push_error("OrderManager: No device data available to spawn order!")
		return null

	if not fault and not dev_data.possible_faults.is_empty():
		fault = dev_data.get_random_fault()

	_order_counter += 1
	var order := Order.new()
	order.initialize("order_%03d" % _order_counter, dev_data, fault)

	_setup_order_device(order, target_desk)

	order.order_completed.connect(_on_order_completed.bind(order))
	order.order_expired.connect(_on_order_expired.bind(order))

	active_orders.append(order)
	order.start()

	SignalBus.order_spawned.emit(order.order_id, dev_data.device_name)
	order_spawned.emit(order)
	return order


## Spawns a new order based on an OrderData resource template
func spawn_order_from_data(data: OrderData, target_desk: ReceptionDesk = null) -> Order:
	if not data or not data.is_valid():
		push_error("OrderManager: Invalid OrderData provided!")
		return null

	_order_counter += 1
	var order := Order.new()
	order.order_id = data.order_id if not data.order_id.is_empty() else ("order_%03d" % _order_counter)
	order.initialize_from_data(data)

	_setup_order_device(order, target_desk)

	order.order_completed.connect(_on_order_completed.bind(order))
	order.order_expired.connect(_on_order_expired.bind(order))

	active_orders.append(order)
	order.start()

	SignalBus.order_spawned.emit(order.order_id, order.get_device_name())
	order_spawned.emit(order)
	return order


## Completes an active order
func complete_order(order: Order) -> void:
	if order and order in active_orders:
		order.complete()


## Finds and completes the order associated with the delivered physical device
func complete_order_for_device(device: Carriable) -> bool:
	for order: Order in active_orders:
		if order.device_instance == device:
			complete_order(order)
			return true

	# Fallback if only 1 active order
	if active_orders.size() == 1:
		complete_order(active_orders[0])
		return true

	return false


## Returns whether there are currently active orders
func has_active_orders() -> bool:
	return not active_orders.is_empty()


## Returns the number of currently active orders
func get_active_order_count() -> int:
	return active_orders.size()


## Returns the first active order in the queue, or null
func get_first_active_order() -> Order:
	if not active_orders.is_empty():
		return active_orders[0]
	return null


func _setup_order_device(order: Order, target_desk: ReceptionDesk = null) -> void:
	var desk: ReceptionDesk = target_desk if target_desk != null else reception_desk
	if not desk:
		desk = _find_reception_desk()

	var scene_to_use: PackedScene = device_scene
	if order.device_data and order.device_data.device_scene:
		scene_to_use = order.device_data.device_scene

	if scene_to_use:
		var node: Node = scene_to_use.instantiate()
		if node is Device:
			var dev := node as Device
			dev.initialize(order.device_data, order.assigned_fault)
			order.device_instance = dev
			if desk:
				desk.spawn_incoming_device(dev)
			else:
				add_child(dev)


## Returns a registered DeviceData by its device_id
func get_device_by_id(target_id: String) -> DeviceData:
	for dev in device_database:
		if dev and dev.device_id == target_id:
			return dev
	return null


## Returns all registered DeviceData matching the specified difficulty tier
func get_devices_by_tier(tier: int) -> Array[DeviceData]:
	var result: Array[DeviceData] = []
	for dev in device_database:
		if dev and dev.difficulty_tier == tier:
			result.append(dev)
	return result


func _on_order_completed(stars: int, score: int, order: Order) -> void:
	active_orders.erase(order)
	completed_orders.append(order)
	total_score += score
	total_stars += stars
	order_completed.emit(order, stars, score)

	_check_all_orders_complete()


func _on_order_expired(order: Order) -> void:
	active_orders.erase(order)
	expired_orders.append(order)
	if reception_desk and order.device_instance and is_instance_valid(reception_desk):
		if reception_desk.has_method("remove_incoming_device"):
			reception_desk.remove_incoming_device(order.device_instance)
	order_expired.emit(order)

	_check_all_orders_complete()


func _check_all_orders_complete() -> void:
	if not active_orders.is_empty():
		return
	if order_spawner and is_instance_valid(order_spawner) and order_spawner.has_method("is_spawning") and order_spawner.is_spawning():
		return
	all_orders_complete.emit()


func _on_device_delivered_at_counter(device: Carriable) -> void:
	complete_order_for_device(device)


func _discover_stations() -> void:
	if not reception_desk:
		reception_desk = _find_reception_desk()
	if not delivery_counter:
		delivery_counter = _find_delivery_counter()

	if delivery_counter and not delivery_counter.device_delivered.is_connected(_on_device_delivered_at_counter):
		delivery_counter.device_delivered.connect(_on_device_delivered_at_counter)


func _find_reception_desk() -> ReceptionDesk:
	var parent_node := get_parent()
	if parent_node:
		var desk: Node = parent_node.get_node_or_null("ReceptionDesk")
		if desk is ReceptionDesk:
			return desk as ReceptionDesk
		desk = parent_node.get_node_or_null("Stations/ReceptionDesk")
		if desk is ReceptionDesk:
			return desk as ReceptionDesk

	var tree := get_tree()
	if tree:
		for child in tree.get_nodes_in_group("stations"):
			if child is ReceptionDesk:
				return child as ReceptionDesk
	return null


func _find_delivery_counter() -> DeliveryCounter:
	var parent_node := get_parent()
	if parent_node:
		var counter: Node = parent_node.get_node_or_null("DeliveryCounter")
		if counter is DeliveryCounter:
			return counter as DeliveryCounter
		counter = parent_node.get_node_or_null("Stations/DeliveryCounter")
		if counter is DeliveryCounter:
			return counter as DeliveryCounter

	var tree := get_tree()
	if tree:
		for child in tree.get_nodes_in_group("stations"):
			if child is DeliveryCounter:
				return child as DeliveryCounter
	return null
