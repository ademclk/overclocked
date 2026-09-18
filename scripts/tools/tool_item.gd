class_name ToolItem
extends Carriable

## A reusable tool (screwdriver, soldering iron, etc.) that players carry.
## Tools are not consumed — they persist across repairs. Limited quantity per workshop.

@export var tool_id: String = "screwdriver"
@export var tool_display_name: String = "Screwdriver"
@export var tool_color: Color = Color(0.85, 0.15, 0.15)  # Red handle

var spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	item_type = "tool"
	item_name = tool_display_name
	add_to_group("tools")

	if spawn_position == Vector3.ZERO and is_inside_tree():
		spawn_position = global_position

	_setup_interaction_zone()
	_setup_tool_visual()
	super._ready()


func _physics_process(_delta: float) -> void:
	# Safety check: Prevent tools from falling through floor or getting permanently lost
	if not is_held and global_position.y < -1.0:
		global_position = spawn_position


func _setup_interaction_zone() -> void:
	if not interaction_zone:
		interaction_zone = get_node_or_null("InteractionZone") as Interactable
	if not interaction_zone:
		interaction_zone = setup_interaction_zone(0.5)
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


func _setup_tool_visual() -> void:
	# Only create visual if no mesh child exists
	if get_node_or_null("MeshInstance3D"):
		return

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"

	var box := BoxMesh.new()
	match tool_id:
		"screwdriver":
			box.size = Vector3(0.05, 0.25, 0.05)
		"soldering_iron":
			box.size = Vector3(0.04, 0.28, 0.04)
		"thermal_paste":
			box.size = Vector3(0.08, 0.12, 0.04)
		"esd_wrist_strap":
			box.size = Vector3(0.12, 0.04, 0.12)
		_:
			box.size = Vector3(0.06, 0.2, 0.06)

	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = tool_color
	mesh_inst.material_override = mat

	add_child(mesh_inst)
