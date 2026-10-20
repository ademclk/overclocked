class_name HazardResolutionPanel
extends PanelContainer

## 3D interactive hazard resolution workstation puzzle panel.
## Like Resident Evil 3D puzzles, players inspect and interact directly in 3D to resolve hazards:
## - Floor Spill: Mopping dirty puddle spots with mop swipes.
## - Cable Tangle: Untangling and rewiring colored cables into junction terminals.
## - Power Surge: Resetting tripped circuit breaker switches and flipping the master lever.
## - Scattered Screws: Gathering loose screws and hardware from the workshop floor.
## - Battery Fire: Aiming and spraying the fire extinguisher to suppress flames.

const HotspotScript = preload("res://scripts/ui/inspection_hotspot.gd")

signal panel_opened()
signal panel_closed()
signal hazard_resolved(hazard: BaseHazard)

@export var owning_player_index: int = 0

var _is_open: bool = false
var _current_hazard: BaseHazard = null
var _owning_player: PlayerCharacter = null

# 3D Camera & Viewport interaction
var _is_dragging: bool = false
var _target_rotation: Vector3 = Vector3(-0.35, 0.0, 0.0)
var _current_rotation: Vector3 = Vector3(-0.35, 0.0, 0.0)
var _target_cam_dist: float = 1.2
var _current_cam_dist: float = 1.2

# 3D Model Tracking & Hotspots
var _preview_mesh: Node3D = null
var _active_hotspots: Array = []
var _primary_hotspot = null
var _cleared_steps: int = 0
var _total_steps: int = 4
var _step_nodes: Array[Node3D] = []
var _step_labels: Array[Label] = []

# UI Node References
@onready var hazard_title: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/HazardTitle") as Label
@onready var hazard_type_badge: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/HazardTypeBadge") as Label
@onready var status_badge: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/StatusBadge") as Label
@onready var task_title: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/TaskPanel/VBox/TaskTitle") as Label
@onready var task_desc: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/TaskPanel/VBox/TaskDesc") as Label
@onready var progress_bar: ProgressBar = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ProgressPanel/VBox/ProgressBar") as ProgressBar
@onready var target_checklist: VBoxContainer = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ProgressPanel/VBox/TargetChecklist") as VBoxContainer
@onready var primary_action_btn: Button = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ActionPanel/VBox/PrimaryActionButton") as Button
@onready var cancel_btn: Button = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ActionPanel/VBox/CancelButton") as Button

# 3D Viewport References
@onready var viewport_panel: PanelContainer = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel") as PanelContainer
@onready var model_root: Node3D = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/3DViewportContainer/SubViewport/HazardModelRoot") as Node3D
@onready var inspection_camera: Camera3D = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/3DViewportContainer/SubViewport/Camera3D") as Camera3D
@onready var hotspot_overlay: Control = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/HotspotOverlay") as Control


func _ready() -> void:
	visible = false
	if cancel_btn:
		cancel_btn.pressed.connect(close_panel)
	if viewport_panel:
		viewport_panel.gui_input.connect(_on_viewport_input)


func is_open() -> bool:
	return _is_open


func open_hazard_panel(player: PlayerCharacter, hazard: BaseHazard) -> void:
	if not hazard or not is_instance_valid(hazard):
		return

	_owning_player = player
	_current_hazard = hazard
	if player:
		owning_player_index = player.player_index
		player.set_movement_locked(true)

	_is_open = true
	visible = true
	_cleared_steps = 0
	_step_nodes.clear()
	_step_labels.clear()

	_clear_3d_preview()
	_setup_hazard_minigame()
	_update_header()
	_update_progress()
	_update_action_button()

	panel_opened.emit()


func close_panel() -> void:
	if not _is_open:
		return

	_is_open = false
	_is_dragging = false
	visible = false

	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)
	_owning_player = null
	_current_hazard = null

	_clear_hotspots()
	_clear_3d_preview()

	panel_closed.emit()


func _clear_3d_preview() -> void:
	if model_root and is_instance_valid(model_root):
		for child in model_root.get_children():
			child.queue_free()
	_preview_mesh = null
	_step_nodes.clear()


func _clear_hotspots() -> void:
	for hs in _active_hotspots:
		if is_instance_valid(hs):
			hs.queue_free()
	_active_hotspots.clear()
	_primary_hotspot = null


func _add_hotspot(hs: Control, is_primary: bool = false) -> void:
	if not hs or not hotspot_overlay:
		return
	hotspot_overlay.add_child(hs)
	_active_hotspots.append(hs)
	if is_primary:
		_primary_hotspot = hs


func _process(delta: float) -> void:
	if not _is_open:
		return

	# Keyboard rotation controls (A/D, W/S, or Arrow Keys)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_target_rotation.y -= delta * 2.5
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_target_rotation.y += delta * 2.5

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_target_rotation.x = clampf(_target_rotation.x - delta * 2.0, -PI * 0.45, PI * 0.45)
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_target_rotation.x = clampf(_target_rotation.x + delta * 2.0, -PI * 0.45, PI * 0.45)

	# Smoothly interpolate rotation
	_current_rotation.x = lerp_angle(_current_rotation.x, _target_rotation.x, delta * 14.0)
	_current_rotation.y = lerp_angle(_current_rotation.y, _target_rotation.y, delta * 14.0)
	_current_rotation.z = lerp_angle(_current_rotation.z, _target_rotation.z, delta * 14.0)

	if model_root and is_instance_valid(model_root):
		model_root.rotation = _current_rotation

	# Camera zoom
	_current_cam_dist = lerpf(_current_cam_dist, _target_cam_dist, delta * 10.0)
	if inspection_camera and is_instance_valid(inspection_camera):
		inspection_camera.position.z = _current_cam_dist

	_update_hotspot_positions()


func _update_hotspot_positions() -> void:
	if not inspection_camera or not model_root:
		return

	for hs in _active_hotspots:
		if not is_instance_valid(hs):
			continue

		var world_pos: Vector3 = model_root.global_transform * hs.target_3d_pos
		if inspection_camera.is_position_behind(world_pos):
			hs.visible = false
			continue

		var screen_2d: Vector2 = inspection_camera.unproject_position(world_pos)
		var arrow_offset_y: float = HotspotScript.BADGE_RADIUS * 2.0 + HotspotScript.ARROW_HEIGHT + 3.0
		hs.position = screen_2d - Vector2(hs.size.x * 0.5, arrow_offset_y)
		hs.visible = true


# =========================================================================
# MINIGAME SCENE SETUPS (Per Hazard Type)
# =========================================================================

func _is_screws_hazard(hazard: BaseHazard) -> bool:
	if not hazard:
		return false
	if hazard is ScatteredScrewsHazard:
		return true
	if hazard is FloorSpillHazard:
		return (hazard as FloorSpillHazard).spill_type == FloorSpillHazard.SpillType.SCREWS
	return hazard.hazard_name.to_lower().contains("screw")


func _setup_hazard_minigame() -> void:
	_clear_hotspots()
	if not _current_hazard:
		return

	if _is_screws_hazard(_current_hazard):
		_setup_screws_minigame(_current_hazard)
	elif _current_hazard is FloorSpillHazard:
		_setup_mop_minigame(_current_hazard as FloorSpillHazard)
	elif _current_hazard is CableTangleHazard:
		_setup_cable_minigame(_current_hazard as CableTangleHazard)
	elif _current_hazard is PowerSurgeHazard:
		_setup_surge_minigame(_current_hazard as PowerSurgeHazard)
	elif _current_hazard is BatteryFireHazard:
		_setup_fire_minigame(_current_hazard as BatteryFireHazard)
	elif _current_hazard is ScatteredScrewsHazard:
		_setup_screws_minigame(_current_hazard as ScatteredScrewsHazard)
	else:
		_setup_generic_minigame(_current_hazard)


## 1. FLOOR SPILL: MOPPING MINIGAME
func _setup_mop_minigame(spill: FloorSpillHazard) -> void:
	_total_steps = 4
	_target_rotation = Vector3(-0.65, 0.0, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 1.25

	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	# Floor tile
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.02, 0.8)
	floor_mesh.mesh = box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.22, 0.25)
	floor_mat.roughness = 0.8
	floor_mesh.material_override = floor_mat
	_preview_mesh.add_child(floor_mesh)

	# Main liquid puddle
	var puddle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.35
	cyl.height = 0.005
	puddle.mesh = cyl
	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color = spill.spill_color if "spill_color" in spill else Color(0.35, 0.2, 0.1, 0.85)
	p_mat.roughness = 0.1
	p_mat.metallic = 0.1
	puddle.material_override = p_mat
	puddle.position.y = 0.012
	_preview_mesh.add_child(puddle)

	# 4 Dirty Stain Spots to Mop
	var spot_offsets: Array[Vector3] = [
		Vector3(-0.14, 0.015, -0.12),
		Vector3(0.12, 0.015, -0.10),
		Vector3(-0.10, 0.015, 0.12),
		Vector3(0.13, 0.015, 0.11),
	]

	_build_checklist(["Mop Northwest Spill Area", "Mop Northeast Spill Area", "Mop Southwest Spill Area", "Mop Southeast Spill Area"])

	for i in range(spot_offsets.size()):
		var spot_pos := spot_offsets[i]
		var spot_mesh := MeshInstance3D.new()
		var scyl := CylinderMesh.new()
		scyl.top_radius = 0.08
		scyl.bottom_radius = 0.08
		scyl.height = 0.008
		spot_mesh.mesh = scyl
		var s_mat := StandardMaterial3D.new()
		s_mat.albedo_color = Color(0.2, 0.12, 0.05)
		s_mat.roughness = 0.15
		spot_mesh.material_override = s_mat
		spot_mesh.position = spot_pos
		_preview_mesh.add_child(spot_mesh)
		_step_nodes.append(spot_mesh)

		var hs = HotspotScript.new(
			"mop_spot_%d" % i,
			"Mop Spot %d" % (i + 1),
			spot_pos + Vector3(0.0, 0.02, 0.0),
			Callable(self, "_on_mop_spot_cleaned").bind(i)
		)
		hs.glyph = "🧹"
		_add_hotspot(hs, i == 0)


func _on_mop_spot_cleaned(index: int) -> void:
	if index < _step_nodes.size() and is_instance_valid(_step_nodes[index]):
		var tw := create_tween()
		tw.tween_property(_step_nodes[index], "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.finished.connect(func(): if is_instance_valid(_step_nodes[index]): _step_nodes[index].visible = false)

	# Disable hotspot
	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "mop_spot_%d" % index:
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(index)


## 2. CABLE TANGLE: UNTANGLING & REWIRING MINIGAME
func _setup_cable_minigame(_tangle: CableTangleHazard) -> void:
	_total_steps = 4
	_target_rotation = Vector3(-0.3, 0.0, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 1.15

	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	# Terminal Junction Box
	var box_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.65, 0.35, 0.12)
	box_mesh.mesh = b
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.18, 0.2, 0.24)
	box_mesh.material_override = b_mat
	_preview_mesh.add_child(box_mesh)

	var colors: Array[Color] = [
		Color(0.9, 0.2, 0.2), # Red
		Color(0.2, 0.5, 0.9), # Blue
		Color(0.2, 0.85, 0.3), # Green
		Color(0.95, 0.8, 0.1) # Yellow
	]
	var color_names: Array[String] = ["Red Cable", "Blue Cable", "Green Cable", "Yellow Cable"]

	_build_checklist(["Untangle & Plug Red Cable", "Untangle & Plug Blue Cable", "Untangle & Plug Green Cable", "Untangle & Plug Yellow Cable"])

	for i in range(4):
		var col: Color = colors[i]
		var x_pos: float = -0.22 + float(i) * 0.15

		# Terminal Port
		var port := MeshInstance3D.new()
		var pcyl := CylinderMesh.new()
		pcyl.top_radius = 0.03
		pcyl.bottom_radius = 0.03
		pcyl.height = 0.02
		port.mesh = pcyl
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = col * 0.4
		pmat.emission_enabled = true
		pmat.emission = col * 0.3
		port.material_override = pmat
		port.position = Vector3(x_pos, 0.08, 0.065)
		port.rotation.x = deg_to_rad(90.0)
		_preview_mesh.add_child(port)

		# Tangled Cable Plug
		var cable := MeshInstance3D.new()
		var ccyl := CylinderMesh.new()
		ccyl.top_radius = 0.025
		ccyl.bottom_radius = 0.025
		ccyl.height = 0.06
		cable.mesh = ccyl
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = col
		cmat.emission_enabled = true
		cmat.emission = col * 0.6
		cable.material_override = cmat
		# Tangled position (offset down and out)
		var tangled_pos := Vector3(x_pos + randf_range(-0.04, 0.04), -0.10 + randf_range(-0.03, 0.03), 0.18 + randf_range(0.0, 0.06))
		cable.position = tangled_pos
		cable.rotation = Vector3(deg_to_rad(randf_range(20, 60)), deg_to_rad(randf_range(-30, 30)), 0)
		_preview_mesh.add_child(cable)
		_step_nodes.append(cable)

		var target_plug_pos := Vector3(x_pos, 0.08, 0.08)

		var hs = HotspotScript.new(
			"cable_%d" % i,
			"Plug %s" % color_names[i],
			tangled_pos + Vector3(0, 0.04, 0),
			Callable(self, "_on_cable_plugged").bind(i, cable, target_plug_pos, pmat, col)
		)
		hs.glyph = "🔌"
		_add_hotspot(hs, i == 0)


func _on_cable_plugged(index: int, cable: MeshInstance3D, target_pos: Vector3, port_mat: StandardMaterial3D, col: Color) -> void:
	if is_instance_valid(cable):
		var tw := create_tween()
		tw.tween_property(cable, "position", target_pos, 0.2).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(cable, "rotation", Vector3(deg_to_rad(90.0), 0, 0), 0.2)
		tw.finished.connect(func():
			if is_instance_valid(port_mat):
				port_mat.emission = col * 1.5
		)

	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "cable_%d" % index:
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(index)


## 3. POWER SURGE: BREAKER RESET & REWIRING MINIGAME
func _setup_surge_minigame(_surge: PowerSurgeHazard) -> void:
	_total_steps = 4
	_target_rotation = Vector3(-0.15, 0.0, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 1.05

	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	# Electrical Breaker Panel
	var panel_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.55, 0.45, 0.1)
	panel_mesh.mesh = b
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.25, 0.28, 0.32)
	panel_mesh.material_override = pmat
	_preview_mesh.add_child(panel_mesh)

	_build_checklist(["Reset Sub-Breaker 1", "Reset Sub-Breaker 2", "Reset Sub-Breaker 3", "Throw Main Circuit Breaker"])

	# 3 Sub-breaker switches
	for i in range(3):
		var x_pos: float = -0.16 + float(i) * 0.16
		var sw := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.04, 0.08, 0.04)
		sw.mesh = sb
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.9, 0.25, 0.2) # Red/tripped
		sw.material_override = smat
		sw.position = Vector3(x_pos, 0.06, 0.06)
		sw.rotation.x = deg_to_rad(-25.0) # Down/tripped
		_preview_mesh.add_child(sw)
		_step_nodes.append(sw)

		var hs = HotspotScript.new(
			"breaker_%d" % i,
			"Reset Breaker %d" % (i + 1),
			Vector3(x_pos, 0.06, 0.08),
			Callable(self, "_on_breaker_reset").bind(i, sw, smat)
		)
		hs.glyph = "⚡"
		_add_hotspot(hs, i == 0)

	# Main Master Lever (4th step)
	var main_lever := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.08, 0.12, 0.05)
	main_lever.mesh = lb
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.8, 0.5, 0.1)
	main_lever.material_override = lmat
	main_lever.position = Vector3(0.0, -0.12, 0.06)
	main_lever.rotation.x = deg_to_rad(-35.0) # Down
	_preview_mesh.add_child(main_lever)
	_step_nodes.append(main_lever)

	var main_hs = HotspotScript.new(
		"main_breaker",
		"Throw Main Breaker",
		Vector3(0.0, -0.12, 0.08),
		Callable(self, "_on_main_breaker_thrown").bind(main_lever, lmat)
	)
	main_hs.glyph = "⚡"
	main_hs.is_enabled = false
	main_hs.disabled_reason = "Reset sub-breakers first"
	_add_hotspot(main_hs, false)


func _on_breaker_reset(index: int, sw: MeshInstance3D, mat: StandardMaterial3D) -> void:
	if is_instance_valid(sw):
		var tw := create_tween()
		tw.tween_property(sw, "rotation:x", deg_to_rad(25.0), 0.15)
		tw.finished.connect(func():
			if is_instance_valid(mat):
				mat.albedo_color = Color(0.25, 0.9, 0.3)
		)

	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "breaker_%d" % index:
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(index)

	# Check if all 3 sub-breakers are reset -> unlock main breaker
	if _cleared_steps == 3:
		for hs in _active_hotspots:
			if is_instance_valid(hs) and hs.action_id == "main_breaker":
				hs.is_enabled = true
				hs.disabled_reason = ""
				_primary_hotspot = hs
				_update_action_button()
				break


func _on_main_breaker_thrown(lever: MeshInstance3D, mat: StandardMaterial3D) -> void:
	if is_instance_valid(lever):
		var tw := create_tween()
		tw.tween_property(lever, "rotation:x", deg_to_rad(35.0), 0.18)
		tw.finished.connect(func():
			if is_instance_valid(mat):
				mat.albedo_color = Color(0.3, 1.0, 0.4)
				mat.emission_enabled = true
				mat.emission = Color(0.2, 0.8, 0.3)
		)

	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "main_breaker":
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(3)


## 4. SCATTERED SCREWS: GROUND HARDWARE GATHERING MINIGAME
func _setup_screws_minigame(_screws: BaseHazard) -> void:
	_total_steps = 5
	_target_rotation = Vector3(-0.7, 0.0, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 1.15

	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	# Concrete ground slab
	var floor_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.85, 0.02, 0.85)
	floor_mesh.mesh = b
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.26, 0.28)
	floor_mesh.material_override = fmat
	_preview_mesh.add_child(floor_mesh)

	var screw_positions: Array[Vector3] = [
		Vector3(-0.22, 0.02, -0.18),
		Vector3(0.18, 0.02, -0.16),
		Vector3(-0.08, 0.02, 0.02),
		Vector3(-0.20, 0.02, 0.19),
		Vector3(0.19, 0.02, 0.17),
	]

	var screw_labels: Array[String] = [
		"Gather Hex Bolt",
		"Gather M3 Screw",
		"Gather Lock Washer",
		"Gather M4 Screw",
		"Gather Phillips Screw"
	]
	_build_checklist(screw_labels)

	for i in range(screw_positions.size()):
		var spos := screw_positions[i]
		var screw := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = 0.07
		screw.mesh = cyl
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.9, 0.9, 0.95)
		smat.metallic = 0.95
		smat.roughness = 0.15
		screw.material_override = smat
		screw.position = spos
		screw.rotation = Vector3(0.0, randf() * TAU, deg_to_rad(80.0))
		_preview_mesh.add_child(screw)
		_step_nodes.append(screw)

		var hs = HotspotScript.new(
			"screw_%d" % i,
			screw_labels[i],
			spos + Vector3(0.0, 0.03, 0.0),
			Callable(self, "_on_screw_gathered").bind(i, screw)
		)
		hs.glyph = "🔩"
		_add_hotspot(hs, i == 0)


func _on_screw_gathered(index: int, screw: MeshInstance3D) -> void:
	if is_instance_valid(screw):
		var tw := create_tween()
		tw.tween_property(screw, "position:y", 0.25, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(screw, "scale", Vector3.ZERO, 0.2)
		tw.finished.connect(func(): if is_instance_valid(screw): screw.visible = false)

	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "screw_%d" % index:
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(index)


## 5. BATTERY FIRE: EXTINGUISHER MINIGAME
func _setup_fire_minigame(_fire: BatteryFireHazard) -> void:
	_total_steps = 3
	_target_rotation = Vector3(-0.4, 0.0, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 1.05

	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	# Charred Battery Pack
	var batt := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.35, 0.12, 0.25)
	batt.mesh = b
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.12, 0.14)
	batt.material_override = bmat
	_preview_mesh.add_child(batt)

	_build_checklist(["Spray Extinguisher Burst 1", "Spray Extinguisher Burst 2", "Suppress Remaining Embers"])

	# 3 Flame billows
	for i in range(3):
		var x_pos: float = -0.1 + float(i) * 0.1
		var flame := MeshInstance3D.new()
		var fcyl := CylinderMesh.new()
		fcyl.top_radius = 0.02
		fcyl.bottom_radius = 0.06
		fcyl.height = 0.16
		flame.mesh = fcyl
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.45, 0.1, 0.9)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.35, 0.05)
		flame.material_override = fmat
		flame.position = Vector3(x_pos, 0.12, 0.0)
		_preview_mesh.add_child(flame)
		_step_nodes.append(flame)

		var hs = HotspotScript.new(
			"flame_%d" % i,
			"Spray Flame %d" % (i + 1),
			Vector3(x_pos, 0.14, 0.0),
			Callable(self, "_on_flame_extinguished").bind(i, flame)
		)
		hs.glyph = "🧯"
		_add_hotspot(hs, i == 0)


func _on_flame_extinguished(index: int, flame: MeshInstance3D) -> void:
	if is_instance_valid(flame):
		var tw := create_tween()
		tw.tween_property(flame, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_QUAD)
		tw.finished.connect(func(): if is_instance_valid(flame): flame.visible = false)

	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.action_id == "flame_%d" % index:
			hs.is_enabled = false
			hs.visible = false
			break

	_step_completed(index)


## 6. GENERIC FALLBACK
func _setup_generic_minigame(hazard: BaseHazard) -> void:
	_total_steps = 3
	_preview_mesh = Node3D.new()
	model_root.add_child(_preview_mesh)

	var icon_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.4, 0.4, 0.4)
	icon_mesh.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.4, 0.2)
	icon_mesh.material_override = mat
	_preview_mesh.add_child(icon_mesh)

	_build_checklist(["Inspect Hazard Issue", "Apply Repair Tool", "Verify Station Safety"])

	for i in range(3):
		var hs = HotspotScript.new(
			"generic_%d" % i,
			"Perform Action %d" % (i + 1),
			Vector3(0.0, 0.15, 0.0),
			Callable(self, "_step_completed").bind(i)
		)
		hs.glyph = "🔧"
		_add_hotspot(hs, i == 0)


# =========================================================================
# PROGRESS & COMPLETION
# =========================================================================

func _step_completed(step_idx: int) -> void:
	_cleared_steps += 1
	if step_idx < _step_labels.size() and is_instance_valid(_step_labels[step_idx]):
		_step_labels[step_idx].text = "✓ " + _step_labels[step_idx].text.substr(2)
		_step_labels[step_idx].modulate = Color(0.35, 0.95, 0.45)

	# Update next primary hotspot
	_primary_hotspot = null
	for hs in _active_hotspots:
		if is_instance_valid(hs) and hs.is_enabled:
			_primary_hotspot = hs
			break

	_update_progress()
	_update_action_button()

	if _cleared_steps >= _total_steps:
		_finish_hazard_resolution()


func _finish_hazard_resolution() -> void:
	if status_badge:
		status_badge.text = "[ RESOLVED! ✓ ]"
		status_badge.modulate = Color(0.3, 1.0, 0.5)

	if primary_action_btn:
		primary_action_btn.disabled = true
		primary_action_btn.text = "✓ HAZARD FULLY RESOLVED"

	if _current_hazard and is_instance_valid(_current_hazard):
		hazard_resolved.emit(_current_hazard)
		_current_hazard.clear()

	# Close after brief victory delay
	var tw := create_tween()
	tw.tween_interval(0.65)
	tw.finished.connect(close_panel)


func _build_checklist(items: Array[String]) -> void:
	if not target_checklist:
		return
	for c in target_checklist.get_children():
		c.queue_free()
	_step_labels.clear()

	for item in items:
		var lbl := Label.new()
		lbl.text = "○ " + item
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
		target_checklist.add_child(lbl)
		_step_labels.append(lbl)


func _update_header() -> void:
	if not _current_hazard:
		return

	var is_screws: bool = _is_screws_hazard(_current_hazard)
	var h_name: String = _current_hazard.hazard_name.to_upper()
	if hazard_title:
		var icon: String = "⚠️"
		if is_screws: icon = "🔩"
		elif _current_hazard is FloorSpillHazard: icon = "☕"
		elif _current_hazard is CableTangleHazard: icon = "🔌"
		elif _current_hazard is PowerSurgeHazard: icon = "⚡"
		elif _current_hazard is BatteryFireHazard: icon = "🧯"
		hazard_title.text = "%s %s — 3D PUZZLE" % [icon, h_name]

	if hazard_type_badge:
		var type_str: String = "SCREWS" if is_screws else _current_hazard.hazard_type.to_upper()
		hazard_type_badge.text = "[ %s ]" % type_str

	if task_title:
		task_title.text = "RESOLUTION TASK"

	if task_desc:
		if is_screws:
			task_desc.text = "Click the glowing hotspots directly in the 3D puzzle view to gather all loose screws into your toolbox."
		elif _current_hazard is FloorSpillHazard:
			task_desc.text = "Click each dirty puddle hotspot directly in the 3D puzzle view to mop it clean before someone slips!"
		elif _current_hazard is CableTangleHazard:
			task_desc.text = "Untangle cords and rewire each color-coded cable into its matching terminal port."
		elif _current_hazard is PowerSurgeHazard:
			task_desc.text = "Reset all tripped sub-breaker switches, then throw the master breaker to restore power."
		elif _current_hazard is BatteryFireHazard:
			task_desc.text = "Aim the fire extinguisher at the base of the flames and discharge foam bursts."
		else:
			task_desc.text = "Complete all resolution steps to make this area safe for work."


func _update_progress() -> void:
	var pct: float = (float(_cleared_steps) / float(maxi(1, _total_steps))) * 100.0
	if progress_bar:
		progress_bar.value = pct

	if status_badge and _cleared_steps < _total_steps:
		status_badge.text = "[ %d / %d RESOLVED ]" % [_cleared_steps, _total_steps]
		status_badge.modulate = Color(0.35, 0.9, 1.0)


func _update_action_button() -> void:
	if not primary_action_btn:
		return

	if _cleared_steps >= _total_steps:
		primary_action_btn.visible = true
		primary_action_btn.disabled = true
		primary_action_btn.text = "✓ COMPLETE"
	elif _primary_hotspot and is_instance_valid(_primary_hotspot) and _primary_hotspot.is_enabled:
		primary_action_btn.visible = true
		primary_action_btn.disabled = true
		primary_action_btn.text = "CLICK 3D HOTSPOT TO RESOLVE"
	else:
		primary_action_btn.visible = false


func _on_primary_action_pressed() -> void:
	if _primary_hotspot and is_instance_valid(_primary_hotspot) and _primary_hotspot.is_enabled:
		_primary_hotspot.trigger_action()


# =========================================================================
# INPUT HANDLING
# =========================================================================

func _on_viewport_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = mb.pressed
			if viewport_panel:
				viewport_panel.accept_event()
			else:
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_cam_dist = clampf(_target_cam_dist - 0.08, 0.5, 2.0)
			if viewport_panel:
				viewport_panel.accept_event()
			else:
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_cam_dist = clampf(_target_cam_dist + 0.08, 0.5, 2.0)
			if viewport_panel:
				viewport_panel.accept_event()
			else:
				accept_event()

	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_target_rotation.y += mm.relative.x * 0.012
		_target_rotation.x = clampf(_target_rotation.x + mm.relative.y * 0.012, -PI * 0.45, PI * 0.45)
		if viewport_panel:
			viewport_panel.accept_event()
		else:
			accept_event()


func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouse:
		if _is_dragging or (viewport_panel and viewport_panel.get_global_rect().has_point(event.global_position)):
			_on_viewport_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	var player_idx: int = owning_player_index
	var cancel := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)
	var interact := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)

	if (
		event.is_action_pressed(cancel)
		or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_Q))
	):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_is_dragging = false

