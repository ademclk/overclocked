class_name PartsShelf
extends BaseStation

## Parts shelf station dispensing replacement components.
## Does not accept devices; players pick up needed components from here.
## Auto-dispenses the appropriate component matching the active diagnosed device's fault,
## or allows cycling through parts. Tracks finite stock per component type.

signal stock_changed(component_id: String, remaining: int)
signal stock_depleted(component_id: String)
signal stock_restocked(component_id: String, new_amount: int)

@export var dispensed_part_name: String = "Replacement Part"
@export var dispensed_part_type: String = "part"
@export var part_scene: PackedScene = null
@export var available_parts: Array[ComponentData] = []

@export_group("Stock Management")
@export var stock_tracking_enabled: bool = true
@export var initial_stock_per_part: int = Constants.DEFAULT_INITIAL_STOCK_PER_PART
@export var stock_display_label: Label3D = null

var _stock: Dictionary = {}
var _selected_part_index: int = 0


func _ready() -> void:
	station_name = "Parts Shelf"
	station_type = "shelf"
	_load_default_parts()
	if stock_tracking_enabled:
		_init_stock()
	super._ready()
	_update_stock_display()


func can_accept_device(_device: Carriable) -> bool:
	return false


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if not player or not player.carry_system:
		return false

	var carry: CarrySystem = player.carry_system
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is DeliveryBox or held.item_type == "delivery" or held.has_method("unpack_at_shelf"):
			return true
		return false

	# Player has empty hands
	return true


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if not player or not player.carry_system:
		return ""

	var carry: CarrySystem = player.carry_system
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is DeliveryBox or held.item_type == "delivery" or held.has_method("unpack_at_shelf"):
			return "Unpack %s" % held.item_name
		return "Hands Full"

	var needed: ComponentData = _get_needed_part()
	if not needed:
		return "No Parts Available"

	var part_display_name: String = needed.component_name if (_has_active_diagnosed_device() or _selected_part_index != 0) else dispensed_part_name

	if stock_tracking_enabled and get_stock(needed.component_id) <= 0:
		return "OUT OF STOCK: %s" % part_display_name

	return "Take %s" % part_display_name


func _on_interacted(player: PlayerCharacter) -> void:
	SignalBus.station_interacted.emit(station_name, player.player_index if player else 0)

	if not player or not player.carry_system:
		return

	var carry: CarrySystem = player.carry_system

	# Case 1: Unpacking a delivery box
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is DeliveryBox:
			(held as DeliveryBox).unpack_at_shelf(self)
			_flash_restocked()
			return
		elif held.has_method("unpack_at_shelf"):
			held.unpack_at_shelf(self)
			_flash_restocked()
			return
		return

	# Case 2: Player taking a replacement component
	if not carry.can_pick_up():
		return

	var needed: ComponentData = _get_needed_part()
	if not needed:
		return

	# Check stock limits
	if stock_tracking_enabled:
		var current_qty: int = get_stock(needed.component_id)
		if current_qty <= 0:
			_flash_out_of_stock()
			SignalBus.part_out_of_stock.emit(needed.component_id)
			return

		var remaining: int = current_qty - 1
		_stock[needed.component_id] = remaining
		stock_changed.emit(needed.component_id, remaining)
		SignalBus.part_dispensed.emit(needed.component_id, remaining)

		if remaining <= 0:
			stock_depleted.emit(needed.component_id)
			SignalBus.part_out_of_stock.emit(needed.component_id)

	var part: Carriable = _create_part_instance(needed)
	if not part:
		return

	if get_parent():
		get_parent().add_child(part)
	else:
		add_child(part)

	carry.pick_up(part)
	_update_stock_display()


## Initializes finite stock counts for all available parts
func _init_stock() -> void:
	_stock.clear()
	for part: ComponentData in available_parts:
		if part:
			_stock[part.component_id] = initial_stock_per_part
	_update_stock_display()


## Resolves a query string to the canonical component_id
func _resolve_component_id(query: String) -> String:
	if query in _stock:
		return query
	for part: ComponentData in available_parts:
		if part:
			if part.component_id == query:
				return part.component_id
			if part.component_type == query or part.component_type.to_lower() == query.to_lower():
				return part.component_id
			if part.component_name.to_lower() == query.to_lower():
				return part.component_id
	return query


## Returns the current stock count for a component type
func get_stock(component_id_or_type: String) -> int:
	if not stock_tracking_enabled:
		return 999
	var cid := _resolve_component_id(component_id_or_type)
	return _stock.get(cid, 0)


## Checks if a component type is in stock
func has_stock(component_id_or_type: String) -> bool:
	if not stock_tracking_enabled:
		return true
	return get_stock(component_id_or_type) > 0


## Restocks a specific component by the given amount
func restock(component_id_or_type: String, amount: int = 1) -> void:
	var cid := _resolve_component_id(component_id_or_type)
	var current_qty: int = _stock.get(cid, 0)
	var new_qty: int = current_qty + amount
	_stock[cid] = new_qty
	stock_changed.emit(cid, new_qty)
	stock_restocked.emit(cid, new_qty)
	SignalBus.part_restocked.emit(cid, new_qty)
	_update_stock_display()


## Restocks all available parts up to or by the specified amount
func restock_all(amount: int = 3) -> void:
	for part: ComponentData in available_parts:
		if part:
			_stock[part.component_id] = amount
			stock_changed.emit(part.component_id, amount)
			stock_restocked.emit(part.component_id, amount)
			SignalBus.part_restocked.emit(part.component_id, amount)
	_update_stock_display()
	_flash_restocked()


## Cycles to the next available part in the shelf inventory
func cycle_next_part() -> ComponentData:
	if available_parts.is_empty():
		return null
	_selected_part_index = (_selected_part_index + 1) % available_parts.size()
	_update_stock_display()
	return available_parts[_selected_part_index]


## Sets the selected part by index
func set_selected_part_index(index: int) -> void:
	if index >= 0 and index < available_parts.size():
		_selected_part_index = index
		_update_stock_display()


## Sets the selected part by component_id or type
func set_selected_part_by_id(query: String) -> void:
	var cid := _resolve_component_id(query)
	for i in range(available_parts.size()):
		if available_parts[i] and (available_parts[i].component_id == cid or available_parts[i].component_id == query or available_parts[i].component_type == query):
			_selected_part_index = i
			_update_stock_display()
			return


## Returns the currently selected part
func get_selected_part() -> ComponentData:
	if available_parts.is_empty():
		return null
	if _selected_part_index >= 0 and _selected_part_index < available_parts.size():
		return available_parts[_selected_part_index]
	return available_parts[0]


## Returns the replacement component needed by an active repair device
func _get_needed_part() -> ComponentData:
	var tree := get_tree()
	if tree:
		var devices: Array[Node] = tree.get_nodes_in_group("devices")
		for node: Node in devices:
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node is Device:
				var dev := node as Device
				if dev.is_diagnosed and dev.assigned_fault:
					if dev.current_repair_state in [
						RepairState.State.DIAGNOSED,
						RepairState.State.DISASSEMBLED
					]:
						if dev.has_method("get_missing_components"):
							var missing: Array[ComponentData] = dev.get_missing_components()
							if not missing.is_empty():
								return missing[0]
						if dev.assigned_fault.has_method("get_required_components"):
							var req: Array[ComponentData] = dev.assigned_fault.get_required_components()
							if not req.is_empty():
								return req[0]
						if dev.assigned_fault.broken_component:
							return dev.assigned_fault.broken_component

	return get_selected_part()


## Checks if an active diagnosed device is currently waiting for parts
func _has_active_diagnosed_device() -> bool:
	var tree := get_tree()
	if tree:
		var devices: Array[Node] = tree.get_nodes_in_group("devices")
		for node: Node in devices:
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node is Device:
				var dev := node as Device
				if dev.is_diagnosed and dev.assigned_fault:
					if dev.current_repair_state in [
						RepairState.State.DIAGNOSED,
						RepairState.State.DISASSEMBLED
					]:
						if dev.has_method("get_missing_components"):
							if not dev.get_missing_components().is_empty():
								return true
						elif dev.assigned_fault.has_method("get_required_components"):
							if not dev.assigned_fault.get_required_components().is_empty():
								return true
						elif dev.assigned_fault.broken_component != null:
							return true
	return false


## Spawns a Carriable representation of the component with metadata
func _create_part_instance(component: ComponentData) -> Carriable:
	var part: Carriable = null
	if part_scene:
		var instance: Node = part_scene.instantiate()
		if instance is Carriable:
			part = instance as Carriable
			if component:
				part.set_meta("component_data", component)
				part.item_name = component.component_name

	if not part:
		part = Carriable.new()
		part.name = component.component_id if component else "ComponentItem"
		part.item_name = component.component_name if component else dispensed_part_name
		part.item_type = dispensed_part_type
		if component:
			part.set_meta("component_data", component)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.1, 0.2)
		mesh_inst.mesh = box

		var mat := StandardMaterial3D.new()
		if component:
			match component.component_type:
				"screen":
					mat.albedo_color = Color(0.2, 0.7, 0.9)
				"battery":
					mat.albedo_color = Color(0.95, 0.8, 0.2)
				"software":
					mat.albedo_color = Color(0.65, 0.3, 0.85)
				"keyboard":
					mat.albedo_color = Color(0.25, 0.25, 0.3)
				"memory":
					mat.albedo_color = Color(0.15, 0.75, 0.35)
				"storage":
					mat.albedo_color = Color(0.85, 0.45, 0.15)
				"cooling":
					mat.albedo_color = Color(0.2, 0.6, 0.85)
				"thermal":
					mat.albedo_color = Color(0.75, 0.75, 0.75)
				"gpu":
					mat.albedo_color = Color(0.85, 0.2, 0.2)
				"power":
					mat.albedo_color = Color(0.9, 0.6, 0.1)
				"motherboard":
					mat.albedo_color = Color(0.1, 0.55, 0.25)
				"optical":
					mat.albedo_color = Color(0.5, 0.5, 0.6)
				"port":
					mat.albedo_color = Color(0.85, 0.75, 0.2)
				"antenna":
					mat.albedo_color = Color(0.4, 0.4, 0.45)
				"audio":
					mat.albedo_color = Color(0.8, 0.35, 0.6)
				_:
					mat.albedo_color = Color(0.3, 0.8, 0.4)
		else:
			mat.albedo_color = Color(0.1, 0.8, 0.9)

		mesh_inst.material_override = mat
		part.add_child(mesh_inst)

	part.setup_interaction_zone()
	return part


func _update_stock_display() -> void:
	if not stock_display_label:
		stock_display_label = get_node_or_null("StockLabel") as Label3D

	if not stock_display_label and is_inside_tree():
		stock_display_label = Label3D.new()
		stock_display_label.name = "StockLabel"
		stock_display_label.font_size = 18
		stock_display_label.outline_size = 4
		stock_display_label.pixel_size = 0.005
		stock_display_label.position = Vector3(0.0, 1.25, 0.25)
		add_child(stock_display_label)

	if not stock_display_label:
		return

	if not stock_tracking_enabled:
		stock_display_label.text = "STOCK: INF"
		stock_display_label.modulate = Color(0.7, 0.9, 0.7)
		return

	var lines: Array[String] = []
	if available_parts.size() <= 8:
		for i in range(available_parts.size()):
			var part: ComponentData = available_parts[i]
			if not part:
				continue
			var count: int = _stock.get(part.component_id, 0)
			var status_str: String = "%d" % count if count > 0 else "OUT"
			var prefix: String = "> " if i == _selected_part_index else "  "
			lines.append("%s%s: %s" % [prefix, part.component_name, status_str])
	else:
		var window_size: int = 7
		var half: int = window_size / 2
		var start_idx: int = clampi(_selected_part_index - half, 0, maxi(0, available_parts.size() - window_size))
		var end_idx: int = mini(available_parts.size(), start_idx + window_size)
		if start_idx > 0:
			lines.append("  ↑ ... (%d more)" % start_idx)
		for i in range(start_idx, end_idx):
			var part: ComponentData = available_parts[i]
			if not part:
				continue
			var count: int = _stock.get(part.component_id, 0)
			var status_str: String = "%d" % count if count > 0 else "OUT"
			var prefix: String = "> " if i == _selected_part_index else "  "
			lines.append("%s%s: %s" % [prefix, part.component_name, status_str])
		if end_idx < available_parts.size():
			lines.append("  ↓ ... (%d more)" % (available_parts.size() - end_idx))

	stock_display_label.text = "\n".join(lines)


func _flash_out_of_stock() -> void:
	if station_label:
		station_label.text = "OUT OF STOCK"
		station_label.modulate = Color(1.0, 0.2, 0.2)
		var tween := create_tween()
		if tween:
			tween.tween_interval(1.0)
			tween.tween_callback(func() -> void:
				if station_label and is_instance_valid(station_label):
					station_label.text = station_name.to_upper()
					station_label.modulate = Color.WHITE
			)


func _flash_restocked() -> void:
	if station_label:
		station_label.text = "RESTOCKED!"
		station_label.modulate = Color(0.2, 1.0, 0.3)
		var tween := create_tween()
		if tween:
			tween.tween_interval(1.2)
			tween.tween_callback(func() -> void:
				if station_label and is_instance_valid(station_label):
					station_label.text = station_name.to_upper()
					station_label.modulate = Color.WHITE
			)


func _load_default_parts() -> void:
	if not available_parts.is_empty():
		return

	var paths: Array[String] = [
		# Phone
		"res://resources/components/screen.tres",
		"res://resources/components/battery.tres",
		"res://resources/components/os_installer.tres",
		# Tablet
		"res://resources/components/tablet_screen.tres",
		"res://resources/components/tablet_battery.tres",
		"res://resources/components/tablet_speaker.tres",
		# Laptop
		"res://resources/components/laptop_keyboard.tres",
		"res://resources/components/laptop_ram.tres",
		"res://resources/components/laptop_ssd.tres",
		"res://resources/components/laptop_screen.tres",
		"res://resources/components/laptop_fan.tres",
		"res://resources/components/thermal_paste.tres",
		# Desktop PC
		"res://resources/components/gpu.tres",
		"res://resources/components/psu.tres",
		"res://resources/components/motherboard.tres",
		"res://resources/components/cpu_cooler.tres",
		"res://resources/components/desktop_ram.tres",
		"res://resources/components/desktop_ssd.tres",
		# Game Console
		"res://resources/components/disc_drive.tres",
		"res://resources/components/console_hdmi_port.tres",
		# Router
		"res://resources/components/router_antenna.tres",
		"res://resources/components/router_firmware.tres",
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is ComponentData:
				available_parts.append(res as ComponentData)
