extends Node

## Test suite for Phase 4F — RepairState & Pipeline Adjustments
## Validates skip_states handling for router firmware fault,
## two-player carry request initiation, timeout countdown, cancellation,
## two-player cooperative carry speed penalty and drop synchronization,
## solo heavy carry speed penalty (40%), and HUD/label visual feedback.

const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")
const DESKTOP_SCENE: PackedScene = preload("res://scenes/devices/DesktopPC.tscn")

func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 4F PIPELINE ADJUSTMENTS TEST SUITE ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_skip_states_router_firmware()
	failures += test_skip_states_regression_standard_pipeline()
	failures += test_two_player_carry_request_and_cancel()
	failures += test_two_player_cooperative_carry_flow()
	failures += test_co_carry_timeout_fallback_to_solo_heavy()
	failures += test_solo_heavy_pickup_single_player()
	failures += test_hud_co_carry_and_solo_heavy_feedback()

	print("=========================================================")
	print("--- PHASE 4F TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 4F TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 4F tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, test_name: String) -> int:
	if condition:
		print("  [PASS] %s" % test_name)
		return 0
	else:
		printerr("  [FAIL] %s" % test_name)
		return 1


func _create_player(idx: int) -> PlayerCharacter:
	var p: PlayerCharacter = PLAYER_SCENE.instantiate() as PlayerCharacter
	p.player_index = idx
	p.add_to_group("players")
	add_child(p)
	return p


func _cleanup_player(p: PlayerCharacter) -> void:
	if p and is_instance_valid(p):
		p.remove_from_group("players")
		p.queue_free()


func _create_desktop(fault: FaultData = null) -> Device:
	var dev: Device = DESKTOP_SCENE.instantiate() as Device
	var desktop_data: DeviceData = load("res://resources/devices/desktop_pc.tres") as DeviceData
	add_child(dev)
	if fault == null and not desktop_data.possible_faults.is_empty():
		fault = desktop_data.possible_faults[0]
	dev.initialize(desktop_data, fault)
	return dev


## 1. Test skip_states on Router Firmware fault
func test_skip_states_router_firmware() -> int:
	print("\n[1] Testing FaultData.skip_states on router firmware fault...")
	var err: int = 0

	var router_data: DeviceData = load("res://resources/devices/router.tres") as DeviceData
	err += _assert(router_data != null, "Loaded router.tres")
	if not router_data:
		return err + 1

	var fw_fault: FaultData = router_data.get_fault_by_id("router_firmware_corrupt")
	err += _assert(fw_fault != null, "Found router_firmware_corrupt fault")
	if not fw_fault:
		return err + 1

	err += _assert(fw_fault.skip_states == ["DISASSEMBLED", "PART_REPLACED", "REASSEMBLED"],
		"skip_states correctly specifies hardware states to skip")

	var dev := Device.new()
	add_child(dev)
	dev.initialize(router_data, fw_fault)
	err += _assert(dev.current_repair_state == RepairState.State.RECEIVED, "Initial state is RECEIVED")

	# Diagnose device
	var diag_adv: bool = dev.advance_repair_state()
	err += _assert(diag_adv, "Advanced to DIAGNOSED")
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Current state is DIAGNOSED")

	# Advance from DIAGNOSED: normally goes to DISASSEMBLED, but with skip_states should jump to SOFTWARE_INSTALLED!
	var skip_adv: bool = dev.advance_repair_state()
	err += _assert(skip_adv, "Advanced past skipped hardware states")
	err += _assert(dev.current_repair_state == RepairState.State.SOFTWARE_INSTALLED,
		"Device jumped directly to SOFTWARE_INSTALLED (bypassed DISASSEMBLED, PART_REPLACED, REASSEMBLED)")

	# Next advance goes to TESTED
	var test_adv: bool = dev.advance_repair_state()
	err += _assert(test_adv, "Advanced to TESTED")
	err += _assert(dev.current_repair_state == RepairState.State.TESTED, "Current state is TESTED")

	# Final advance goes to DELIVERED
	var deliv_adv: bool = dev.advance_repair_state()
	err += _assert(deliv_adv, "Advanced to DELIVERED")
	err += _assert(dev.current_repair_state == RepairState.State.DELIVERED, "Current state is DELIVERED")

	dev.queue_free()
	return err


## 2. Test regression: standard pipeline faults without skip_states
func test_skip_states_regression_standard_pipeline() -> int:
	print("\n[2] Testing standard pipeline regression without skip_states...")
	var err: int = 0

	var phone_data: DeviceData = load("res://resources/devices/phone.tres") as DeviceData
	var phone_fault: FaultData = phone_data.get_fault_by_id("phone_cracked_screen")
	err += _assert(phone_fault != null, "Loaded phone_cracked_screen fault")
	err += _assert(phone_fault.skip_states.is_empty(), "Phone fault skip_states is empty")

	var dev := Device.new()
	add_child(dev)
	dev.initialize(phone_data, phone_fault)

	# Normal sequential flow
	dev.advance_repair_state()
	err += _assert(dev.current_repair_state == RepairState.State.DIAGNOSED, "Phone goes to DIAGNOSED")
	dev.advance_repair_state()
	err += _assert(dev.current_repair_state == RepairState.State.DISASSEMBLED, "Phone goes to DISASSEMBLED (not skipped)")
	dev.advance_repair_state()
	err += _assert(dev.current_repair_state == RepairState.State.PART_REPLACED, "Phone goes to PART_REPLACED")
	dev.advance_repair_state()
	err += _assert(dev.current_repair_state == RepairState.State.REASSEMBLED, "Phone goes to REASSEMBLED")

	dev.queue_free()
	return err


## 3. Test two-player carry request initiation and manual cancellation
func test_two_player_carry_request_and_cancel() -> int:
	print("\n[3] Testing two-player carry request initiation and cancellation...")
	var err: int = 0

	var dev := _create_desktop()
	err += _assert(dev.device_data != null and dev.device_data.carry_requires_two_players, "Desktop PC requires two players")

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# P1 attempts to pick up Desktop -> Should start carry request since 2 players exist
	p1.carry_system.pick_up(dev)

	err += _assert(p1.carry_system.current_carry_state == CarrySystem.CarryState.CARRY_REQUESTED,
		"P1 carry state is CARRY_REQUESTED")
	err += _assert(p1.carry_system.is_carry_requested(), "is_carry_requested() returns true")
	err += _assert(not p1.carry_system.is_carrying(), "P1 is not holding item yet")
	err += _assert(dev.carry_request_active, "Device carry_request_active is true")
	err += _assert(dev.carry_requester == p1, "Device carry_requester is P1")
	err += _assert(dev.carry_request_timer > 2.9, "Carry request timer set to ~3.0s")
	err += _assert(dev.device_label != null and dev.device_label.text.contains("Waiting for P2"), "DeviceLabel shows co-carry waiting prompt")

	# P1 presses drop / cancels request
	p1.carry_system.cancel_two_player_carry_request()

	err += _assert(p1.carry_system.current_carry_state == CarrySystem.CarryState.IDLE, "P1 carry state is IDLE after cancel")
	err += _assert(not dev.carry_request_active, "Device carry_request_active is false after cancel")
	err += _assert(dev.carry_requester == null, "Device carry_requester cleared after cancel")
	err += _assert(dev.device_label != null and not dev.device_label.text.contains("Waiting for P2"), "DeviceLabel waiting hint cleared")

	dev.queue_free()
	_cleanup_player(p1)
	_cleanup_player(p2)
	return err


## 4. Test two-player cooperative carry flow: acceptance, speed penalty, synchronized drop
func test_two_player_cooperative_carry_flow() -> int:
	print("\n[4] Testing cooperative two-player carry acceptance, speed penalty, and drop...")
	var err: int = 0

	var p1 := _create_player(0)
	p1.global_position = Vector3(0, 0, 0)
	var p2 := _create_player(1)
	p2.global_position = Vector3(2.0, 0, 0)

	var dev := _create_desktop()

	# P1 initiates request
	p1.carry_system.pick_up(dev)
	err += _assert(p1.carry_system.is_carry_requested(), "P1 requested carry")

	# P2 accepts co-carry
	p2.carry_system.pick_up(dev)

	var expected_co_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.TWO_PLAYER_CARRY_SPEED_MULTIPLIER
	err += _assert(p1.carry_system.current_carry_state == CarrySystem.CarryState.CO_CARRYING, "P1 state is CO_CARRYING")
	err += _assert(p2.carry_system.current_carry_state == CarrySystem.CarryState.CO_CARRYING, "P2 state is CO_CARRYING")
	err += _assert(p1.carry_system.is_co_carrying and p2.carry_system.is_co_carrying, "Both players is_co_carrying are true")
	err += _assert(p1.carry_system.co_carry_partner == p2, "P1 partner is P2")
	err += _assert(p2.carry_system.co_carry_partner == p1, "P2 partner is P1")
	err += _assert(is_equal_approx(p1.move_speed, expected_co_speed), "P1 move speed slowed to 60%")
	err += _assert(is_equal_approx(p2.move_speed, expected_co_speed), "P2 move speed slowed to 60%")
	err += _assert(not dev.carry_request_active, "Device carry request is no longer active")

	# Device midpoint calculation check
	var expected_mid_x: float = (p1.global_position.x + p2.global_position.x) * 0.5
	err += _assert(is_equal_approx(dev.global_position.x, expected_mid_x), "Device positioned at midpoint between players")

	# Either player drops -> both release
	p2.carry_system.drop_item()

	err += _assert(p1.carry_system.current_carry_state == CarrySystem.CarryState.IDLE, "P1 released to IDLE on partner drop")
	err += _assert(p2.carry_system.current_carry_state == CarrySystem.CarryState.IDLE, "P2 released to IDLE")
	err += _assert(not p1.carry_system.is_carrying() and not p2.carry_system.is_carrying(), "Neither player is carrying")
	err += _assert(is_equal_approx(p1.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "P1 move speed restored to 100%")
	err += _assert(is_equal_approx(p2.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "P2 move speed restored to 100%")

	dev.queue_free()
	_cleanup_player(p1)
	_cleanup_player(p2)
	return err


## 5. Test co-carry timeout fallback to solo heavy carry
func test_co_carry_timeout_fallback_to_solo_heavy() -> int:
	print("\n[5] Testing co-carry timeout auto-fallback to solo heavy carry...")
	var err: int = 0

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	var dev := _create_desktop()

	p1.carry_system.pick_up(dev)
	err += _assert(dev.carry_request_active, "Carry request is active")

	# Advance time past 3.0s timeout
	dev._process(3.5)

	var expected_solo_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.ONE_PLAYER_HEAVY_CARRY_SPEED
	err += _assert(not dev.carry_request_active, "Carry request closed after timeout")
	err += _assert(p1.carry_system.is_carrying(), "P1 is now carrying item after timeout")
	err += _assert(p1.carry_system.current_carry_state == CarrySystem.CarryState.CARRYING, "P1 state is CARRYING")
	err += _assert(p1.carry_system.is_solo_heavy_carrying(), "is_solo_heavy_carrying() returns true")
	err += _assert(is_equal_approx(p1.move_speed, expected_solo_speed), "P1 slowed to 40% speed for solo heavy carry")

	# Drop restores speed
	p1.carry_system.drop_item()
	err += _assert(is_equal_approx(p1.move_speed, Constants.DEFAULT_PLAYER_MOVE_SPEED), "P1 speed restored to 100% on drop")

	dev.queue_free()
	_cleanup_player(p1)
	_cleanup_player(p2)
	return err


## 6. Test solo heavy pickup directly in single player
func test_solo_heavy_pickup_single_player() -> int:
	print("\n[6] Testing solo heavy pickup when only 1 player is in game...")
	var err: int = 0

	var p1 := _create_player(0)
	var dev := _create_desktop()

	# Single player picks up -> should immediately enter solo heavy carry without 3s delay
	p1.carry_system.pick_up(dev)

	var expected_solo_speed: float = Constants.DEFAULT_PLAYER_MOVE_SPEED * Constants.ONE_PLAYER_HEAVY_CARRY_SPEED
	err += _assert(p1.carry_system.is_carrying(), "P1 immediately carrying desktop")
	err += _assert(not dev.carry_request_active, "No carry request needed for solo game")
	err += _assert(p1.carry_system.is_solo_heavy_carrying(), "is_solo_heavy_carrying() is true")
	err += _assert(is_equal_approx(p1.move_speed, expected_solo_speed), "P1 speed is 40%")

	p1.carry_system.drop_item()
	dev.queue_free()
	_cleanup_player(p1)
	return err


## 7. Test HUD visual feedback for co-carry and solo heavy carry
func test_hud_co_carry_and_solo_heavy_feedback() -> int:
	print("\n[7] Testing HUD visual feedback for co-carry and solo heavy carry...")
	var err: int = 0

	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn") as PackedScene
	var hud: HUD = hud_scene.instantiate() as HUD
	add_child(hud)

	var p1 := _create_player(0)
	var dev := _create_desktop()

	hud.setup_multiplayer([p1])

	# 1) Carry requested state: HUD prompt should show co-carry waiting text
	p1.carry_system.request_two_player_carry(dev)
	hud._update_interaction_prompt()
	err += _assert(hud.interaction_prompt.visible, "Prompt visible when carry requested")
	err += _assert(hud.prompt_label.text.contains("Waiting for second player"),
		"Prompt shows 'Waiting for second player... (Press [Drop] to cancel)'")

	# 2) Solo heavy carry: HUD prompt should show warning banner when carrying alone
	p1.carry_system.cancel_two_player_carry_request()
	p1.carry_system.pick_up_solo_heavy(dev)
	hud._update_interaction_prompt()
	hud._update_repair_progress(dev)

	err += _assert(hud.interaction_prompt.visible, "Prompt visible while solo heavy carrying")
	err += _assert(hud.prompt_label.text.contains("Carrying alone — very slow"),
		"Prompt shows '⚠️ Carrying alone — very slow!'")
	err += _assert(hud.state_label.text.contains("Carrying alone"),
		"state_label contains '⚠️ Carrying alone!'")

	p1.carry_system.drop_item()
	dev.queue_free()
	_cleanup_player(p1)
	hud.queue_free()
	return err
