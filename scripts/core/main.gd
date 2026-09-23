class_name Main
extends Node3D

## Main orchestrator scene for Overclocked.
## Owns the camera rig, manages workshop level instancing, and hosts the UI layer.

const DEFAULT_WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/Workshop_Debug.tscn")

@export var default_level: PackedScene = DEFAULT_WORKSHOP_SCENE
@export var debug_overlay_visible: bool = true
@export var show_lobby: bool = false
@export var lobby_scene: PackedScene = preload("res://scenes/ui/LobbyScreen.tscn")

var current_level: Node = null
var lobby_screen: LobbyScreen = null

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var camera_rig: CameraRig = $CameraRig
@onready var ui: CanvasLayer = $UI
@onready var debug_label: Label = $UI/DebugLabel
@onready var hud: HUD = $UI.get_node_or_null("HUD") as HUD


func _ready() -> void:
	if has_node("Workshop"):
		current_level = get_node("Workshop")
	elif default_level:
		load_level(default_level)

	if show_lobby:
		open_lobby()
	else:
		if GameManager.current_state == GameState.State.MENU:
			GameManager.change_state(GameState.State.PLAYING)

	_setup_camera()
	_setup_hud()
	_update_debug_label()


func open_lobby() -> void:
	if lobby_screen:
		lobby_screen.visible = true
		GameManager.change_state(GameState.State.MENU)
		return
	if lobby_scene and ui:
		lobby_screen = lobby_scene.instantiate() as LobbyScreen
		ui.add_child(lobby_screen)
		lobby_screen.all_players_ready.connect(_on_lobby_all_players_ready)
		lobby_screen.lobby_cancelled.connect(_on_lobby_cancelled)
		GameManager.change_state(GameState.State.MENU)


func _on_lobby_all_players_ready(player_count: int, _device_assignments: Dictionary) -> void:
	if lobby_screen:
		lobby_screen.visible = false
	if current_level:
		if current_level.has_method("despawn_all_players") and current_level.has_method("spawn_player"):
			current_level.call("despawn_all_players")
			for i in range(player_count):
				current_level.call("spawn_player", i)
	_setup_camera()
	_setup_hud()
	GameManager.change_state(GameState.State.PLAYING)


func _on_lobby_cancelled() -> void:
	if lobby_screen:
		lobby_screen.visible = false
	if GameManager.current_state == GameState.State.MENU:
		GameManager.change_state(GameState.State.PLAYING)


func _process(_delta: float) -> void:
	if debug_overlay_visible and debug_label:
		_update_debug_label()


func _update_debug_label() -> void:
	var state_name: String = GameState.to_string_name(GameManager.current_state)
	var fps: int = Engine.get_frames_per_second()

	var order_info: String = "None"
	var device_state_info: String = "None"
	var carried_info: String = "Empty"

	if current_level:
		var order_mgr: OrderManager = null
		if "order_manager" in current_level and current_level.order_manager:
			order_mgr = current_level.order_manager
		elif current_level.has_node("OrderManager"):
			order_mgr = current_level.get_node("OrderManager") as OrderManager

		if order_mgr and order_mgr.has_active_orders():
			var ord: Order = order_mgr.get_first_active_order()
			order_info = "%s (%.0fs)" % [ord.get_device_name(), ord.time_remaining]
			if ord.device_instance:
				device_state_info = ord.device_instance.get_repair_state()
				if ord.device_instance.is_diagnosed and ord.assigned_fault:
					device_state_info += " (%s)" % ord.assigned_fault.fault_name

		var player: PlayerCharacter = null
		if current_level.has_method("get_player"):
			player = current_level.call("get_player", 0)
		elif current_level.has_node("Entities/PlayerCharacter"):
			player = current_level.get_node("Entities/PlayerCharacter") as PlayerCharacter
		elif current_level.has_node("PlayerCharacter"):
			player = current_level.get_node("PlayerCharacter") as PlayerCharacter

		if player and player.carry_system and player.carry_system.is_carrying():
			var item: Carriable = player.carry_system.get_held_item()
			if item:
				carried_info = item.item_name
				if item is Device:
					carried_info += " [%s]" % item.get_repair_state()

	debug_label.text = "Overclocked | State: %s | FPS: %d\nOrder: %s | Device: %s | Carried: %s" % [
		state_name, fps, order_info, device_state_info, carried_info
	]


## Loads a new workshop level scene as a child node, replacing any existing level
func load_level(level_scene: PackedScene) -> void:
	if current_level:
		if current_level.get_parent() == self:
			remove_child(current_level)
		current_level.queue_free()
		current_level = null

	if level_scene:
		current_level = level_scene.instantiate()
		current_level.name = "Workshop"
		add_child(current_level)
		_setup_camera()
		_setup_hud()
		SignalBus.level_loaded.emit(String(current_level.name))


## Reloads the default level and signals level restart
func reload_level() -> void:
	var level_scene: PackedScene = (
		default_level if default_level != null else DEFAULT_WORKSHOP_SCENE
	)
	load_level(level_scene)
	SignalBus.level_restarted.emit()


## Frames the camera on the active level bounds if available
func _setup_camera() -> void:
	if not camera_rig:
		return

	camera_rig.make_current()

	if current_level and current_level.has_method("get_room_bounds"):
		var bounds: AABB = current_level.call("get_room_bounds")
		camera_rig.frame_bounds(bounds.position, bounds.position + bounds.size)
		camera_rig.set_room_bounds(bounds)

	if current_level and current_level.has_method("get_active_players"):
		camera_rig.set_tracked_players(current_level.call("get_active_players"))
		camera_rig.snap_to_target()


func _setup_hud() -> void:
	if not hud:
		return
	var players: Array[PlayerCharacter] = []
	var order_mgr: OrderManager = null
	if current_level:
		if current_level.has_method("get_active_players"):
			var active: Array = current_level.call("get_active_players")
			for p in active:
				if p is PlayerCharacter and is_instance_valid(p):
					players.append(p as PlayerCharacter)
		elif current_level.has_method("get_player"):
			var p0: PlayerCharacter = current_level.call("get_player", 0)
			if p0:
				players.append(p0)
		elif current_level.has_node("Entities/PlayerCharacter"):
			var p: PlayerCharacter = current_level.get_node("Entities/PlayerCharacter") as PlayerCharacter
			if p:
				players.append(p)
		elif current_level.has_node("PlayerCharacter"):
			var p: PlayerCharacter = current_level.get_node("PlayerCharacter") as PlayerCharacter
			if p:
				players.append(p)

		if "order_manager" in current_level and current_level.order_manager:
			order_mgr = current_level.order_manager
		elif current_level.has_node("OrderManager"):
			order_mgr = current_level.get_node("OrderManager") as OrderManager

	hud.setup(players, order_mgr)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_reload"):
		reload_level()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_overlay_visible = not debug_overlay_visible
		if debug_label:
			debug_label.visible = debug_overlay_visible
		get_viewport().set_input_as_handled()
