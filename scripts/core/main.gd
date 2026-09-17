class_name Main
extends Node3D

## Main orchestrator scene for Overclocked.
## Owns the camera rig, manages workshop level instancing, and hosts the UI layer.

const DEFAULT_WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/Workshop_Debug.tscn")

@export var default_level: PackedScene = DEFAULT_WORKSHOP_SCENE
@export var debug_overlay_visible: bool = true

var current_level: Node = null

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

	if GameManager.current_state == GameState.State.MENU:
		GameManager.change_state(GameState.State.PLAYING)

	_setup_camera()
	_setup_hud()
	_update_debug_label()


func _process(_delta: float) -> void:
	if debug_overlay_visible and debug_label:
		_update_debug_label()


func _update_debug_label() -> void:
	var state_name: String = GameState.to_string_name(GameManager.current_state)
	var fps: int = Engine.get_frames_per_second()
	debug_label.text = "Phase 0 — Overclocked | State: %s | FPS: %d" % [state_name, fps]


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


func _setup_hud() -> void:
	if not hud:
		return
	var player: PlayerCharacter = null
	var order_mgr: OrderManager = null
	if current_level:
		if current_level.has_method("get_player"):
			player = current_level.call("get_player", 0)
		elif current_level.has_node("Entities/PlayerCharacter"):
			player = current_level.get_node("Entities/PlayerCharacter") as PlayerCharacter
		elif current_level.has_node("PlayerCharacter"):
			player = current_level.get_node("PlayerCharacter") as PlayerCharacter

		if "order_manager" in current_level and current_level.order_manager:
			order_mgr = current_level.order_manager
		elif current_level.has_node("OrderManager"):
			order_mgr = current_level.get_node("OrderManager") as OrderManager

	hud.setup(player, order_mgr)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_reload"):
		reload_level()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_overlay_visible = not debug_overlay_visible
		if debug_label:
			debug_label.visible = debug_overlay_visible
		get_viewport().set_input_as_handled()
