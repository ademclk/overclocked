class_name DeviceData
extends Resource

## Static archetype definition of a device category (e.g. Phone, Laptop, Console).
## Defines possible faults, base repair timer, difficulty, carry behavior, and visual identity.

@export var device_name: String = ""
@export var device_id: String = ""
@export_multiline var description: String = ""
@export var possible_faults: Array[FaultData] = []
@export var base_repair_time: float = 60.0
@export var difficulty_tier: int = 1       ## 1=Phone/Tablet, 2=Laptop, 3=Desktop, 4=Console/Router
@export var requires_software: bool = false
@export var device_weight: float = 1.0     ## Relative spawn probability (higher = more common)

## Visual and carry properties:
@export var device_color: Color = Color(0.5, 0.5, 0.5)     ## In-world mesh tint for visual identity
@export var device_scene: PackedScene = null                  ## Custom scene override — null = use Device.tscn
@export var carry_requires_two_players: bool = false          ## Desktop PC / server rack needs 2 players to carry


## Returns true if all required fields are set and faults are valid
func is_valid() -> bool:
	if device_id.is_empty() or device_name.is_empty():
		return false
	if possible_faults.is_empty():
		return false
	for fault in possible_faults:
		if fault == null or not fault.is_valid():
			return false
	return true


## Selects a random fault, respecting per-fault weight if set
func get_random_fault() -> FaultData:
	if possible_faults.is_empty():
		return null
	# Weighted selection: faults with weight > 0 use weighted pool
	var total_weight: float = 0.0
	for fault in possible_faults:
		total_weight += fault.weight if fault.weight > 0.0 else 1.0
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for fault in possible_faults:
		cumulative += fault.weight if fault.weight > 0.0 else 1.0
		if roll <= cumulative:
			return fault
	return possible_faults.back()


## Returns a specific fault by its fault_id
func get_fault_by_id(target_id: String) -> FaultData:
	for fault in possible_faults:
		if fault and fault.fault_id == target_id:
			return fault
	return null
