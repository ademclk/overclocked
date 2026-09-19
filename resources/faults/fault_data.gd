class_name FaultData
extends Resource

## Definition of a specific device defect or fault.
## Supports single-component and multi-component faults (Phase 4).

@export var fault_name: String = ""
@export var fault_id: String = ""
@export_multiline var symptom_description: String = ""

## Phase 1-3 compat: single broken component. Returns broken_components[0] if populated.
@export var broken_component: ComponentData = null

## Phase 4: multi-component faults (replaces broken_component for complex faults)
@export var broken_components: Array[ComponentData] = []

@export var diagnosis_time: float = 2.0
@export var repair_time: float = 3.0
@export var requires_software_reinstall: bool = false

## Phase 4 additions:
@export var is_multi_fault: bool = false                      ## True when multiple components need replacing
@export var fault_display_tags: Array[String] = []            ## Tags shown at diagnosis: ["screen", "battery"]
@export var requires_workbench_step_count: int = 1            ## How many workbench passes needed (Laptop = 2)
@export var skip_states: Array[String] = []                   ## States in the pipeline this fault skips (e.g. router firmware)
@export var intermittent: bool = false                        ## 💡 First diagnosis shows "No Fault Found"
@export var weight: float = 1.0                               ## Relative spawn probability (higher = more common)


## Returns all components needing replacement for this fault
func get_required_components() -> Array[ComponentData]:
	if not broken_components.is_empty():
		return broken_components
	if broken_component != null:
		return [broken_component]
	return []


## Returns whether this fault definition has necessary fields
func is_valid() -> bool:
	if fault_id.is_empty() or fault_name.is_empty():
		return false
	# A fault must require at least one thing: component, software, or both
	var has_component: bool = (not broken_components.is_empty()) or broken_component != null
	if not has_component and not requires_software_reinstall:
		return false
	for comp in broken_components:
		if comp == null or not comp.is_valid():
			return false
	return true
