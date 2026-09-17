class_name BaseStation
extends StaticBody3D

## Base class for all workshop stations in Overclocked.
## Handles device acceptance, processing state, visual feedback, and interaction hooks.

signal device_accepted(device: Carriable)
signal device_removed(device: Carriable)
signal processing_started(device: Carriable)
signal processing_completed(device: Carriable)
signal station_state_changed(old_state: StationState, new_state: StationState)

enum StationState {
	IDLE,
	OCCUPIED,
	PROCESSING,
	COMPLETE,
}

@export var station_name: String = "Station"
@export var station_type: String = "generic"
@export var processing_time: float = 2.0
@export var accepted_device_states: Array[String] = []

var current_state: StationState = StationState.IDLE:
	set(value):
		if current_state != value:
			var old_state := current_state
			current_state = value
			_on_state_changed(old_state, current_state)
			station_state_changed.emit(old_state, current_state)

var placed_device: Carriable = null
var _processing_timer: float = 0.0
var _is_processing: bool = false
var _station_material: StandardMaterial3D = null

@onready var device_slot: Marker3D = get_node_or_null("DeviceSlot") as Marker3D
@onready var interaction_zone: Interactable = get_node_or_null("InteractionZone") as Interactable
@onready var station_label: Label3D = get_node_or_null("StationLabel") as Label3D
@onready var progress_indicator: Node3D = get_node_or_null("ProgressIndicator") as Node3D
@onready var progress_label: Label3D = (
	get_node_or_null("ProgressIndicator/ProgressLabel") as Label3D
	if has_node("ProgressIndicator/ProgressLabel")
	else null
)
@onready var station_mesh: Node3D = get_node_or_null("StationMesh") as Node3D


func _ready() -> void:
	collision_layer = Constants.COLLISION_MASK_STATIONS
	collision_mask = 0

	if interaction_zone:
		interaction_zone.interacted.connect(_on_interacted)
		interaction_zone.focus_gained.connect(_on_focus_gained)
		interaction_zone.focus_lost.connect(_on_focus_lost)

	if station_label:
		station_label.text = station_name.to_upper()

	_setup_station_material()
	_update_visual_state()


func _physics_process(delta: float) -> void:
	if _is_processing:
		_processing_timer += delta
		_update_progress_indicator()
		_apply_processing_wobble()
		if _processing_timer >= processing_time:
			_complete_processing()


func can_accept_device(device: Carriable) -> bool:
	return current_state == StationState.IDLE and device != null


func accept_device(device: Carriable) -> void:
	if not device:
		return

	placed_device = device
	current_state = StationState.OCCUPIED

	if device.get_parent():
		device.get_parent().remove_child(device)

	if device_slot:
		device_slot.add_child(device)
		device.position = Vector3.ZERO
		device.rotation = Vector3.ZERO
	else:
		add_child(device)
		device.position = Vector3(0.0, 0.9, 0.0)

	_update_visual_state()
	device_accepted.emit(device)


func remove_device() -> Carriable:
	var device: Carriable = placed_device
	_reset_processing_wobble()
	placed_device = null
	_is_processing = false
	_processing_timer = 0.0
	current_state = StationState.IDLE

	if device and device_slot and device.get_parent() == device_slot:
		device_slot.remove_child(device)
	elif device and device.get_parent() == self:
		remove_child(device)

	if device:
		device.position = Vector3.ZERO
		device.rotation = Vector3.ZERO

	_update_visual_state()
	device_removed.emit(device)
	return device


func start_processing() -> void:
	if placed_device and current_state == StationState.OCCUPIED:
		_is_processing = true
		_processing_timer = 0.0
		current_state = StationState.PROCESSING
		_update_visual_state()
		processing_started.emit(placed_device)


func _complete_processing() -> void:
	_is_processing = false
	_reset_processing_wobble()
	current_state = StationState.COMPLETE
	_update_visual_state()
	_on_processing_done()
	processing_completed.emit(placed_device)


func _apply_processing_wobble() -> void:
	if placed_device and is_instance_valid(placed_device):
		var wobble_y: float = sin(_processing_timer * 18.0) * 0.015
		placed_device.position.y = wobble_y


func _reset_processing_wobble() -> void:
	if placed_device and is_instance_valid(placed_device):
		placed_device.position = Vector3.ZERO
		placed_device.rotation = Vector3.ZERO


func get_progress() -> float:
	if processing_time <= 0.0:
		return 1.0
	return clampf(_processing_timer / processing_time, 0.0, 1.0)


## Override in subclasses to determine if a player can interact with the station
func can_player_interact(_player: PlayerCharacter) -> bool:
	return true


## Override in subclasses to return HUD interaction prompt
func get_interaction_prompt(_player: PlayerCharacter) -> String:
	return "Interact with %s" % station_name


## Override in subclasses to apply station-specific effects to the device upon processing completion
func _on_processing_done() -> void:
	pass


## Override in subclasses to define station interaction response
func _on_interacted(player: PlayerCharacter) -> void:
	SignalBus.station_interacted.emit(station_name, player.player_index if player else 0)


func _on_focus_gained(_player: PlayerCharacter) -> void:
	_set_highlight(true)


func _on_focus_lost(_player: PlayerCharacter) -> void:
	_set_highlight(false)


func _on_state_changed(_old_state: StationState, _new_state: StationState) -> void:
	_update_visual_state()


func _setup_station_material() -> void:
	if not station_mesh:
		return
	var mesh_inst: MeshInstance3D = station_mesh.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst:
		return

	var source_mat: Material = mesh_inst.material_override
	if not source_mat:
		source_mat = mesh_inst.get_surface_override_material(0)
	if not source_mat and mesh_inst.mesh:
		source_mat = mesh_inst.mesh.material

	if source_mat is StandardMaterial3D:
		_station_material = source_mat.duplicate() as StandardMaterial3D
		mesh_inst.material_override = _station_material


func _set_highlight(highlighted: bool) -> void:
	if _station_material:
		_station_material.emission_enabled = highlighted
		if highlighted:
			_station_material.emission = Color(0.2, 0.25, 0.3)


func _update_visual_state() -> void:
	_update_progress_indicator()


func _update_progress_indicator() -> void:
	if not progress_label:
		return

	match current_state:
		StationState.IDLE:
			progress_label.text = ""
			progress_label.visible = false
		StationState.OCCUPIED:
			progress_label.text = ""
			progress_label.visible = false
		StationState.PROCESSING:
			progress_label.visible = true
			var pct: int = int(get_progress() * 100.0)
			var total_bars: int = 8
			var filled_bars: int = int(round(get_progress() * total_bars))
			var bar_str: String = ""
			for i in range(total_bars):
				bar_str += "■" if i < filled_bars else "□"
			progress_label.text = "%s %d%%" % [bar_str, pct]
			progress_label.modulate = Color(1.0, 0.85, 0.2)
		StationState.COMPLETE:
			progress_label.visible = true
			progress_label.text = "✓ READY"
			progress_label.modulate = Color(0.2, 0.9, 0.3)
