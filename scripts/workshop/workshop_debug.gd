class_name WorkshopDebug
extends Node3D

## Placeholder debug workshop level for Overclocked.
## Provides room geometry, collision boundaries, workbench station, lighting, and spawn markers.

@onready var spawn_point_p1: Marker3D = $SpawnPoint_P1
@onready var floor_node: CSGBox3D = $Floor
@onready var workbench: CSGBox3D = $Workbench
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D

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
		Vector3(-size_2d.x * 0.5, 0.0, -size_2d.y * 0.5),
		Vector3(size_2d.x, 2.5, size_2d.y)
	)
