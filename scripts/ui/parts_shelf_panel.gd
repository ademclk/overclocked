class_name PartsShelfPanel
extends PanelContainer

## Visual catalog panel for Parts Shelf.
## Displays all workshop components with icons, names, and stock counts.
## Highlights currently needed components in distinct gold/green.
## Clicking an available component dispenses and equips it directly to the player.

signal panel_opened()
signal panel_closed()
signal part_selected(component_id: String)

@export var owning_player_index: int = 0

var _is_open: bool = false
var _owning_player: PlayerCharacter = null
var _shelf: PartsShelf = null

# Theme Colors
const COLOR_CARD_NORMAL_BG := Color(0.14, 0.16, 0.20, 0.95)
const COLOR_CARD_NORMAL_BORDER := Color(0.25, 0.30, 0.38, 0.9)
const COLOR_CARD_NEEDED_BG := Color(0.18, 0.16, 0.06, 0.98)
const COLOR_CARD_NEEDED_BORDER := Color(1.0, 0.82, 0.2, 1.0)
const COLOR_CARD_DISABLED_BG := Color(0.10, 0.11, 0.13, 0.8)

@onready var title_label: Label = get_node_or_null("MarginContainer/VBox/Header/TitleLabel") as Label
@onready var cards_container: GridContainer = get_node_or_null("MarginContainer/VBox/Scroll/CardsContainer") as GridContainer
@onready var close_btn: Button = get_node_or_null("MarginContainer/VBox/Footer/CloseButton") as Button


func _ready() -> void:
	visible = false
	if close_btn:
		close_btn.pressed.connect(close_panel)


func is_open() -> bool:
	return _is_open


func open_shelf_panel(player: PlayerCharacter, shelf: PartsShelf) -> void:
	if not shelf or not is_instance_valid(shelf):
		return

	_owning_player = player
	_shelf = shelf
	if player:
		owning_player_index = player.player_index
		player.set_movement_locked(true)

	_is_open = true
	visible = true
	_populate_cards()
	panel_opened.emit()


func close_panel() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false

	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)
	_owning_player = null
	_shelf = null
	panel_closed.emit()


func _get_needed_component_ids() -> Array[String]:
	var needed_ids: Array[String] = []

	# Check 1: Held device
	if _owning_player and _owning_player.carry_system and _owning_player.carry_system.is_carrying():
		var held: Carriable = _owning_player.carry_system.get_held_item()
		if held is Device:
			for comp in (held as Device).get_missing_components():
				if comp and not needed_ids.has(comp.component_id):
					needed_ids.append(comp.component_id)

	# Check 2: Active device on Repair Table / Stations
	if needed_ids.is_empty() and is_inside_tree():
		var repair_tables := get_tree().get_nodes_in_group("repair_tables")
		for rt in repair_tables:
			if rt is BaseStation and rt.placed_device is Device:
				for comp in (rt.placed_device as Device).get_missing_components():
					if comp and not needed_ids.has(comp.component_id):
						needed_ids.append(comp.component_id)

	# Check 3: Shelf's own context resolver
	if needed_ids.is_empty() and _shelf and _shelf.has_method("_get_needed_part"):
		var shelf_needed: ComponentData = _shelf._get_needed_part()
		if shelf_needed and not needed_ids.has(shelf_needed.component_id):
			needed_ids.append(shelf_needed.component_id)

	return needed_ids


func _populate_cards() -> void:
	if not cards_container:
		return

	for c in cards_container.get_children():
		c.queue_free()

	if not _shelf:
		return

	var needed_ids := _get_needed_component_ids()
	var parts := _shelf.available_parts

	for comp in parts:
		if not comp:
			continue

		var is_needed: bool = needed_ids.has(comp.component_id)
		var stock: int = _shelf.get_stock(comp.component_id) if _shelf.stock_tracking_enabled else 99
		var card := _create_component_card(comp, is_needed, stock)
		cards_container.add_child(card)


func _create_component_card(comp: ComponentData, is_needed: bool, stock: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(170, 150)

	var style := StyleBoxFlat.new()
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2

	if is_needed:
		style.bg_color = COLOR_CARD_NEEDED_BG
		style.border_color = COLOR_CARD_NEEDED_BORDER
	elif stock <= 0:
		style.bg_color = COLOR_CARD_DISABLED_BG
		style.border_color = Color(0.3, 0.3, 0.35, 0.6)
	else:
		style.bg_color = COLOR_CARD_NORMAL_BG
		style.border_color = COLOR_CARD_NORMAL_BORDER

	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Needed Tag
	if is_needed:
		var tag := Label.new()
		tag.text = "★ NEEDED"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		vbox.add_child(tag)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 14)
		vbox.add_child(spacer)

	# Icon Glyph
	var icon_lbl := Label.new()
	icon_lbl.text = _get_glyph_for_component(comp.component_id)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 28)
	vbox.add_child(icon_lbl)

	# Component Name
	var name_lbl := Label.new()
	name_lbl.text = comp.component_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	# Stock Status
	var stock_lbl := Label.new()
	if stock > 0:
		stock_lbl.text = "Stock: %d" % stock
		stock_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5) if is_needed else Color(0.7, 0.75, 0.8))
	else:
		stock_lbl.text = "OUT OF STOCK"
		stock_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(stock_lbl)

	# Selection Button Overlay
	var btn := Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.disabled = (stock <= 0)
	btn.pressed.connect(func() -> void: _on_card_selected(comp.component_id))
	panel.add_child(btn)

	return panel


func _on_card_selected(comp_id: String) -> void:
	if not _shelf or not _owning_player:
		close_panel()
		return

	var carry: CarrySystem = _owning_player.carry_system
	if not carry or not carry.can_pick_up():
		close_panel()
		return

	var part: Carriable = _shelf.dispense_part(comp_id)
	if part:
		carry.pick_up(part)
		part_selected.emit(comp_id)

	close_panel()


func _get_glyph_for_component(comp_id: String) -> String:
	var id := comp_id.to_lower()
	if id.contains("screen"): return "📱"
	if id.contains("battery"): return "🔋"
	if id.contains("fan"): return "💨"
	if id.contains("ram"): return "🧠"
	if id.contains("paste"): return "🧪"
	if id.contains("keyboard"): return "⌨️"
	if id.contains("antenna") or id.contains("wifi"): return "📡"
	return "📦"


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	var player_idx: int = owning_player_index
	var cancel := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)

	if (
		event.is_action_pressed(cancel)
		or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_Q or event.keycode == KEY_TAB))
	):
		close_panel()
		get_viewport().set_input_as_handled()
