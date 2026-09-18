class_name Carriable
extends Node3D

## Base class for items the player can pick up, carry, and place.
## Devices, parts, and tools extend this. Includes claim contention locking
## for multiplayer and visual feedback.

signal picked_up(player: PlayerCharacter)
signal dropped(position: Vector3)
signal placed_on_station(station: Node)
signal claim_attempted(player: PlayerCharacter, success: bool)
signal claim_released
signal claim_contested(claiming_player: PlayerCharacter)

@export var item_name: String = "Item"
@export var item_type: String = "generic" # "device", "part", "tool"

var is_held: bool = false
var held_by: PlayerCharacter = null

## Claim system to prevent two players grabbing the same item simultaneously
var claimed_by: PlayerCharacter = null
var _claim_timer: float = 0.0
const CLAIM_DURATION: float = 0.1 # Brief claim window (100ms)

var interaction_zone: Interactable = null


func _ready() -> void:
	if not interaction_zone:
		interaction_zone = get_node_or_null("InteractionZone") as Interactable


func _process(delta: float) -> void:
	# Auto-expire claims that weren't followed by a pick-up
	if not is_held and claimed_by and _claim_timer > 0.0:
		_claim_timer -= delta
		if _claim_timer <= 0.0:
			release_claim()


## Attempts to claim this item for a player.
## Returns true if claimed successfully, false if already held or claimed by someone else.
func try_claim(player: PlayerCharacter) -> bool:
	if is_held:
		claim_attempted.emit(player, false)
		return false
	if claimed_by != null and claimed_by != player and is_instance_valid(claimed_by):
		claim_attempted.emit(player, false)
		return false
	claimed_by = player
	_claim_timer = CLAIM_DURATION
	claim_attempted.emit(player, true)
	return true


## Checks whether this player can claim this item without modifying claim state.
func can_claim(player: PlayerCharacter) -> bool:
	if is_held:
		return false
	if claimed_by != null and claimed_by != player and is_instance_valid(claimed_by):
		return false
	return true


## Releases any active claim on this item.
func release_claim() -> void:
	claimed_by = null
	_claim_timer = 0.0
	claim_released.emit()


func pick_up(player: PlayerCharacter) -> void:
	if not try_claim(player):
		return
	is_held = true
	held_by = player
	_claim_timer = 0.0
	if interaction_zone:
		interaction_zone.is_interactable = false
	picked_up.emit(player)


func drop(drop_position: Vector3) -> void:
	is_held = false
	held_by = null
	release_claim()
	global_position = drop_position
	if interaction_zone:
		interaction_zone.is_interactable = true
	dropped.emit(drop_position)


func place_on(station: Node) -> void:
	is_held = false
	held_by = null
	release_claim()
	if interaction_zone:
		interaction_zone.is_interactable = false
	placed_on_station.emit(station)


## Sets up an interaction zone for ground pickup if one does not already exist.
func setup_interaction_zone(radius: float = 0.6) -> Interactable:
	if interaction_zone:
		return interaction_zone
	var zone := Interactable.new()
	zone.name = "InteractionZone"
	zone.collision_layer = Constants.COLLISION_MASK_ITEMS
	zone.collision_mask = 0
	zone.interaction_prompt = "Pick Up %s" % item_name
	zone.is_interactable = not is_held
	zone.can_interact_handler = func(p: PlayerCharacter) -> bool:
		return not is_held and can_claim(p) and (p == null or p.carry_system == null or p.carry_system.can_pick_up())

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	zone.add_child(shape)

	add_child(zone)
	interaction_zone = zone

	zone.interacted.connect(
		func(p: PlayerCharacter) -> void:
			if not is_held and p and p.carry_system and p.carry_system.can_pick_up():
				p.carry_system.pick_up(self)
	)
	return zone


## Checks if another player is near or focusing on this item when claimed
func is_contested_by_other_players(claiming_player: PlayerCharacter) -> bool:
	if not claiming_player:
		return false
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	elif claiming_player.is_inside_tree():
		tree = claiming_player.get_tree()
	if not tree:
		return false

	var item_pos: Vector3 = global_position if is_inside_tree() else claiming_player.global_position

	var players: Array[Node] = tree.get_nodes_in_group("players")
	for p: Node in players:
		if p is PlayerCharacter and p != claiming_player and is_instance_valid(p) and not p.is_queued_for_deletion():
			var other: PlayerCharacter = p as PlayerCharacter
			if other.interaction_system:
				var focus: Interactable = other.interaction_system.get_current_focus()
				if focus and (focus == interaction_zone or focus.get_parent() == self or focus == self):
					return true
				for in_range in other.interaction_system.get_interactables_in_range():
					if in_range and (in_range == interaction_zone or in_range.get_parent() == self or in_range == self):
						return true
			if other.is_inside_tree() and other.global_position.distance_to(item_pos) <= 2.2:
				return true
	return false


## Triggers a brief visual emission flash and scale pulse on claim contention
func trigger_claim_flash(flash_color: Color = Color.WHITE) -> void:
	claim_contested.emit(held_by if held_by else claimed_by)
	var tween := create_tween()
	if not tween:
		return
	tween.set_parallel(true)

	var meshes: Array[MeshInstance3D] = []
	_find_mesh_instances(self, meshes)

	for mesh in meshes:
		var mat: Material = mesh.material_override
		if not mat and mesh.get_surface_override_material_count() > 0:
			mat = mesh.get_surface_override_material(0)
		if not mat and mesh.mesh:
			mat = mesh.mesh.material

		if mat is StandardMaterial3D:
			var flash_mat := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			flash_mat.emission_enabled = true
			flash_mat.emission = flash_color
			flash_mat.emission_energy_multiplier = 2.0
			mesh.material_override = flash_mat
			tween.tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.25)
			tween.chain().tween_callback(func() -> void:
				if is_instance_valid(mesh):
					mesh.material_override = mat
			)

	var original_scale: Vector3 = scale
	tween.tween_property(self, "scale", original_scale * 1.25, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", original_scale, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _find_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		_find_mesh_instances(child, result)
