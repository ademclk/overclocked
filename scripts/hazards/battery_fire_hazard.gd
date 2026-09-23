class_name BatteryFireHazard
extends BaseHazard

## Lithium battery fire hazard resulting from damaged batteries.
## Requires correct extinguishing method (Fire Extinguisher).
## Pouring water causes an explosive chemical reaction that spreads the fire!

signal fire_exploded()

var is_exploded: bool = false


func _ready() -> void:
	hazard_name = "Battery Fire"
	hazard_type = "fire"
	duration = 20.0
	warning_duration = 1.0
	clear_time = 2.0
	can_be_cleared = true
	affects_players = true
	affects_stations = true
	player_speed_multiplier = 0.5

	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape:
		shape = CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 1.5
		shape.shape = sphere
		add_child(shape)

	if not interaction_zone and can_be_cleared:
		var iz := Interactable.new()
		iz.name = "InteractionZone"
		var iz_shape := CollisionShape3D.new()
		var iz_sphere := SphereShape3D.new()
		iz_sphere.radius = 2.0
		iz_shape.shape = iz_sphere
		iz.add_child(iz_shape)
		add_child(iz)
		interaction_zone = iz

	super._ready()


func use_extinguisher(player: PlayerCharacter = null) -> void:
	SignalBus.hazard_resolution_started.emit(hazard_name, "extinguisher")
	_clearing_player = player
	clear_time = 2.0
	current_state = HazardState.CLEARING
	_clear_timer = 0.0


func pour_water(player: PlayerCharacter = null) -> void:
	# WRONG CHOICE: Lithium + water = explosive spread
	is_exploded = true
	clear_time = clear_time * 2.0
	duration = duration + 10.0
	SignalBus.hazard_wrong_choice.emit(hazard_name, "pour_water")
	fire_exploded.emit()

	# Expand collision area
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape and shape.shape is SphereShape3D:
		(shape.shape as SphereShape3D).radius *= 1.5


func smother_with_cloth(player: PlayerCharacter = null) -> void:
	SignalBus.hazard_resolution_started.emit(hazard_name, "smother")
	_clearing_player = player
	clear_time = 6.0
	current_state = HazardState.CLEARING
	_clear_timer = 0.0
