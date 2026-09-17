class_name PartsShelf
extends BaseStation

## Parts shelf station dispensing replacement components.
## Does not accept devices; players pick up needed components from here.

@export var dispensed_part_name: String = "Replacement Part"
@export var dispensed_part_type: String = "part"
@export var part_scene: PackedScene = null


func _ready() -> void:
	station_name = "Parts Shelf"
	station_type = "shelf"
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	return (
		player != null
		and player.carry_system != null
		and player.carry_system.can_pick_up()
	)


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if player and player.carry_system and player.carry_system.can_pick_up():
		return "Take %s" % dispensed_part_name
	return "Hands Full"


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if not player or not player.carry_system or not player.carry_system.can_pick_up():
		return

	var part: Carriable = _spawn_part()
	if part:
		player.carry_system.pick_up(part)


func _spawn_part() -> Carriable:
	if part_scene:
		return part_scene.instantiate() as Carriable

	# Fallback placeholder Carriable component
	var part := Carriable.new()
	part.name = "ComponentItem"
	part.item_name = dispensed_part_name
	part.item_type = dispensed_part_type

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.1, 0.25)
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.8, 0.9)
	mesh_inst.material_override = mat

	part.add_child(mesh_inst)
	return part
