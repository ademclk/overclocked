class_name FaultData
extends Resource

## Definition of a specific device defect or fault.
## Identifies symptoms, required component replacement, and repair times.

@export var fault_name: String = ""
@export var fault_id: String = ""
@export_multiline var symptom_description: String = ""
@export var broken_component: ComponentData = null
@export var diagnosis_time: float = 2.0
@export var repair_time: float = 3.0
@export var requires_software_reinstall: bool = false


## Validates that this fault definition has necessary IDs, names, and component references
func is_valid() -> bool:
	if fault_id.is_empty() or fault_name.is_empty():
		return false
	if broken_component != null and not broken_component.is_valid():
		return false
	return true
