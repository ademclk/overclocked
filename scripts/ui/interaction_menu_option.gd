class_name InteractionMenuOption
extends RefCounted

## A single option in a Resident Evil-style interaction menu.

var option_id: String = ""
var label: String = ""
var description: String = ""
var icon_path: String = ""
var is_enabled: bool = true
var disabled_reason: String = ""      ## "Requires Screwdriver" / "Device not diagnosed"
var hotkey_hint: String = ""          ## "[E]" / "[A]"
var action_callable: Callable = Callable()  ## Called when option is selected
var requires_confirmation: bool = false     ## Show "Are you sure?" for destructive actions


func _init(id: String = "", p_label: String = "", p_desc: String = "", p_callable: Callable = Callable(), enabled: bool = true) -> void:
	option_id = id
	label = p_label
	description = p_desc
	action_callable = p_callable
	is_enabled = enabled
