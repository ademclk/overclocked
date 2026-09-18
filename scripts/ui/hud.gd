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

# Nodes matching Phase 1G & 2G Scene Tree specification
@onready var order_panel: VBoxContainer = $OrderPanel
@onready var order_entry_template: HBoxContainer = $OrderPanel/OrderEntry

# Multiplayer carried items panel
@onready var carried_items_panel: HBoxContainer = get_node_or_null("CarriedItemsPanel") as HBoxContainer

# Backward compatibility references for Phase 1
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


func _ready() -> void:
	_connect_signal_bus()
	_setup_carry_slots()
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
		interaction_prompt.visible = false
		prompt_label.text = ""
		return

	var prompt_text: String = best_focus.get_prompt_text(best_player)
	if prompt_text.is_empty():
		interaction_prompt.visible = false
		prompt_label.text = ""
	elif not best_focus.can_interact(best_player):
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
		state_label.text = "Current Device: %s [%s]" % [
			device.item_name,
			device.get_repair_state()
		]
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
	var name_label: Label = entry.get_node_or_null("DeviceName") as Label
	var timer_bar: ProgressBar = entry.get_node_or_null("TimerBar") as ProgressBar

	if name_label:
		var dev_name: String = order.get_device_name()
		if order.device_instance and is_instance_valid(order.device_instance):
			if order.device_instance.is_diagnosed and order.assigned_fault:
				dev_name += " (%s)" % order.assigned_fault.fault_name
			dev_name += " [%s]" % order.device_instance.get_repair_state()
		name_label.text = dev_name

	if timer_bar:
		timer_bar.max_value = order.time_limit
		timer_bar.value = order.time_remaining

		# Color change based on urgency: >50% green, 20-50% yellow, <20% red
		var ratio: float = order.get_time_ratio()
		if ratio >= 0.5:
			timer_bar.modulate = COLOR_TIMER_HEALTHY
		elif ratio >= 0.2:
			timer_bar.modulate = COLOR_TIMER_WARNING
		else:
			timer_bar.modulate = COLOR_TIMER_CRITICAL


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
