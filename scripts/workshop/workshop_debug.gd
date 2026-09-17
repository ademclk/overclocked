class_name WorkshopDebug
extends Node3D

## Placeholder debug workshop level for Overclocked.
## Provides room geometry, collision boundaries, workbench station, lighting, and spawn markers.

const DEFAULT_PLAYER_SCENE: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")

@export var auto_spawn_player: bool = true
@export var player_scene: PackedScene = DEFAULT_PLAYER_SCENE

var active_players: Array[PlayerCharacter] = []

@onready var spawn_point_p1: Marker3D = $SpawnPoint_P1
@onready var floor_node: CSGBox3D = $Floor
@onready var workbench: CSGBox3D = $Workbench
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D


func _ready() -> void:
	if auto_spawn_player:
		spawn_player(0)


## Spawns a player character at the designated spawn marker.
func spawn_player(player_index: int = 0) -> PlayerCharacter:
	var scene_to_spawn: PackedScene = player_scene if player_scene != null else DEFAULT_PLAYER_SCENE
	var player: PlayerCharacter = scene_to_spawn.instantiate() as PlayerCharacter
	player.player_index = player_index
	add_child(player)
	player.global_position = get_spawn_position(player_index)
	active_players.append(player)
	SignalBus.player_joined.emit(player_index)
	return player


## Returns the active player for single-player, or player at index
func get_player(player_index: int = 0) -> PlayerCharacter:
	for player in active_players:
		if is_instance_valid(player) and player.player_index == player_index:
			return player
	return null


## Returns the 3D spawn position for a given player index.
func get_spawn_position(_player_index: int = 0) -> Vector3:
	if spawn_point_p1:
		return spawn_point_p1.global_position
	return Vector3(1.5, 0.0, 1.5)


## Returns the workshop floor dimensions in meters (X = width, Y = depth).
func get_room_size() -> Vector2:
	if floor_node:
		return Vector2(floor_node.size.x, floor_node.size.z)
	return Constants.DEBUG_ROOM_SIZE


## Returns the global position of the primary workbench.
func get_workbench_position() -> Vector3:
	if workbench:
		return workbench.global_position
	return Vector3(-2.0, 0.45, -1.5)


## Returns the bounding box (AABB) of the workshop floor.
func get_room_bounds() -> AABB:
	var size_2d: Vector2 = get_room_size()
	return AABB(
		Vector3(-size_2d.x * 0.5, 0.0, -size_2d.y * 0.5), Vector3(size_2d.x, 2.5, size_2d.y)
	)
