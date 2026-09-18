class_name InteractionSystem
extends Node

## Attached to PlayerCharacter. Manages detecting, focusing, and interacting
## with nearby Interactable nodes.

signal focus_changed(old_focus: Interactable, new_focus: Interactable)
signal interaction_triggered(interactable: Interactable)

var _current_focus: Interactable = null
var _interactables_in_range: Array[Interactable] = []

@onready var player: PlayerCharacter = get_parent() as PlayerCharacter
@onready var detection_area: Area3D = (
	player.get_node_or_null("InteractionArea") as Area3D if player else null
)


func _ready() -> void:
	if not detection_area and player:
		detection_area = player.get_node_or_null("InteractionArea") as Area3D
	if detection_area:
		detection_area.area_entered.connect(_on_area_entered)
		detection_area.area_exited.connect(_on_area_exited)


func _process(_delta: float) -> void:
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return

	var player_idx: int = player.player_index
	var interact_action := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)
	var pick_up_action := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_PICK_UP)

	var is_triggered: bool = (
		event.is_action_pressed(interact_action)
		or event.is_action_pressed(pick_up_action)
		or (event is InputEventAction and (event.action == &"interact" or event.action == &"pick_up"))
	)

	if is_triggered and _current_focus:
		if _current_focus.can_interact(player):
			_current_focus.interact(player)
			interaction_triggered.emit(_current_focus)
			if get_viewport():
				get_viewport().set_input_as_handled()


func _update_focus() -> void:
	var nearest: Interactable = _find_nearest_interactable()
	if nearest != _current_focus:
		var old_focus: Interactable = _current_focus
		if _current_focus and is_instance_valid(_current_focus):
			_current_focus.focus_lost.emit(player)
		_current_focus = nearest
		if _current_focus and is_instance_valid(_current_focus):
			_current_focus.focus_gained.emit(player)
		focus_changed.emit(old_focus, _current_focus)


func _find_nearest_interactable() -> Interactable:
	var closest: Interactable = null
	var closest_dist: float = INF
	var valid_interactables: Array[Interactable] = []

	for interactable in _interactables_in_range:
		if is_instance_valid(interactable):
			valid_interactables.append(interactable)
			if interactable.is_interactable:
				var dist: float = (
					player.global_position.distance_squared_to(interactable.global_position)
					if player
					else 0.0
				)
				if dist < closest_dist:
					closest_dist = dist
					closest = interactable

	_interactables_in_range = valid_interactables
	return closest


func get_current_focus() -> Interactable:
	return _current_focus


func get_prompt_text() -> String:
	if _current_focus:
		return _current_focus.get_prompt_text(player)
	return ""


func get_interactables_in_range() -> Array[Interactable]:
	return _interactables_in_range


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable and not _interactables_in_range.has(area):
		_interactables_in_range.append(area)


func _on_area_exited(area: Area3D) -> void:
	if area is Interactable:
		_interactables_in_range.erase(area)
		if _current_focus == area:
			if is_instance_valid(_current_focus):
				_current_focus.focus_lost.emit(player)
			var old_focus: Interactable = _current_focus
			_current_focus = null
			focus_changed.emit(old_focus, null)
