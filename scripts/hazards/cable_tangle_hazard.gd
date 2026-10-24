class_name CableTangleHazard
extends BaseHazard

## Cable tangle hazard that traps tools or slows down workstation throughput.

var cables_cut: bool = false


func _ready() -> void:
	hazard_name = "Cable Tangle"
	hazard_type = "tangle"
	duration = 0.0
	warning_duration = 1.0
	clear_time = 5.0
	can_be_cleared = true
	affects_players = true
	affects_stations = true
	player_speed_multiplier = 0.6

	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape:
		shape = CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 1.2
		shape.shape = sphere
		add_child(shape)

	if not interaction_zone and can_be_cleared:
		var iz := Interactable.new()
		iz.name = "InteractionZone"
		var iz_shape := CollisionShape3D.new()
		var iz_sphere := SphereShape3D.new()
		iz_sphere.radius = 1.6
		iz_shape.shape = iz_sphere
		iz.add_child(iz_shape)
		add_child(iz)
		interaction_zone = iz

	super._ready()


func untangle_carefully(player: PlayerCharacter = null) -> void:
	SignalBus.hazard_resolution_started.emit(hazard_name, "untangle_carefully")
	_clearing_player = player
	clear_time = 5.0
	current_state = HazardState.CLEARING
	_clear_timer = 0.0


func cut_cables(player: PlayerCharacter = null) -> void:
	cables_cut = true
	SignalBus.hazard_resolution_started.emit(hazard_name, "cut_cables")
	SignalBus.hazard_wrong_choice.emit(hazard_name, "cut_cables")
	if player and player.carry_system and player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held and held.item_type == "tool":
			if "current_durability" in held:
				held.current_durability = 0
			if "tool_id" in held:
				SignalBus.tool_broken.emit(held.tool_id)
	clear()
