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

# Nodes matching Phase 1G Scene Tree specification
@onready var order_panel: VBoxContainer = $OrderPanel
@onready var order_entry_template: HBoxContainer = $OrderPanel/OrderEntry
@onready var carried_item_panel: HBoxContainer = $CarriedItemPanel
@onready var carried_item_icon: TextureRect = $CarriedItemPanel/ItemIcon
@onready var carried_item_name: Label = $CarriedItemPanel/ItemName
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
var _order_manager: OrderManager = null

# Active order UI entries: Order -> HBoxContainer
var _order_entries: Dictionary = {}
var _banner_tween: Tween = null
var current_score: int = 0
var current_stars: int = 0


func _ready() -> void:
	_connect_signal_bus()
	_update_star_display(0)
	_update_score_display(0)
	_update_carried_item()
	_update_interaction_prompt()
	_update_repair_progress(null)

	# Auto-discover player and order manager if not explicitly set via setup()
	_auto_discover_dependencies()


func _process(_delta: float) -> void:
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


## Initializes HUD with specific player and order manager instances
func setup(player: PlayerCharacter = null, order_manager: OrderManager = null) -> void:
	if player:
		_set_tracked_player(player)

	if order_manager:
		_set_order_manager(order_manager)


## Sets and binds to a specific PlayerCharacter
func _set_tracked_player(player: PlayerCharacter) -> void:
	if _tracked_player == player:
		return

	if _tracked_player and is_instance_valid(_tracked_player):
		if _tracked_player.carry_system:
			if _tracked_player.carry_system.item_picked.is_connected(_on_item_picked):
				_tracked_player.carry_system.item_picked.disconnect(_on_item_picked)
			if _tracked_player.carry_system.item_dropped.is_connected(_on_item_dropped):
				_tracked_player.carry_system.item_dropped.disconnect(_on_item_dropped)
			if _tracked_player.carry_system.item_placed.is_connected(_on_item_placed):
				_tracked_player.carry_system.item_placed.disconnect(_on_item_placed)

	_tracked_player = player

	if _tracked_player and _tracked_player.carry_system:
		_tracked_player.carry_system.item_picked.connect(_on_item_picked)
		_tracked_player.carry_system.item_dropped.connect(_on_item_dropped)
		_tracked_player.carry_system.item_placed.connect(_on_item_placed)

	_update_carried_item()
	_update_interaction_prompt()


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
	if not _tracked_player:
		var tree := get_tree()
		if tree:
			var players: Array[Node] = tree.get_nodes_in_group("players")
			for node: Node in players:
				if node is PlayerCharacter and is_instance_valid(node):
					_set_tracked_player(node as PlayerCharacter)
					break

	if not _order_manager:
		var tree := get_tree()
		if tree:
			var mgr: Node = tree.get_first_node_in_group("order_managers")
			if mgr is OrderManager:
				_set_order_manager(mgr as OrderManager)


## Updates contextual interaction prompt text and visibility
func _update_interaction_prompt() -> void:
	if not interaction_prompt or not prompt_label:
		return

	if not _tracked_player or not _tracked_player.interaction_system:
		interaction_prompt.visible = false
		prompt_label.text = ""
		return

	var focus: Interactable = _tracked_player.interaction_system.get_current_focus()
	if focus and focus.can_interact(_tracked_player):
		var action_name: String = InputHelper.get_action_prompt(InputHelper.ACTION_INTERACT)
		var prompt_text: String = focus.get_prompt_text(_tracked_player)

		if prompt_text.begins_with("Press "):
			prompt_label.text = prompt_text
		elif prompt_text.is_empty():
			prompt_label.text = "Press %s to interact" % action_name
		else:
			prompt_label.text = "Press %s to %s" % [action_name, prompt_text]

		interaction_prompt.visible = true
	else:
		interaction_prompt.visible = false
		prompt_label.text = ""


## Updates carried item label and repair progress indicator
func _update_carried_item() -> void:
	if not carried_item_name:
		return

	if _tracked_player and _tracked_player.carry_system and _tracked_player.carry_system.is_carrying():
		var item: Carriable = _tracked_player.carry_system.get_held_item()
		if item and is_instance_valid(item):
			var display_text: String = item.item_name
			if item is Device:
				var dev := item as Device
				display_text += " [%s]" % dev.get_repair_state()
				if dev.is_diagnosed and dev.assigned_fault:
					display_text += " (%s)" % dev.assigned_fault.fault_name
				_update_repair_progress(dev)
			else:
				_update_repair_progress(null)

			carried_item_name.text = display_text
			if carried_item_panel:
				carried_item_panel.visible = true
			return

	carried_item_name.text = "—"
	_update_repair_progress(null)


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


func _on_bus_player_joined(player_id: int) -> void:
	if not _tracked_player and player_id == 0:
		_auto_discover_dependencies()


func _on_bus_order_spawned(_order_id: String, _device_type: String) -> void:
	if not _order_manager:
		_auto_discover_dependencies()


func _on_bus_order_completed(_order_id: String, score: int, stars: int) -> void:
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
