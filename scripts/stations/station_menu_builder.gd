class_name StationMenuBuilder
extends RefCounted

## Builds contextual InteractionMenuOption arrays for each station type.
## Evaluates station state, placed device, player's carry state, and tool availability.

static func build_menu(station: BaseStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	if not station or not player:
		return []

	if station is WorkbenchStation:
		return _build_workbench_menu(station as WorkbenchStation, player)
	elif station is DiagnosticBench:
		return _build_diagnostic_menu(station as DiagnosticBench, player)
	elif station is PartsShelf:
		return _build_parts_shelf_menu(station as PartsShelf, player)
	elif station is SoftwareStation:
		return _build_software_menu(station as SoftwareStation, player)
	elif station is ReceptionDesk:
		return _build_reception_menu(station as ReceptionDesk, player)
	elif station is DeliveryCounter:
		return _build_delivery_menu(station as DeliveryCounter, player)

	return _build_generic_menu(station, player)


static func _build_workbench_menu(wb: WorkbenchStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system
	var has_device_on_bench: bool = wb.placed_device != null

	if not has_device_on_bench:
		# Empty bench options
		if carry and carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is Device:
				var dev: Device = held as Device
				var place_opt := InteractionMenuOption.new(
					"place_device",
					"Place %s on Bench" % held.item_name,
					"Set down the %s for repair work." % held.item_name,
					func() -> void: wb._on_interacted(player),
					wb._can_accept_workbench_item(held)
				)
				if not place_opt.is_enabled:
					if dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
						place_opt.disabled_reason = "No hardware repair needed (software only)"
					else:
						place_opt.disabled_reason = "Cannot repair at workbench"
				options.append(place_opt)

				# Examine held device
				var examine_held := InteractionMenuOption.new(
					"examine",
					"Examine %s" % held.item_name,
					_build_device_description(dev),
					func() -> void: _trigger_device_examination(player, dev)
				)
				options.append(examine_held)
			elif held is ToolItem:
				var place_tool := InteractionMenuOption.new(
					"place_tool",
					"Place %s on Bench" % held.item_name,
					"Leave the tool on the workbench for later use.",
					func() -> void: wb._try_place_tool(player),
					wb.get_bench_tool() == null
				)
				if not place_tool.is_enabled:
					place_tool.disabled_reason = "Bench already has a tool"
				options.append(place_tool)
		elif wb.get_bench_tool() != null:
			var tool: ToolItem = wb.get_bench_tool()
			var pickup_tool := InteractionMenuOption.new(
				"pick_up_tool",
				"Pick Up %s" % tool.tool_display_name,
				"Pick up the tool from the workbench.",
				func() -> void: wb._try_pick_up_tool(player),
				carry != null and carry.can_pick_up()
			)
			if not pickup_tool.is_enabled:
				pickup_tool.disabled_reason = "Hands full"
			options.append(pickup_tool)
	else:
		# Bench has a device
		var dev: Device = wb.placed_device as Device if wb.placed_device is Device else null
		if dev:
			# Examine is always available
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev)
			)
			options.append(examine_opt)

			var r_state: String = str(dev.get_repair_state())
			match r_state:
				"DIAGNOSED":
					var has_tool: bool = wb._has_required_tool(player)
					var disasm := InteractionMenuOption.new(
						"disassemble",
						"Disassemble Device",
						"Open the device to access internal components.",
						func() -> void:
							wb.set_active_user(player)
							var hud := player.get_tree().get_first_node_in_group("hud") if (player and player.is_inside_tree()) else null
							if hud and hud.has_method("start_repair_minigame"):
								hud.start_repair_minigame(player, dev, "screw", func() -> void:
									var tool: ToolItem = wb.get_bench_tool()
									if not tool and player and player.carry_system and player.carry_system.is_carrying():
										var held: Carriable = player.carry_system.get_held_item()
										if held is ToolItem: tool = held as ToolItem
									if tool: tool.use_tool()
									wb._start_disassembly()
									wb._complete_processing()
								)
							else:
								wb._start_disassembly(),
						has_tool
					)
					if not has_tool:
						disasm.disabled_reason = "Needs %s" % wb.required_tool_name
					options.append(disasm)

				"DISASSEMBLED":
					if carry and carry.is_carrying():
						var held: Carriable = carry.get_held_item()
						if held and held.item_type == "part":
							var is_valid_part: bool = wb._is_valid_replacement_part(dev, held)
							var install := InteractionMenuOption.new(
								"install_part",
								"Install %s" % held.item_name,
								"Install this component into the device.",
								func() -> void: wb._try_install_part(player),
								is_valid_part
							)
							if not is_valid_part:
								install.disabled_reason = "Wrong part for this device"
							options.append(install)

					if dev.assigned_fault and dev.assigned_fault.is_multi_fault:
						var missing: Array[ComponentData] = dev.get_missing_components()
						if not missing.is_empty():
							var names: PackedStringArray = []
							for m in missing:
								if m:
									names.append(m.component_name)
							var info := InteractionMenuOption.new(
								"missing_parts_info",
								"Needed: %s" % ", ".join(names),
								"These components still need to be installed before reassembly.",
								Callable(),
								false
							)
							info.disabled_reason = "Info only"
							options.append(info)

				"PART_REPLACED":
					var has_tool: bool = wb._has_required_tool(player)
					var reassem := InteractionMenuOption.new(
						"reassemble",
						"Reassemble Device",
						"Close up the device. Component installation complete.",
						func() -> void:
							wb.set_active_user(player)
							var hud := player.get_tree().get_first_node_in_group("hud") if (player and player.is_inside_tree()) else null
							if hud and hud.has_method("start_repair_minigame"):
								hud.start_repair_minigame(player, dev, "screw", func() -> void:
									var tool: ToolItem = wb.get_bench_tool()
									if not tool and player and player.carry_system and player.carry_system.is_carrying():
										var held: Carriable = player.carry_system.get_held_item()
										if held is ToolItem: tool = held as ToolItem
									if tool: tool.use_tool()
									wb._try_reassemble(player)
									wb._complete_processing()
								)
							else:
								wb._try_reassemble(player),
						has_tool
					)
					if not has_tool:
						reassem.disabled_reason = "Needs %s" % wb.required_tool_name
					options.append(reassem)

			# Pick up option
			var can_pick: bool = carry != null and carry.can_pick_up()
			var pickup := InteractionMenuOption.new(
				"pick_up",
				"Pick Up Device",
				"Remove the device from the workbench.",
				func() -> void: wb._try_pick_up(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)
		else:
			# Non-device generic carriable on bench
			var can_pick: bool = carry != null and carry.can_pick_up()
			var pickup := InteractionMenuOption.new(
				"pick_up",
				"Pick Up Item",
				"Remove the item from the workbench.",
				func() -> void: wb._try_pick_up(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)

	# Cancel option
	options.append(_create_cancel_option())
	return options


static func _build_diagnostic_menu(diag: DiagnosticBench, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if not diag.placed_device:
		if carry and carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			var can_diag: bool = diag._is_valid_device_state(held)
			var diag_opt := InteractionMenuOption.new(
				"diagnose_device",
				"Place Device to Diagnose",
				"Place %s on the diagnostic bench to inspect faults." % held.item_name,
				func() -> void: diag._on_interacted(player),
				can_diag
			)
			if not can_diag:
				diag_opt.disabled_reason = "Device must be in RECEIVED state"
			options.append(diag_opt)

			if held is Device:
				var examine_held := InteractionMenuOption.new(
					"examine",
					"Examine %s" % held.item_name,
					_build_device_description(held as Device),
					func() -> void: _trigger_device_examination(player, held as Device)
				)
				options.append(examine_held)
	else:
		var dev: Device = diag.placed_device as Device if diag.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev)
			)
			options.append(examine_opt)

		if diag.current_state == BaseStation.StationState.COMPLETE:
			var can_pick: bool = carry != null and carry.can_pick_up()
			var pickup := InteractionMenuOption.new(
				"pick_up",
				"Pick Up Diagnosed Device",
				"Remove the diagnosed device and proceed with repairs.",
				func() -> void: diag._on_interacted(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)
		elif diag.current_state == BaseStation.StationState.OCCUPIED:
			var run_diag := InteractionMenuOption.new(
				"run_diagnosis",
				"Run Diagnostics",
				"Start automated diagnostics to detect defects.",
				func() -> void: diag.start_processing(),
				true
			)
			options.append(run_diag)

	options.append(_create_cancel_option())
	return options


static func _build_parts_shelf_menu(shelf: PartsShelf, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if carry and carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is DeliveryBox or held.item_type == "delivery" or held.has_method("unpack_at_shelf"):
			var unpack_opt := InteractionMenuOption.new(
				"unpack_delivery",
				"Unpack %s" % held.item_name,
				"Stock the incoming parts delivery onto the shelf.",
				func() -> void: shelf._on_interacted(player),
				true
			)
			options.append(unpack_opt)
	else:
		# Empty hands: show needed part first, then other available parts
		var needed: ComponentData = shelf._get_needed_part()
		if needed:
			var stock_qty: int = shelf.get_stock(needed.component_id) if shelf.stock_tracking_enabled else 99
			var is_in_stock: bool = stock_qty > 0
			var take_needed := InteractionMenuOption.new(
				"take_needed_part",
				"Take %s (Needed)" % needed.component_name,
				"Take %s from the shelf (Stock: %d)." % [needed.component_name, stock_qty],
				func() -> void:
					var part: Carriable = shelf.dispense_part(needed.component_id)
					if part and carry and carry.can_pick_up():
						carry.pick_up(part),
				is_in_stock
			)
			if not is_in_stock:
				take_needed.disabled_reason = "Out of Stock"
			options.append(take_needed)

		# Browse remaining parts
		for part_data in shelf.available_parts:
			if not part_data or (needed and part_data.component_id == needed.component_id):
				continue
			var qty: int = shelf.get_stock(part_data.component_id) if shelf.stock_tracking_enabled else 99
			var in_stock: bool = qty > 0
			var take_opt := InteractionMenuOption.new(
				"take_part_%s" % part_data.component_id,
				"Take %s" % part_data.component_name,
				"Take %s from the shelf (Stock: %d)." % [part_data.component_name, qty],
				func() -> void:
					var p: Carriable = shelf.dispense_part(part_data.component_id)
					if p and carry and carry.can_pick_up():
						carry.pick_up(p),
				in_stock
			)
			if not in_stock:
				take_opt.disabled_reason = "Out of Stock"
			options.append(take_opt)
			if options.size() >= 5:
				break

	options.append(_create_cancel_option())
	return options


static func _build_software_menu(soft: SoftwareStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if not soft.placed_device:
		if carry and carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			var can_install: bool = soft._is_valid_device_state(held)
			var place_opt := InteractionMenuOption.new(
				"place_device_software",
				"Place %s for Software" % held.item_name,
				"Place device on software station for OS flashing and firmware tests.",
				func() -> void: soft._on_interacted(player),
				can_install
			)
			if not can_install:
				place_opt.disabled_reason = "Requires REASSEMBLED state"
			options.append(place_opt)

			if held is Device:
				var examine_held := InteractionMenuOption.new(
					"examine",
					"Examine %s" % held.item_name,
					_build_device_description(held as Device),
					func() -> void: _trigger_device_examination(player, held as Device)
				)
				options.append(examine_held)
	else:
		var dev: Device = soft.placed_device as Device if soft.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev)
			)
			options.append(examine_opt)

		if soft.current_state == BaseStation.StationState.COMPLETE:
			var can_pick: bool = carry != null and carry.can_pick_up()
			var pickup := InteractionMenuOption.new(
				"pick_up",
				"Pick Up Tested Device",
				"Remove tested device and deliver to counter.",
				func() -> void: soft._on_interacted(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)
		elif soft.current_state == BaseStation.StationState.OCCUPIED:
			var start_soft := InteractionMenuOption.new(
				"run_software",
				"Install OS & Run Tests",
				"Flash firmware and execute diagnostic checks.",
				func() -> void: soft.start_processing(),
				true
			)
			options.append(start_soft)

	options.append(_create_cancel_option())
	return options


static func _build_reception_menu(reception: ReceptionDesk, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if reception.placed_device:
		var dev: Device = reception.placed_device as Device if reception.placed_device is Device else null
		var can_pick: bool = carry != null and carry.can_pick_up() and reception.placed_device.can_claim(player)
		var pickup_opt := InteractionMenuOption.new(
			"accept_order",
			"Accept Order (%s)" % reception.placed_device.item_name,
			"Pick up incoming device and begin repair process.",
			func() -> void: reception._on_interacted(player),
			can_pick
		)
		if not can_pick:
			if carry != null and not carry.can_pick_up():
				pickup_opt.disabled_reason = "Hands full"
			else:
				pickup_opt.disabled_reason = "Claimed by another player"
		options.append(pickup_opt)

		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev)
			)
			options.append(examine_opt)

	options.append(_create_cancel_option())
	return options


static func _build_delivery_menu(delivery: DeliveryCounter, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if carry and carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		var can_deliv: bool = delivery._is_valid_delivery_device(held)
		var deliver_opt := InteractionMenuOption.new(
			"deliver_device",
			"Deliver %s" % held.item_name,
			"Fulfill order and earn points.",
			func() -> void: delivery._on_interacted(player),
			can_deliv
		)
		if not can_deliv:
			deliver_opt.disabled_reason = "Device must be in TESTED state"
		options.append(deliver_opt)

		if held is Device:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Before Delivery",
				_build_device_description(held as Device),
				func() -> void: _trigger_device_examination(player, held as Device)
			)
			options.append(examine_opt)

	options.append(_create_cancel_option())
	return options


static func _build_generic_menu(station: BaseStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var can_act: bool = station.can_player_interact(player)
	var interact_opt := InteractionMenuOption.new(
		"interact",
		station.get_interaction_prompt(player),
		"Interact with %s." % station.station_name,
		func() -> void: station._on_interacted(player),
		can_act
	)
	options.append(interact_opt)
	options.append(_create_cancel_option())
	return options


static func _create_cancel_option() -> InteractionMenuOption:
	return InteractionMenuOption.new(
		"cancel",
		"Cancel",
		"Close this menu and return to gameplay.",
		Callable(),
		true
	)


static func _build_device_description(dev: Device) -> String:
	if not dev:
		return "No device information."
	var lines: PackedStringArray = []
	lines.append("Device: %s" % dev.item_name)
	lines.append("State: %s" % dev.get_repair_state())
	if (dev.is_diagnosed or dev.current_repair_state != RepairState.State.RECEIVED) and dev.assigned_fault:
		lines.append("Fault: %s" % dev.assigned_fault.fault_name)
		if dev.assigned_fault.is_multi_fault:
			var required: Array[ComponentData] = dev.assigned_fault.get_required_components()
			var missing: Array[ComponentData] = dev.get_missing_components()
			for comp in required:
				if comp:
					var installed: bool = not missing.any(func(m: ComponentData) -> bool: return m != null and m.component_id == comp.component_id)
					lines.append("  %s %s" % ["✓" if installed else "○", comp.component_name])
	return "\n".join(lines)


static func _trigger_device_examination(player: PlayerCharacter, dev: Device) -> void:
	if not dev or not player:
		return
	SignalBus.device_examined.emit(player.player_index, dev.item_name)
	var hud := player.get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_examination_panel"):
		hud.open_examination_panel(player, dev)
