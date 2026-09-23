class_name BaseStation
extends StaticBody3D

## Base class for all workshop stations in Overclocked.
## Handles device acceptance, processing state, visual feedback, and interaction hooks.

signal device_accepted(device: Carriable)
signal device_removed(device: Carriable)
signal processing_started(device: Carriable)
signal processing_completed(device: Carriable)
signal station_state_changed(old_state: StationState, new_state: StationState)
signal user_changed(old_user: PlayerCharacter, new_user: PlayerCharacter)

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
var _is_rushing: bool = false
var _station_material: StandardMaterial3D = null
var _active_user: PlayerCharacter = null
var _focusing_players: Array[PlayerCharacter] = []


func is_rushing() -> bool:
	return _is_rushing

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
	add_to_group("stations")
	collision_layer = Constants.COLLISION_MASK_STATIONS
	collision_mask = 0

	if interaction_zone:
		interaction_zone.interaction_type = "instant"
		interaction_zone.interacted.connect(_on_interacted)
		interaction_zone.focus_gained.connect(_on_focus_gained)
		interaction_zone.focus_lost.connect(_on_focus_lost)

	if station_label:
		station_label.text = station_name.to_upper()

	_setup_station_material()
	_update_visual_state()


var _world_label: WorldLabel = null


func get_world_label() -> WorldLabel:
	return _world_label


func setup_world_label() -> WorldLabel:
	if not _world_label:
		_world_label = WorldLabel.new()
		_world_label.target_node = self
		_world_label.world_offset = Vector3(0, 1.8, 0)
		_world_label.set_station_style(station_type)
		_world_label.set_text(station_name.to_upper())
	return _world_label


func _physics_process(delta: float) -> void:
	if _is_processing:
		_is_rushing = false
		if _active_user and is_instance_valid(_active_user):
			var pid: int = _active_user.player_index
			var rush_action := MultiplayerInput.action_name(pid, "rush")
			if Input.is_action_pressed(rush_action) or Input.is_action_pressed(&"rush"):
				_is_rushing = true

		var speed_mult: float = (1.0 / Constants.RUSH_SPEED_BONUS) if _is_rushing else 1.0
		_processing_timer += delta * speed_mult
		_update_progress_indicator()
		_apply_processing_wobble()

		if _processing_timer >= processing_time:
			if _is_rushing and randf() < Constants.RUSH_FAILURE_CHANCE:
				# Fumbled!
				_processing_timer = maxf(0.0, processing_time - Constants.RUSH_FAILURE_PENALTY)
				SignalBus.repair_fumbled.emit(station_name)
				SignalBus.repair_rushed.emit(station_name, false)
				return

			if _is_rushing:
				SignalBus.repair_rushed.emit(station_name, true)
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

	device.visible = true
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
	clear_active_user()

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


func open_examination_workstation(player: PlayerCharacter) -> void:
	if not player or not is_inside_tree():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_examination_panel"):
		var dev: Device = placed_device as Device if placed_device is Device else null
		if not dev and player.carry_system and player.carry_system.is_carrying():
			var held: Carriable = player.carry_system.get_held_item()
			if held is Device:
				dev = held as Device
		if dev:
			hud.open_examination_panel(player, dev, self)


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
	if _active_user != null and not _focusing_players.has(_active_user):
		clear_active_user()


func _apply_processing_wobble() -> void:
	if placed_device and is_instance_valid(placed_device):
		var base_y: float = 0.0 if (device_slot and placed_device.get_parent() == device_slot) else 0.9
		var wobble_y: float = sin(_processing_timer * 18.0) * 0.015
		placed_device.position.y = base_y + wobble_y


func _reset_processing_wobble() -> void:
	if placed_device and is_instance_valid(placed_device):
		var base_y: float = 0.0 if (device_slot and placed_device.get_parent() == device_slot) else 0.9
		placed_device.position = Vector3(0.0, base_y, 0.0)
		placed_device.rotation = Vector3.ZERO


func get_progress() -> float:
	if processing_time <= 0.0:
		return 1.0
	return clampf(_processing_timer / processing_time, 0.0, 1.0)


## Call when a player starts using this station
func set_active_user(player: PlayerCharacter) -> void:
	if _active_user != player:
		var old_user := _active_user
		_active_user = player
		user_changed.emit(old_user, _active_user)
		var pid: int = player.player_index if player else 0
		SignalBus.station_occupied.emit(station_name, pid)
		_update_visual_state()


## Call when a player stops using this station (walks away, picks up device)
func clear_active_user(player: PlayerCharacter = null) -> void:
	if player == null or _active_user == player:
		if _active_user != null:
			var old_user := _active_user
			_active_user = null
			user_changed.emit(old_user, null)
			SignalBus.station_released.emit(station_name)
			SignalBus.station_freed.emit(station_name)
			_update_visual_state()


func get_active_user() -> PlayerCharacter:
	return _active_user


func is_occupied() -> bool:
	return _active_user != null and is_instance_valid(_active_user)


## Override in subclasses to determine if a player can interact with the station
func can_player_interact(player: PlayerCharacter) -> bool:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return false
	return true


## Override in subclasses to return HUD interaction prompt
func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)
	return "Interact with %s" % station_name


## Override in subclasses to apply station-specific effects to the device upon processing completion
func _on_processing_done() -> void:
	pass


## Override in subclasses to define station interaction response
func _on_interacted(player: PlayerCharacter) -> void:
	SignalBus.station_interacted.emit(station_name, player.player_index if player else 0)


func _on_focus_gained(player: PlayerCharacter) -> void:
	if player and not _focusing_players.has(player):
		_focusing_players.append(player)
	_set_highlight(true)


func _on_focus_lost(player: PlayerCharacter) -> void:
	if player:
		_focusing_players.erase(player)
	_set_highlight(not _focusing_players.is_empty())
	if _active_user == player and not _is_processing:
		clear_active_user(player)


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
	if not _station_material:
		return
	if is_occupied() and _active_user:
		_station_material.emission_enabled = true
		var color_idx: int = _active_user.player_index % Constants.PLAYER_COLORS.size()
		_station_material.emission = Constants.PLAYER_COLORS[color_idx] * 0.6
	elif highlighted or not _focusing_players.is_empty():
		_station_material.emission_enabled = true
		_station_material.emission = Color(0.2, 0.25, 0.3)
	else:
		_station_material.emission_enabled = false


func _exit_tree() -> void:
	if _world_label and is_instance_valid(_world_label):
		_world_label.queue_free()
		_world_label = null


func _update_visual_state() -> void:
	_update_progress_indicator()
	_set_highlight(not _focusing_players.is_empty())
	if _world_label and is_instance_valid(_world_label):
		match current_state:
			StationState.PROCESSING:
				_world_label.set_text("%s (%d%%)" % [station_name.to_upper(), int(get_progress() * 100.0)])
			StationState.COMPLETE:
				_world_label.set_text("%s [READY]" % station_name.to_upper())
			_:
				if placed_device and is_instance_valid(placed_device):
					if placed_device.has_method("get_repair_state"):
						_world_label.set_text("%s [%s]" % [station_name.to_upper(), placed_device.get_repair_state()])
					else:
						_world_label.set_text("%s [%s]" % [station_name.to_upper(), placed_device.item_name])
				else:
					_world_label.set_text(station_name.to_upper())


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
