class_name Carriable
extends Node3D

## Base class for items the player can pick up, carry, and place.
## Devices, parts, and tools extend this.

signal picked_up(player: PlayerCharacter)
signal dropped(position: Vector3)
signal placed_on_station(station: Node)

@export var item_name: String = "Item"
@export var item_type: String = "generic" # "device", "part", "tool"

var is_held: bool = false
var held_by: PlayerCharacter = null


func pick_up(player: PlayerCharacter) -> void:
	is_held = true
	held_by = player
	picked_up.emit(player)


func drop(drop_position: Vector3) -> void:
	is_held = false
	held_by = null
	global_position = drop_position
	dropped.emit(drop_position)


func place_on(station: Node) -> void:
	is_held = false
	held_by = null
	placed_on_station.emit(station)
