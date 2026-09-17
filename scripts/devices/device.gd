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
var installed_component: ComponentData = null

@onready var device_label: Label3D = get_node_or_null("DeviceLabel") as Label3D
@onready var device_mesh: MeshInstance3D = get_node_or_null("DeviceMesh") as MeshInstance3D
@onready var interaction_zone: Interactable = get_node_or_null("InteractionZone") as Interactable


func _ready() -> void:
	item_type = "device"
	if device_data:
		item_name = device_data.device_name
		if not assigned_fault and not device_data.possible_faults.is_empty():
			assigned_fault = device_data.possible_faults[0]

	_setup_interaction_zone()
	_update_label()


## Configures device data and assigned fault at creation
func initialize(data: DeviceData, fault: FaultData = null) -> void:
	device_data = data
	item_name = data.device_name if data else "Device"
	item_type = "device"
	assigned_fault = fault if fault != null else (data.get_random_fault() if data else null)
	current_repair_state = RepairState.State.RECEIVED
	is_diagnosed = false
	installed_component = null
	_update_label()


## Returns human-readable string of the current repair state
func get_repair_state() -> String:
	return RepairState.to_string_name(current_repair_state)


## Sets repair state from string representation
func set_repair_state(state_name: String) -> bool:
	var target_state: RepairState.State = RepairState.from_string_name(state_name)
	return advance_state(target_state)


## Validates and transitions device to a target repair state
func advance_state(new_state: RepairState.State) -> bool:
	if not RepairState.can_transition(current_repair_state, new_state):
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


## Advances device to the next sequential state defined in the state machine
func advance_repair_state() -> bool:
	if current_repair_state in RepairState.TRANSITIONS:
		var next_states: Array = RepairState.TRANSITIONS[current_repair_state]
		if not next_states.is_empty():
			return advance_state(next_states[0])
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


## Attempts to install a replacement component
func try_install_component(component: ComponentData) -> bool:
	if not component:
		return false
	if not assigned_fault or not assigned_fault.broken_component:
		installed_component = component
		return true

	if component.component_id == assigned_fault.broken_component.component_id:
		installed_component = component
		return true

	return false


## Installs replacement part and advances state to PART_REPLACED
func install_part() -> bool:
	if current_repair_state == RepairState.State.DISASSEMBLED:
		return advance_state(RepairState.State.PART_REPLACED)
	return false


## Flashes software and transitions through testing
func install_software() -> bool:
	if current_repair_state == RepairState.State.REASSEMBLED:
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
	if interaction_zone:
		interaction_zone.is_interactable = false


## Overrides Carriable.drop to enable ground interaction zone
func drop(drop_position: Vector3) -> void:
	super.drop(drop_position)
	if interaction_zone:
		interaction_zone.is_interactable = true


## Overrides Carriable.place_on to disable ground interaction zone
func place_on(station: Node) -> void:
	super.place_on(station)
	if interaction_zone:
		interaction_zone.is_interactable = false


func _setup_interaction_zone() -> void:
	if not interaction_zone:
		return

	interaction_zone.interaction_prompt = "Pick Up %s" % item_name
	interaction_zone.is_interactable = not is_held

	# Connect interaction to pick up if player interacts while on the ground
	interaction_zone.interacted.connect(
		func(player: PlayerCharacter) -> void:
			if not is_held and player and player.carry_system and player.carry_system.can_pick_up():
				player.carry_system.pick_up(self)
	)


func _update_label() -> void:
	if not device_label:
		return

	var text_str := "%s\n[%s]" % [item_name, get_repair_state()]
	if is_diagnosed and assigned_fault:
		text_str += "\n(%s)" % assigned_fault.fault_name
	device_label.text = text_str
