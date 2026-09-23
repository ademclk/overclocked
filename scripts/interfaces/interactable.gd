class_name Interactable
extends Area3D

## Base class for all interactable objects in the workshop.
## Stations, devices, and items extend this or use it as an interaction zone.

signal interacted(player: PlayerCharacter)
signal focus_gained(player: PlayerCharacter)
signal focus_lost(player: PlayerCharacter)

@export var interaction_prompt: String = "Interact"
@export var is_interactable: bool = true
@export var interaction_type: String = "instant"  ## "instant" or "menu"

var is_focused: bool = false
var focused_by_player: PlayerCharacter = null
var can_interact_handler: Callable = Callable()


func _ready() -> void:
	# Default to station/item collision layers if not explicitly configured
	if collision_layer == 1:
		collision_layer = Constants.COLLISION_MASK_STATIONS
	focus_gained.connect(_on_focus_gained)
	focus_lost.connect(_on_focus_lost)


## Override in subclasses. Called when player presses interact while focused.
func interact(player: PlayerCharacter) -> void:
	if not can_interact(player):
		return
	interacted.emit(player)


## Override to define whether interaction is currently available.
func can_interact(player: PlayerCharacter) -> bool:
	if not is_interactable:
		return false
	if can_interact_handler.is_valid():
		return can_interact_handler.call(player)
	return true


## Returns the display text for the HUD interaction prompt.
func get_prompt_text(_player: PlayerCharacter) -> String:
	return interaction_prompt


func _on_focus_gained(player: PlayerCharacter) -> void:
	is_focused = true
	focused_by_player = player


func _on_focus_lost(_player: PlayerCharacter) -> void:
	is_focused = false
	focused_by_player = null
