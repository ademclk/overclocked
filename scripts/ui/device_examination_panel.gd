class_name DeviceExaminationPanel
extends PanelContainer

## Resident Evil 7 / 8 / 9 style 3D inspectable workstation puzzle panel.
## Allows players to rotate/zoom the device in full 3D, and perform the actual repair work
## (Diagnose, Disassemble, Install Parts, Reassemble, Flash Software) via 3D interactive
## hotspot badges (circular action glyph + downward pointer arrow), exactly like RE puzzles.

const HotspotScript = preload("res://scripts/ui/inspection_hotspot.gd")

signal panel_opened()
signal panel_closed()
signal action_performed(action_id: String)

@export var owning_player_index: int = 0

var _is_open: bool = false
var _current_device: Device = null
var _owning_player: PlayerCharacter = null
var _current_station: BaseStation = null

# 3D Inspection interaction state
var _is_dragging: bool = false
var _target_rotation: Vector3 = Vector3(-0.25, 0.45, 0.0)
var _current_rotation: Vector3 = Vector3(-0.25, 0.45, 0.0)
var _target_cam_dist: float = 0.95
var _current_cam_dist: float = 0.95
var _auto_rotate: bool = false

# 3D Model Tracking & Hotspots
var _preview_mesh: Node3D = null
var _active_hotspots: Array = []
var _primary_hotspot = null
var _is_scanning: bool = false

# UI Node References
@onready var device_title: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/DeviceTitle") as Label
@onready var station_badge: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/StationBadge") as Label
@onready var state_badge: Label = get_node_or_null("MarginContainer/VBoxContainer/Header/StateBadge") as Label
@onready var fault_name_label: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/FaultPanel/VBox/FaultName") as Label
@onready var fault_desc_label: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/FaultPanel/VBox/FaultDesc") as Label
@onready var parts_container: VBoxContainer = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/PartsPanel/VBox/PartsList") as VBoxContainer
@onready var roadmap_container: HBoxContainer = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/RoadmapPanel/RoadmapContainer") as HBoxContainer
@onready var next_step_label: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/NextStepPanel/NextStepLabel") as Label
@onready var tool_status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ActionPanel/VBox/ToolStatusLabel") as Label
@onready var primary_action_btn: Button = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ActionPanel/VBox/PrimaryActionButton") as Button
@onready var pick_up_btn: Button = get_node_or_null("MarginContainer/VBoxContainer/Content/InfoSection/ActionPanel/VBox/PickUpButton") as Button

# 3D Viewport References
@onready var model_root: Node3D = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/3DViewportContainer/SubViewport/ModelRoot") as Node3D
@onready var inspection_camera: Camera3D = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/3DViewportContainer/SubViewport/Camera3D") as Camera3D
@onready var viewport_panel: PanelContainer = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel") as PanelContainer
@onready var hotspot_overlay: Control = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/HotspotOverlay") as Control
@onready var scan_effect_layer: Control = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/ScanEffectLayer") as Control
@onready var scan_line: ColorRect = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/ScanEffectLayer/ColorRect") as ColorRect
@onready var scan_label: Label = get_node_or_null("MarginContainer/VBoxContainer/Content/3DSection/ViewportPanel/ScanEffectLayer/ScanLabel") as Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	if primary_action_btn:
		primary_action_btn.pressed.connect(_on_primary_action_pressed)
	if pick_up_btn:
		pick_up_btn.pressed.connect(_trigger_pick_up)


func is_open() -> bool:
	return _is_open


func open_panel(player: PlayerCharacter, device: Device, station: BaseStation = null) -> void:
	if not device:
		return

	_owning_player = player
	if player:
		owning_player_index = player.player_index
	_current_device = device
	_current_station = station

	# If station was not passed, discover station from hierarchy
	if not _current_station and device:
		var p := device.get_parent()
		while p != null:
			if p is BaseStation:
				_current_station = p as BaseStation
				break
			p = p.get_parent()

	_is_open = true

	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(true)

	_setup_3d_preview(device)
	_refresh_all()

	visible = true
	panel_opened.emit()
	SignalBus.device_examined.emit(owning_player_index, device.item_name)


func close_panel() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false

	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)

	_clear_hotspots()
	_clear_3d_preview()
	_current_device = null
	_current_station = null
	panel_closed.emit()


func _refresh_all() -> void:
	if not _current_device:
		return
	_populate_device_info()
	_build_roadmap()
	_update_next_step()
	_update_chassis_3d_state()
	_build_hotspots()


func _setup_3d_preview(device: Device) -> void:
	_clear_3d_preview()
	if not model_root:
		return

	var mesh_node: Node3D = device.get_node_or_null("DeviceMesh") as Node3D
	_preview_mesh = null

	if mesh_node:
		_preview_mesh = mesh_node.duplicate() as Node3D
	else:
		# Fallback: create 3D box
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.06, 0.45)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.5, 0.8)
		mat.metallic = 0.5
		mat.roughness = 0.3
		mi.material_override = mat
		_preview_mesh = mi

	if _preview_mesh:
		_preview_mesh.visible = true
		for child in _preview_mesh.find_children("*", "Node3D"):
			if child is Node3D:
				child.visible = true
		_preview_mesh.position = Vector3.ZERO
		_preview_mesh.rotation = Vector3.ZERO

		# Scale factor per device type so each object fills the RE inspection viewport
		var dev_name: String = device.item_name.to_lower()
		var scale_factor: float = 2.4
		if dev_name.contains("phone"):
			scale_factor = 2.8
		elif dev_name.contains("tablet"):
			scale_factor = 2.2
		elif dev_name.contains("laptop"):
			scale_factor = 1.6
		elif dev_name.contains("console"):
			scale_factor = 1.5
		elif dev_name.contains("desktop"):
			scale_factor = 0.8
		elif dev_name.contains("router"):
			scale_factor = 1.8

		_preview_mesh.scale = Vector3.ONE * scale_factor
		model_root.add_child(_preview_mesh)

	# Reset orientation & zoom to classic RE angled view
	_target_rotation = Vector3(-0.25, 0.45, 0.0)
	_current_rotation = _target_rotation
	_target_cam_dist = 0.95
	_current_cam_dist = 0.95
	_auto_rotate = false


func _clear_3d_preview() -> void:
	if model_root and is_instance_valid(model_root):
		for child in model_root.get_children():
			child.queue_free()
	_preview_mesh = null


## Updates 3D mesh chassis opening/closing based on device repair state
func _update_chassis_3d_state() -> void:
	if not _preview_mesh or not _current_device:
		return

	var state: String = str(_current_device.get_repair_state())
	var is_open_state: bool = (state == "DISASSEMBLED" or state == "PART_REPLACED")

	# Screen mesh for Phone / Tablet
	var screen: Node3D = _preview_mesh.get_node_or_null("ScreenMesh") as Node3D
	if screen:
		if is_open_state:
			screen.position = Vector3(0.0, 0.08, 0.04)
			screen.rotation.x = deg_to_rad(15.0)
		else:
			screen.position = Vector3(0.0, 0.02, 0.0)
			screen.rotation = Vector3.ZERO

	# Lid / Keyboard for Laptop
	var lid: Node3D = _preview_mesh.get_node_or_null("LidMesh") as Node3D
	var kb: Node3D = _preview_mesh.get_node_or_null("KeyboardMesh") as Node3D
	if lid:
		lid.rotation.x = deg_to_rad(-70.0) if is_open_state else deg_to_rad(-30.0)
	if kb:
		kb.position.y = 0.06 if is_open_state else 0.02

	# SidePanel for DesktopPC
	var side: Node3D = _preview_mesh.get_node_or_null("SidePanel") as Node3D
	if side:
		side.position.x = 0.22 if is_open_state else 0.11


func _process(delta: float) -> void:
	if not _is_open:
		return

	# Manual keyboard rotation controls (A/D, W/S, or Arrow Keys)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_target_rotation.y -= delta * 2.5
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_target_rotation.y += delta * 2.5

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_target_rotation.x = clampf(_target_rotation.x - delta * 2.0, -PI * 0.45, PI * 0.45)
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_target_rotation.x = clampf(_target_rotation.x + delta * 2.0, -PI * 0.45, PI * 0.45)

	# Smoothly interpolate rotation (inertia / damping)
	_current_rotation.x = lerp_angle(_current_rotation.x, _target_rotation.x, delta * 14.0)
	_current_rotation.y = lerp_angle(_current_rotation.y, _target_rotation.y, delta * 14.0)
	_current_rotation.z = lerp_angle(_current_rotation.z, _target_rotation.z, delta * 14.0)

	if model_root and is_instance_valid(model_root):
		model_root.rotation = _current_rotation

	# Smoothly interpolate camera zoom
	_current_cam_dist = lerpf(_current_cam_dist, _target_cam_dist, delta * 10.0)
	if inspection_camera and is_instance_valid(inspection_camera):
		inspection_camera.position.z = _current_cam_dist

	# Update 3D hotspot projection positions in 2D overlay
	_update_hotspot_positions()


## Projects 3D hotspot locations to 2D screen coordinates, aligning the arrow tip precisely
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

		# Surface normal dot product test: hide hotspots on back side facing away from camera
		if hs.target_normal != Vector3.ZERO:
			var to_cam: Vector3 = (inspection_camera.global_position - world_pos).normalized()
			var norm: Vector3 = (model_root.global_transform.basis * hs.target_normal).normalized()
			if norm.dot(to_cam) < -0.15:
				hs.visible = false
				continue

		var screen_2d: Vector2 = inspection_camera.unproject_position(world_pos)
		var arrow_offset_y: float = HotspotScript.BADGE_RADIUS * 2.0 + HotspotScript.ARROW_HEIGHT + 3.0
		hs.position = screen_2d - Vector2(hs.size.x * 0.5, arrow_offset_y)
		hs.visible = true


func _clear_hotspots() -> void:
	for hs in _active_hotspots:
		if is_instance_valid(hs):
			hs.queue_free()
	_active_hotspots.clear()
	_primary_hotspot = null


## Builds contextual 3D hotspot badges based on station, device type, and repair state
func _build_hotspots() -> void:
	_clear_hotspots()
	if not _current_device or not hotspot_overlay:
		return

	var state: String = str(_current_device.get_repair_state())
	var dev_name: String = _current_device.item_name.to_lower()
	var station_type: String = _current_station.station_type if _current_station else ""

	match state:
		"RECEIVED":
			# Diagnostic Bench Hotspot
			var scan_hs = HotspotScript.new(
				"diagnose",
				"Run Hardware Diagnostics",
				Vector3(0.0, 0.03, 0.0),
				Callable(self, "_trigger_diagnosis")
			)
			scan_hs.glyph = "🔍"
			_add_hotspot(scan_hs, true)

		"DIAGNOSED":
			# Defect indicator highlight
			if _current_device.assigned_fault:
				var defect_hs = HotspotScript.new(
					"defect_info",
					"Fault: %s" % _current_device.assigned_fault.fault_name,
					Vector3(0.0, 0.03, 0.0)
				)
				defect_hs.glyph = "⚠️"
				defect_hs.is_defect_highlight = true
				_add_hotspot(defect_hs, false)

			# Disassembly screw hotspots at 4 corners
			var screw_coords: Array[Vector3] = [
				Vector3(-0.09, 0.02, -0.12),
				Vector3(0.09, 0.02, -0.12),
				Vector3(-0.09, 0.02, 0.12),
				Vector3(0.09, 0.02, 0.12)
			]
			if dev_name.contains("laptop"):
				screw_coords = [
					Vector3(-0.16, 0.02, -0.10),
					Vector3(0.16, 0.02, -0.10),
					Vector3(-0.16, 0.02, 0.10),
					Vector3(0.16, 0.02, 0.10)
				]
			elif dev_name.contains("desktop"):
				screw_coords = [
					Vector3(0.11, 0.15, -0.15),
					Vector3(0.11, 0.15, 0.15),
					Vector3(0.11, -0.15, -0.15),
					Vector3(0.11, -0.15, 0.15)
				]

			var has_tool: bool = _check_tool_available()
			for i in range(screw_coords.size()):
				var pos := screw_coords[i]
				var hs = HotspotScript.new(
					"unscrew_%d" % i,
					"Unscrew Casing" if i == 0 else "",
					pos,
					Callable(self, "_trigger_disassembly")
				)
				hs.glyph = "🔧"
				hs.is_enabled = has_tool
				hs.disabled_reason = "Needs Screwdriver" if not has_tool else ""
				_add_hotspot(hs, i == 0)

		"DISASSEMBLED":
			# Component slots for missing replacement parts
			var missing: Array[ComponentData] = _current_device.get_missing_components()
			var carried_part: Carriable = _get_carried_part()

			if not missing.is_empty():
				for i in range(missing.size()):
					var comp := missing[i]
					if not comp:
						continue
					var slot_pos := _get_component_slot_pos(comp.component_id, i)
					var can_install: bool = false
					if carried_part != null:
						if _current_station and _current_station.has_method("_is_valid_replacement_part"):
							can_install = _current_station._is_valid_replacement_part(_current_device, carried_part)
						else:
							can_install = carried_part.item_name.to_lower().contains(comp.component_name.to_lower())

					var hs = HotspotScript.new(
						"install_%s" % comp.component_id,
						"Install %s" % comp.component_name,
						slot_pos,
						Callable(self, "_trigger_install_part").bind(comp)
					)
					hs.glyph = "📦"
					hs.is_enabled = can_install
					hs.disabled_reason = "Carrying %s" % carried_part.item_name if (carried_part and not can_install) else "Need part from shelf"
					_add_hotspot(hs, i == 0)

		"PART_REPLACED":
			# Reassembly screw hotspots
			var has_tool: bool = _check_tool_available()
			var hs = HotspotScript.new(
				"reassemble",
				"Fasten & Reassemble",
				Vector3(0.0, 0.03, 0.0),
				Callable(self, "_trigger_reassembly")
			)
			hs.glyph = "🔧"
			hs.is_enabled = has_tool
			hs.disabled_reason = "Needs Screwdriver" if not has_tool else ""
			_add_hotspot(hs, true)

		"REASSEMBLED":
			# Software Station Flash OS Hotspot
			var hs = HotspotScript.new(
				"flash_os",
				"Plug USB & Flash OS",
				Vector3(0.0, 0.02, 0.12),
				Callable(self, "_trigger_software_flash")
			)
			hs.glyph = "💻"
			_add_hotspot(hs, true)

		"TESTED":
			# Tested / Ready Hotspot
			var hs = HotspotScript.new(
				"tested_info",
				"Verified 100% — Ready for Delivery",
				Vector3(0.0, 0.03, 0.0)
			)
			hs.glyph = "✅"
			_add_hotspot(hs, false)

	_update_action_button()


func _add_hotspot(hs: Control, is_primary: bool = false) -> void:
	if not hs or not hotspot_overlay:
		return
	hotspot_overlay.add_child(hs)
	_active_hotspots.append(hs)
	if is_primary:
		_primary_hotspot = hs


func _get_component_slot_pos(comp_id: String, index: int) -> Vector3:
	var dev_name: String = _current_device.item_name.to_lower()
	if dev_name.contains("phone"):
		if comp_id.contains("screen"): return Vector3(0.0, 0.02, 0.05)
		if comp_id.contains("battery"): return Vector3(0.04, 0.01, -0.04)
	elif dev_name.contains("laptop"):
		if comp_id.contains("fan"): return Vector3(-0.11, 0.02, -0.04)
		if comp_id.contains("paste"): return Vector3(0.0, 0.02, -0.04)
		if comp_id.contains("ram"): return Vector3(0.10, 0.02, 0.0)
		if comp_id.contains("keyboard"): return Vector3(0.0, 0.03, 0.06)
	elif dev_name.contains("desktop"):
		if comp_id.contains("gpu"): return Vector3(0.0, 0.08, 0.05)
		if comp_id.contains("psu"): return Vector3(0.0, -0.14, -0.10)
		if comp_id.contains("ram"): return Vector3(0.0, 0.14, -0.02)
		if comp_id.contains("cooler") or comp_id.contains("paste"): return Vector3(0.0, 0.16, -0.10)

	# Default slot positions staggered
	var offsets: Array[Vector3] = [
		Vector3(-0.06, 0.02, -0.04),
		Vector3(0.06, 0.02, -0.04),
		Vector3(0.0, 0.02, 0.05)
	]
	return offsets[index % offsets.size()]


func _check_tool_available() -> bool:
	if _current_station and _current_station is WorkbenchStation:
		return (_current_station as WorkbenchStation)._has_required_tool(_owning_player)
	if _owning_player and _owning_player.carry_system and _owning_player.carry_system.is_carrying():
		var held: Carriable = _owning_player.carry_system.get_held_item()
		if held is ToolItem and (held as ToolItem).tool_id == "screwdriver":
			return true
	return false


func _get_carried_part() -> Carriable:
	if _owning_player and _owning_player.carry_system and _owning_player.carry_system.is_carrying():
		var held: Carriable = _owning_player.carry_system.get_held_item()
		if held and held.item_type == "part":
			return held
	return null


# =========================================================================
# ACTIONS (Work performed directly through this 3D puzzle panel)
# =========================================================================

func _trigger_diagnosis() -> void:
	if not _current_device:
		return

	_start_scan_anim(func() -> void:
		_current_device.diagnose()
		if _current_station:
			if _current_station.has_method("_complete_processing"):
				_current_station._complete_processing()
			elif _current_station.has_method("_on_processing_done"):
				_current_station._on_processing_done()
		action_performed.emit("diagnose")
		_refresh_all()
	, "🔍 RUNNING HARDWARE DIAGNOSTIC SCAN...")


func _trigger_disassembly() -> void:
	if not _current_device:
		return
	if not _check_tool_available():
		if tool_status_label:
			tool_status_label.text = "⚠️ Screwdriver required to disassemble!"
			tool_status_label.modulate = Color(1.0, 0.35, 0.3)
		return

	# Decrement tool durability if using workbench tool or carried tool
	_consume_tool_use()

	if _current_station and _current_station is WorkbenchStation:
		var wb := _current_station as WorkbenchStation
		wb.set_active_user(_owning_player)
		wb._start_disassembly()
		wb._complete_processing()
	else:
		_current_device.advance_repair_state()

	action_performed.emit("disassemble")
	_refresh_all()


func _trigger_install_part(comp: ComponentData) -> void:
	if not _current_device:
		return

	var carried := _get_carried_part()
	if not carried:
		return

	if _current_station and _current_station is WorkbenchStation:
		var wb := _current_station as WorkbenchStation
		wb._try_install_part(_owning_player)
	else:
		_current_device.install_component(comp)
		if _owning_player and _owning_player.carry_system:
			_owning_player.carry_system.drop_item()
			carried.queue_free()

	action_performed.emit("install_part")
	_refresh_all()


func _trigger_reassembly() -> void:
	if not _current_device:
		return
	if not _check_tool_available():
		return

	_consume_tool_use()

	if _current_station and _current_station is WorkbenchStation:
		var wb := _current_station as WorkbenchStation
		wb._try_reassemble(_owning_player)
		wb._complete_processing()
	else:
		_current_device.advance_repair_state()

	action_performed.emit("reassemble")
	_refresh_all()


func _trigger_software_flash() -> void:
	if not _current_device:
		return

	_start_scan_anim(func() -> void:
		if _current_device.has_method("install_software"):
			_current_device.install_software()
		else:
			_current_device.advance_repair_state()

		if _current_station:
			if _current_station.has_method("_complete_processing"):
				_current_station._complete_processing()
			elif _current_station.has_method("_on_processing_done"):
				_current_station._on_processing_done()

		action_performed.emit("flash_os")
		_refresh_all()
	, "⚡ INSTALLING OPERATING SYSTEM & DIAGNOSTICS...")


func _trigger_pick_up() -> void:
	if not _current_device or not _owning_player or not _owning_player.carry_system:
		close_panel()
		return

	if not _owning_player.carry_system.can_pick_up():
		return

	var dev: Device = _current_device
	if _current_station and _current_station.placed_device == dev:
		_current_station.remove_device()

	close_panel()
	_owning_player.carry_system.pick_up(dev)


func _consume_tool_use() -> void:
	if _owning_player and _owning_player.carry_system and _owning_player.carry_system.is_carrying():
		var held: Carriable = _owning_player.carry_system.get_held_item()
		if held is ToolItem:
			(held as ToolItem).use_tool()
			return
	if _current_station and _current_station is WorkbenchStation:
		var t: ToolItem = (_current_station as WorkbenchStation).get_bench_tool()
		if t:
			t.use_tool()


func _start_scan_anim(on_complete: Callable, label_text: String = "⚡ DIAGNOSTIC SCAN IN PROGRESS...") -> void:
	if _is_scanning:
		return
	_is_scanning = true
	if scan_effect_layer:
		scan_effect_layer.visible = true
	if scan_label:
		scan_label.text = label_text

	var tw := create_tween()
	if scan_line:
		scan_line.position.y = 0.0
		tw.tween_property(scan_line, "position:y", 480.0, 0.9).set_trans(Tween.TRANS_SINE)

	tw.finished.connect(func() -> void:
		_is_scanning = false
		if scan_effect_layer:
			scan_effect_layer.visible = false
		if on_complete.is_valid():
			on_complete.call()
	)


func _on_primary_action_pressed() -> void:
	if _primary_hotspot and is_instance_valid(_primary_hotspot):
		_primary_hotspot.trigger_action()


# =========================================================================
# DOSSIER & HUD UPDATES
# =========================================================================

func _populate_device_info() -> void:
	if not _current_device:
		return

	var tier_str: String = "TIER %d" % (_current_device.device_data.difficulty_tier if _current_device.device_data else 1)
	if device_title:
		device_title.text = "🔍 %s  •  %s" % [
			_current_device.item_name.to_upper(),
			tier_str
		]

	if state_badge:
		state_badge.text = "[ %s ]" % _current_device.get_repair_state()

	if station_badge:
		var st_name: String = _current_station.station_name.to_upper() if _current_station else "INSPECT"
		station_badge.text = "[ %s ]" % st_name

	if fault_name_label:
		if (_current_device.is_diagnosed or _current_device.current_repair_state != RepairState.State.RECEIVED) and _current_device.assigned_fault:
			fault_name_label.text = "FAULT: %s" % _current_device.assigned_fault.fault_name.to_upper()
			fault_name_label.modulate = Color(1.0, 0.4, 0.3)
		else:
			fault_name_label.text = "FAULT: UNKNOWN (NEEDS DIAGNOSIS)"
			fault_name_label.modulate = Color(0.7, 0.7, 0.7)

	if fault_desc_label:
		if (_current_device.is_diagnosed or _current_device.current_repair_state != RepairState.State.RECEIVED) and _current_device.assigned_fault:
			var desc: String = ""
			if "symptom_description" in _current_device.assigned_fault:
				desc = _current_device.assigned_fault.symptom_description
			elif "description" in _current_device.assigned_fault:
				desc = _current_device.assigned_fault.description
			if desc.is_empty():
				desc = "Hardware defect identified. Requires component replacement."
			fault_desc_label.text = "Symptoms: %s" % desc
		else:
			fault_desc_label.text = "Symptoms: Run Diagnostic Scan to analyze defective components."

	if parts_container:
		for child in parts_container.get_children():
			child.queue_free()

		if (_current_device.is_diagnosed or _current_device.current_repair_state != RepairState.State.RECEIVED) and _current_device.assigned_fault:
			var req: Array[ComponentData] = _current_device.assigned_fault.get_required_components()
			var missing: Array[ComponentData] = _current_device.get_missing_components()
			for comp in req:
				if comp:
					var is_installed: bool = not missing.any(func(m: ComponentData) -> bool: return m != null and m.component_id == comp.component_id)
					var p_lbl := Label.new()
					p_lbl.text = " %s  %s" % ["✓" if is_installed else "❌", comp.component_name]
					p_lbl.add_theme_font_size_override("font_size", 14)
					p_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4) if is_installed else Color(1.0, 0.45, 0.35))
					parts_container.add_child(p_lbl)
		else:
			var unk := Label.new()
			unk.text = "  ○ Components pending diagnostic analysis"
			unk.add_theme_font_size_override("font_size", 13)
			unk.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
			parts_container.add_child(unk)

	# Update tool status label
	if tool_status_label:
		var has_tool := _check_tool_available()
		if has_tool:
			tool_status_label.text = "🔧 Screwdriver: Ready ✓"
			tool_status_label.modulate = Color(0.4, 0.9, 0.5)
		else:
			tool_status_label.text = "⚠️ Screwdriver: Not present"
			tool_status_label.modulate = Color(0.9, 0.65, 0.3)


func _build_roadmap() -> void:
	if not roadmap_container or not _current_device:
		return

	for child in roadmap_container.get_children():
		child.queue_free()

	var states: Array[String] = [
		"RECEIVED", "DIAGNOSED", "DISASSEMBLED",
		"PART_REPLACED", "REASSEMBLED", "TESTED", "DELIVERED"
	]

	var active_states: Array[String] = []
	for st in states:
		if _current_device.assigned_fault and _current_device.assigned_fault.skip_states.has(st):
			continue
		active_states.append(st)

	var current: String = str(_current_device.get_repair_state())
	var current_idx: int = active_states.find(current)

	for i in range(active_states.size()):
		var st_name: String = active_states[i]
		var is_past: bool = (i < current_idx)
		var is_current: bool = (i == current_idx)

		var node := Label.new()
		var prefix := "✓ " if is_past else ("● " if is_current else "○ ")
		node.text = prefix + st_name.replace("_", " ").capitalize()
		node.add_theme_font_size_override("font_size", 13)

		if is_current:
			node.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		elif is_past:
			node.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		else:
			node.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))

		roadmap_container.add_child(node)

		if i < active_states.size() - 1:
			var arrow := Label.new()
			arrow.text = " → "
			arrow.add_theme_font_size_override("font_size", 12)
			arrow.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
			roadmap_container.add_child(arrow)


func _update_next_step() -> void:
	if next_step_label and _current_device:
		next_step_label.text = "💡 NEXT STEP: %s" % get_next_step_hint(_current_device)


func _update_action_button() -> void:
	if not primary_action_btn:
		return

	if _primary_hotspot and is_instance_valid(_primary_hotspot):
		primary_action_btn.visible = true
		primary_action_btn.text = "[E] %s" % _primary_hotspot.action_label.to_upper()
		primary_action_btn.disabled = not _primary_hotspot.is_enabled
	else:
		primary_action_btn.visible = false

	if pick_up_btn and _owning_player and _owning_player.carry_system:
		pick_up_btn.visible = _owning_player.carry_system.can_pick_up()


static func get_next_step_hint(device: Device) -> String:
	if not device:
		return ""
	var state: String = str(device.get_repair_state())
	match state:
		"RECEIVED":
			return "Take this device to the Diagnostic Bench to identify the fault."
		"DIAGNOSED":
			if device.assigned_fault and device.assigned_fault.skip_states.has("DISASSEMBLED"):
				return "This device needs software only. Take it to the Software Station."
			return "Take this device to a Workbench and disassemble it with a screwdriver."
		"DISASSEMBLED":
			var missing := device.get_missing_components()
			if missing.is_empty():
				return "All parts installed. Reassemble the device at the Workbench."
			var names: PackedStringArray = []
			for m in missing:
				if m:
					names.append(m.component_name)
			return "Get these parts from the Parts Shelf: %s" % ", ".join(names)
		"PART_REPLACED":
			return "Reassemble the device at the Workbench (needs screwdriver)."
		"REASSEMBLED":
			return "Take to the Software Station to reinstall OS and run diagnostic tests."
		"TESTED":
			return "Device is fully repaired and tested! Deliver it at the Delivery Counter."
		"DELIVERED":
			return "Device delivered. Great work!"
	return "Proceed with repair."


# =========================================================================
# INPUT CONTROLS
# =========================================================================

func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = mb.pressed
			if _is_dragging:
				_auto_rotate = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_cam_dist = clampf(_target_cam_dist - 0.08, 0.45, 1.8)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_cam_dist = clampf(_target_cam_dist + 0.08, 0.45, 1.8)
			accept_event()

	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_target_rotation.y += mm.relative.x * 0.012
		_target_rotation.x = clampf(_target_rotation.x + mm.relative.y * 0.012, -PI * 0.45, PI * 0.45)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	var player_idx: int = owning_player_index
	var cancel := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)
	var interact := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)

	if (
		event.is_action_pressed(cancel)
		or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_Q or event.keycode == KEY_TAB))
	):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(interact) or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_ENTER)):
		_on_primary_action_pressed()
		get_viewport().set_input_as_handled()
	elif player_idx == 0 and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_trigger_pick_up()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		# Reset 3D view
		_target_rotation = Vector3(-0.25, 0.45, 0.0)
		_target_cam_dist = 0.95
		_auto_rotate = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_gui_input(event)
