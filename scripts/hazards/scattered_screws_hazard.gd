class_name ScatteredScrewsHazard
extends BaseHazard

## Hazard representing loose screws and hardware scattered on the workshop floor.
## Causes slipping / movement speed reduction until gathered up.
## Resolved via the 3D screw gathering minigame.

@export var screw_count: int = 5

var _screw_meshes: Array[Node3D] = []


func _ready() -> void:
	hazard_name = "Scattered Screws"
	hazard_type = "screws"
	player_speed_multiplier = 0.65
	clear_time = 2.0
	super._ready()
	_create_screw_visuals()


func _create_screw_visuals() -> void:
	if not hazard_visual:
		hazard_visual = Node3D.new()
		hazard_visual.name = "HazardVisual"
		add_child(hazard_visual)

	for i in range(screw_count):
		var screw := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = 0.08
		screw.mesh = cyl

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.85, 0.9)
		mat.metallic = 0.95
		mat.roughness = 0.2
		screw.material_override = mat

		var angle := (float(i) / float(screw_count)) * TAU
		var radius := randf_range(0.2, 0.5)
		screw.position = Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)
		screw.rotation = Vector3(0.0, randf() * TAU, deg_to_rad(80.0))
		hazard_visual.add_child(screw)
		_screw_meshes.append(screw)


func clear() -> void:
	for s in _screw_meshes:
		if is_instance_valid(s):
			s.queue_free()
	_screw_meshes.clear()
	super.clear()
