class_name InteractionMenu
extends PanelContainer

## RE-style interaction menu. Opens when player interacts with a menu-type interactable.
## Presents contextual options. Captures input for the owning player only.

signal option_selected(option_id: String)
signal menu_closed()
signal menu_opened()

@export var owning_player_index: int = 0
@export var max_visible_options: int = 6
@export var auto_close_distance: float = Constants.MENU_AUTO_CLOSE_DISTANCE
@export var quick_action_enabled: bool = false

var _options: Array[InteractionMenuOption] = []
var _selected_index: int = 0
var _target_interactable: Interactable = null
var _target_node: Node3D = null
var _owning_player: PlayerCharacter = null
var _is_open: bool = false
var _hazard_target: BaseHazard = null

@onready var header_icon: TextureRect = get_node_or_null("VBoxContainer/HeaderPanel/TargetIcon") as TextureRect
@onready var header_name: Label = get_node_or_null("VBoxContainer/HeaderPanel/TargetName") as Label
@onready var header_timer: Label = get_node_or_null("VBoxContainer/HeaderPanel/HeaderTimer") as Label
@onready var options_container: VBoxContainer = get_node_or_null("VBoxContainer/OptionsContainer") as VBoxContainer
@onready var description_label: RichTextLabel = get_node_or_null("VBoxContainer/DescriptionPanel/DescriptionLabel") as RichTextLabel
@onready var controls_hint: HBoxContainer = get_node_or_null("VBoxContainer/ControlsHint") as HBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = Constants.INTERACTION_MENU_WIDTH


func is_open() -> bool:
	return _is_open


func get_target_interactable() -> Interactable:
	return _target_interactable


func get_options() -> Array[InteractionMenuOption]:
	return _options


func get_selected_index() -> int:
	return _selected_index


func open_menu(player: PlayerCharacter, interactable: Interactable, options: Array[InteractionMenuOption]) -> void:
	if _is_open:
		return

	_owning_player = player
	if player:
		owning_player_index = player.player_index
	_target_interactable = interactable
	_target_node = interactable.get_parent() as Node3D if (interactable and interactable.get_parent() is Node3D) else (interactable as Node3D)
	_options = options
	_selected_index = 0
	_is_open = true

	# Check for hazard target
	_hazard_target = null
	if interactable and interactable.get_parent() is BaseHazard:
		_hazard_target = interactable.get_parent() as BaseHazard

	# Quick-action check: if enabled and only 1 actionable option (excluding cancel)
	if quick_action_enabled and _options.size() > 0:
		var actionable := _options.filter(func(o: InteractionMenuOption) -> bool: return o.is_enabled and o.option_id != "cancel")
		if actionable.size() == 1:
			var opt: InteractionMenuOption = actionable[0]
			_is_open = false
			visible = false
			option_selected.emit(opt.option_id)
			SignalBus.interaction_menu_option_selected.emit(owning_player_index, opt.option_id)
			if opt.action_callable.is_valid():
				opt.action_callable.call()
			menu_closed.emit()
			SignalBus.interaction_menu_closed.emit(owning_player_index)
			return

	# Find first enabled option
	for i in range(_options.size()):
		if _options[i].is_enabled:
			_selected_index = i
			break

	_update_header()
	_build_options()
	_update_description()

	# Lock player movement while menu is open
	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(true)

	visible = true
	var target_display: String = _target_interactable.interaction_prompt if _target_interactable else "Unknown"
	menu_opened.emit()
	SignalBus.interaction_menu_opened.emit(owning_player_index, target_display)


func close_menu() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false

	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)

	_options.clear()
	_target_interactable = null
	_target_node = null
	_hazard_target = null
	menu_closed.emit()
	SignalBus.interaction_menu_closed.emit(owning_player_index)


func _process(_delta: float) -> void:
	if not _is_open:
		return

	# Auto-close if player walked/moved away
	if _owning_player and _target_node and is_instance_valid(_owning_player) and is_instance_valid(_target_node):
		var dist: float = _owning_player.global_position.distance_to(_target_node.global_position)
		if dist > auto_close_distance:
			close_menu()
			return

	# Update hazard countdown timer if present
	if _hazard_target and is_instance_valid(_hazard_target) and header_timer:
		if _hazard_target.duration > 0.0:
			var rem: float = maxf(0.0, _hazard_target.duration - _hazard_target._active_timer)
			header_timer.text = "⏱ %.1fs" % rem
			header_timer.visible = true
		else:
			header_timer.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	var player_idx: int = owning_player_index
	var nav_up := MultiplayerInput.action_name(player_idx, "move_up")
	var nav_down := MultiplayerInput.action_name(player_idx, "move_down")
	var confirm := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)
	var cancel := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_DROP)

	if event.is_action_pressed(nav_up) or event.is_action_pressed(&"menu_up") or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_W or event.keycode == KEY_UP)):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(nav_down) or event.is_action_pressed(&"menu_down") or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_S or event.keycode == KEY_DOWN)):
		_navigate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(confirm) or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)):
		_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(cancel) or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_Q or event.keycode == KEY_ESCAPE)):
		close_menu()
		get_viewport().set_input_as_handled()


func _navigate(direction: int) -> void:
	if _options.is_empty():
		return

	var old_index: int = _selected_index
	var new_index: int = clampi(_selected_index + direction, 0, _options.size() - 1)

	var attempts: int = 0
	while attempts < _options.size() and not _options[new_index].is_enabled:
		new_index = clampi(new_index + direction, 0, _options.size() - 1)
		attempts += 1
		if new_index == 0 or new_index == _options.size() - 1:
			break

	if _options[new_index].is_enabled:
		_selected_index = new_index

	if _selected_index != old_index:
		_build_options()
		_update_description()


func _confirm_selection() -> void:
	if _selected_index < 0 or _selected_index >= _options.size():
		return
	var opt: InteractionMenuOption = _options[_selected_index]
	if not opt.is_enabled:
		return

	option_selected.emit(opt.option_id)
	SignalBus.interaction_menu_option_selected.emit(owning_player_index, opt.option_id)

	var callable := opt.action_callable
	close_menu()

	if callable.is_valid():
		callable.call()


func _update_header() -> void:
	if header_name:
		if _target_interactable:
			header_name.text = _target_interactable.interaction_prompt.to_upper()
		else:
			header_name.text = "INTERACTION"
	if header_timer:
		header_timer.visible = _hazard_target != null


func _build_options() -> void:
	if not options_container:
		return

	for child in options_container.get_children():
		child.queue_free()

	for i in range(_options.size()):
		var opt: InteractionMenuOption = _options[i]
		var row := _create_option_row(opt, i == _selected_index)
		options_container.add_child(row)


func _create_option_row(opt: InteractionMenuOption, is_selected: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var indicator := Label.new()
	indicator.text = "▶ " if is_selected else "   "
	indicator.custom_minimum_size.x = 24
	indicator.add_theme_font_size_override("font_size", 18)
	indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if is_selected else Color(0.4, 0.4, 0.4))
	row.add_child(indicator)

	var label := Label.new()
	label.text = opt.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	if is_selected:
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	elif opt.is_enabled:
		label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	else:
		label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	row.add_child(label)

	if not opt.is_enabled and not opt.disabled_reason.is_empty():
		var hint := Label.new()
		hint.text = "[%s]" % opt.disabled_reason
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
		row.add_child(hint)
	elif not opt.hotkey_hint.is_empty():
		var hint := Label.new()
		hint.text = opt.hotkey_hint
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(hint)

	return row


func _update_description() -> void:
	if description_label and _selected_index >= 0 and _selected_index < _options.size():
		var opt := _options[_selected_index]
		var desc_text := opt.description
		if not opt.is_enabled and not opt.disabled_reason.is_empty():
			desc_text += "\n[color=#ff5555]Unavailable: %s[/color]" % opt.disabled_reason
		description_label.text = desc_text
