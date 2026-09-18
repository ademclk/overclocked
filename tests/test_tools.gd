extends Node

## Test suite for Phase 3C: Tool System
## Tests ToolItem carriable mechanics, Screwdriver scene, workbench tool requirements,
## bench tool placement and persistence, wrong tool detection, and WorkshopDebug integration.

const SCREWDRIVER_SCENE_PATH: String = "res://scenes/tools/Screwdriver.tscn"
const WORKBENCH_SCENE_PATH: String = "res://scenes/stations/WorkbenchStation.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT_PATH: String = "res://resources/faults/phone_cracked_screen.tres"
const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/Workshop_Debug.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 3C TOOL SYSTEM TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_tool_item_properties_and_visuals()
	failures += test_tool_carriable_and_claim_system()
	failures += test_workbench_tool_requirement_disassembly()
	failures += test_workbench_tool_requirement_reassembly()
	failures += test_workbench_tool_persistence_and_retrieval()
	failures += test_wrong_tool_rejection()
	failures += test_workshop_debug_tool_spawning_and_hotkeys()

	print("=========================================================")
	print("--- PHASE 3C TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 3C TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 3C tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		print("  [FAIL] %s" % test_name)
		return 1


## 1. Test ToolItem properties, visuals, and fall-through protection
func test_tool_item_properties_and_visuals() -> int:
	print("\n[1] Testing ToolItem properties, visuals, and safety bounds...")
	var err: int = 0

	var tool := ToolItem.new()
	tool.tool_id = "screwdriver"
	tool.tool_display_name = "Screwdriver"
	add_child(tool)

	err += _assert(tool.item_type == "tool", "tool.item_type is 'tool'")
	err += _assert(tool.item_name == "Screwdriver", "tool.item_name is 'Screwdriver'")
	err += _assert(tool.is_in_group("tools"), "tool is in 'tools' group")

	var mesh_inst: MeshInstance3D = tool.get_node_or_null("MeshInstance3D") as MeshInstance3D
	err += _assert(mesh_inst != null, "Tool dynamically created MeshInstance3D")
	err += _assert(mesh_inst.mesh is BoxMesh, "Tool mesh is a BoxMesh")

	# Test additional tool visuals
	var soldering_iron := ToolItem.new()
	soldering_iron.tool_id = "soldering_iron"
	soldering_iron.tool_display_name = "Soldering Iron"
	add_child(soldering_iron)
	var iron_mesh: MeshInstance3D = soldering_iron.get_node_or_null("MeshInstance3D") as MeshInstance3D
	err += _assert(iron_mesh != null and iron_mesh.mesh is BoxMesh, "Soldering iron created mesh")
	err += _assert((iron_mesh.mesh as BoxMesh).size.y > 0.25, "Soldering iron has elongated mesh")

	# Test fall protection safety check: y < -1.0 resets to spawn_position
	tool.spawn_position = Vector3(1.0, 0.5, 2.0)
	tool.global_position = Vector3(1.0, -2.5, 2.0)
	tool._physics_process(0.016)
	err += _assert(tool.global_position == tool.spawn_position, "Tool falling below -1.0 Y resets to spawn_position")

	tool.queue_free()
	soldering_iron.queue_free()
	return err


## 2. Test Tool Carriable, drop, and multiplayer contention
func test_tool_carriable_and_claim_system() -> int:
	print("\n[2] Testing Tool carriable mechanics and multiplayer contention...")
	var err: int = 0

	var sd_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	var tool: ToolItem = sd_scene.instantiate() as ToolItem
	add_child(tool)
	tool.global_position = Vector3(0, 0, 0)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var p1: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	p1.player_index = 0
	add_child(p1)

	var p2: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	p2.player_index = 1
	add_child(p2)

	# P1 picks up tool
	err += _assert(tool.interaction_zone != null, "Screwdriver scene has interaction_zone")
	err += _assert(tool.can_claim(p1), "P1 can claim tool on floor")
	p1.carry_system.pick_up(tool)
	err += _assert(p1.carry_system.is_carrying(), "P1 is carrying screwdriver")
	err += _assert(p1.carry_system.get_held_item() == tool, "P1 held item is the screwdriver")
	err += _assert(tool.is_held, "tool.is_held is true")

	# P2 cannot pick up while P1 is holding
	err += _assert(not tool.can_claim(p2), "P2 cannot claim tool held by P1")
	err += _assert(not tool.try_claim(p2), "P2 try_claim rejected")

	# P1 drops tool
	p1.carry_system.drop_item()
	err += _assert(not p1.carry_system.is_carrying(), "P1 hands empty after drop")
	err += _assert(not tool.is_held, "tool is no longer held")
	err += _assert(tool.can_claim(p2), "P2 can now claim dropped screwdriver")

	# P2 picks up tool
	p2.carry_system.pick_up(tool)
	err += _assert(p2.carry_system.is_carrying(), "P2 successfully picked up screwdriver")
	err += _assert(p2.carry_system.get_held_item() == tool, "P2 held item is screwdriver")

	p1.queue_free()
	p2.queue_free()
	tool.queue_free()
	return err


## 3. Test Workbench tool requirement for disassembly
func test_workbench_tool_requirement_disassembly() -> int:
	print("\n[3] Testing Workbench disassembly requiring screwdriver...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = true
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	add_child(dev)

	# Place DIAGNOSED device on workbench
	player.carry_system.pick_up(dev)
	wb._on_interacted(player)

	err += _assert(wb.placed_device == dev, "Diagnosed device placed on workbench")
	err += _assert(not wb._is_processing, "Disassembly did NOT auto-start without tool")
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Device remains in DIAGNOSED state")
	err += _assert(not wb.can_player_interact(player), "Player without tool CANNOT interact to disassemble (action blocked)")
	err += _assert(wb.get_interaction_prompt(player) == "Needs screwdriver", "Prompt correctly displays 'Needs screwdriver'")

	# Player gets a screwdriver and returns to workbench
	var tool_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	var screwdriver: ToolItem = tool_scene.instantiate() as ToolItem
	add_child(screwdriver)
	player.carry_system.pick_up(screwdriver)

	err += _assert(wb.can_player_interact(player), "Player carrying screwdriver CAN interact with workbench")
	err += _assert(wb.get_interaction_prompt(player) == "Disassemble Device", "Prompt displays 'Disassemble Device'")

	# Interacting places tool on bench and starts disassembly
	wb._on_interacted(player)
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver placed on workbench as bench tool")
	err += _assert(not player.carry_system.is_carrying(), "Player hands freed after placing tool")
	err += _assert(wb._is_processing, "Disassembly processing is active")

	# Finish disassembly
	wb._physics_process(wb.disassembly_time + 0.1)
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Device reached DISASSEMBLED state")
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver persists on bench after disassembly")

	player.queue_free()
	dev.queue_free()
	screwdriver.queue_free()
	wb.queue_free()
	return err


## 4. Test Workbench reassembly requiring screwdriver
func test_workbench_tool_requirement_reassembly() -> int:
	print("\n[4] Testing Workbench reassembly requiring screwdriver...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = true
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)
	dev.advance_state(RepairState.State.PART_REPLACED)
	add_child(dev)

	wb.accept_device(dev)

	# Case A: Device in PART_REPLACED state, NO tool on bench, player empty-handed
	err += _assert(not wb.can_player_interact(player), "Player cannot reassemble without tool")
	err += _assert(wb.get_interaction_prompt(player) == "Needs screwdriver to reassemble", "Prompt displays 'Needs screwdriver to reassemble'")

	# Case B: Screwdriver placed on bench
	var sd_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	var screwdriver: ToolItem = sd_scene.instantiate() as ToolItem
	add_child(screwdriver)
	player.carry_system.pick_up(screwdriver)

	# Player places tool on bench
	wb._on_interacted(player)
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver placed on workbench")

	# Player with empty hands can now start reassembly
	err += _assert(wb.can_player_interact(player), "Player can now reassemble with bench tool present")
	err += _assert(wb.get_interaction_prompt(player) == "Reassemble Device", "Prompt is 'Reassemble Device'")

	wb._on_interacted(player)
	err += _assert(wb._is_processing, "Reassembly processing started")

	wb._physics_process(wb.reassembly_time + 0.1)
	err += _assert(dev.current_repair_state == RepairState.State.REASSEMBLED, "Device is REASSEMBLED")
	err += _assert(wb.current_state == BaseStation.StationState.COMPLETE, "Workbench state is COMPLETE")

	player.queue_free()
	dev.queue_free()
	screwdriver.queue_free()
	wb.queue_free()
	return err


## 5. Test Workbench tool persistence across repairs and retrieval
func test_workbench_tool_persistence_and_retrieval() -> int:
	print("\n[5] Testing Workbench tool persistence and retrieval...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = true
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	var sd_scene: PackedScene = load(SCREWDRIVER_SCENE_PATH)
	var screwdriver: ToolItem = sd_scene.instantiate() as ToolItem
	add_child(screwdriver)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	dev.advance_state(RepairState.State.DISASSEMBLED)
	dev.advance_state(RepairState.State.PART_REPLACED)
	dev.advance_state(RepairState.State.REASSEMBLED)
	add_child(dev)

	wb.accept_device(dev)
	wb.current_state = BaseStation.StationState.COMPLETE

	# Manually attach bench tool to simulate tool sitting on bench
	player.carry_system.pick_up(screwdriver)
	wb._try_place_tool(player)
	err += _assert(wb.get_bench_tool() == screwdriver, "Tool on bench alongside reassembled device")

	# Step 1: Player picks up the REASSEMBLED device
	wb._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == dev, "Player picked up reassembled device")
	err += _assert(wb.placed_device == null, "Workbench has no device placed")
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver persists on bench after device is removed")

	# Step 2: Player delivers/drops device, then returns to pick up the screwdriver
	player.carry_system.drop_item()
	err += _assert(not player.carry_system.is_carrying(), "Player hands empty")
	err += _assert(wb.can_player_interact(player), "Player can interact to pick up tool from bench")
	err += _assert(wb.get_interaction_prompt(player) == "Pick Up Screwdriver", "Prompt is 'Pick Up Screwdriver'")

	wb._on_interacted(player)
	err += _assert(player.carry_system.get_held_item() == screwdriver, "Player picked up screwdriver from bench")
	err += _assert(wb.get_bench_tool() == null, "Workbench tool slot is now empty")

	# Step 3: Player places screwdriver on empty workbench
	err += _assert(wb.can_player_interact(player), "Player can place screwdriver on empty workbench")
	err += _assert(wb.get_interaction_prompt(player) == "Place Screwdriver on Workbench", "Prompt is 'Place Screwdriver on Workbench'")
	wb._on_interacted(player)
	err += _assert(wb.get_bench_tool() == screwdriver, "Screwdriver placed on empty workbench")
	err += _assert(not player.carry_system.is_carrying(), "Player hands free after placing on empty workbench")

	player.queue_free()
	dev.queue_free()
	screwdriver.queue_free()
	wb.queue_free()
	return err


## 6. Test wrong tool detection and rejection
func test_wrong_tool_rejection() -> int:
	print("\n[6] Testing wrong tool detection and rejection...")
	var err: int = 0

	var wb_scene: PackedScene = load(WORKBENCH_SCENE_PATH)
	var wb: WorkbenchStation = wb_scene.instantiate() as WorkbenchStation
	wb.requires_tool = true
	wb.required_tool_id = "screwdriver"
	wb.required_tool_name = "screwdriver"
	add_child(wb)

	var p_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = p_scene.instantiate() as PlayerCharacter
	add_child(player)

	# Create wrong tool (soldering iron)
	var wrong_tool := ToolItem.new()
	wrong_tool.tool_id = "soldering_iron"
	wrong_tool.tool_display_name = "Soldering Iron"
	add_child(wrong_tool)
	player.carry_system.pick_up(wrong_tool)

	var dev_scene: PackedScene = load(DEVICE_SCENE_PATH)
	var dev: Device = dev_scene.instantiate() as Device
	dev.initialize(load(PHONE_DATA_PATH), load(CRACKED_SCREEN_FAULT_PATH))
	dev.diagnose()
	add_child(dev)
	wb.accept_device(dev)

	err += _assert(wb._has_wrong_tool(player), "wb._has_wrong_tool returns true for soldering iron")
	err += _assert(not wb.can_player_interact(player), "Wrong tool interaction is blocked")
	err += _assert(wb.get_interaction_prompt(player) == "Wrong Tool: Needs screwdriver", "Prompt displays 'Wrong Tool: Needs screwdriver'")

	player.queue_free()
	dev.queue_free()
	wrong_tool.queue_free()
	wb.queue_free()
	return err


## 7. Test WorkshopDebug tool spawning and hotkeys
func test_workshop_debug_tool_spawning_and_hotkeys() -> int:
	print("\n[7] Testing WorkshopDebug tool spawning and hotkeys...")
	var err: int = 0

	var ws_scene: PackedScene = load(WORKSHOP_SCENE_PATH)
	var workshop: WorkshopDebug = ws_scene.instantiate() as WorkshopDebug
	workshop.auto_spawn_player = true
	workshop.auto_start_round = false
	workshop.screwdriver_count = 2
	add_child(workshop)

	err += _assert(workshop.has_node("Tools"), "Workshop has 'Tools' container node")

	# Start round -> spawns tools
	workshop.start_round()

	var tools := workshop.get_all_tools()
	err += _assert(tools.size() == 2, "Workshop spawned 2 screwdrivers at round start")
	for t in tools:
		err += _assert(t is ToolItem and t.tool_id == "screwdriver", "Spawned item is a screwdriver ToolItem")

	# Test Ctrl+F7 hotkey toggles workbench requires_tool
	err += _assert(workshop.workbench.requires_tool == true, "Workbench requires_tool is initially true")
	workshop._debug_toggle_tool_requirement()
	err += _assert(workshop.workbench.requires_tool == false, "Ctrl+F7 toggled requires_tool to false")
	workshop._debug_toggle_tool_requirement()
	err += _assert(workshop.workbench.requires_tool == true, "Ctrl+F7 toggled requires_tool back to true")

	workshop.queue_free()
	return err
