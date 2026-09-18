class_name CarrySystem
extends Node

## Attached to PlayerCharacter. Manages picking up, holding, dropping,
## and placing one Carriable item at a time.

signal item_picked(item: Carriable)
signal item_dropped(item: Carriable)
signal item_placed(item: Carriable, station: Node)

var held_item: Carriable = null

@onready var player: PlayerCharacter = get_parent() as PlayerCharacter
@onready var carry_position: Marker3D = (
	player.get_node_or_null("CarryPosition") as Marker3D if player else null
)


func _ready() -> void:
	if not carry_position and player:
		carry_position = player.get_node_or_null("CarryPosition") as Marker3D


func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return

	var player_idx: int = player.player_index
	var drop_action := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)
	var is_drop: bool = (
		event.is_action_pressed(drop_action)
		or (player_idx == 0 and event is InputEventAction and event.action == &"drop")
	)

	if is_drop and is_carrying():
		drop_item()
		get_viewport().set_input_as_handled()


func is_carrying() -> bool:
	return held_item != null


func get_held_item() -> Carriable:
	return held_item


func can_pick_up() -> bool:
	return held_item == null


func pick_up(item: Carriable) -> void:
	if not can_pick_up():
		push_warning("CarrySystem: Already carrying an item!")
		return

	if not is_instance_valid(item):
		return

	# Claim check — prevent two players grabbing simultaneously
	if not item.try_claim(player):
		return

	# Check if this grab was contested by another player
	var was_contested: bool = item.is_contested_by_other_players(player)
	if was_contested:
		var flash_color: Color = player.get_player_color() if player else Color.WHITE
		item.trigger_claim_flash(flash_color)

	held_item = item
	item.visible = true
	item.pick_up(player)

	# Reparent item to carry position for visual attachment
	if item.get_parent():
		item.get_parent().remove_child(item)

	if carry_position:
		carry_position.add_child(item)
		item.position = Vector3.ZERO
		item.rotation = Vector3.ZERO
	elif player:
		player.add_child(item)
		item.position = Vector3(0, 2.05, 0)

	item_picked.emit(item)
	var player_idx: int = player.player_index if player else 0
	SignalBus.item_picked_up.emit(item.item_name, player_idx)
	if SignalBus.has_signal("item_claimed"):
		SignalBus.item_claimed.emit(item.item_name, player_idx, was_contested)


func drop_item() -> void:
	if not held_item:
		return

	var item: Carriable = held_item
	var drop_pos: Vector3 = _calculate_drop_position()
	held_item = null

	if item.get_parent():
		item.get_parent().remove_child(item)

	# Add back to workshop/level container
	if player and player.get_parent():
		player.get_parent().add_child(item)
	elif player:
		player.add_sibling(item)

	item.drop(drop_pos)

	item_dropped.emit(item)
	var player_idx: int = player.player_index if player else 0
	SignalBus.item_dropped.emit(item.item_name, player_idx)


func place_on_station(station: Node) -> void:
	if not held_item:
		return

	var item: Carriable = held_item
	held_item = null

	if item.get_parent():
		item.get_parent().remove_child(item)

	item.visible = true
	item.place_on(station)
	item_placed.emit(item, station)


func _calculate_drop_position() -> Vector3:
	if not player:
		return Vector3.ZERO
	var forward: Vector3 = player.get_facing_direction()
	return player.global_position + forward * 0.8
