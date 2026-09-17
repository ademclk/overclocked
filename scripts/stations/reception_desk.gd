class_name ReceptionDesk
extends BaseStation

## Reception desk station where customers drop off devices and players pick them up.
## Player cannot place devices on the reception desk; they take incoming devices from here.


func _ready() -> void:
	station_name = "Reception Desk"
	station_type = "reception"
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	return (
		placed_device != null
		and player != null
		and player.carry_system != null
		and player.carry_system.can_pick_up()
	)


func get_interaction_prompt(_player: PlayerCharacter) -> String:
	if placed_device:
		return "Pick Up Device"
	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if placed_device and player and player.carry_system and player.carry_system.can_pick_up():
		var device: Carriable = remove_device()
		player.carry_system.pick_up(device)


## Helper method to place an incoming customer device onto the desk
func spawn_incoming_device(device: Carriable) -> void:
	if placed_device:
		remove_device()
	accept_device(device)


## Returns whether a device is currently waiting on the desk
func has_device() -> bool:
	return placed_device != null
