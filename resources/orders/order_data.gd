class_name OrderData
extends Resource

## Static configuration resource for customer repair orders.
## Can define device type, forced fault, custom time limit,
## star rating thresholds, and customer metadata.

@export var order_id: String = ""
@export var device_data: DeviceData = null
@export var specific_fault: FaultData = null
@export var custom_time_limit: float = 0.0
@export var base_score: int = 100
@export_range(0.0, 1.0) var three_star_threshold: float = 0.5
@export_range(0.0, 1.0) var two_star_threshold: float = 0.2
@export var is_priority: bool = false
@export var customer_name: String = "Customer"


## Returns whether the order data has valid device definitions
func is_valid() -> bool:
	return device_data != null and device_data.is_valid()


## Returns the effective time limit for this order, preferring custom over device base time
func get_effective_time_limit() -> float:
	if custom_time_limit > 0.0:
		return custom_time_limit
	if device_data:
		return device_data.base_repair_time
	return 60.0
