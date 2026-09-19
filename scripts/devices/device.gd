class_name Device
extends Carriable

## Runtime instance of a physical device being repaired in Overclocked.
## Tracks repair pipeline progression, assigned defects, installed components,
## and provides ground interaction and visual status feedback.

signal repair_state_changed(old_state: RepairState.State, new_state: RepairState.State)
signal diagnosed(fault: FaultData)
signal repair_completed

@export var device_data: DeviceData = null

var current_repair_state: RepairState.State = RepairState.State.RECEIVED
var assigned_fault: FaultData = null
var is_diagnosed: bool = false
var installed_components: Array[ComponentData] = []

## Backward-compatible accessor for single-component queries
var installed_component: ComponentData:
	get:
		return installed_components[0] if not installed_components.is_empty() else null
	set(value):
		if value == null:
			installed_components.clear()
		elif installed_components.is_empty():
			installed_components.append(value)
		else:
			installed_components[0] = value

# Co-op two-player carry state
var carry_request_active: bool = false
var carry_requester: PlayerCharacter = null
var carry_request_timer: float = 0.0
var co_carrier_b: PlayerCharacter = null

@onready var device_label: Label3D = get_node_or_null("DeviceLabel") as Label3D
@onready var device_mesh: MeshInstance3D = get_node_or_null("DeviceMesh") as MeshInstance3D


func _ready() -> void:
	add_to_group("devices")
	item_type = "device"
	if device_data:
		item_name = device_data.device_name
		if not assigned_fault and not device_data.possible_faults.is_empty():
			assigned_fault = device_data.possible_faults[0]

	_apply_device_color()
	_setup_interaction_zone()
	_update_label()


func _process(delta: float) -> void:
	if carry_request_active:
		carry_request_timer -= delta
		if carry_request_timer <= 0.0:
			carry_request_active = false
			if is_instance_valid(carry_requester) and carry_requester.carry_system and carry_requester.carry_system.can_pick_up():
				carry_requester.carry_system.pick_up_solo_heavy(self)
			carry_requester = null
			if interaction_zone:
				if device_data and device_data.carry_requires_two_players:
					interaction_zone.interaction_prompt = "Requires 2 players to carry!"
				else:
					interaction_zone.interaction_prompt = "Pick Up %s" % item_name

	# Update position between co-carriers during two-player carry
	if is_held and co_carrier_b and held_by and is_instance_valid(held_by) and is_instance_valid(co_carrier_b):
		global_position = (held_by.global_position + co_carrier_b.global_position) * 0.5 + Vector3(0, 1.0, 0)


## Configures device data and assigned fault at creation
func initialize(data: DeviceData, fault: FaultData = null) -> void:
	device_data = data
	item_name = data.device_name if data else "Device"
	item_type = "device"
	assigned_fault = fault if fault != null else (data.get_random_fault() if data else null)
	current_repair_state = RepairState.State.RECEIVED
	is_diagnosed = false
	installed_components.clear()
	carry_request_active = false
	carry_requester = null
	co_carrier_b = null
	_apply_device_color()
	_setup_interaction_zone()
	_update_label()


## Applies device_color from DeviceData to the root device mesh
func _apply_device_color() -> void:
	if not device_data or not device_mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = device_data.device_color
	device_mesh.material_override = mat


## Returns human-readable string of the current repair state
func get_repair_state() -> String:
	return RepairState.to_string_name(current_repair_state)


## Sets repair state from string representation
func set_repair_state(state_name: String) -> bool:
	var target_state: RepairState.State = RepairState.from_string_name(state_name)
	return advance_state(target_state)


## Validates and transitions device to a target repair state
func advance_state(new_state: RepairState.State) -> bool:
	var fault_skips: Array[String] = assigned_fault.skip_states if assigned_fault else []
	if not RepairState.can_transition(current_repair_state, new_state, fault_skips):
		push_warning(
			(
				"Device: Invalid repair transition %s -> %s"
				% [
					RepairState.to_string_name(current_repair_state),
					RepairState.to_string_name(new_state)
				]
			)
		)
		return false

	var old_state: RepairState.State = current_repair_state
	current_repair_state = new_state
	repair_state_changed.emit(old_state, new_state)
	_update_label()

	if new_state == RepairState.State.DELIVERED:
		repair_completed.emit()

	return true


## Advances device to the next sequential state defined in the state machine,
## automatically skipping states defined in the assigned fault's skip_states.
func advance_repair_state() -> bool:
	if current_repair_state in RepairState.TRANSITIONS:
		var next_states: Array = RepairState.TRANSITIONS[current_repair_state]
		if next_states.is_empty():
			return false
		var next: RepairState.State = next_states[0]

		# Skip states listed in fault's skip_states
		if assigned_fault and not assigned_fault.skip_states.is_empty():
			while RepairState.to_string_name(next) in assigned_fault.skip_states:
				if next in RepairState.TRANSITIONS and not RepairState.TRANSITIONS[next].is_empty():
					next = RepairState.TRANSITIONS[next][0]
				else:
					break

		return advance_state(next)
	return false


## Diagnoses device, revealing defect information
func diagnose() -> void:
	if current_repair_state == RepairState.State.RECEIVED:
		if advance_state(RepairState.State.DIAGNOSED):
			is_diagnosed = true
			diagnosed.emit(assigned_fault)
	else:
		is_diagnosed = true
		diagnosed.emit(assigned_fault)
	_update_label()


## Returns components still needed for this fault
func get_missing_components() -> Array[ComponentData]:
	if not assigned_fault:
		return []
	var required: Array[ComponentData] = assigned_fault.get_required_components()
	var installed_ids: Array[String] = []
	for c: ComponentData in installed_components:
		if c:
			installed_ids.append(c.component_id)
	var missing: Array[ComponentData] = []
	for c: ComponentData in required:
		if c and c.component_id not in installed_ids:
			missing.append(c)
	return missing


## Attempts to install a replacement component; returns true if accepted
func try_install_component(component: ComponentData) -> bool:
	if not component:
		return false
	if not assigned_fault:
		installed_components.append(component)
		return true

	var required: Array[ComponentData] = assigned_fault.get_required_components()
	var required_ids: Array[String] = []
	for c: ComponentData in required:
		if c:
			required_ids.append(c.component_id)

	# Check if this component is one we need
	if component.component_id not in required_ids:
		return false

	# Check if already installed
	for installed: ComponentData in installed_components:
		if installed and installed.component_id == component.component_id:
			return false  # Already have this one

	installed_components.append(component)
	var remaining: int = get_missing_components().size()
	SignalBus.multi_fault_component_installed.emit(item_name, component.component_name, remaining)
	if remaining == 0 and assigned_fault.is_multi_fault:
		SignalBus.multi_fault_complete.emit(item_name)
	_update_label()
	return true


## Installs replacement part and advances state to PART_REPLACED
func install_part() -> bool:
	if current_repair_state == RepairState.State.DISASSEMBLED:
		if assigned_fault and assigned_fault.is_multi_fault:
			var missing: Array[ComponentData] = get_missing_components()
			if not missing.is_empty():
				return false
		return advance_state(RepairState.State.PART_REPLACED)
	return false


## Flashes software and transitions through testing
func install_software() -> bool:
	if current_repair_state == RepairState.State.REASSEMBLED:
		if advance_state(RepairState.State.SOFTWARE_INSTALLED):
			return advance_state(RepairState.State.TESTED)
	elif current_repair_state == RepairState.State.DIAGNOSED and assigned_fault and assigned_fault.skip_states.has("DISASSEMBLED"):
		if advance_state(RepairState.State.SOFTWARE_INSTALLED):
			return advance_state(RepairState.State.TESTED)
	elif current_repair_state == RepairState.State.SOFTWARE_INSTALLED:
		return advance_state(RepairState.State.TESTED)
	return false


## Completes testing step
func test_device() -> bool:
	if current_repair_state == RepairState.State.SOFTWARE_INSTALLED:
		return advance_state(RepairState.State.TESTED)
	return false


## Delivers device to customer
func deliver() -> bool:
	if current_repair_state == RepairState.State.TESTED:
		return advance_state(RepairState.State.DELIVERED)
	return false


## Returns whether this device requires the software station
func needs_software() -> bool:
	if device_data and device_data.requires_software:
		return true
	if assigned_fault and assigned_fault.requires_software_reinstall:
		return true
	return false


## Overrides Carriable.pick_up to disable ground interaction zone
func pick_up(player: PlayerCharacter) -> void:
	super.pick_up(player)
	visible = true
	if device_mesh:
		device_mesh.visible = true
	if device_label:
		device_label.visible = true
	if interaction_zone:
		interaction_zone.is_interactable = false


## Overrides Carriable.drop to enable ground interaction zone
func drop(drop_position: Vector3) -> void:
	super.drop(drop_position)
	visible = true
	co_carrier_b = null
	carry_request_active = false
	carry_requester = null
	if device_mesh:
		device_mesh.visible = true
	if device_label:
		device_label.visible = true
	if interaction_zone:
		interaction_zone.is_interactable = true
		if device_data and device_data.carry_requires_two_players:
			interaction_zone.interaction_prompt = "Requires 2 players to carry!"
		else:
			interaction_zone.interaction_prompt = "Pick Up %s" % item_name


## Overrides Carriable.place_on to disable ground interaction zone
func place_on(station: Node) -> void:
	super.place_on(station)
	visible = true
	co_carrier_b = null
	carry_request_active = false
	carry_requester = null
	if device_mesh:
		device_mesh.visible = true
	if device_label:
		device_label.visible = true
	if interaction_zone:
		interaction_zone.is_interactable = false


func _setup_interaction_zone() -> void:
	if not interaction_zone:
		interaction_zone = get_node_or_null("InteractionZone") as Interactable
	if not interaction_zone:
		return

	if device_data and device_data.carry_requires_two_players:
		interaction_zone.interaction_prompt = "Requires 2 players to carry!"
	else:
		interaction_zone.interaction_prompt = "Pick Up %s" % item_name

	interaction_zone.is_interactable = not is_held
	interaction_zone.can_interact_handler = func(p: PlayerCharacter) -> bool:
		return not is_held and can_claim(p) and (p == null or p.carry_system == null or p.carry_system.can_pick_up())

	if not interaction_zone.interacted.is_connected(_on_interaction_zone_interacted):
		interaction_zone.interacted.connect(_on_interaction_zone_interacted)


func _on_interaction_zone_interacted(player: PlayerCharacter) -> void:
	if not is_held and player and player.carry_system and player.carry_system.can_pick_up():
		player.carry_system.pick_up(self)


func _update_label() -> void:
	if not device_label:
		return

	var text_str := "%s\n[%s]" % [item_name, get_repair_state()]
	if is_diagnosed and assigned_fault:
		text_str += "\n(%s)" % assigned_fault.fault_name
		if assigned_fault.is_multi_fault:
			var required: Array[ComponentData] = assigned_fault.get_required_components()
			var missing: Array[ComponentData] = get_missing_components()
			var tags: PackedStringArray = []
			for comp in required:
				if comp:
					var is_installed: bool = not missing.any(func(m: ComponentData) -> bool: return m != null and m.component_id == comp.component_id)
					tags.append("%s%s" % ["✓" if is_installed else "○", comp.component_name])
			if not tags.is_empty():
				text_str += "\n[%s]" % " ".join(tags)
	device_label.text = text_str
