class_name Order
extends RefCounted

## A single runtime repair order: device + fault + time limit + scoring.
## Ticked during physics frames to countdown remaining time and calculate stars upon delivery.

signal timer_updated(time_remaining: float, total_time: float)
signal order_completed(stars: int, score: int)
signal order_expired

var order_id: String = ""
var device_data: DeviceData = null
var assigned_fault: FaultData = null
var device_instance: Device = null
var order_data: OrderData = null

var time_limit: float = 60.0
var time_remaining: float = 60.0
var is_active: bool = false
var is_completed: bool = false
var is_expired: bool = false
var is_priority: bool = false

# Star thresholds (percentage of time remaining)
var three_star_threshold: float = 0.5   # 50%+ time remaining = 3 stars
var two_star_threshold: float = 0.2     # 20%+ time remaining = 2 stars
var base_score: int = 100


## Initializes the order from raw parameters
func initialize(id: String, dev_data: DeviceData, fault: FaultData = null, limit: float = 0.0) -> void:
	order_id = id
	device_data = dev_data
	assigned_fault = fault if fault != null else (dev_data.get_random_fault() if dev_data else null)
	time_limit = limit if limit > 0.0 else (dev_data.base_repair_time if dev_data else 60.0)
	time_remaining = time_limit
	is_priority = false


## Initializes the order from an OrderData resource template
func initialize_from_data(data: OrderData) -> void:
	order_data = data
	if not data.order_id.is_empty():
		order_id = data.order_id
	device_data = data.device_data
	assigned_fault = data.specific_fault if data.specific_fault != null else (data.device_data.get_random_fault() if data.device_data else null)
	time_limit = data.get_effective_time_limit()
	time_remaining = time_limit
	three_star_threshold = data.three_star_threshold
	two_star_threshold = data.two_star_threshold
	base_score = data.base_score
	if "is_priority" in data:
		is_priority = data.is_priority


## Activates the order and starts the countdown
func start() -> void:
	is_active = true
	is_completed = false
	is_expired = false
	if time_remaining <= 0.0:
		time_remaining = time_limit


## Advances the timer by delta seconds
func tick(delta: float) -> void:
	if not is_active or is_completed or is_expired:
		return

	time_remaining -= delta
	timer_updated.emit(time_remaining, time_limit)

	if time_remaining <= 0.0:
		time_remaining = 0.0
		expire()


## Completes the order, calculates stars & score, and emits completion signals
func complete() -> void:
	if not is_active or is_completed or is_expired:
		return

	is_active = false
	is_completed = true
	var stars: int = _calculate_stars()
	var score: int = _calculate_score(stars)

	order_completed.emit(stars, score)
	SignalBus.order_completed.emit(order_id, score, stars)


## Expires the order when time runs out completely
func expire() -> void:
	if is_expired or is_completed:
		return

	is_active = false
	is_expired = true
	time_remaining = 0.0

	order_expired.emit()
	SignalBus.order_expired.emit(order_id)


## Returns the proportion of remaining time [0.0 - 1.0]
func get_time_ratio() -> float:
	if time_limit <= 0.0:
		return 0.0
	return clampf(time_remaining / time_limit, 0.0, 1.0)


## Returns the number of stars currently eligible based on remaining time
func get_stars_for_current_time() -> int:
	return _calculate_stars()


## Returns the name of the device being repaired
func get_device_name() -> String:
	if device_data:
		return device_data.device_name
	if device_instance:
		return device_instance.item_name
	return "Device"


## Returns the name of the assigned fault
func get_fault_name() -> String:
	if assigned_fault:
		return assigned_fault.fault_name
	if device_instance and device_instance.assigned_fault:
		return device_instance.assigned_fault.fault_name
	return "Unknown Fault"


func _calculate_stars() -> int:
	if is_expired or time_remaining <= 0.0:
		return 0

	var ratio: float = get_time_ratio()
	if ratio >= three_star_threshold:
		return 3
	elif ratio >= two_star_threshold:
		return 2
	else:
		return 1


func _calculate_score(stars: int) -> int:
	return base_score * stars
