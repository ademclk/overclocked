class_name DeliveryBox
extends Carriable

## A delivery box containing replacement parts that arrives mid-round.
## Must be picked up and carried to the Parts Shelf and unpacked via interaction.

@export var contained_parts: Dictionary = {}  ## component_id -> quantity
@export var default_restock_amount: int = 2

var spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	item_type = "delivery"
	if item_name.is_empty() or item_name == "Carriable":
		item_name = "Parts Delivery Box"
	add_to_group("delivery_boxes")

	if spawn_position == Vector3.ZERO and is_inside_tree():
		spawn_position = global_position

	_setup_interaction_zone()
	_setup_visual()
	super._ready()


func _physics_process(_delta: float) -> void:
	if not is_held and global_position.y < -1.0:
		global_position = spawn_position


func _setup_interaction_zone() -> void:
	if not interaction_zone:
		interaction_zone = get_node_or_null("InteractionZone") as Interactable
	if not interaction_zone:
		interaction_zone = setup_interaction_zone(0.6)
		return

	interaction_zone.interaction_prompt = "Pick Up %s" % item_name
	interaction_zone.is_interactable = not is_held
	interaction_zone.can_interact_handler = func(p: PlayerCharacter) -> bool:
		return not is_held and can_claim(p) and (p == null or p.carry_system == null or p.carry_system.can_pick_up())

	if not interaction_zone.interacted.is_connected(_on_interaction_zone_interacted):
		interaction_zone.interacted.connect(_on_interaction_zone_interacted)


func _on_interaction_zone_interacted(player: PlayerCharacter) -> void:
	if not is_held and player and player.carry_system and player.carry_system.can_pick_up():
		player.carry_system.pick_up(self)


func drop(drop_position: Vector3) -> void:
	super.drop(drop_position)
	if spawn_position == Vector3.ZERO:
		spawn_position = drop_position


func _setup_visual() -> void:
	if get_node_or_null("MeshInstance3D"):
		return

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"

	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.25, 0.35)
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.45, 0.25)  # Cardboard brown
	mat.roughness = 0.8
	mesh_inst.material_override = mat

	add_child(mesh_inst)


## Called when the box is unpacked at a parts shelf
func unpack_at_shelf(shelf: PartsShelf) -> void:
	if not shelf or not is_instance_valid(shelf):
		return

	if contained_parts.is_empty():
		for part: ComponentData in shelf.available_parts:
			if part:
				shelf.restock(part.component_id, default_restock_amount)
	else:
		for component_id: String in contained_parts:
			var qty: int = contained_parts[component_id]
			shelf.restock(component_id, qty)

	# Clean up from player carry system if held
	if is_held and held_by and held_by.carry_system:
		held_by.carry_system.drop_item()

	queue_free()
