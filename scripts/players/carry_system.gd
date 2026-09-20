class_name CarrySystem
extends Node

## Attached to PlayerCharacter. Manages picking up, holding, dropping,
## and placing one Carriable item at a time.
## Handles heavy solo carry and two-player cooperative carry for Phase 4.

signal item_picked(item: Carriable)
signal item_dropped(item: Carriable)
signal item_placed(item: Carriable, station: Node)
signal carry_state_changed(old_state: CarryState, new_state: CarryState)

enum CarryState {
	IDLE,
	CARRYING,
	CARRY_REQUESTED,
	CO_CARRYING,
}

var current_carry_state: CarryState = CarryState.IDLE:
	set(value):
		if current_carry_state != value:
			var old_state := current_carry_state
			current_carry_state = value
			carry_state_changed.emit(old_state, current_carry_state)

var held_item: Carriable = null
var is_co_carrying: bool = false
var co_carry_partner: PlayerCharacter = null
var active_carry_request_device: Device = null

@onready var player: PlayerCharacter = get_parent() as PlayerCharacter
@onready var carry_position: Marker3D = (
	player.get_node_or_null("CarryPosition") as Marker3D if player else null
)


func _ready() -> void:
	if not carry_position and player:
		carry_position = player.get_node_or_null("CarryPosition") as Marker3D


func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return

	var player_idx: int = player.player_index
	var drop_action := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)
	var is_drop: bool = (
		event.is_action_pressed(drop_action)
		or (player_idx == 0 and event is InputEventAction and event.action == &"drop")
	)

	if is_drop:
		if current_carry_state == CarryState.CARRY_REQUESTED:
			cancel_two_player_carry_request()
			get_viewport().set_input_as_handled()
		elif is_carrying():
			drop_item()
			get_viewport().set_input_as_handled()


func is_carrying() -> bool:
	return held_item != null


func is_carry_requested() -> bool:
	return current_carry_state == CarryState.CARRY_REQUESTED


func is_solo_heavy_carrying() -> bool:
	if is_carrying() and not is_co_carrying:
		if held_item is Device:
			var dev := held_item as Device
			return dev.device_data != null and dev.device_data.carry_requires_two_players
	return false


func get_held_item() -> Carriable:
	return held_item


func can_pick_up() -> bool:
	return held_item == null and current_carry_state != CarryState.CARRY_REQUESTED


func pick_up(item: Carriable) -> void:
	if not can_pick_up():
		push_warning("CarrySystem: Already carrying an item!")
		return

	if not is_instance_valid(item):
		return

	# Handle heavy devices requiring two players
	if item is Device:
		var dev := item as Device
		if dev.device_data and dev.device_data.carry_requires_two_players:
			var players: Array[Node] = []
			if player and player.is_inside_tree():
				for p in player.get_tree().get_nodes_in_group("players"):
					if is_instance_valid(p) and not p.is_queued_for_deletion():
						players.append(p)

			# Single-player fallback: carry alone at 40% speed
			if players.size() <= 1:
				pick_up_solo_heavy(dev)
				return

			# Multiplayer: First player requests co-carry
			if not dev.carry_request_active:
				request_two_player_carry(dev)
				return
			# Second player joins the carry request
			elif dev.carry_requester != player and is_instance_valid(dev.carry_requester):
				_start_two_player_carry(dev, dev.carry_requester, player)
				return

	_perform_standard_pickup(item)


## Initiates a cooperative two-player carry request with 3-second timeout
func request_two_player_carry(dev: Device) -> bool:
	if not can_pick_up() or not is_instance_valid(dev):
		return false

	active_carry_request_device = dev
	dev.carry_request_active = true
	dev.carry_requester = player
	dev.carry_request_timer = Constants.TWO_PLAYER_CARRY_REQUEST_TIMEOUT
	current_carry_state = CarryState.CARRY_REQUESTED
	var p_idx: int = player.player_index if player else 0
	SignalBus.device_carry_requested.emit(dev.item_name, p_idx)
	if dev.interaction_zone:
		dev.interaction_zone.interaction_prompt = "Help carry %s!" % dev.item_name
	dev._update_label()
	return true


## Cancels an active two-player carry request
func cancel_two_player_carry_request(dev: Device = null) -> void:
	var target_dev: Device = dev if dev != null else active_carry_request_device
	active_carry_request_device = null
	if current_carry_state == CarryState.CARRY_REQUESTED:
		current_carry_state = CarryState.IDLE
	if target_dev and is_instance_valid(target_dev):
		target_dev.carry_request_active = false
		target_dev.carry_requester = null
		if target_dev.interaction_zone:
			if target_dev.device_data and target_dev.device_data.carry_requires_two_players:
				target_dev.interaction_zone.interaction_prompt = "Requires 2 players to carry!"
			else:
				target_dev.interaction_zone.interaction_prompt = "Pick Up %s" % target_dev.item_name
		target_dev._update_label()


## Executes single-player heavy carry with reduced movement speed
func pick_up_solo_heavy(item: Device) -> void:
	if not can_pick_up() or not is_instance_valid(item):
		return
	active_carry_request_device = null
	_perform_standard_pickup(item)
	current_carry_state = CarryState.CARRYING
	if player:
		player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.ONE_PLAYER_HEAVY_CARRY_SPEED


## Starts cooperative two-player carry
func _start_two_player_carry(dev: Device, p_a: PlayerCharacter, p_b: PlayerCharacter) -> void:
	dev.carry_request_active = false
	dev.carry_requester = null

	# Set speeds to 60%
	p_a.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER
	p_b.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER

	if p_a.carry_system:
		p_a.carry_system.held_item = dev
		p_a.carry_system.is_co_carrying = true
		p_a.carry_system.co_carry_partner = p_b
		p_a.carry_system.active_carry_request_device = null
		p_a.carry_system.current_carry_state = CarryState.CO_CARRYING
	if p_b.carry_system:
		p_b.carry_system.held_item = dev
		p_b.carry_system.is_co_carrying = true
		p_b.carry_system.co_carry_partner = p_a
		p_b.carry_system.active_carry_request_device = null
		p_b.carry_system.current_carry_state = CarryState.CO_CARRYING

	dev.is_held = true
	dev.held_by = p_a
	dev.co_carrier_b = p_b
	dev.release_claim()
	if dev.interaction_zone:
		dev.interaction_zone.is_interactable = false

	# Position device midway between the two players
	dev.global_position = (p_a.global_position + p_b.global_position) * 0.5 + Vector3(0, 1.0, 0)

	SignalBus.device_carry_started.emit(dev.item_name, p_a.player_index, p_b.player_index)
	p_a.carry_system.item_picked.emit(dev)
	p_b.carry_system.item_picked.emit(dev)


func _perform_standard_pickup(item: Carriable) -> void:
	# Claim check — prevent two players grabbing simultaneously
	if not item.try_claim(player):
		return

	# Check if this grab was contested by another player
	var was_contested: bool = item.is_contested_by_other_players(player)
	if was_contested:
		var flash_color: Color = player.get_player_color() if player else Color.WHITE
		item.trigger_claim_flash(flash_color)

	held_item = item
	current_carry_state = CarryState.CARRYING
	active_carry_request_device = null
	item.visible = true
	item.pick_up(player)

	# Reparent item to carry position for visual attachment
	if item.get_parent():
		item.get_parent().remove_child(item)

	if carry_position:
		carry_position.add_child(item)
		item.position = Vector3.ZERO
		item.rotation = Vector3.ZERO
	elif player:
		player.add_child(item)
		item.position = Vector3(0, 2.05, 0)

	item_picked.emit(item)
	var player_idx: int = player.player_index if player else 0
	SignalBus.item_picked_up.emit(item.item_name, player_idx)
	if SignalBus.has_signal("item_claimed"):
		SignalBus.item_claimed.emit(item.item_name, player_idx, was_contested)


func drop_item() -> void:
	if not held_item:
		return

	var item: Carriable = held_item
	held_item = null
	current_carry_state = CarryState.IDLE
	active_carry_request_device = null

	# Reset player speed
	if player:
		player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED

	# If this was a co-op carry, clean up partner as well
	if is_co_carrying and is_instance_valid(co_carry_partner):
		var partner: PlayerCharacter = co_carry_partner
		is_co_carrying = false
		co_carry_partner = null
		if partner.carry_system:
			partner.carry_system.held_item = null
			partner.carry_system.is_co_carrying = false
			partner.carry_system.co_carry_partner = null
			partner.carry_system.active_carry_request_device = null
			partner.carry_system.current_carry_state = CarryState.IDLE
		partner.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED

	var drop_pos: Vector3 = _calculate_drop_position()

	if item.get_parent():
		item.get_parent().remove_child(item)

	# Add back to workshop/level container
	if player and player.get_parent():
		player.get_parent().add_child(item)
	elif player:
		player.add_sibling(item)

	item.drop(drop_pos)

	item_dropped.emit(item)
	var player_idx: int = player.player_index if player else 0
	SignalBus.item_dropped.emit(item.item_name, player_idx)


func place_on_station(station: Node) -> void:
	if not held_item:
		return

	var item: Carriable = held_item
	held_item = null
	current_carry_state = CarryState.IDLE
	active_carry_request_device = null

	# Reset player speed
	if player:
		player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED

	# If this was a co-op carry, clean up partner as well
	if is_co_carrying and is_instance_valid(co_carry_partner):
		var partner: PlayerCharacter = co_carry_partner
		is_co_carrying = false
		co_carry_partner = null
		if partner.carry_system:
			partner.carry_system.held_item = null
			partner.carry_system.is_co_carrying = false
			partner.carry_system.co_carry_partner = null
			partner.carry_system.active_carry_request_device = null
			partner.carry_system.current_carry_state = CarryState.IDLE
		partner.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED

	if item.get_parent():
		item.get_parent().remove_child(item)

	item.visible = true
	item.place_on(station)
	item_placed.emit(item, station)


func _calculate_drop_position() -> Vector3:
	if not player:
		return Vector3.ZERO
	var forward: Vector3 = player.get_facing_direction()
	return player.global_position + forward * 0.8
