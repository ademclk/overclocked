extends Node

## Test suite for Phase 1B: InteractionSystem, CarrySystem, Interactable, and Carriable.


func _ready() -> void:
	print("--- RUNNING INTERACTION & CARRY TESTS ---")

	# 1. Test Interactable base class
	print("Testing Interactable base class...")
	var interactable := Interactable.new()
	assert(interactable.interaction_prompt == "Interact")
	assert(interactable.is_interactable == true)
	assert(interactable.has_signal("interacted"))
	assert(interactable.has_signal("focus_gained"))
	assert(interactable.has_signal("focus_lost"))

	# 2. Test Carriable base class
	print("Testing Carriable base class...")
	var carriable := Carriable.new()
	carriable.item_name = "TestGadget"
	carriable.item_type = "device"
	assert(carriable.is_held == false)
	assert(carriable.held_by == null)
	assert(carriable.has_signal("picked_up"))
	assert(carriable.has_signal("dropped"))
	assert(carriable.has_signal("placed_on_station"))

	# 3. Instantiate PlayerCharacter with child systems
	print("Testing PlayerCharacter with child systems...")
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	assert(player_scene != null, "Failed to load PlayerCharacter.tscn")

	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player)

	assert(player.interaction_system != null, "player.interaction_system missing")
	assert(player.carry_system != null, "player.carry_system missing")

	# 4. Test InteractionSystem range & focus detection
	print("Testing InteractionSystem detection and focus...")
	var zone1 := Interactable.new()
	zone1.name = "Zone1"
	zone1.interaction_prompt = "Examine Zone 1"
	var shape1 := CollisionShape3D.new()
	var box1 := BoxShape3D.new()
	box1.size = Vector3(1, 1, 1)
	shape1.shape = box1
	zone1.add_child(shape1)
	add_child(zone1)
	zone1.global_position = Vector3(1.0, 0.0, 0.0)

	var zone2 := Interactable.new()
	zone2.name = "Zone2"
	zone2.interaction_prompt = "Examine Zone 2"
	var shape2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(1, 1, 1)
	shape2.shape = box2
	zone2.add_child(shape2)
	add_child(zone2)
	zone2.global_position = Vector3(2.0, 0.0, 0.0)

	# Simulate area detection
	player.interaction_system._on_area_entered(zone2)
	player.interaction_system._update_focus()
	assert(
		player.interaction_system.get_current_focus() == zone2,
		"Zone2 should be focused when alone in range"
	)
	assert(zone2.is_focused == true, "Zone2 should have is_focused == true")
	assert(player.interaction_system.get_prompt_text() == "Examine Zone 2")

	# Now add zone1 which is closer (dist 1.0 < dist 2.0)
	player.interaction_system._on_area_entered(zone1)
	player.interaction_system._update_focus()
	assert(
		player.interaction_system.get_current_focus() == zone1,
		"Zone1 should gain focus as it is closer"
	)
	assert(zone1.is_focused == true, "Zone1 should now be focused")
	assert(zone2.is_focused == false, "Zone2 should have lost focus")

	# Test interaction trigger on focused interactable
	var interaction_results := {
		"interacted_zone": null,
		"player": null,
	}
	zone1.interacted.connect(
		func(p: PlayerCharacter) -> void:
			interaction_results.interacted_zone = zone1
			interaction_results.player = p
	)

	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player.interaction_system._unhandled_input(interact_event)
	assert(
		interaction_results.interacted_zone == zone1,
		"Interacting should trigger zone1.interacted"
	)
	assert(interaction_results.player == player, "Interacted player mismatch")

	# Test area exit
	player.interaction_system._on_area_exited(zone1)
	player.interaction_system._update_focus()
	assert(
		player.interaction_system.get_current_focus() == zone2,
		"Zone2 should regain focus after zone1 exits"
	)

	player.interaction_system._on_area_exited(zone2)
	player.interaction_system._update_focus()
	assert(
		player.interaction_system.get_current_focus() == null,
		"Focus should be null when all exit"
	)

	# 5. Test CarrySystem (Pickup, hold, single item rule, drop, place)
	print("Testing CarrySystem operations...")
	var test_item := Carriable.new()
	test_item.name = "TestPhone"
	test_item.item_name = "Phone"
	add_child(test_item)
	test_item.global_position = Vector3(0, 0, 0)

	var second_item := Carriable.new()
	second_item.name = "SecondPhone"
	second_item.item_name = "Phone2"
	add_child(second_item)

	# Signal tracking
	var carry_results := {
		"picked": null,
		"dropped": null,
		"global_picked": "",
		"global_dropped": "",
	}

	player.carry_system.item_picked.connect(
		func(item: Carriable) -> void: carry_results.picked = item
	)
	player.carry_system.item_dropped.connect(
		func(item: Carriable) -> void: carry_results.dropped = item
	)
	SignalBus.item_picked_up.connect(
		func(name: String, _pid: int) -> void: carry_results.global_picked = name
	)
	SignalBus.item_dropped.connect(
		func(name: String, _pid: int) -> void: carry_results.global_dropped = name
	)

	assert(player.carry_system.can_pick_up() == true, "Should be able to pick up initially")
	assert(player.carry_system.is_carrying() == false, "Should not be carrying initially")

	# Pick up first item
	player.carry_system.pick_up(test_item)
	assert(player.carry_system.is_carrying() == true, "is_carrying should be true")
	assert(player.carry_system.get_held_item() == test_item, "Held item mismatch")
	assert(test_item.is_held == true, "test_item.is_held should be true")
	assert(test_item.held_by == player, "test_item.held_by should be player")
	assert(test_item.get_parent() == player.carry_position, "Item should be parented to CarryPosition")
	assert(carry_results.picked == test_item, "item_picked signal was not emitted")
	assert(carry_results.global_picked == "Phone", "SignalBus.item_picked_up was not emitted")

	# Enforce single item limit
	assert(player.carry_system.can_pick_up() == false, "can_pick_up should be false when already carrying")
	player.carry_system.pick_up(second_item)
	assert(
		player.carry_system.get_held_item() == test_item,
		"Should reject picking up a second item"
	)

	# Drop item
	# Set player facing right (+X)
	player.character_model.rotation.y = atan2(1.0, 0.0) # PI/2 -> facing +X
	player.carry_system.drop_item()

	assert(player.carry_system.is_carrying() == false, "is_carrying should be false after drop")
	assert(player.carry_system.get_held_item() == null, "Held item should be null after drop")
	assert(test_item.is_held == false, "test_item.is_held should be false")
	assert(test_item.held_by == null, "test_item.held_by should be null")
	assert(test_item.get_parent() != player.carry_position, "Item should no longer be child of CarryPosition")
	assert(carry_results.dropped == test_item, "item_dropped signal was not emitted")
	assert(carry_results.global_dropped == "Phone", "SignalBus.item_dropped was not emitted")

	# Test drop position is in front of player
	var expected_drop_x: float = player.global_position.x + 0.8
	assert(
		is_equal_approx(test_item.global_position.x, expected_drop_x),
		"Dropped item X should be in front of player"
	)

	# Test drop via InputEventAction "drop"
	player.carry_system.pick_up(test_item)
	assert(player.carry_system.is_carrying() == true)
	var drop_event := InputEventAction.new()
	drop_event.action = &"drop"
	drop_event.pressed = true
	player.carry_system._unhandled_input(drop_event)
	assert(player.carry_system.is_carrying() == false, "Item should be dropped on 'drop' action")

	# Test place_on_station
	player.carry_system.pick_up(test_item)
	var dummy_station := Node3D.new()
	dummy_station.name = "DummyStation"
	add_child(dummy_station)

	var place_results := {
		"item": null,
		"station": null,
	}
	player.carry_system.item_placed.connect(
		func(it: Carriable, st: Node) -> void:
			place_results.item = it
			place_results.station = st
	)

	player.carry_system.place_on_station(dummy_station)
	assert(player.carry_system.is_carrying() == false)
	assert(place_results.item == test_item, "item_placed signal item mismatch")
	assert(place_results.station == dummy_station, "item_placed signal station mismatch")
	assert(test_item.is_held == false)

	print("--- ALL INTERACTION & CARRY TESTS PASSED SUCCESSFULLY ---")
	interactable.free()
	carriable.free()
	zone1.queue_free()
	zone2.queue_free()
	dummy_station.queue_free()
	test_item.queue_free()
	second_item.queue_free()
	player.queue_free()
	get_tree().quit(0)
