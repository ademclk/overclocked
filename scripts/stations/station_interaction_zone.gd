class_name StationInteractionZone
extends Interactable

## Dedicated interaction zone for workshop stations.
## Delegates interaction checks, prompts, and focus events to its parent BaseStation.

var station: BaseStation = null


func _ready() -> void:
	if not station and get_parent() is BaseStation:
		station = get_parent() as BaseStation
	super._ready()


func can_interact(player: PlayerCharacter) -> bool:
	if not is_interactable:
		return false
	if station:
		return station.can_player_interact(player)
	return true


func get_prompt_text(player: PlayerCharacter) -> String:
	if station:
		var custom_prompt: String = station.get_interaction_prompt(player)
		if not custom_prompt.is_empty():
			return custom_prompt
	return super.get_prompt_text(player)


func _on_focus_gained(player: PlayerCharacter) -> void:
	super._on_focus_gained(player)
	if station:
		station._on_focus_gained(player)


func _on_focus_lost(player: PlayerCharacter) -> void:
	super._on_focus_lost(player)
	if station:
		station._on_focus_lost(player)
