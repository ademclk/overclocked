class_name DeviceData
extends Resource

## Static archetype definition of a device category (e.g. Phone, Laptop, Console).
## Defines possible faults, base repair timer, difficulty, and requirements.

@export var device_name: String = ""
@export var device_id: String = ""
@export_multiline var description: String = ""
@export var possible_faults: Array[FaultData] = []
@export var base_repair_time: float = 60.0
@export var difficulty_tier: int = 1
@export var requires_software: bool = false


## Validates device definition data and references
func is_valid() -> bool:
	if device_id.is_empty() or device_name.is_empty():
		return false
	if possible_faults.is_empty():
		return false
	for fault in possible_faults:
		if fault == null or not fault.is_valid():
			return false
	return true


## Selects and returns a random fault from the device's catalog
func get_random_fault() -> FaultData:
	if possible_faults.is_empty():
		return null
	return possible_faults[randi() % possible_faults.size()]


## Returns a specific fault by its fault_id
func get_fault_by_id(target_id: String) -> FaultData:
	for fault in possible_faults:
		if fault and fault.fault_id == target_id:
			return fault
	return null
