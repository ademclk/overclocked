class_name DeliveryCounter
extends BaseStation

## Delivery counter station where players deliver fully repaired and tested devices
## to fulfill customer orders and earn scores.

signal device_delivered(device: Carriable)


@export var order_manager: Node = null


func _ready() -> void:
	station_name = "Delivery Counter"
	station_type = "delivery"
	accepted_device_states = ["TESTED"]
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	if not player or not player.carry_system:
		return false
	if player.carry_system.is_carrying():
		return _is_valid_delivery_device(player.carry_system.get_held_item())
	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if player and player.carry_system and player.carry_system.is_carrying():
		if _is_valid_delivery_device(player.carry_system.get_held_item()):
			return "Deliver Repaired Device"
	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	if player.carry_system.is_carrying():
		var device: Carriable = player.carry_system.get_held_item()
		if _is_valid_delivery_device(device):
			player.carry_system.place_on_station(self)
			accept_device(device)
			current_state = StationState.COMPLETE
			device_delivered.emit(device)
			SignalBus.device_repaired.emit(device.item_name)
			if device.has_method("deliver"):
				device.deliver()

			var mgr: OrderManager = order_manager as OrderManager if order_manager is OrderManager else _find_order_manager()
			if mgr:
				mgr.complete_order_for_device(device)


func _find_order_manager() -> OrderManager:
	if get_parent():
		var mgr: Node = get_parent().get_node_or_null("OrderManager")
		if mgr is OrderManager:
			return mgr as OrderManager
	var tree := get_tree()
	if tree:
		var managers: Array[Node] = tree.get_nodes_in_group("order_managers")
		if not managers.is_empty() and managers[0] is OrderManager:
			return managers[0] as OrderManager
	return null


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _is_valid_delivery_device(device)


func _is_valid_delivery_device(device: Carriable) -> bool:
	if device == null:
		return false
	if device is Device:
		return (device as Device).current_repair_state == RepairState.State.TESTED
	if device.has_method("get_repair_state"):
		return str(device.get_repair_state()) == "TESTED"
	# Fallback for generic Carriable in station unit tests
	return device.item_type == "device"
