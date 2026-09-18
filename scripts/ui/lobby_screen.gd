class_name LobbyScreen
extends Control

## Player lobby for join/ready flow before gameplay starts.
## Manages controller detection, player slot assignment, visual color feedback,
## and ready-up synchronization before transitioning to gameplay.

signal all_players_ready(player_count: int, device_assignments: Dictionary)
signal lobby_cancelled
signal player_slot_joined(slot_index: int, device_id: int)
signal player_slot_left(slot_index: int)
signal player_slot_ready_changed(slot_index: int, is_ready: bool)

enum SlotState { EMPTY, JOINED, READY }

const MAX_SLOTS: int = 4
const MIN_PLAYERS_TO_START: int = 1

const COLOR_EMPTY_BORDER: Color = Color(0.25, 0.3, 0.4, 0.4)
const COLOR_READY_TEXT: Color = Color(0.25, 0.95, 0.35, 1.0)
const COLOR_WAITING_TEXT: Color = Color(0.95, 0.75, 0.2, 1.0)

var _slot_states: Array[SlotState] = [
	SlotState.EMPTY, SlotState.EMPTY, SlotState.EMPTY, SlotState.EMPTY
]
# Device IDs: -2 = unassigned, -1 = keyboard 0 (WASD), -3 = keyboard 1 (Arrows), 0+ = joypad index
var _slot_devices: Array[int] = [-2, -2, -2, -2]

@onready var title_label: Label = get_node_or_null("Title") as Label
@onready var slots_container: HBoxContainer = get_node_or_null("SlotsContainer") as HBoxContainer
@onready var connected_info_label: Label = get_node_or_null("ConnectedInfo") as Label
@onready var instruction_label: Label = get_node_or_null("InstructionLabel") as Label
@onready var start_prompt: Label = get_node_or_null("StartPrompt") as Label
@onready var start_button: Button = get_node_or_null("StartButton") as Button


func _ready() -> void:
	_update_all_slots_ui()
	_update_connected_controllers_display()
	_check_all_ready()

	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	if start_button:
		start_button.pressed.connect(start_game)

	# Connect per-slot action buttons if present
	if slots_container:
		for i in range(MAX_SLOTS):
			var slot_node: Control = slots_container.get_node_or_null("PlayerSlot%d" % (i + 1)) as Control
			if slot_node:
				var btn: Button = slot_node.find_child("SlotButton", true, false) as Button
				if btn:
					var slot_idx: int = i
					btn.pressed.connect(func() -> void: _on_slot_button_pressed(slot_idx))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_pressed() and not event.is_echo():
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			if get_joined_count() == 0:
				lobby_cancelled.emit()
				if get_viewport():
					get_viewport().set_input_as_handled()
				return

		var device_id: int = _get_device_from_event(event)
		if device_id == -2:
			return

		var existing_slot: int = _find_slot_for_device(device_id)
		if existing_slot >= 0:
			if _is_cancel_action(event, device_id):
				_handle_slot_cancel(existing_slot)
				if get_viewport():
					get_viewport().set_input_as_handled()
			elif _is_confirm_action(event, device_id):
				if are_all_ready() and _is_start_button(event, device_id):
					start_game()
				else:
					_toggle_ready(existing_slot)
				if get_viewport():
					get_viewport().set_input_as_handled()
		else:
			# New device — join first available slot
			_try_join(device_id)
			if get_viewport():
				get_viewport().set_input_as_handled()


func _get_device_from_event(event: InputEvent) -> int:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# Keyboard player 0 (WASD + E/F/G/Space)
		if code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_G, KEY_SPACE]:
			return -1
		# Keyboard player 1 (Arrows + Numpad keys)
		elif code in [
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
			KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_ENTER, KEY_KP_ENTER
		]:
			return -3
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion:
			if absf((event as InputEventJoypadMotion).axis_value) < 0.5:
				return -2
		return event.device
	return -2


func _is_confirm_action(event: InputEvent, device_id: int) -> bool:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if device_id == -1:
			return code in [KEY_E, KEY_F, KEY_SPACE, KEY_ENTER]
		elif device_id == -3:
			return code in [KEY_KP_1, KEY_KP_2, KEY_ENTER, KEY_KP_ENTER]
	elif event is InputEventJoypadButton:
		var btn: JoyButton = (event as InputEventJoypadButton).button_index
		return btn == JOY_BUTTON_A or btn == JOY_BUTTON_START or btn == JOY_BUTTON_X
	return false


func _is_cancel_action(event: InputEvent, device_id: int) -> bool:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if device_id == -1:
			return code in [KEY_G, KEY_Q, KEY_ESCAPE]
		elif device_id == -3:
			return code in [KEY_KP_3, KEY_BACKSPACE]
	elif event is InputEventJoypadButton:
		var btn: JoyButton = (event as InputEventJoypadButton).button_index
		return btn == JOY_BUTTON_B or btn == JOY_BUTTON_BACK
	return false


func _is_start_button(event: InputEvent, _device_id: int) -> bool:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	return false


func _find_slot_for_device(device_id: int) -> int:
	for i in range(MAX_SLOTS):
		if _slot_states[i] != SlotState.EMPTY and _slot_devices[i] == device_id:
			return i
	return -1


func _try_join(device_id: int) -> int:
	for i in range(MAX_SLOTS):
		if _slot_states[i] == SlotState.EMPTY:
			_slot_states[i] = SlotState.JOINED
			_slot_devices[i] = device_id
			_update_slot_ui(i)
			_check_all_ready()
			player_slot_joined.emit(i, device_id)
			return i
	return -1


func _toggle_ready(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		return
	if _slot_states[slot] == SlotState.JOINED:
		_slot_states[slot] = SlotState.READY
		player_slot_ready_changed.emit(slot, true)
	elif _slot_states[slot] == SlotState.READY:
		_slot_states[slot] = SlotState.JOINED
		player_slot_ready_changed.emit(slot, false)
	_update_slot_ui(slot)
	_check_all_ready()


func _handle_slot_cancel(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		return
	if _slot_states[slot] == SlotState.READY:
		_slot_states[slot] = SlotState.JOINED
		player_slot_ready_changed.emit(slot, false)
		_update_slot_ui(slot)
		_check_all_ready()
	elif _slot_states[slot] == SlotState.JOINED:
		_slot_states[slot] = SlotState.EMPTY
		_slot_devices[slot] = -2
		_update_slot_ui(slot)
		_check_all_ready()
		player_slot_left.emit(slot)


func _on_slot_button_pressed(slot: int) -> void:
	if _slot_states[slot] == SlotState.EMPTY:
		# Join with virtual keyboard/controller
		var dev_id: int = -1 if slot == 0 else (-3 if slot == 1 else (slot - 2))
		_try_join(dev_id)
	elif _slot_states[slot] == SlotState.JOINED:
		_toggle_ready(slot)
	elif _slot_states[slot] == SlotState.READY:
		_toggle_ready(slot)


## Programmatically joins a player to a slot (useful for tests and automation)
func join_player(slot_index: int, device_id: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _slot_states[slot_index] != SlotState.EMPTY:
		return false
	_slot_states[slot_index] = SlotState.JOINED
	_slot_devices[slot_index] = device_id
	_update_slot_ui(slot_index)
	_check_all_ready()
	player_slot_joined.emit(slot_index, device_id)
	return true


## Programmatically removes a player from a slot
func leave_player(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _slot_states[slot_index] == SlotState.EMPTY:
		return false
	_slot_states[slot_index] = SlotState.EMPTY
	_slot_devices[slot_index] = -2
	_update_slot_ui(slot_index)
	_check_all_ready()
	player_slot_left.emit(slot_index)
	return true


## Programmatically sets a player's ready state
func set_player_ready(slot_index: int, is_ready: bool) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _slot_states[slot_index] == SlotState.EMPTY:
		return false
	var target_state := SlotState.READY if is_ready else SlotState.JOINED
	if _slot_states[slot_index] != target_state:
		_slot_states[slot_index] = target_state
		_update_slot_ui(slot_index)
		_check_all_ready()
		player_slot_ready_changed.emit(slot_index, is_ready)
	return true


func is_slot_empty(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return true
	return _slot_states[slot_index] == SlotState.EMPTY


func is_slot_ready(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	return _slot_states[slot_index] == SlotState.READY


func get_slot_state(slot_index: int) -> SlotState:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return SlotState.EMPTY
	return _slot_states[slot_index]


func get_slot_device(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return -2
	return _slot_devices[slot_index]


func get_joined_count() -> int:
	var count: int = 0
	for state in _slot_states:
		if state != SlotState.EMPTY:
			count += 1
	return count


func get_ready_count() -> int:
	var count: int = 0
	for state in _slot_states:
		if state == SlotState.READY:
			count += 1
	return count


func are_all_ready() -> bool:
	var joined_count: int = get_joined_count()
	var ready_count: int = get_ready_count()
	return joined_count >= MIN_PLAYERS_TO_START and joined_count == ready_count


func get_device_assignments() -> Dictionary:
	var assignments: Dictionary = {}
	for i in range(MAX_SLOTS):
		if _slot_states[i] != SlotState.EMPTY:
			var dev: int = _slot_devices[i]
			# Map -3 (keyboard 1) to -1 for MultiplayerInput
			assignments[i] = -1 if dev < 0 else dev
	return assignments


func _check_all_ready() -> void:
	var all_ready: bool = are_all_ready()
	if start_prompt:
		start_prompt.visible = all_ready
	if start_button:
		start_button.visible = all_ready
		start_button.disabled = not all_ready


func start_game() -> void:
	if not are_all_ready():
		return
	var count: int = get_joined_count()
	var assignments: Dictionary = get_device_assignments()
	apply_device_assignments()
	all_players_ready.emit(count, assignments)


func apply_device_assignments() -> void:
	var assignments: Dictionary = get_device_assignments()
	for slot_idx in assignments:
		var dev_id: int = assignments[slot_idx]
		MultiplayerInput.assign_device(slot_idx, dev_id)
		SignalBus.player_device_assigned.emit(slot_idx, dev_id)

	if GameManager:
		GameManager.registered_player_count = get_joined_count()
		GameManager.registered_device_assignments = assignments.duplicate()


func reset_all_slots() -> void:
	for i in range(MAX_SLOTS):
		_slot_states[i] = SlotState.EMPTY
		_slot_devices[i] = -2
		_update_slot_ui(i)
	_check_all_ready()


func _update_all_slots_ui() -> void:
	for i in range(MAX_SLOTS):
		_update_slot_ui(i)


func _update_slot_ui(slot_index: int) -> void:
	if not slots_container:
		return
	var slot_node: Control = slots_container.get_node_or_null("PlayerSlot%d" % (slot_index + 1)) as Control
	if not slot_node:
		return

	var player_color: Color = Constants.PLAYER_COLORS[slot_index % Constants.PLAYER_COLORS.size()]
	var state: SlotState = _slot_states[slot_index]
	var dev_id: int = _slot_devices[slot_index]

	var slot_label: Label = slot_node.find_child("SlotLabel", true, false) as Label
	var device_label: Label = slot_node.find_child("DeviceLabel", true, false) as Label
	var ready_indicator: Label = slot_node.find_child("ReadyIndicator", true, false) as Label
	var prompt_label: Label = slot_node.find_child("PromptLabel", true, false) as Label
	var color_badge: ColorRect = slot_node.find_child("ColorBadge", true, false) as ColorRect
	var btn: Button = slot_node.find_child("SlotButton", true, false) as Button

	match state:
		SlotState.EMPTY:
			if slot_label:
				slot_label.text = "P%d\nPRESS TO JOIN" % (slot_index + 1)
				slot_label.modulate = Color(0.7, 0.75, 0.85, 0.7)
			if device_label:
				device_label.text = "No Device"
				device_label.modulate = Color(0.5, 0.55, 0.65, 0.6)
			if ready_indicator:
				ready_indicator.text = "—"
				ready_indicator.modulate = Color(0.5, 0.55, 0.65, 0.6)
			if prompt_label:
				prompt_label.text = "[Press Any Button]"
			if color_badge:
				color_badge.color = Color(0.3, 0.35, 0.4, 0.3)
			if btn:
				btn.text = "Join"
			_set_slot_border_color(slot_node, COLOR_EMPTY_BORDER)

		SlotState.JOINED:
			if slot_label:
				slot_label.text = "● PLAYER %d" % (slot_index + 1)
				slot_label.modulate = player_color
			if device_label:
				device_label.text = _get_device_name(dev_id, slot_index)
				device_label.modulate = Color.WHITE
			if ready_indicator:
				ready_indicator.text = "NOT READY"
				ready_indicator.modulate = COLOR_WAITING_TEXT
			if prompt_label:
				prompt_label.text = _get_slot_prompt(slot_index, dev_id, false)
			if color_badge:
				color_badge.color = player_color
			if btn:
				btn.text = "Ready"
			_set_slot_border_color(slot_node, player_color)

		SlotState.READY:
			if slot_label:
				slot_label.text = "● PLAYER %d" % (slot_index + 1)
				slot_label.modulate = player_color
			if device_label:
				device_label.text = _get_device_name(dev_id, slot_index)
				device_label.modulate = Color.WHITE
			if ready_indicator:
				ready_indicator.text = "★ READY!"
				ready_indicator.modulate = COLOR_READY_TEXT
			if prompt_label:
				prompt_label.text = _get_slot_prompt(slot_index, dev_id, true)
			if color_badge:
				color_badge.color = player_color
			if btn:
				btn.text = "Unready"
			_set_slot_border_color(slot_node, COLOR_READY_TEXT)


func _set_slot_border_color(slot_node: Control, color: Color) -> void:
	var style: StyleBox = slot_node.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var new_style: StyleBoxFlat = (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		new_style.border_color = color
		slot_node.add_theme_stylebox_override("panel", new_style)


func _get_device_name(dev_id: int, slot_index: int) -> String:
	match dev_id:
		-1:
			return "Keyboard (WASD + E/F/G)"
		-3:
			return "Keyboard (Arrows + Num)"
		_:
			if dev_id >= 0:
				var joy_name: String = Input.get_joy_name(dev_id)
				if joy_name.is_empty():
					return "Gamepad %d" % (dev_id + 1)
				return "%s (%d)" % [joy_name, dev_id + 1]
			return "Player %d" % (slot_index + 1)


func _get_slot_prompt(slot_index: int, dev_id: int, is_ready: bool) -> String:
	if not is_ready:
		if dev_id == -1:
			return "[E] Ready | [G] Leave"
		elif dev_id == -3:
			return "[Num 1] Ready | [Num 3] Leave"
		else:
			return "(A) Ready | (B) Leave"
	else:
		if dev_id == -1:
			return "[E] or [G] Unready"
		elif dev_id == -3:
			return "[Num 1] Unready"
		else:
			return "(B) Unready"


func _update_connected_controllers_display() -> void:
	if connected_info_label:
		var joy_count: int = Input.get_connected_joypads().size()
		connected_info_label.text = "Connected Controllers: %d | Keyboard Split: P1 (WASD) / P2 (Arrows)" % joy_count


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_update_connected_controllers_display()
	if not connected:
		var slot: int = _find_slot_for_device(device)
		if slot >= 0:
			leave_player(slot)
