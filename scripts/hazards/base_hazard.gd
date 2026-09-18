class_name BaseHazard
extends Area3D

## Base class for all workshop hazards in Overclocked.
## Hazards are Area3D nodes that affect players or stations within their zone.
## Subclasses override _apply_effect() and _remove_effect() for specific behavior.

signal hazard_activated(hazard: BaseHazard)
signal hazard_cleared(hazard: BaseHazard)
signal hazard_expired(hazard: BaseHazard)

enum HazardState {
	INACTIVE,      ## Not yet visible or active
	WARNING,       ## Flashing warning before activation (1-2 seconds)
	ACTIVE,        ## Hazard is live and affecting players/stations
	CLEARING,      ## Being cleared by a player (interaction in progress)
	CLEARED,       ## Cleared by player action — about to be freed
}

@export var hazard_name: String = "Hazard"
@export var hazard_type: String = "generic"
@export var duration: float = 0.0              ## 0 = permanent until cleared, >0 = auto-expires
@export var warning_duration: float = 1.5      ## Seconds of warning flash before activation
@export var clear_time: float = 1.0            ## Seconds of interact-to-clear
@export var can_be_cleared: bool = true         ## Whether players can interact to remove it
@export var affects_players: bool = true        ## Whether it slows/stuns players
@export var affects_stations: bool = false      ## Whether it disables stations
@export var player_speed_multiplier: float = 1.0  ## Applied while player is in zone (0.5 = half speed)

var current_state: HazardState = HazardState.INACTIVE
var _active_timer: float = 0.0
var _warning_timer: float = 0.0
var _clear_timer: float = 0.0
var _affected_players: Array[PlayerCharacter] = []
var _affected_station: BaseStation = null
var _clearing_player: PlayerCharacter = null

@onready var hazard_visual: Node3D = get_node_or_null("HazardVisual") as Node3D
@onready var hazard_label: Label3D = get_node_or_null("HazardLabel") as Label3D
@onready var warning_indicator: Node3D = get_node_or_null("WarningIndicator") as Node3D
@onready var interaction_zone: Interactable = get_node_or_null("InteractionZone") as Interactable


func _ready() -> void:
	add_to_group("hazards")
	collision_layer = Constants.COLLISION_MASK_HAZARDS
	collision_mask = Constants.COLLISION_MASK_PLAYERS

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if interaction_zone and can_be_cleared:
		interaction_zone.interacted.connect(_on_clear_interacted)
		interaction_zone.interaction_prompt = "Clear %s" % hazard_name
		interaction_zone.can_interact_handler = func(_p: PlayerCharacter) -> bool:
			return current_state in [HazardState.ACTIVE, HazardState.CLEARING]

	_set_visual_state()


func _physics_process(delta: float) -> void:
	match current_state:
		HazardState.WARNING:
			_warning_timer -= delta
			_flash_warning(delta)
			if _warning_timer <= 0.0:
				activate()

		HazardState.ACTIVE:
			if duration > 0.0:
				_active_timer += delta
				if _active_timer >= duration:
					expire()
			_process_active_effects(delta)

		HazardState.CLEARING:
			if _clearing_player and is_instance_valid(_clearing_player):
				if global_position.distance_to(_clearing_player.global_position) > Constants.DEFAULT_INTERACTION_DISTANCE * 2.0:
					cancel_clearing()
					return
			_clear_timer += delta
			_set_visual_state()
			if _clear_timer >= clear_time:
				clear()


## Begins the warning phase before the hazard activates
func spawn_with_warning() -> void:
	current_state = HazardState.WARNING
	_warning_timer = warning_duration
	visible = true
	monitoring = false
	if warning_indicator:
		warning_indicator.visible = true
	if hazard_visual:
		hazard_visual.visible = false
	_set_visual_state()


## Immediately activates the hazard (skip warning)
func activate() -> void:
	current_state = HazardState.ACTIVE
	_active_timer = 0.0
	monitoring = true
	if warning_indicator:
		warning_indicator.visible = false
	if hazard_visual:
		hazard_visual.visible = true
	_set_visual_state()
	_on_activated()

	# Re-check overlapping bodies already in zone
	for body in get_overlapping_bodies():
		_on_body_entered(body)

	hazard_activated.emit(self)
	SignalBus.hazard_activated.emit(hazard_name, hazard_type)


## Called when the hazard expires naturally (timer ran out)
func expire() -> void:
	_cleanup_effects()
	current_state = HazardState.CLEARED
	hazard_expired.emit(self)
	SignalBus.hazard_expired.emit(hazard_name)
	queue_free()


## Called when a player successfully clears the hazard
func clear() -> void:
	_cleanup_effects()
	current_state = HazardState.CLEARED
	hazard_cleared.emit(self)
	SignalBus.hazard_cleared.emit(hazard_name)
	queue_free()


## Starts the clearing interaction (player holds or presses interact)
func start_clearing(player: PlayerCharacter) -> void:
	if current_state != HazardState.ACTIVE or not can_be_cleared:
		return
	current_state = HazardState.CLEARING
	_clearing_player = player
	_clear_timer = 0.0
	_set_visual_state()


## Cancels an in-progress clear (player walked away)
func cancel_clearing() -> void:
	if current_state == HazardState.CLEARING:
		current_state = HazardState.ACTIVE
		_clearing_player = null
		_clear_timer = 0.0
		_set_visual_state()


## Returns clear progress from 0.0 to 1.0
func get_clear_progress() -> float:
	if clear_time <= 0.0:
		return 1.0
	return clampf(_clear_timer / clear_time, 0.0, 1.0)


## Override in subclasses: what happens when hazard activates
func _on_activated() -> void:
	pass


## Override in subclasses: per-frame effect while active
func _process_active_effects(_delta: float) -> void:
	pass


## Override in subclasses: apply effect when player enters zone
func _apply_effect(player: PlayerCharacter) -> void:
	if affects_players and player_speed_multiplier != 1.0:
		player.move_speed *= player_speed_multiplier


## Override in subclasses: remove effect when player leaves zone
func _remove_effect(player: PlayerCharacter) -> void:
	if affects_players and player_speed_multiplier != 1.0:
		player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED


func _cleanup_effects() -> void:
	for player in _affected_players:
		if is_instance_valid(player):
			_remove_effect(player)
	_affected_players.clear()
	monitoring = false


func _on_body_entered(body: Node3D) -> void:
	if current_state != HazardState.ACTIVE and current_state != HazardState.CLEARING:
		return
	if body is PlayerCharacter:
		var player := body as PlayerCharacter
		if not _affected_players.has(player):
			_affected_players.append(player)
			_apply_effect(player)


func _on_body_exited(body: Node3D) -> void:
	if body is PlayerCharacter:
		var player := body as PlayerCharacter
		if _affected_players.has(player):
			_affected_players.erase(player)
			_remove_effect(player)


func _on_clear_interacted(player: PlayerCharacter) -> void:
	if current_state == HazardState.ACTIVE:
		start_clearing(player)
	# For instant-clear hazards (clear_time <= 0), clear immediately
	if clear_time <= 0.0:
		clear()


func _flash_warning(_delta: float) -> void:
	if warning_indicator:
		var flash: float = sin(Time.get_ticks_msec() * 0.015) * 0.5 + 0.5
		warning_indicator.visible = flash > 0.3


func _set_visual_state() -> void:
	if hazard_label:
		if current_state == HazardState.CLEARING and clear_time > 0.0:
			hazard_label.text = "Clearing (%.0f%%)" % [get_clear_progress() * 100.0]
		else:
			hazard_label.text = "⚠ %s" % hazard_name.to_upper()
		hazard_label.visible = current_state in [HazardState.ACTIVE, HazardState.CLEARING]
