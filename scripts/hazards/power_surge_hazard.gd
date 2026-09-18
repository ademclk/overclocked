class_name PowerSurgeHazard
extends BaseHazard

## Disables a target station for the hazard's duration.
## The station cannot process devices or be interacted with while surged.
## Players can clear the surge by interacting with the hazard (holding interact for clear_time).

@export var target_station: BaseStation = null

var _original_label_text: String = ""
var _original_label_color: Color = Color.WHITE


func _ready() -> void:
	hazard_name = "Power Surge"
	hazard_type = "surge"
	duration = Constants.DEFAULT_SURGE_DURATION      # 15.0s
	warning_duration = 2.0
	clear_time = Constants.DEFAULT_SURGE_CLEAR_TIME  # 3.0s
	can_be_cleared = true
	affects_players = false
	affects_stations = true

	# Ensure CollisionShape3D exists
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape:
		shape = CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 1.5, 1.5)
		shape.shape = box
		add_child(shape)

	# Ensure InteractionZone exists
	if not interaction_zone and can_be_cleared:
		var iz := Interactable.new()
		iz.name = "InteractionZone"
		var iz_shape := CollisionShape3D.new()
		var iz_sphere := SphereShape3D.new()
		iz_sphere.radius = 1.8
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
		lbl.modulate = Color(0.4, 0.7, 1.0)
		add_child(lbl)
		hazard_label = lbl

	super._ready()


func _on_activated() -> void:
	if not target_station and has_meta("target_station"):
		target_station = get_meta("target_station") as BaseStation

	if target_station and is_instance_valid(target_station):
		_disable_station(target_station)

	# Create electrical sparking visual
	if hazard_visual:
		var old_mesh := hazard_visual.get_node_or_null("SurgeMesh")
		if old_mesh:
			old_mesh.queue_free()

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "SurgeMesh"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.4
		torus.outer_radius = 0.7
		mesh_inst.mesh = torus

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.8, 1.0)
		mat.emission_energy_multiplier = 2.0
		mesh_inst.material_override = mat

		hazard_visual.add_child(mesh_inst)


func _process_active_effects(delta: float) -> void:
	# Visual: pulsing electrical spark effect
	if hazard_label:
		var spark: float = sin(Time.get_ticks_msec() * 0.02) * 0.5 + 0.5
		hazard_label.modulate = Color(0.3 + spark * 0.7, 0.6 + spark * 0.4, 1.0)

	var surge_mesh := hazard_visual.get_node_or_null("SurgeMesh") as MeshInstance3D if hazard_visual else null
	if surge_mesh:
		surge_mesh.rotate_y(delta * 4.0)
		var scale_val: float = 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.15
		surge_mesh.scale = Vector3(scale_val, scale_val, scale_val)


func clear() -> void:
	if target_station and is_instance_valid(target_station):
		_enable_station(target_station)
	super.clear()


func expire() -> void:
	if target_station and is_instance_valid(target_station):
		_enable_station(target_station)
	super.expire()


func _disable_station(station: BaseStation) -> void:
	if station.interaction_zone:
		station.interaction_zone.is_interactable = false

	if station.station_label:
		_original_label_text = station.station_label.text
		_original_label_color = station.station_label.modulate
		station.station_label.text = "⚡ %s [OFFLINE]" % station.station_name.to_upper()
		station.station_label.modulate = Color(0.5, 0.5, 0.7)


func _enable_station(station: BaseStation) -> void:
	if station.interaction_zone:
		station.interaction_zone.is_interactable = true

	if station.station_label:
		if not _original_label_text.is_empty():
			station.station_label.text = _original_label_text
		else:
			station.station_label.text = station.station_name.to_upper()
		station.station_label.modulate = _original_label_color
