class_name OrderSpawner
extends Node

## Automatic order generation with configurable rate, pressure ramping,
## and priority order injection. Plugs into OrderManager.

signal spawn_rate_changed(new_interval: float)
signal order_spawned_by_spawner(order: Order)

@export_group("Timing")
@export var spawn_interval: float = 25.0       ## Seconds between order spawns
@export var min_interval: float = 12.0          ## Floor — never spawns faster than this
@export var initial_delay: float = 5.0          ## Delay before first auto-spawn
@export var ramp_enabled: bool = true           ## Whether spawn rate increases over time
@export var ramp_factor: float = 0.92           ## Multiply interval by this each spawn

@export_group("Queue Limits")
@export var max_active_orders: int = 5          ## Won't spawn if active >= max
@export var max_total_orders: int = 0           ## 0 = unlimited. Total orders per round

@export_group("Priority Orders")
@export var priority_chance: float = 0.15       ## Probability of an order being "priority"
@export var priority_time_multiplier: float = 0.6  ## Priority orders get 60% of normal time
@export var priority_score_multiplier: float = 1.5 ## Priority orders give 150% score

@export_group("References")
@export var order_manager: OrderManager = null

var _spawn_timer: float = 0.0
var _current_interval: float = 25.0
var _total_spawned: int = 0
var _is_active: bool = false
var _initial_delay_timer: float = 0.0


func _ready() -> void:
	_current_interval = spawn_interval
	_discover_order_manager()


func _physics_process(delta: float) -> void:
	if not _is_active or not order_manager:
		return

	# Handle initial delay
	if _initial_delay_timer > 0.0:
		_initial_delay_timer -= delta
		if _initial_delay_timer > 0.0:
			return

	_spawn_timer += delta
	if _spawn_timer >= _current_interval:
		_spawn_timer = 0.0
		try_spawn_order()


## Starts automatic order spawning
func start() -> void:
	_is_active = true
	_spawn_timer = 0.0
	_initial_delay_timer = initial_delay
	_current_interval = spawn_interval
	_total_spawned = 0
	_discover_order_manager()


## Stops automatic order spawning
func stop() -> void:
	_is_active = false
	_spawn_timer = 0.0


## Returns whether the spawner is currently active
func is_spawning() -> bool:
	return _is_active


## Returns the current spawn interval (may differ from base due to ramping)
func get_current_interval() -> float:
	return _current_interval


## Returns total orders spawned this round
func get_total_spawned() -> int:
	return _total_spawned


## Returns remaining initial delay
func get_initial_delay_remaining() -> float:
	return maxf(0.0, _initial_delay_timer)


## Attempts to spawn a new order through the OrderManager
func try_spawn_order(forced_priority: Variant = null) -> Order:
	if not order_manager:
		return null

	# Check queue cap
	if order_manager.get_active_order_count() >= max_active_orders:
		return null  # Queue full — skip this spawn cycle

	# Check total cap
	if max_total_orders > 0 and _total_spawned >= max_total_orders:
		stop()
		return null

	# Determine if this is a priority order
	var is_priority: bool = false
	if forced_priority is bool:
		is_priority = forced_priority as bool
	else:
		is_priority = (randf() < priority_chance)

	# Spawn the order
	var order: Order = order_manager.spawn_order()
	if order:
		_total_spawned += 1

		if is_priority:
			_apply_priority(order)

		# Ramp up spawn rate for next order
		if ramp_enabled:
			_current_interval = maxf(min_interval, _current_interval * ramp_factor)
			spawn_rate_changed.emit(_current_interval)

		order_spawned_by_spawner.emit(order)
		return order

	return null


func _apply_priority(order: Order) -> void:
	order.time_limit *= priority_time_multiplier
	order.time_remaining = order.time_limit
	order.base_score = int(round(float(order.base_score) * priority_score_multiplier))
	order.is_priority = true
	order.timer_updated.emit(order.time_remaining, order.time_limit)


func _discover_order_manager() -> void:
	if order_manager and is_instance_valid(order_manager):
		if "order_spawner" in order_manager:
			order_manager.order_spawner = self
		return

	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is OrderManager:
				order_manager = child as OrderManager
				if "order_spawner" in order_manager:
					order_manager.order_spawner = self
				return

	var tree := get_tree()
	if tree:
		var mgr: Node = tree.get_first_node_in_group("order_managers")
		if mgr is OrderManager:
			order_manager = mgr as OrderManager
			if "order_spawner" in order_manager:
				order_manager.order_spawner = self
			return
