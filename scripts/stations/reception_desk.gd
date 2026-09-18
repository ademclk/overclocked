class_name ReceptionDesk
extends BaseStation

## Reception desk station where customers drop off devices and players pick them up.
## Player cannot place devices on the reception desk; they take incoming devices from here.


var _incoming_queue: Array[Carriable] = []


func _ready() -> void:
	station_name = "Reception Desk"
	station_type = "reception"
	super._ready()


func can_accept_device(_device: Carriable) -> bool:
	return false


func can_player_interact(player: PlayerCharacter) -> bool:
	return (
		placed_device != null
		and placed_device.can_claim(player)
		and player != null
		and player.carry_system != null
		and player.carry_system.can_pick_up()
	)


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if placed_device:
		if player and not placed_device.can_claim(player):
			var claiming_p: PlayerCharacter = placed_device.claimed_by
			if claiming_p and is_instance_valid(claiming_p):
				return "Claimed by P%d" % [claiming_p.player_index + 1]
			return "In Use"
		if not _incoming_queue.is_empty():
			return "Pick Up Device (+%d in queue)" % _incoming_queue.size()
		return "Pick Up Device"
	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if placed_device and player and player.carry_system and player.carry_system.can_pick_up():
		if not placed_device.try_claim(player):
			return
		var device: Carriable = remove_device()
		player.carry_system.pick_up(device)


func remove_device() -> Carriable:
	var dev: Carriable = super.remove_device()
	_advance_incoming_queue()
	return dev


func accept_device(device: Carriable) -> void:
	super.accept_device(device)
	if device:
		device.visible = true


func _advance_incoming_queue() -> void:
	while placed_device == null and not _incoming_queue.is_empty():
		var next_dev: Carriable = _incoming_queue.pop_front()
		if is_instance_valid(next_dev):
			accept_device(next_dev)
			break


## Helper method to place an incoming customer device onto the desk
func spawn_incoming_device(device: Carriable) -> void:
	if not device:
		return
	if placed_device == null:
		accept_device(device)
	else:
		_incoming_queue.append(device)
		if device.get_parent():
			device.get_parent().remove_child(device)
		add_child(device)
		device.visible = false


## Removes a device from incoming queue or placed slot if order expired/cancelled
func remove_incoming_device(device: Carriable) -> void:
	_incoming_queue.erase(device)
	if placed_device == device:
		remove_device()


## Returns whether a device is currently waiting on the desk or in queue
func has_device() -> bool:
	return placed_device != null or not _incoming_queue.is_empty()


## Returns the number of devices waiting in queue behind the current one
func get_incoming_queue_count() -> int:
	return _incoming_queue.size()
