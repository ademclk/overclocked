class_name HazardMenuBuilder
extends RefCounted

## Builds contextual InteractionMenuOption arrays for each hazard type.
## Each hazard type presents a multi-step resolution puzzle with risk/reward choices.

static func build_menu(hazard: BaseHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	if not hazard or not player:
		return []

	if hazard is PowerSurgeHazard:
		return _build_surge_menu(hazard as PowerSurgeHazard, player)
	elif hazard is FloorSpillHazard:
		var spill := hazard as FloorSpillHazard
		if spill.spill_type == FloorSpillHazard.SpillType.SCREWS:
			return _build_screws_menu(spill, player)
		else:
			return _build_spill_menu(spill, player)
	elif hazard is BatteryFireHazard:
		return _build_battery_fire_menu(hazard as BatteryFireHazard, player)
	elif hazard is CableTangleHazard:
		return _build_cable_tangle_menu(hazard as CableTangleHazard, player)
	elif hazard is ScatteredScrewsHazard:
		return _build_screws_menu(hazard as ScatteredScrewsHazard, player)

	return _build_generic_hazard_menu(hazard, player)


static func _build_surge_menu(surge: PowerSurgeHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var station_name_str: String = surge.target_station.station_name if surge.target_station else "Workbench"

	var reset_opt := InteractionMenuOption.new(
		"reset_breaker",
		"Reset Circuit Breaker (3D Puzzle)",
		"Flip tripped switches in the 3D breaker panel to safely restore power to %s." % station_name_str,
		func() -> void:
			SignalBus.hazard_resolution_started.emit(surge.hazard_name, "reset_breaker")
			var hud := surge.get_tree().get_first_node_in_group("hud") if surge.is_inside_tree() else null
			if hud and hud.has_method("open_hazard_minigame"):
				hud.open_hazard_minigame(player, surge)
			else:
				surge.clear_time = 3.0
				surge._on_clear_interacted(player),
		true
	)
	options.append(reset_opt)

	var unplug_opt := InteractionMenuOption.new(
		"unplug_station",
		"Unplug Station",
		"Cut the surge immediately, but station stays off for an extra 10 seconds.",
		func() -> void:
			SignalBus.hazard_resolution_started.emit(surge.hazard_name, "unplug_station")
			surge.clear()
			if surge.target_station:
				surge.target_station.processing_time += 10.0,
		true
	)
	options.append(unplug_opt)

	var wait_opt := InteractionMenuOption.new(
		"wait_surge",
		"Wait It Out",
		"Allow the surge to dissipate naturally over time.",
		Callable(),
		true
	)
	options.append(wait_opt)

	var examine_opt := InteractionMenuOption.new(
		"examine_surge",
		"Examine Damage",
		"Power surge affecting %s. Station operations disabled until resolved." % station_name_str,
		Callable(),
		true
	)
	options.append(examine_opt)

	options.append(_create_cancel_option())
	return options


static func _build_spill_menu(spill: FloorSpillHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []

	var mop_opt := InteractionMenuOption.new(
		"mop_spill",
		"Mop Up (3D Puzzle)",
		"Mop up the dirty spots across the spill.",
		func() -> void:
			SignalBus.hazard_resolution_started.emit(spill.hazard_name, "mop")
			var hud := spill.get_tree().get_first_node_in_group("hud") if spill.is_inside_tree() else null
			if hud and hud.has_method("open_hazard_minigame"):
				hud.open_hazard_minigame(player, spill)
			else:
				spill.clear_time = 3.0
				spill._on_clear_interacted(player),
		true
	)
	options.append(mop_opt)

	var caution_opt := InteractionMenuOption.new(
		"caution_sign",
		"Put Down Caution Sign",
		"Doesn't clear the spill, but alerts players and mitigates slow penalty.",
		func() -> void:
			spill.player_speed_multiplier = 0.8
			SignalBus.hazard_resolution_completed.emit(spill.hazard_name, "caution_sign"),
		true
	)
	options.append(caution_opt)

	options.append(_create_cancel_option())
	return options


static func build_overheating_menu(dev: Device, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	var remove_opt := InteractionMenuOption.new(
		"remove_device",
		"Remove from Bench (Cool Down)",
		"Pick up the device to let it cool down naturally in hands.",
		func() -> void:
			if dev and carry and carry.can_pick_up():
				carry.pick_up(dev)
				if dev.has_meta("is_overheated"):
					dev.remove_meta("is_overheated"),
		carry != null and carry.can_pick_up()
	)
	if carry != null and not carry.can_pick_up():
		remove_opt.disabled_reason = "Hands full"
	options.append(remove_opt)

	var coolant_opt := InteractionMenuOption.new(
		"apply_coolant",
		"Apply Compressed Air / Coolant",
		"Blast compressed air to rapidly reduce thermal load.",
		func() -> void:
			SignalBus.hazard_resolution_started.emit("Overheating", "coolant")
			if dev and dev.has_meta("is_overheated"):
				dev.remove_meta("is_overheated"),
		true
	)
	options.append(coolant_opt)

	var shutdown_opt := InteractionMenuOption.new(
		"force_shutdown",
		"Force Shutdown",
		"Emergency shutdown stops the heat immediately.",
		func() -> void:
			SignalBus.hazard_resolution_started.emit("Overheating", "force_shutdown")
			if dev and dev.has_meta("is_overheated"):
				dev.remove_meta("is_overheated"),
		true
	)
	options.append(shutdown_opt)

	options.append(_create_cancel_option())
	return options


static func _build_battery_fire_menu(fire: BatteryFireHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []

	var ext_opt := InteractionMenuOption.new(
		"fire_extinguisher",
		"Use Fire Extinguisher (3D Puzzle)",
		"Aim extinguisher foam bursts at flames to suppress safely.",
		func() -> void:
			var hud := fire.get_tree().get_first_node_in_group("hud") if fire.is_inside_tree() else null
			if hud and hud.has_method("open_hazard_minigame"):
				hud.open_hazard_minigame(player, fire)
			else:
				fire.use_extinguisher(player),
		true
	)
	options.append(ext_opt)

	# Pour Water is deliberately available so players can make the mistake!
	var water_opt := InteractionMenuOption.new(
		"pour_water",
		"Pour Water",
		"Pour a bucket of water over the fire.",
		func() -> void: fire.pour_water(player),
		true
	)
	options.append(water_opt)

	var smother_opt := InteractionMenuOption.new(
		"smother_fire",
		"Smother with Fire Blanket",
		"Slowly smother the fire (6s).",
		func() -> void: fire.smother_with_cloth(player),
		true
	)
	options.append(smother_opt)

	options.append(_create_cancel_option())
	return options


static func _build_cable_tangle_menu(tangle: CableTangleHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []

	var untangle_opt := InteractionMenuOption.new(
		"untangle_carefully",
		"Untangle Carefully (3D Puzzle)",
		"Untangle and rewire each colored cable into its matching terminal port.",
		func() -> void:
			var hud := tangle.get_tree().get_first_node_in_group("hud") if tangle.is_inside_tree() else null
			if hud and hud.has_method("open_hazard_minigame"):
				hud.open_hazard_minigame(player, tangle)
			else:
				tangle.untangle_carefully(player),
		true
	)
	options.append(untangle_opt)

	var cut_opt := InteractionMenuOption.new(
		"cut_cables",
		"Cut Cables (Fast)",
		"Snip cables free in 1 second, but destroys or dulls your tool!",
		func() -> void: tangle.cut_cables(player),
		true
	)
	options.append(cut_opt)

	options.append(_create_cancel_option())
	return options


static func _build_screws_menu(screws: BaseHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []

	var gather_opt := InteractionMenuOption.new(
		"gather_screws",
		"Gather Screws (3D Puzzle)",
		"Collect all loose screws and hardware into the magnetic parts tray.",
		func() -> void:
			SignalBus.hazard_resolution_started.emit(screws.hazard_name, "gather_screws")
			var hud := screws.get_tree().get_first_node_in_group("hud") if screws.is_inside_tree() else null
			if hud and hud.has_method("open_hazard_minigame"):
				hud.open_hazard_minigame(player, screws)
			else:
				screws.clear(),
		true
	)
	options.append(gather_opt)

	var caution_opt := InteractionMenuOption.new(
		"caution_sign",
		"Put Down Caution Sign",
		"Doesn't pick up the screws, but alerts technicians and mitigates slow penalty.",
		func() -> void:
			screws.player_speed_multiplier = 0.85
			SignalBus.hazard_resolution_completed.emit(screws.hazard_name, "caution_sign"),
		true
	)
	options.append(caution_opt)

	options.append(_create_cancel_option())
	return options


static func _build_generic_hazard_menu(hazard: BaseHazard, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var clear_opt := InteractionMenuOption.new(
		"clear_hazard",
		"Clear %s" % hazard.hazard_name,
		"Attempt to resolve the hazard.",
		func() -> void: hazard._on_clear_interacted(player),
		hazard.can_be_cleared
	)
	options.append(clear_opt)
	options.append(_create_cancel_option())
	return options


static func _create_cancel_option() -> InteractionMenuOption:
	return InteractionMenuOption.new(
		"cancel",
		"Cancel",
		"Back away from the hazard.",
		Callable(),
		true
	)
