extends Node

## Test suite for Shared Inventory & Item Contention
## Tests:
## 1. Item claim system exclusivity (only one player can claim an item)
## 2. Carriable claimed_by field and try_claim / can_claim / release_claim
## 3. Claim expiration timer (claims auto-expire if not picked up)
## 4. Reception Desk: only one player can take the device per order
## 5. Parts Shelf: each player can independently get parts (separate instances)
## 6. Items dropped on the floor are available to anyone (no permanent ownership)
## 7. Contention detection and claim flash when another player is reaching for / focusing on an item
## 8. SignalBus integration (item_claimed signal with contested flag)

const PLAYER_SCENE_PATH: String = "res://scenes/characters/PlayerCharacter.tscn"
const DEVICE_SCENE_PATH: String = "res://scenes/devices/Device.tscn"
const RECEPTION_SCENE_PATH: String = "res://scenes/stations/ReceptionDesk.tscn"
const PARTS_SHELF_SCENE_PATH: String = "res://scenes/stations/PartsShelf.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 2E SHARED INVENTORY & CONTENTION TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_carriable_claim_basics()
	failures += test_claim_expiration_timeout()
	failures += test_claim_locking_prevents_simultaneous_pickup()
	failures += test_same_player_reclaiming()
	failures += test_floor_drop_releases_ownership()
	failures += test_reception_desk_exclusivity()
	failures += test_parts_shelf_independence()
	failures += test_ground_part_pickup()
	failures += test_contested_claim_detection_and_flash()
	failures += test_signalbus_item_claimed_emission()

	print("=========================================================")
	print("--- PHASE 2E TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 2E SHARED INVENTORY TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 2E tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_player(index: int) -> PlayerCharacter:
	var scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player: PlayerCharacter = scene.instantiate() as PlayerCharacter
	player.player_index = index
	add_child(player)
	return player


## 1. Verify Carriable claim fields and API
func test_carriable_claim_basics() -> int:
	print("\n[1] Testing Carriable claim fields and methods...")
	var err: int = 0

	var item := Carriable.new()
	add_child(item)

	err += _assert(item.claimed_by == null, "claimed_by is initially null")
	err += _assert(item.can_claim(null), "can_claim is true initially")

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# P1 claims item
	var claim_ok: bool = item.try_claim(p1)
	err += _assert(claim_ok, "p1 successfully claims unclaimed item")
	err += _assert(item.claimed_by == p1, "claimed_by is now p1")
	err += _assert(item.can_claim(p1), "p1 can still claim their own claimed item")
	err += _assert(not item.can_claim(p2), "p2 cannot claim item claimed by p1")

	# P2 attempts claim while claimed by P1
	var p2_claim: bool = item.try_claim(p2)
	err += _assert(not p2_claim, "p2 try_claim fails when claimed by p1")
	err += _assert(item.claimed_by == p1, "claimed_by remains p1")

	# Manual release
	item.release_claim()
	err += _assert(item.claimed_by == null, "claimed_by is null after release_claim")
	err += _assert(item.can_claim(p2), "p2 can claim after release_claim")

	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 2. Verify claim expiration timeout (100ms auto-expiration)
func test_claim_expiration_timeout() -> int:
	print("\n[2] Testing claim duration auto-expiration...")
	var err: int = 0

	var item := Carriable.new()
	add_child(item)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	item.try_claim(p1)
	err += _assert(item.claimed_by == p1, "p1 holds claim")

	# Simulate 0.05s elapsed (halfway through 0.1s CLAIM_DURATION)
	item._process(0.05)
	err += _assert(item.claimed_by == p1, "p1 still holds claim at 50ms")

	# Simulate another 0.06s elapsed (total 0.11s > 0.10s CLAIM_DURATION)
	item._process(0.06)
	err += _assert(item.claimed_by == null, "claim expired after CLAIM_DURATION timeout")
	err += _assert(item.can_claim(p2), "p2 can now claim expired item")

	# P2 can now claim it
	err += _assert(item.try_claim(p2), "p2 successfully claims after timeout")
	err += _assert(item.claimed_by == p2, "p2 is now claimant")

	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 3. Verify claim locking prevents simultaneous pick up in CarrySystem
func test_claim_locking_prevents_simultaneous_pickup() -> int:
	print("\n[3] Testing CarrySystem claim locking on simultaneous grab...")
	var err: int = 0

	var item := Carriable.new()
	item.item_name = "ContestedWidget"
	add_child(item)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# P1 claims and picks up
	p1.carry_system.pick_up(item)
	err += _assert(p1.carry_system.is_carrying(), "p1 picked up item")
	err += _assert(p1.carry_system.get_held_item() == item, "p1 is carrying the item")
	err += _assert(item.is_held, "item.is_held is true")
	err += _assert(item.held_by == p1, "item.held_by is p1")

	# P2 attempts pick up of already-held item
	p2.carry_system.pick_up(item)
	err += _assert(not p2.carry_system.is_carrying(), "p2 cannot pick up item held by p1")
	err += _assert(item.held_by == p1, "item.held_by remains p1")

	# Clean up
	p1.carry_system.drop_item()
	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 4. Verify same player re-claiming succeeds
func test_same_player_reclaiming() -> int:
	print("\n[4] Testing same player re-claiming...")
	var err: int = 0

	var item := Carriable.new()
	add_child(item)
	var p1 := _create_player(0)

	err += _assert(item.try_claim(p1), "initial claim by p1 succeeds")
	item._process(0.08) # Almost expired
	err += _assert(item.try_claim(p1), "re-claiming by p1 succeeds and refreshes timer")
	item._process(0.05)
	err += _assert(item.claimed_by == p1, "claim still active due to refresh")

	item.queue_free()
	p1.queue_free()
	return err


## 5. Verify dropping on floor releases ownership
func test_floor_drop_releases_ownership() -> int:
	print("\n[5] Testing floor drop releases ownership...")
	var err: int = 0

	var item := Carriable.new()
	item.item_name = "FloorItem"
	add_child(item)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	p1.carry_system.pick_up(item)
	err += _assert(item.is_held, "item is held by p1")

	p1.carry_system.drop_item()
	err += _assert(not item.is_held, "item is not held after drop")
	err += _assert(item.claimed_by == null, "claimed_by is cleared on drop")
	err += _assert(item.held_by == null, "held_by is cleared on drop")
	err += _assert(item.can_claim(p2), "p2 can claim item dropped on floor")

	# P2 picks it up from floor
	p2.carry_system.pick_up(item)
	err += _assert(p2.carry_system.is_carrying(), "p2 picked up dropped item from floor")
	err += _assert(item.held_by == p2, "item is now held by p2")

	p2.carry_system.drop_item()
	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 6. Verify Reception Desk: only one player can take the device per order
func test_reception_desk_exclusivity() -> int:
	print("\n[6] Testing Reception Desk device pickup exclusivity...")
	var err: int = 0

	var desk: ReceptionDesk = load(RECEPTION_SCENE_PATH).instantiate() as ReceptionDesk
	add_child(desk)

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	desk.spawn_incoming_device(dev)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	err += _assert(desk.has_device(), "desk has device")
	err += _assert(desk.can_player_interact(p1), "p1 can interact with desk")
	err += _assert(desk.can_player_interact(p2), "p2 can interact with desk")

	# P1 claims the device on desk
	dev.try_claim(p1)
	err += _assert(not desk.can_player_interact(p2), "p2 cannot interact once dev is claimed by p1")
	var prompt_p2 := desk.get_interaction_prompt(p2)
	err += _assert(prompt_p2.begins_with("Claimed by P1"), "prompt indicates claimed by P1 (got: %s)" % prompt_p2)

	# P1 takes the device
	desk._on_interacted(p1)
	err += _assert(p1.carry_system.is_carrying(), "p1 took device from desk")
	err += _assert(not desk.has_device(), "desk is now empty")
	err += _assert(not desk.can_player_interact(p2), "p2 cannot interact with empty desk")

	# If P2 also calls _on_interacted, nothing happens
	desk._on_interacted(p2)
	err += _assert(not p2.carry_system.is_carrying(), "p2 did not get device")

	p1.carry_system.drop_item()
	dev.queue_free()
	desk.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 7. Verify Parts Shelf independence: separate parts spawned per request
func test_parts_shelf_independence() -> int:
	print("\n[7] Testing Parts Shelf multi-player independence...")
	var err: int = 0

	var shelf: PartsShelf = load(PARTS_SHELF_SCENE_PATH).instantiate() as PartsShelf
	add_child(shelf)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	err += _assert(shelf.can_player_interact(p1), "p1 can interact with parts shelf")
	err += _assert(shelf.can_player_interact(p2), "p2 can interact with parts shelf")

	# P1 takes a part
	shelf._on_interacted(p1)
	err += _assert(p1.carry_system.is_carrying(), "p1 got a part")
	var part1: Carriable = p1.carry_system.get_held_item()

	# P2 also takes a part concurrently
	err += _assert(shelf.can_player_interact(p2), "p2 can still interact with parts shelf")
	shelf._on_interacted(p2)
	err += _assert(p2.carry_system.is_carrying(), "p2 got a part")
	var part2: Carriable = p2.carry_system.get_held_item()

	# Verify they are two completely independent instances
	err += _assert(part1 != null and part2 != null, "both parts are valid instances")
	err += _assert(part1 != part2, "part1 and part2 are distinct Carriable instances")
	err += _assert(part1.held_by == p1, "part1 held by p1")
	err += _assert(part2.held_by == p2, "part2 held by p2")

	p1.carry_system.drop_item()
	p2.carry_system.drop_item()
	part1.queue_free()
	part2.queue_free()
	shelf.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 8. Verify ground part pickup via setup_interaction_zone
func test_ground_part_pickup() -> int:
	print("\n[8] Testing dropped part pickup from floor...")
	var err: int = 0

	var shelf: PartsShelf = load(PARTS_SHELF_SCENE_PATH).instantiate() as PartsShelf
	add_child(shelf)

	var p1 := _create_player(0)
	var p2 := _create_player(1)

	# P1 gets part and drops it
	shelf._on_interacted(p1)
	var part: Carriable = p1.carry_system.get_held_item()
	err += _assert(part.interaction_zone != null, "part has interaction_zone for ground pickup")

	p1.carry_system.drop_item()
	err += _assert(not part.is_held, "part dropped on floor")
	err += _assert(part.interaction_zone.is_interactable, "part interaction_zone is interactable on floor")

	# P2 picks up the part from the floor
	part.interaction_zone.interact(p2)
	err += _assert(p2.carry_system.is_carrying(), "p2 picked up dropped part from floor")
	err += _assert(p2.carry_system.get_held_item() == part, "p2 holds the dropped part")
	err += _assert(not part.interaction_zone.is_interactable, "interaction_zone disabled while held by p2")

	p2.carry_system.drop_item()
	part.queue_free()
	shelf.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 9. Verify contested claim detection and claim flash
func test_contested_claim_detection_and_flash() -> int:
	print("\n[9] Testing contested claim detection and flash...")
	var err: int = 0

	var dev: Device = load(DEVICE_SCENE_PATH).instantiate() as Device
	add_child(dev)
	dev.global_position = Vector3(0.0, 0.0, 0.0)

	var p1 := _create_player(0)
	p1.global_position = Vector3(0.5, 0.0, 0.0)

	var p2 := _create_player(1)
	p2.global_position = Vector3(0.8, 0.0, 0.0) # Close to dev (< 2.2m)

	# Contested signal tracker
	var tracker := {"count": 0, "claiming_p": null}
	dev.claim_contested.connect(func(claiming_p: PlayerCharacter) -> void:
		tracker.count += 1
		tracker.claiming_p = claiming_p
	)

	# P1 grabs item while P2 is also right next to it
	err += _assert(dev.is_contested_by_other_players(p1), "dev is contested by nearby p2")
	p1.carry_system.pick_up(dev)

	err += _assert(tracker.count == 1, "claim_contested signal fired on contested grab")
	err += _assert(tracker.claiming_p == p1, "claim_contested passed correct claiming player")
	err += _assert(p1.carry_system.is_carrying(), "p1 carries the contested item")

	p1.carry_system.drop_item()
	dev.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err


## 10. Verify SignalBus.item_claimed emission with contested flag
func test_signalbus_item_claimed_emission() -> int:
	print("\n[10] Testing SignalBus.item_claimed emission...")
	var err: int = 0

	var item := Carriable.new()
	item.item_name = "SignalItem"
	add_child(item)

	var p1 := _create_player(0)
	var p2 := _create_player(1)
	p1.global_position = Vector3(0.0, 0.0, 0.0)
	p2.global_position = Vector3(10.0, 0.0, 0.0) # Far away (> 2.2m)

	var received_signal := {
		"item_name": "",
		"player_id": -1,
		"contested": false,
		"fired": false
	}

	SignalBus.item_claimed.connect(
		func(name: String, pid: int, contested: bool) -> void:
			received_signal.item_name = name
			received_signal.player_id = pid
			received_signal.contested = contested
			received_signal.fired = true
	)

	# Pick up uncontested
	p1.carry_system.pick_up(item)
	err += _assert(received_signal.fired, "SignalBus.item_claimed was emitted")
	err += _assert(received_signal.item_name == "SignalItem", "item_name matches")
	err += _assert(received_signal.player_id == 0, "player_id matches p1")
	err += _assert(not received_signal.contested, "contested is false when other player is far")

	p1.carry_system.drop_item()
	item.queue_free()
	p1.queue_free()
	p2.queue_free()
	return err
