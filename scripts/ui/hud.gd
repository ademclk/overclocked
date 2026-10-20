class_name HUD
extends Control

## In-game HUD showing orders, carried item, score, interaction prompts,
## and repair pipeline progress.
##
## Tracks active orders and their countdown timers with dynamic color coding,
## displays currently carried items with repair state tags, shows contextual button prompts,
## and displays session score and star ratings.

signal hud_visibility_changed(is_visible: bool)

# Timer urgency color thresholds
const COLOR_TIMER_HEALTHY: Color = Color(0.25, 0.85, 0.35, 1.0)   # > 50%
const COLOR_TIMER_WARNING: Color = Color(0.95, 0.75, 0.20, 1.0)   # 20% - 50%
const COLOR_TIMER_CRITICAL: Color = Color(0.95, 0.25, 0.20, 1.0)  # < 20%

const COLOR_STAR_EARNED: Color = Color(1.0, 0.85, 0.2, 1.0)
const COLOR_STAR_EMPTY: Color = Color(0.35, 0.38, 0.45, 1.0)

# Nodes matching Scene Tree specification
@onready var order_panel: VBoxContainer = $OrderPanel
@onready var order_entry_template: HBoxContainer = $OrderPanel/OrderEntry

# Multiplayer carried items panel
@onready var carried_items_panel: HBoxContainer = get_node_or_null("CarriedItemsPanel") as HBoxContainer

# Backward compatibility references
@onready var carried_item_panel: HBoxContainer = get_node_or_null("CarriedItemPanel") as HBoxContainer
@onready var carried_item_icon: TextureRect = (
	get_node_or_null("CarriedItemPanel/ItemIcon") as TextureRect
	if has_node("CarriedItemPanel/ItemIcon")
	else null
)
@onready var carried_item_name: Label = (
	get_node_or_null("CarriedItemPanel/ItemName") as Label
	if has_node("CarriedItemPanel/ItemName")
	else null
)

@onready var score_panel: HBoxContainer = $ScorePanel
@onready var star_display: HBoxContainer = $ScorePanel/StarDisplay
@onready var score_label: Label = $ScorePanel/ScoreLabel
@onready var interaction_prompt: PanelContainer = $InteractionPrompt
@onready var prompt_label: Label = $InteractionPrompt/PromptLabel
@onready var repair_progress: VBoxContainer = $RepairProgress
@onready var state_label: Label = $RepairProgress/StateLabel

# Optional completion banner for star pop-in animation
@onready var completion_banner: PanelContainer = get_node_or_null("CompletionBanner") as PanelContainer
@onready var banner_label: Label = (
	get_node_or_null("CompletionBanner/BannerLabel") as Label
	if has_node("CompletionBanner/BannerLabel")
	else null
)

var _tracked_player: PlayerCharacter = null
var _tracked_players: Array[PlayerCharacter] = []
var _order_manager: OrderManager = null

# Active order UI entries: Order -> HBoxContainer
var _order_entries: Dictionary = {}
var _banner_tween: Tween = null
var current_score: int = 0
var current_stars: int = 0

# Contextual Interaction & Inspection UI Elements
var combo_display: Label = null
var _interaction_menus: Dictionary = {}
var _examination_panel: DeviceExaminationPanel = null
var _tool_durability_bars: Dictionary = {}


func _ready() -> void:
	add_to_group("hud")
	_connect_signal_bus()
	_setup_carry_slots()
	_setup_contextual_ui()
	_update_star_display(0)
	_update_score_display(0)
	_update_carried_item()
	_update_interaction_prompt()
	_update_repair_progress(null)

	# Auto-discover player(s) and order manager if not explicitly set via setup()
	_auto_discover_dependencies()


func _process(_delta: float) -> void:
	_clean_tracked_players()
	_update_interaction_prompt()
	_update_carried_item()
	_update_active_orders()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			visible = not visible
			hud_visibility_changed.emit(visible)
			if get_viewport():
				get_viewport().set_input_as_handled()


## Initializes HUD with specific player(s) and order manager instances
func setup(players_or_player: Variant = null, order_manager: OrderManager = null) -> void:
	if players_or_player is Array:
		var list: Array[PlayerCharacter] = []
		for p in players_or_player:
			if p is PlayerCharacter and is_instance_valid(p):
				list.append(p as PlayerCharacter)
		setup_multiplayer(list, order_manager)
	elif players_or_player is PlayerCharacter:
		setup_multiplayer([players_or_player as PlayerCharacter], order_manager)
	elif order_manager:
		_set_order_manager(order_manager)


## Setup with multiple players
func setup_multiplayer(players: Array[PlayerCharacter], order_manager: OrderManager = null) -> void:
	for p in _tracked_players:
		if is_instance_valid(p):
			_unbind_player_signals(p)

	_tracked_players.clear()
	for p in players:
		if p and is_instance_valid(p) and not _tracked_players.has(p):
			_tracked_players.append(p)
			_bind_player_signals(p)

	# Set first player as primary (for backward compatibility)
	if not _tracked_players.is_empty():
		_tracked_player = _tracked_players[0]
	else:
		_tracked_player = null

	if order_manager:
		_set_order_manager(order_manager)

	_setup_carry_slots()
	_update_carried_item()
	_update_interaction_prompt()


func set_tracked_players(players: Array[PlayerCharacter]) -> void:
	setup_multiplayer(players, _order_manager)


func add_tracked_player(player: PlayerCharacter) -> void:
	if not player or not is_instance_valid(player):
		return
	if _tracked_players.has(player):
		return
	_tracked_players.append(player)
	_bind_player_signals(player)
	if _tracked_player == null:
		_tracked_player = player
	_setup_carry_slots()
	_update_carried_item()
	_update_interaction_prompt()


func remove_tracked_player(player: PlayerCharacter) -> void:
	if not player:
		return
	if _tracked_players.has(player):
		_unbind_player_signals(player)
		_tracked_players.erase(player)
	if _tracked_player == player:
		_tracked_player = _tracked_players[0] if not _tracked_players.is_empty() else null
	_setup_carry_slots()
	_update_carried_item()
	_update_interaction_prompt()


func get_tracked_players() -> Array[PlayerCharacter]:
	_clean_tracked_players()
	return _tracked_players.duplicate()


## Sets and binds to a specific single PlayerCharacter (backward compatibility)
func _set_tracked_player(player: PlayerCharacter) -> void:
	if player:
		setup_multiplayer([player], _order_manager)
	else:
		for p in _tracked_players:
			if is_instance_valid(p):
				_unbind_player_signals(p)
		_tracked_players.clear()
		_tracked_player = null
		_setup_carry_slots()
		_update_carried_item()
		_update_interaction_prompt()


func _bind_player_signals(player: PlayerCharacter) -> void:
	if not player or not is_instance_valid(player):
		return
	if player.carry_system:
		if not player.carry_system.item_picked.is_connected(_on_any_item_picked):
			player.carry_system.item_picked.connect(_on_any_item_picked)
		if not player.carry_system.item_dropped.is_connected(_on_any_item_dropped):
			player.carry_system.item_dropped.connect(_on_any_item_dropped)
		if not player.carry_system.item_placed.is_connected(_on_any_item_placed):
			player.carry_system.item_placed.connect(_on_any_item_placed)


func _unbind_player_signals(player: PlayerCharacter) -> void:
	if not player or not is_instance_valid(player):
		return
	if player.carry_system:
		if player.carry_system.item_picked.is_connected(_on_any_item_picked):
			player.carry_system.item_picked.disconnect(_on_any_item_picked)
		if player.carry_system.item_dropped.is_connected(_on_any_item_dropped):
			player.carry_system.item_dropped.disconnect(_on_any_item_dropped)
		if player.carry_system.item_placed.is_connected(_on_any_item_placed):
			player.carry_system.item_placed.disconnect(_on_any_item_placed)
		if player.carry_system.item_picked.is_connected(_on_item_picked):
			player.carry_system.item_picked.disconnect(_on_item_picked)
		if player.carry_system.item_dropped.is_connected(_on_item_dropped):
			player.carry_system.item_dropped.disconnect(_on_item_dropped)
		if player.carry_system.item_placed.is_connected(_on_item_placed):
			player.carry_system.item_placed.disconnect(_on_item_placed)


func _clean_tracked_players() -> void:
	var removed: bool = false
	for i in range(_tracked_players.size() - 1, -1, -1):
		if not is_instance_valid(_tracked_players[i]):
			_tracked_players.remove_at(i)
			removed = true
	if _tracked_player and not is_instance_valid(_tracked_player):
		_tracked_player = _tracked_players[0] if not _tracked_players.is_empty() else null
		removed = true
	if removed:
		_setup_carry_slots()


## Sets and binds to a specific OrderManager
func _set_order_manager(mgr: OrderManager) -> void:
	if _order_manager == mgr:
		return

	if _order_manager and is_instance_valid(_order_manager):
		if _order_manager.order_spawned.is_connected(_on_order_spawned):
			_order_manager.order_spawned.disconnect(_on_order_spawned)
		if _order_manager.order_completed.is_connected(_on_order_completed):
			_order_manager.order_completed.disconnect(_on_order_completed)
		if _order_manager.order_expired.is_connected(_on_order_expired):
			_order_manager.order_expired.disconnect(_on_order_expired)

	_order_manager = mgr

	if _order_manager:
		_order_manager.order_spawned.connect(_on_order_spawned)
		_order_manager.order_completed.connect(_on_order_completed)
		_order_manager.order_expired.connect(_on_order_expired)

		# Populate existing active orders if any
		for order: Order in _order_manager.active_orders:
			_create_or_get_order_entry(order)

		_update_score_display(_order_manager.total_score)
		_update_star_display(_order_manager.total_stars)


## Connects global SignalBus events for loose coupling
func _connect_signal_bus() -> void:
	if not SignalBus:
		return

	SignalBus.player_joined.connect(_on_bus_player_joined)
	SignalBus.player_spawned.connect(_on_bus_player_spawned)
	SignalBus.player_left.connect(_on_bus_player_left)
	SignalBus.order_spawned.connect(_on_bus_order_spawned)
	SignalBus.order_completed.connect(_on_bus_order_completed)
	SignalBus.order_expired.connect(_on_bus_order_expired)
	SignalBus.item_picked_up.connect(_on_bus_item_picked_up)
	SignalBus.item_dropped.connect(_on_bus_item_dropped)
	SignalBus.device_state_changed.connect(_on_bus_device_state_changed)
	SignalBus.diagnosis_revealed.connect(_on_bus_diagnosis_revealed)
	SignalBus.interaction_prompt_changed.connect(_on_bus_prompt_changed)
	SignalBus.carried_item_changed.connect(_on_bus_carried_item_changed)
	SignalBus.combo_updated.connect(_on_bus_combo_updated)
	SignalBus.combo_broken.connect(_on_bus_combo_broken)
	SignalBus.tool_durability_changed.connect(_on_bus_tool_durability_changed)
	SignalBus.device_examined.connect(_on_bus_device_examined)


func _auto_discover_dependencies() -> void:
	var tree := get_tree()
	if not tree:
		return

	var players_in_tree: Array[Node] = tree.get_nodes_in_group("players")
	var found_players: Array[PlayerCharacter] = []
	for node: Node in players_in_tree:
		if node is PlayerCharacter and is_instance_valid(node) and not node.is_queued_for_deletion():
			found_players.append(node as PlayerCharacter)

	found_players.sort_custom(func(a: PlayerCharacter, b: PlayerCharacter) -> bool:
		return a.player_index < b.player_index
	)

	if not found_players.is_empty():
		var needs_update: bool = found_players.size() != _tracked_players.size()
		if not needs_update:
			for i in range(found_players.size()):
				if found_players[i] != _tracked_players[i]:
					needs_update = true
					break
		if needs_update:
			setup_multiplayer(found_players, _order_manager)

	if not _order_manager:
		var mgr: Node = tree.get_first_node_in_group("order_managers")
		if mgr is OrderManager:
			_set_order_manager(mgr as OrderManager)


## Configures slot visibility and colors based on tracked players
func _setup_carry_slots() -> void:
	if not carried_items_panel:
		return

	var count: int = _tracked_players.size()
	for i in range(Constants.MAX_PLAYERS):
		var slot_name: String = "P%dCarrySlot" % (i + 1)
		var slot: Control = carried_items_panel.get_node_or_null(slot_name) as Control
		if not slot:
			continue

		var is_active: bool = (i < count)
		slot.visible = is_active

		if is_active:
			var player: PlayerCharacter = _tracked_players[i]
			var player_color: Color = (
				player.get_player_color()
				if player.has_method("get_player_color")
				else (
					Constants.PLAYER_COLORS[player.player_index % Constants.PLAYER_COLORS.size()]
					if not Constants.PLAYER_COLORS.is_empty()
					else Color.WHITE
				)
			)
			var tag_label: Label = slot.get_node_or_null("PlayerTag") as Label
			if not tag_label:
				tag_label = slot.find_child("PlayerTag", true, false) as Label
			if tag_label:
				tag_label.text = "● P%d" % (player.player_index + 1)
				tag_label.modulate = player_color


## Updates contextual interaction prompt text and visibility
func _update_interaction_prompt() -> void:
	if not interaction_prompt or not prompt_label:
		return

	var candidates: Array[PlayerCharacter] = []
	if not _tracked_players.is_empty():
		candidates = _tracked_players
	elif _tracked_player and is_instance_valid(_tracked_player):
		candidates = [_tracked_player]

	if candidates.is_empty():
		interaction_prompt.visible = false
		prompt_label.text = ""
		return

	# First check if any tracked player is waiting for a co-carry partner
	for player in candidates:
		if not player or not is_instance_valid(player) or not player.carry_system:
			continue
		if player.carry_system.is_carry_requested():
			prompt_label.text = "Waiting for second player... (Press [Drop] to cancel)"
			interaction_prompt.visible = true
			return

	var best_player: PlayerCharacter = null
	var best_focus: Interactable = null
	var min_distance: float = INF

	for player in candidates:
		if not player or not is_instance_valid(player) or not player.interaction_system:
			continue
		var focus: Interactable = player.interaction_system.get_current_focus()
		if focus and is_instance_valid(focus):
			var dist: float = 0.0
			if focus is Node3D:
				dist = player.global_position.distance_to((focus as Node3D).global_position)
			elif focus.get_parent() is Node3D:
				dist = player.global_position.distance_to((focus.get_parent() as Node3D).global_position)
			if dist < min_distance:
				min_distance = dist
				best_player = player
				best_focus = focus

	if not best_player or not best_focus:
		# Check if any candidate is currently carrying a heavy device alone
		for player in candidates:
			if not player or not is_instance_valid(player) or not player.carry_system:
				continue
			if player.carry_system.is_solo_heavy_carrying():
				var flash: float = sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
				prompt_label.text = "⚠️ Carrying alone — very slow!"
				prompt_label.modulate = Color(1.0, 0.3 + 0.7 * flash, 0.3 + 0.7 * flash)
				interaction_prompt.visible = true
				return
		prompt_label.modulate = Color.WHITE
		interaction_prompt.visible = false
		prompt_label.text = ""
		return

	var prompt_text: String = best_focus.get_prompt_text(best_player)
	if prompt_text.is_empty():
		for player in candidates:
			if not player or not is_instance_valid(player) or not player.carry_system:
				continue
			if player.carry_system.is_solo_heavy_carrying():
				var flash: float = sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
				prompt_label.text = "⚠️ Carrying alone — very slow!"
				prompt_label.modulate = Color(1.0, 0.3 + 0.7 * flash, 0.3 + 0.7 * flash)
				interaction_prompt.visible = true
				return
		prompt_label.modulate = Color.WHITE
		interaction_prompt.visible = false
		prompt_label.text = ""
	elif not best_focus.can_interact(best_player):
		prompt_label.modulate = Color.WHITE
		prompt_label.text = prompt_text
		interaction_prompt.visible = true
	elif prompt_text.begins_with("Press "):
		prompt_label.text = prompt_text
		interaction_prompt.visible = true
	else:
		var action_prompt: String = MultiplayerInput.get_player_action_prompt(
			best_player.player_index, MultiplayerInput.BASE_INTERACT
		)
		prompt_label.text = "Press %s to %s" % [action_prompt, prompt_text]
		interaction_prompt.visible = true


## Updates carried item label and repair progress indicator
func _update_carried_item() -> void:
	_update_all_carried_items()

	var primary_player: PlayerCharacter = (
		_tracked_player
		if (_tracked_player and is_instance_valid(_tracked_player))
		else (_tracked_players[0] if not _tracked_players.is_empty() else null)
	)

	var primary_device: Device = null
	if primary_player and primary_player.carry_system and primary_player.carry_system.is_carrying():
		var item: Carriable = primary_player.carry_system.get_held_item()
		if item and is_instance_valid(item):
			var display_text: String = item.item_name
			if item is Device:
				var dev := item as Device
				primary_device = dev
				display_text += " [%s]" % dev.get_repair_state()
				if dev.is_diagnosed and dev.assigned_fault:
					if dev.assigned_fault.is_multi_fault:
						var tag_list: String = ", ".join(dev.assigned_fault.fault_display_tags) if not dev.assigned_fault.fault_display_tags.is_empty() else dev.assigned_fault.fault_name
						display_text += " (%s - Needs: %s)" % [dev.assigned_fault.fault_name, tag_list]
					else:
						display_text += " (%s)" % dev.assigned_fault.fault_name
			if carried_item_name:
				carried_item_name.text = display_text
			if carried_item_panel:
				carried_item_panel.visible = (_tracked_players.size() <= 1 and not carried_items_panel)
	else:
		if carried_item_name:
			carried_item_name.text = "—"

	var active_dev: Device = primary_device
	if not active_dev:
		for player in _tracked_players:
			if player and is_instance_valid(player) and player.carry_system and player.carry_system.is_carrying():
				var held := player.carry_system.get_held_item()
				if held is Device:
					active_dev = held as Device
					break
	_update_repair_progress(active_dev)


## Updates carried items for all active player slots
func _update_all_carried_items() -> void:
	if not carried_items_panel:
		return

	for i in range(Constants.MAX_PLAYERS):
		var slot_name: String = "P%dCarrySlot" % (i + 1)
		var slot: Control = carried_items_panel.get_node_or_null(slot_name) as Control
		if not slot:
			continue

		if i >= _tracked_players.size():
			slot.visible = false
			continue

		slot.visible = true
		var player: PlayerCharacter = _tracked_players[i]
		if not player or not is_instance_valid(player):
			continue

		var item_label: Label = slot.get_node_or_null("ItemName") as Label
		if not item_label:
			item_label = slot.find_child("ItemName", true, false) as Label
		if not item_label:
			continue

		if player.carry_system and player.carry_system.is_carrying():
			var item: Carriable = player.carry_system.get_held_item()
			if item and is_instance_valid(item):
				var text: String = item.item_name
				if item is Device:
					var dev := item as Device
					text += " [%s]" % dev.get_repair_state()
					if dev.is_diagnosed and dev.assigned_fault:
						if dev.assigned_fault.is_multi_fault:
							var tag_list: String = ", ".join(dev.assigned_fault.fault_display_tags) if not dev.assigned_fault.fault_display_tags.is_empty() else dev.assigned_fault.fault_name
							text += " (%s - Needs: %s)" % [dev.assigned_fault.fault_name, tag_list]
						else:
							text += " (%s)" % dev.assigned_fault.fault_name
				item_label.text = text
			else:
				item_label.text = "—"
		else:
			item_label.text = "—"


## Updates repair progress label based on carried or active device
func _update_repair_progress(device: Device) -> void:
	if not state_label:
		return

	if device and is_instance_valid(device):
		var state_text: String = "Current Device: %s [%s]" % [
			device.item_name,
			device.get_repair_state()
		]
		if device.device_data and device.device_data.carry_requires_two_players and device.is_held and not device.co_carrier_b:
			state_text += " - ⚠️ Carrying alone!"
		state_label.text = state_text
	elif _order_manager and _order_manager.has_active_orders():
		var active_order: Order = _order_manager.get_first_active_order()
		if active_order and active_order.device_instance and is_instance_valid(active_order.device_instance):
			state_label.text = "Order Device: %s [%s]" % [
				active_order.get_device_name(),
				active_order.device_instance.get_repair_state()
			]
		else:
			state_label.text = "Pipeline: RECEIVED → DIAGNOSED → REPAIR → DELIVER"
	else:
		state_label.text = "Pipeline: RECEIVED → DIAGNOSED → REPAIR → DELIVER"


## Updates order list, progress bars, and timer colors each frame
func _update_active_orders() -> void:
	if not _order_manager:
		# If no OrderManager node, clean up stale entries if order list exists
		if _order_entries.is_empty() and order_entry_template:
			order_entry_template.visible = false
		return

	# Remove entries for orders that are no longer active
	var active_list: Array[Order] = _order_manager.active_orders
	var to_remove: Array[Order] = []
	for order in _order_entries.keys():
		if not (order in active_list) or not is_instance_valid(order):
			to_remove.append(order)

	for order in to_remove:
		_remove_order_entry(order)

	# Ensure all active orders have a row
	for order in active_list:
		if not _order_entries.has(order):
			_create_or_get_order_entry(order)

	# Update existing order rows
	for order in active_list:
		var entry: HBoxContainer = _order_entries.get(order) as HBoxContainer
		if entry and is_instance_valid(entry):
			_update_order_row(entry, order)


func _update_order_row(entry: HBoxContainer, order: Order) -> void:
	var icon: TextureRect = entry.get_node_or_null("DeviceIcon") as TextureRect
	var tier_label: Label = entry.get_node_or_null("TierLabel") as Label
	var name_label: Label = entry.get_node_or_null("DeviceName") as Label
	var timer_bar: ProgressBar = entry.get_node_or_null("TimerBar") as ProgressBar

	if icon:
		if order.device_data and order.device_data.device_color:
			icon.modulate = order.device_data.device_color
		else:
			icon.modulate = Color.WHITE

	if not tier_label:
		tier_label = Label.new()
		tier_label.name = "TierLabel"
		tier_label.custom_minimum_size = Vector2(24, 0)
		tier_label.theme_override_font_sizes = {"font_size": 14}
		tier_label.theme_override_colors = {"font_color": Color(1.0, 0.85, 0.2)}
		tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		entry.add_child(tier_label)
		entry.move_child(tier_label, 1)

	if tier_label:
		if order.device_data:
			var tier: int = clampi(order.device_data.difficulty_tier, 1, 4)
			tier_label.text = "★".repeat(tier)
			tier_label.visible = true
		else:
			tier_label.visible = false

	if name_label:
		var dev_name: String = order.get_device_name()
		if order.device_instance and is_instance_valid(order.device_instance):
			if order.device_instance.is_diagnosed and order.assigned_fault:
				if order.assigned_fault.is_multi_fault:
					var tag_str := ""
					if not order.assigned_fault.fault_display_tags.is_empty():
						var tags: PackedStringArray = []
						for t in order.assigned_fault.fault_display_tags:
							tags.append(t.capitalize())
						tag_str = " + ".join(tags)
					else:
						var comp_names: PackedStringArray = []
						for c in order.assigned_fault.get_required_components():
							if c:
								comp_names.append(c.component_name)
						tag_str = " + ".join(comp_names) if not comp_names.is_empty() else order.assigned_fault.fault_name
					dev_name += " (%s - Needs: %s)" % [order.assigned_fault.fault_name, tag_str]
				else:
					dev_name += " (%s)" % order.assigned_fault.fault_name
			dev_name += " [%s]" % order.device_instance.get_repair_state()
		if order.is_priority:
			dev_name = "⚡ " + dev_name
		name_label.text = dev_name

	var ratio: float = order.get_time_ratio()
	if ratio < 0.3:
		# Device Priority Glow (<30% time remaining causes order entry to pulse red)
		var pulse: float = (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
		entry.modulate = Color(1.0, 0.35 + 0.65 * (1.0 - pulse), 0.35 + 0.65 * (1.0 - pulse))
	elif order.is_priority:
		# Priority styling: red-orange tint for visual urgency
		entry.modulate = Color(1.0, 0.7, 0.3)
	else:
		entry.modulate = Color.WHITE

	if timer_bar:
		timer_bar.max_value = order.time_limit
		timer_bar.value = order.time_remaining

		# Color change based on urgency: >50% green, 20-50% yellow, 10-20% red, <10% flashing red
		ratio = order.get_time_ratio()
		if ratio >= 0.5:
			timer_bar.modulate = COLOR_TIMER_HEALTHY
		elif ratio >= 0.2:
			timer_bar.modulate = COLOR_TIMER_WARNING
		elif ratio >= 0.1:
			timer_bar.modulate = COLOR_TIMER_CRITICAL
		else:
			# Flashing red for critical urgency (<10%)
			var flash: float = sin(Time.get_ticks_msec() * 0.01) * 0.5 + 0.5
			timer_bar.modulate = Color(1.0, flash * 0.3, flash * 0.2)


func _create_or_get_order_entry(order: Order) -> HBoxContainer:
	if _order_entries.has(order):
		return _order_entries[order]

	var entry: HBoxContainer = null
	if _order_entries.is_empty() and order_entry_template:
		# Use the pre-existing template node for the first order
		entry = order_entry_template
		entry.visible = true
	elif order_entry_template:
		# Duplicate template for subsequent orders
		entry = order_entry_template.duplicate() as HBoxContainer
		order_panel.add_child(entry)
		entry.visible = true

	if entry:
		_order_entries[order] = entry
		_update_order_row(entry, order)

	return entry


func _remove_order_entry(order: Order) -> void:
	if not _order_entries.has(order):
		return

	var entry: HBoxContainer = _order_entries[order]
	_order_entries.erase(order)

	if entry == order_entry_template:
		entry.visible = false
	elif is_instance_valid(entry):
		entry.queue_free()


## Updates score display label
func _update_score_display(score: int) -> void:
	current_score = score
	if score_label:
		score_label.text = "Score: %d" % score


## Updates star display container
func _update_star_display(stars: int) -> void:
	current_stars = stars
	if not star_display:
		return

	# If individual Star1, Star2, Star3 nodes exist, color them
	var star1: Label = star_display.get_node_or_null("Star1") as Label
	var star2: Label = star_display.get_node_or_null("Star2") as Label
	var star3: Label = star_display.get_node_or_null("Star3") as Label
	var star_count: Label = star_display.get_node_or_null("StarCount") as Label

	if star1:
		star1.modulate = COLOR_STAR_EARNED if stars >= 1 else COLOR_STAR_EMPTY
	if star2:
		star2.modulate = COLOR_STAR_EARNED if stars >= 2 else COLOR_STAR_EMPTY
	if star3:
		star3.modulate = COLOR_STAR_EARNED if stars >= 3 else COLOR_STAR_EMPTY

	if star_count:
		star_count.text = "★ %d" % stars
		star_count.visible = stars > 3


## Shows order completion pop-in animation banner
func show_order_completed_animation(stars: int, score: int) -> void:
	if not completion_banner or not banner_label:
		return

	var stars_text: String = ""
	for i in range(stars):
		stars_text += "★ "

	banner_label.text = "REPAIR COMPLETE!\n%s\n+%d PTS" % [stars_text.strip_edges(), score]
	completion_banner.visible = true
	completion_banner.modulate = Color(1.0, 1.0, 1.0, 1.0)
	completion_banner.scale = Vector2(0.8, 0.8)

	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(completion_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fade_tween := create_tween()
	fade_tween.tween_interval(1.8)
	fade_tween.tween_property(completion_banner, "modulate:a", 0.0, 0.4)
	fade_tween.tween_callback(func() -> void:
		completion_banner.visible = false
	)


# Signal Handlers
func _on_any_item_picked(_item: Carriable) -> void:
	_update_carried_item()


func _on_any_item_dropped(_item: Carriable) -> void:
	_update_carried_item()


func _on_any_item_placed(_item: Carriable, _station: Node) -> void:
	_update_carried_item()


func _on_item_picked(_item: Carriable) -> void:
	_update_carried_item()


func _on_item_dropped(_item: Carriable) -> void:
	_update_carried_item()


func _on_item_placed(_item: Carriable, _station: Node) -> void:
	_update_carried_item()


func _on_order_spawned(order: Order) -> void:
	_create_or_get_order_entry(order)


func _on_order_completed(order: Order, stars: int, score: int) -> void:
	_remove_order_entry(order)
	if _order_manager:
		_update_score_display(_order_manager.total_score)
		_update_star_display(_order_manager.total_stars)
	else:
		_update_score_display(current_score + score)
		_update_star_display(current_stars + stars)

	show_order_completed_animation(stars, score)


func _on_order_expired(order: Order) -> void:
	_remove_order_entry(order)


func _on_bus_player_joined(_player_id: int) -> void:
	_auto_discover_dependencies()


func _on_bus_player_spawned(_player_id: int, player: Node) -> void:
	if player is PlayerCharacter and is_instance_valid(player):
		add_tracked_player(player as PlayerCharacter)
	else:
		_auto_discover_dependencies()



func _on_bus_player_left(player_id: int) -> void:
	for i in range(_tracked_players.size() - 1, -1, -1):
		var p: PlayerCharacter = _tracked_players[i]
		if is_instance_valid(p) and p.player_index == player_id:
			remove_tracked_player(p)
			break


func _on_bus_order_spawned(_order_id: String, _device_type: String) -> void:
	if not _order_manager:
		_auto_discover_dependencies()


func _on_bus_order_completed(_order_id: String, score: int, stars: int) -> void:
	if _order_manager:
		_update_score_display(_order_manager.total_score)
		_update_star_display(_order_manager.total_stars)
	else:
		_update_score_display(current_score + score)
		_update_star_display(current_stars + stars)
	show_order_completed_animation(stars, score)


func _on_bus_order_expired(_order_id: String) -> void:
	pass


func _on_bus_item_picked_up(_item_name: String, _player_id: int) -> void:
	_update_carried_item()


func _on_bus_item_dropped(_item_name: String, _player_id: int) -> void:
	_update_carried_item()


func _on_bus_device_state_changed(_device_name: String, _old_state: String, _new_state: String) -> void:
	_update_carried_item()


func _on_bus_diagnosis_revealed(_device_name: String, _fault_name: String) -> void:
	_update_carried_item()
	_update_active_orders()


func _on_bus_prompt_changed(text: String) -> void:
	if interaction_prompt and prompt_label:
		if not text.is_empty():
			prompt_label.text = text
			interaction_prompt.visible = true
		else:
			interaction_prompt.visible = false


func _on_bus_carried_item_changed(item_name: String) -> void:
	if carried_item_name:
		carried_item_name.text = item_name if not item_name.is_empty() else "—"


func _setup_contextual_ui() -> void:
	if score_panel and not combo_display:
		combo_display = Label.new()
		combo_display.name = "ComboDisplay"
		combo_display.add_theme_font_size_override("font_size", 16)
		combo_display.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		combo_display.visible = false
		score_panel.add_child(combo_display)


func _on_bus_combo_updated(multiplier: float, streak: int) -> void:
	if combo_display:
		if multiplier > 1.0 and streak > 0:
			combo_display.visible = true
			combo_display.text = "🔥 ×%.1f (%d)" % [multiplier, streak]
			# Pop animation
			var tween := create_tween()
			combo_display.scale = Vector2(1.25, 1.25)
			tween.tween_property(combo_display, "scale", Vector2.ONE, 0.2)
		else:
			combo_display.visible = false


func _on_bus_combo_broken() -> void:
	if combo_display:
		combo_display.visible = false


func _on_bus_tool_durability_changed(tool_id: String, current: int, max_val: int) -> void:
	# Update durability display if tracked
	if _tool_durability_bars.has(tool_id):
		var bar: ProgressBar = _tool_durability_bars[tool_id] as ProgressBar
		if bar and is_instance_valid(bar):
			bar.max_value = max_val
			bar.value = current


var _active_minigame: RepairMinigame = null


func start_repair_minigame(player: PlayerCharacter, device: Device, _minigame_type: String = "screw", on_complete: Callable = Callable(), on_fail: Callable = Callable()) -> void:
	if _active_minigame and is_instance_valid(_active_minigame):
		_active_minigame.queue_free()
		_active_minigame = null

	var minigame_scene: PackedScene = load("res://scenes/ui/RepairMinigame.tscn")
	if not minigame_scene:
		if on_complete.is_valid():
			on_complete.call()
		return

	var mg := minigame_scene.instantiate() as RepairMinigame
	_active_minigame = mg
	add_child(mg)

	mg.minigame_completed.connect(func(_rating: int) -> void:
		_active_minigame = null
		mg.queue_free()
		if player and is_instance_valid(player):
			player.set_movement_locked(false)
		if on_complete.is_valid():
			on_complete.call()
	)

	mg.minigame_skipped.connect(func() -> void:
		_active_minigame = null
		mg.queue_free()
		if player and is_instance_valid(player):
			player.set_movement_locked(false)
		if on_complete.is_valid():
			on_complete.call()
	)

	mg.minigame_failed.connect(func() -> void:
		_active_minigame = null
		mg.queue_free()
		if player and is_instance_valid(player):
			player.set_movement_locked(false)
		if on_fail.is_valid():
			on_fail.call()
	)

	mg.start_minigame(player, device, device.assigned_fault if device else null)


func _setup_world_labels_for_stations() -> void:
	var tree := get_tree()
	if not tree:
		return
	var stations: Array[Node] = tree.get_nodes_in_group("stations")
	for s in stations:
		if s is BaseStation and s.has_method("setup_world_label"):
			var wl: WorldLabel = s.setup_world_label()
			if wl and not wl.is_inside_tree():
				add_child(wl)


func _on_bus_device_examined(player_id: int, _device_name: String) -> void:
	if _examination_panel and _examination_panel.is_open():
		return

	var player: PlayerCharacter = null
	for p in _tracked_players:
		if is_instance_valid(p) and p.player_index == player_id:
			player = p
			break
	if not player and not _tracked_players.is_empty():
		player = _tracked_players[0]

	if player and player.carry_system and player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held is Device:
			open_examination_panel(player, held as Device)


func get_interaction_menu_for_player(player_idx: int = 0) -> InteractionMenu:
	if _interaction_menus.has(player_idx) and is_instance_valid(_interaction_menus[player_idx]):
		return _interaction_menus[player_idx]

	var menu_scene: PackedScene = load("res://scenes/ui/InteractionMenu.tscn")
	if menu_scene:
		var menu := menu_scene.instantiate() as InteractionMenu
		menu.name = "InteractionMenu_P%d" % player_idx
		menu.owning_player_index = player_idx
		add_child(menu)
		menu.position = Vector2(1380, 280)
		_interaction_menus[player_idx] = menu
		return menu
	return null


func open_examination_panel(player: PlayerCharacter, device: Device, station: BaseStation = null) -> void:
	if not _examination_panel or not is_instance_valid(_examination_panel):
		var panel_scene: PackedScene = load("res://scenes/ui/DeviceExaminationPanel.tscn")
		if panel_scene:
			_examination_panel = panel_scene.instantiate() as DeviceExaminationPanel
			add_child(_examination_panel)
	if _examination_panel:
		_examination_panel.open_panel(player, device, station)


var _hazard_panel: HazardResolutionPanel = null

func open_hazard_minigame(player: PlayerCharacter, hazard: BaseHazard) -> void:
	if not _hazard_panel or not is_instance_valid(_hazard_panel):
		var panel_scene: PackedScene = load("res://scenes/ui/HazardResolutionPanel.tscn")
		if panel_scene:
			_hazard_panel = panel_scene.instantiate() as HazardResolutionPanel
			add_child(_hazard_panel)
	if _hazard_panel:
		_hazard_panel.open_hazard_panel(player, hazard)


var _parts_shelf_panel: PartsShelfPanel = null

func open_parts_shelf_panel(player: PlayerCharacter, shelf: PartsShelf) -> void:
	if not _parts_shelf_panel or not is_instance_valid(_parts_shelf_panel):
		var panel_scene: PackedScene = load("res://scenes/ui/PartsShelfPanel.tscn")
		if panel_scene:
			_parts_shelf_panel = panel_scene.instantiate() as PartsShelfPanel
			add_child(_parts_shelf_panel)
	if _parts_shelf_panel:
		_parts_shelf_panel.open_shelf_panel(player, shelf)
