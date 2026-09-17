class_name ComponentData
extends Resource

## Definition of a replacement component or part for repair tasks.

@export var component_name: String = ""
@export var component_id: String = ""
@export var component_type: String = "" # "screen", "battery", "software", etc.


## Returns whether this component data is properly configured
func is_valid() -> bool:
	return not component_id.is_empty() and not component_name.is_empty()
