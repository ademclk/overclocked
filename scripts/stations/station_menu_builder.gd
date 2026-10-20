class_name StationMenuBuilder
extends RefCounted

## Builds contextual InteractionMenuOption arrays for each station type.
## Evaluates station state, placed device, player's carry state, and tool availability.

static func build_menu(station: BaseStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	if not station or not player:
		return []

	if station is RepairTableStation:
		return _build_repair_table_menu(station as RepairTableStation, player)
	elif station is WorkbenchStation:
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
	elif station is TrashBin or station.station_type == "trash":
		return _build_trash_menu(station, player)

	return _build_generic_menu(station, player)


static func _build_workbench_menu(wb: WorkbenchStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system
	var has_device_on_bench: bool = wb.placed_device != null

	if not has_device_on_bench:
		# Empty bench options
		if carry and carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is Device or held.item_type == "device":
				var dev: Device = held as Device if held is Device else null
				var place_opt := InteractionMenuOption.new(
					"place_device",
					"Place %s on Workbench" % held.item_name,
					"Devices cannot be placed on Workbench. Use Repair Table for hardware repairs.",
					Callable(),
					false
				)
				place_opt.disabled_reason = "Cannot place devices on Workbench (Use Repair Table)"
				options.append(place_opt)

				# Examine held device
				if dev:
					var examine_held := InteractionMenuOption.new(
						"examine",
						"Examine %s" % held.item_name,
						_build_device_description(dev),
						func() -> void: _trigger_device_examination(player, dev, wb)
					)
					options.append(examine_held)
			elif held is ToolItem:
				if wb.get_bench_tool() == null:
					var place_tool := InteractionMenuOption.new(
						"place_tool",
						"Place %s on Bench" % held.item_name,
						"Leave the tool on the workbench for later use.",
						func() -> void: wb._try_place_tool(player),
						true
					)
					options.append(place_tool)
				else:
					var drop_tool := InteractionMenuOption.new(
						"drop_tool",
						"Drop %s to Ground" % held.item_name,
						"Place the tool on the floor so your hands are free.",
						func() -> void: player.carry_system.drop_item(),
						true
					)
					options.append(drop_tool)
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
		# Bench has a device (recovery / bug rescue)
		var dev: Device = wb.placed_device as Device if wb.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev, wb)
			)
			options.append(examine_opt)

		var is_holding_tool: bool = carry != null and carry.is_carrying() and carry.get_held_item() is ToolItem
		var can_pick: bool = carry != null and (carry.can_pick_up() or is_holding_tool)
		var pickup_label: String = "Pick Up Device" if not is_holding_tool else "Pick Up Device (Stow Tool)"
		var pickup := InteractionMenuOption.new(
			"pick_up",
			pickup_label,
			"Remove the device from the workbench.",
			func() -> void: wb._try_pick_up(player),
			can_pick
		)
		if not can_pick:
			pickup.disabled_reason = "Hands full"
		options.append(pickup)

	options.append(_create_cancel_option())
	return options


static func _build_repair_table_menu(table: RepairTableStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system
	var has_device_on_table: bool = table.placed_device != null

	if not has_device_on_table:
		if carry and carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is Device:
				var dev: Device = held as Device
				var can_place: bool = table._can_accept_repair_item(held)
				var place_opt := InteractionMenuOption.new(
					"place_device",
					"Place %s on Repair Table" % held.item_name,
					"Set down the %s for repair work." % held.item_name,
					func() -> void: table._on_interacted(player),
					can_place
				)
				if not can_place:
					if dev.current_repair_state == RepairState.State.RECEIVED:
						place_opt.disabled_reason = "Must be diagnosed at Diagnostic Bench first"
					elif dev.current_repair_state == RepairState.State.REASSEMBLED:
						place_opt.disabled_reason = "Hardware repair complete - take to Software Station"
					elif dev.current_repair_state == RepairState.State.TESTED:
						place_opt.disabled_reason = "Device tested - take to Delivery Counter"
					elif dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
						place_opt.disabled_reason = "No hardware repair needed (software only)"
					else:
						place_opt.disabled_reason = "Cannot repair at this table"
				options.append(place_opt)

				# Examine held device
				var examine_held := InteractionMenuOption.new(
					"examine",
					"Examine %s" % held.item_name,
					_build_device_description(dev),
					func() -> void: _trigger_device_examination(player, dev, table)
				)
				options.append(examine_held)
			elif held is ToolItem:
				if table.get_bench_tool() == null:
					var place_tool := InteractionMenuOption.new(
						"place_tool",
						"Place %s on Repair Table" % held.item_name,
						"Leave the tool on the repair table for later use.",
						func() -> void: table._try_place_tool(player),
						true
					)
					options.append(place_tool)
				else:
					var drop_tool := InteractionMenuOption.new(
						"drop_tool",
						"Drop %s to Ground" % held.item_name,
						"Place the tool on the floor so your hands are free.",
						func() -> void: player.carry_system.drop_item(),
						true
					)
					options.append(drop_tool)
		elif table.get_bench_tool() != null:
			var tool: ToolItem = table.get_bench_tool()
			var pickup_tool := InteractionMenuOption.new(
				"pick_up_tool",
				"Pick Up %s" % tool.tool_display_name,
				"Pick up the tool from the repair table.",
				func() -> void: table._try_pick_up_tool(player),
				carry != null and carry.can_pick_up()
			)
			if not pickup_tool.is_enabled:
				pickup_tool.disabled_reason = "Hands full"
			options.append(pickup_tool)
	else:
		# Table has a device
		var dev: Device = table.placed_device as Device if table.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev, table)
			)
			options.append(examine_opt)

			var r_state: String = str(dev.get_repair_state())
			match r_state:
				"DIAGNOSED":
					var has_tool: bool = table._has_required_tool(player)
					var disasm := InteractionMenuOption.new(
						"disassemble",
						"Disassemble Device",
						"Open the device to access internal components.",
						func() -> void:
							table.set_active_user(player)
							var hud := player.get_tree().get_first_node_in_group("hud") if (player and player.is_inside_tree()) else null
							if hud and not hud.is_queued_for_deletion() and hud.has_method("start_repair_minigame"):
								hud.start_repair_minigame(player, dev, "screw", func() -> void:
									var tool: ToolItem = table.get_bench_tool()
									if not tool and player and player.carry_system and player.carry_system.is_carrying():
										var held: Carriable = player.carry_system.get_held_item()
										if held is ToolItem: tool = held as ToolItem
									if tool: tool.use_tool()
									table._start_disassembly()
									table._complete_processing()
								)
							else:
								table._start_disassembly(),
						has_tool
					)
					if not has_tool:
						disasm.disabled_reason = "Needs %s" % table.required_tool_name
					options.append(disasm)

				"DISASSEMBLED":
					if carry and carry.is_carrying():
						var held: Carriable = carry.get_held_item()
						if held and held.item_type == "part":
							var is_valid_part: bool = table._is_valid_replacement_part(dev, held)
							var install := InteractionMenuOption.new(
								"install_part",
								"Install %s" % held.item_name,
								"Install this component into the device.",
								func() -> void: table._try_install_part(player),
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
					var has_tool: bool = table._has_required_tool(player)
					var reassem := InteractionMenuOption.new(
						"reassemble",
						"Reassemble Device",
						"Close up the device. Component installation complete.",
						func() -> void:
							table.set_active_user(player)
							var hud := player.get_tree().get_first_node_in_group("hud") if (player and player.is_inside_tree()) else null
							if hud and not hud.is_queued_for_deletion() and hud.has_method("start_repair_minigame"):
								hud.start_repair_minigame(player, dev, "screw", func() -> void:
									var tool: ToolItem = table.get_bench_tool()
									if not tool and player and player.carry_system and player.carry_system.is_carrying():
										var held: Carriable = player.carry_system.get_held_item()
										if held is ToolItem: tool = held as ToolItem
									if tool: tool.use_tool()
									table._start_reassembly()
									table._complete_processing()
								)
							else:
								table._start_reassembly(),
						has_tool
					)
					if not has_tool:
						reassem.disabled_reason = "Needs %s" % table.required_tool_name
					options.append(reassem)

			if carry and carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held is ToolItem:
					if table.get_bench_tool() == null:
						var stow_tool := InteractionMenuOption.new(
							"place_tool",
							"Place %s on Repair Table" % held.item_name,
							"Leave the tool on the table so your hands are free.",
							func() -> void: table._try_place_tool(player),
							true
						)
						options.append(stow_tool)
					else:
						var drop_tool := InteractionMenuOption.new(
							"drop_tool",
							"Drop %s to Ground" % held.item_name,
							"Place the tool on the floor so your hands are free.",
							func() -> void: player.carry_system.drop_item(),
							true
						)
						options.append(drop_tool)

			var is_holding_tool: bool = carry != null and carry.is_carrying() and carry.get_held_item() is ToolItem
			var can_pick: bool = carry != null and (carry.can_pick_up() or is_holding_tool)
			var pickup_label: String = "Pick Up Device" if not is_holding_tool else "Pick Up Device (Stow Tool)"
			var pickup := InteractionMenuOption.new(
				"pick_up",
				pickup_label,
				"Remove the device from the repair table.",
				func() -> void: table._try_pick_up(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)
		else:
			var is_holding_tool: bool = carry != null and carry.is_carrying() and carry.get_held_item() is ToolItem
			var can_pick: bool = carry != null and (carry.can_pick_up() or is_holding_tool)
			var pickup_label: String = "Pick Up Item" if not is_holding_tool else "Pick Up Item (Stow Tool)"
			var pickup := InteractionMenuOption.new(
				"pick_up",
				pickup_label,
				"Remove the item from the repair table.",
				func() -> void: table._try_pick_up(player),
				can_pick
			)
			if not can_pick:
				pickup.disabled_reason = "Hands full"
			options.append(pickup)

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
					func() -> void: _trigger_device_examination(player, held as Device, diag)
				)
				options.append(examine_held)
	else:
		var dev: Device = diag.placed_device as Device if diag.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev, diag)
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
		# Open visual catalog UI
		var open_catalog := InteractionMenuOption.new(
			"open_parts_catalog",
			"Select Component (Open Visual Catalog)",
			"Open visual shelf UI with component cards and stock counts.",
			func() -> void:
				var hud := player.get_tree().get_first_node_in_group("hud") if (player and player.is_inside_tree()) else null
				if hud and hud.has_method("open_parts_shelf_panel"):
					hud.open_parts_shelf_panel(player, shelf)
				else:
					shelf._on_interacted(player),
			true
		)
		options.append(open_catalog)

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
					func() -> void: _trigger_device_examination(player, held as Device, soft)
				)
				options.append(examine_held)
	else:
		var dev: Device = soft.placed_device as Device if soft.placed_device is Device else null
		if dev:
			var examine_opt := InteractionMenuOption.new(
				"examine",
				"Examine Device",
				_build_device_description(dev),
				func() -> void: _trigger_device_examination(player, dev, soft)
			)
			options.append(examine_opt)

		if soft.current_state == BaseStation.StationState.COMPLETE:
			var is_holding_tool: bool = carry != null and carry.is_carrying() and carry.get_held_item() is ToolItem
			var can_pick: bool = carry != null and (carry.can_pick_up() or is_holding_tool)
			var pickup_label: String = "Pick Up Tested Device" if not is_holding_tool else "Pick Up Tested Device (Drop Tool)"
			var pickup := InteractionMenuOption.new(
				"pick_up",
				pickup_label,
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
				func() -> void: _trigger_device_examination(player, dev, reception)
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
				func() -> void: _trigger_device_examination(player, held as Device, delivery)
			)
			options.append(examine_opt)

	options.append(_create_cancel_option())
	return options


static func _build_trash_menu(trash: BaseStation, player: PlayerCharacter) -> Array[InteractionMenuOption]:
	var options: Array[InteractionMenuOption] = []
	var carry: CarrySystem = player.carry_system

	if carry and carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is ToolItem:
			var opt := InteractionMenuOption.new(
				"trash_tool_blocked",
				"Cannot Trash Tool",
				"Tools are valuable workshop equipment and cannot be trashed.",
				Callable(),
				false
			)
			opt.disabled_reason = "Cannot trash tools"
			options.append(opt)
		elif held is Device or held.item_type == "device":
			var opt := InteractionMenuOption.new(
				"trash_device_blocked",
				"Cannot Trash Customer Device",
				"Customer devices cannot be thrown in the trash!",
				Callable(),
				false
			)
			opt.disabled_reason = "Cannot trash customer devices"
			options.append(opt)
		else:
			var trash_opt := InteractionMenuOption.new(
				"trash_item",
				"Throw %s in Trash" % held.item_name,
				"Discard this item permanently into the trash bin.",
				func() -> void:
					if trash is TrashBin:
						(trash as TrashBin).dispose_item(player)
					elif trash.has_method("dispose_item"):
						trash.dispose_item(player)
					else:
						trash._on_interacted(player),
				true
			)
			options.append(trash_opt)
	else:
		var empty_opt := InteractionMenuOption.new(
			"trash_empty_hands",
			"Trash Bin Empty",
			"You are not carrying anything to throw into the trash.",
			Callable(),
			false
		)
		empty_opt.disabled_reason = "Hands empty"
		options.append(empty_opt)

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


static func _trigger_device_examination(player: PlayerCharacter, dev: Device, station: BaseStation = null) -> void:
	if not dev or not player:
		return
	SignalBus.device_examined.emit(player.player_index, dev.item_name)
	var hud := player.get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_examination_panel"):
		hud.open_examination_panel(player, dev, station)
