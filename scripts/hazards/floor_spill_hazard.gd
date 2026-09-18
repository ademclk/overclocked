class_name FloorSpillHazard
extends BaseHazard

## Floor hazard that slows players walking through it.
## Spawns as a circular patch on the floor. Players move at half speed while inside.
## Can be cleared by interacting with it (mopping / sweeping).

enum SpillType {
	COFFEE,
	SCREWS,
}

@export var spill_type: SpillType = SpillType.COFFEE
@export var spill_radius: float = 1.2
@export var spill_color: Color = Color(0.35, 0.2, 0.08, 0.7)  # Coffee brown


func _ready() -> void:
	if spill_type == SpillType.SCREWS:
		hazard_name = "Dropped Screws"
		spill_color = Color(0.6, 0.62, 0.68, 0.8)
	else:
		hazard_name = "Coffee Spill"
		spill_color = Color(0.35, 0.2, 0.08, 0.75)

	hazard_type = "floor"
	duration = 0.0                # Permanent until cleared
	warning_duration = 1.0
	clear_time = Constants.DEFAULT_SPILL_CLEAR_TIME  # 2.0 seconds to mop up / sweep
	can_be_cleared = true
	affects_players = true
	affects_stations = false
	player_speed_multiplier = Constants.DEFAULT_SPILL_SLOW_FACTOR  # 0.45 speed

	# Ensure CollisionShape3D exists
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape:
		shape = CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = spill_radius
		shape.shape = sphere
		add_child(shape)
	elif shape.shape is SphereShape3D:
		(shape.shape as SphereShape3D).radius = spill_radius

	# Ensure InteractionZone exists
	if not interaction_zone and can_be_cleared:
		var iz := Interactable.new()
		iz.name = "InteractionZone"
		var iz_shape := CollisionShape3D.new()
		var iz_sphere := SphereShape3D.new()
		iz_sphere.radius = spill_radius + 0.3
		iz_shape.shape = iz_sphere
		iz.add_child(iz_shape)
		add_child(iz)
		interaction_zone = iz

	if not hazard_visual:
		var vis := Node3D.new()
		vis.name = "HazardVisual"
		add_child(vis)
		hazard_visual = vis

	if not hazard_label:
		var lbl := Label3D.new()
		lbl.name = "HazardLabel"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.8, 0.0)
		lbl.font_size = 28
		lbl.modulate = Color(1.0, 0.8, 0.2)
		add_child(lbl)
		hazard_label = lbl

	super._ready()

	if interaction_zone:
		interaction_zone.interaction_prompt = "Sweep Screws" if spill_type == SpillType.SCREWS else "Mop Coffee"


func _on_activated() -> void:
	if hazard_label:
		hazard_label.text = "🔩 SCREWS" if spill_type == SpillType.SCREWS else "☕ COFFEE"

	# Create spill visual (flat disc on floor)
	if hazard_visual:
		# Remove old mesh if any
		var old_mesh := hazard_visual.get_node_or_null("SpillMesh")
		if old_mesh:
			old_mesh.queue_free()

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "SpillMesh"
		var disc := CylinderMesh.new()
		disc.top_radius = spill_radius
		disc.bottom_radius = spill_radius
		disc.height = 0.02
		mesh_inst.mesh = disc

		var mat := StandardMaterial3D.new()
		mat.albedo_color = spill_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.2 if spill_type == SpillType.COFFEE else 0.5
		mat.metallic = 0.0 if spill_type == SpillType.COFFEE else 0.8
		mesh_inst.material_override = mat

		hazard_visual.add_child(mesh_inst)

		if spill_type == SpillType.SCREWS:
			# Scatter small screw pieces
			var screw_mat := StandardMaterial3D.new()
			screw_mat.albedo_color = Color(0.85, 0.85, 0.9)
			screw_mat.metallic = 0.95
			screw_mat.roughness = 0.3

			for i in range(5):
				var angle := randf() * TAU
				var dist := randf() * (spill_radius * 0.7)
				var screw := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(0.08, 0.04, 0.15)
				screw.mesh = sm
				screw.material_override = screw_mat
				screw.position = Vector3(cos(angle) * dist, 0.02, sin(angle) * dist)
				screw.rotation.y = randf() * TAU
				hazard_visual.add_child(screw)
