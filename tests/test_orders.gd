extends Node

## Test suite for Phase 1F: Order System
## Tests Order lifecycle, timer ticking, star thresholds, scoring,
## OrderData resources, OrderManager spawning, and delivery integration.

const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const CRACKED_SCREEN_FAULT: String = "res://resources/faults/phone_cracked_screen.tres"
const ORDER_PHONE_RESOURCE: String = "res://resources/orders/order_phone_repair.tres"


func _ready() -> void:
	print("--- RUNNING ORDER SYSTEM TESTS (PHASE 1F) ---")
	var failures: int = 0

	failures += test_order_data_resource()
	failures += test_order_lifecycle_and_timer()
	failures += test_order_scoring_ratios()
	failures += test_order_expiry()
	failures += test_order_manager_spawning()
	failures += test_order_manager_delivery_integration()
	failures += test_order_manager_expiry()

	print("--- ORDER SYSTEM TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL ORDER SYSTEM TESTS PASSED SUCCESSFULLY ---")
		get_tree().quit(0)
	else:
		printerr("Order system tests FAILED with %d error(s)." % failures)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


func _create_test_player() -> PlayerCharacter:
	var player_scene: PackedScene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate()
	add_child(player)
	return player


## Test OrderData resource configuration
func test_order_data_resource() -> int:
	print("Testing OrderData resource...")
	var err: int = 0

	var order_res: Resource = load(ORDER_PHONE_RESOURCE)
	err += _assert(order_res != null, "Loaded order_phone_repair.tres")
	err += _assert(order_res is OrderData, "Resource is instance of OrderData")

	var data := order_res as OrderData
	err += _assert(data.is_valid(), "OrderData.is_valid() returns true")
	err += _assert(data.device_data != null, "OrderData has device_data assigned")
	err += _assert(data.specific_fault != null, "OrderData has specific_fault assigned")
	err += _assert(data.get_effective_time_limit() == 60.0, "Effective time limit is 60.0s")
	err += _assert(data.three_star_threshold == 0.5, "Three star threshold is 0.5")
	err += _assert(data.two_star_threshold == 0.2, "Two star threshold is 0.2")
	err += _assert(data.base_score == 100, "Base score is 100")
	return err


## Test Order lifecycle, start, tick, and timer signal emissions
func test_order_lifecycle_and_timer() -> int:
	print("Testing Order lifecycle and countdown timer...")
	var err: int = 0

	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var order := Order.new()
	order.initialize("order_test_01", phone_data, null, 40.0)

	err += _assert(not order.is_active, "Order is not active before start()")
	err += _assert(order.time_remaining == 40.0, "Initial time remaining is 40.0")

	var timer_updates: Array[float] = []
	order.timer_updated.connect(func(remaining: float, _total: float) -> void:
		timer_updates.append(remaining)
	)

	order.start()
	err += _assert(order.is_active, "Order is active after start()")

	# Tick by 10 seconds
	order.tick(10.0)
	err += _assert(is_equal_approx(order.time_remaining, 30.0), "Time remaining is 30.0 after 10s tick")
	err += _assert(not timer_updates.is_empty(), "timer_updated signal emitted")
	err += _assert(is_equal_approx(order.get_time_ratio(), 0.75), "Time ratio is 0.75")
	err += _assert(order.get_device_name() == "Phone", "Device name is Phone")

	return err


## Test 3-star, 2-star, and 1-star calculations
func test_order_scoring_ratios() -> int:
	print("Testing Star and Score calculation ratios...")
	var err: int = 0

	var phone_data: DeviceData = load(PHONE_DATA_PATH)

	# Case 1: 3 stars (>= 50% time remaining)
	var order1 := Order.new()
	order1.initialize("ord_1", phone_data, null, 100.0)
	order1.start()
	order1.tick(40.0) # 60s remaining (60%)
	err += _assert(order1.get_stars_for_current_time() == 3, "60% time remaining qualifies for 3 stars")

	var completed_stars: Array[int] = [0]
	var completed_score: Array[int] = [0]
	order1.order_completed.connect(func(stars: int, score: int) -> void:
		completed_stars[0] = stars
		completed_score[0] = score
	)
	order1.complete()
	err += _assert(order1.is_completed, "Order 1 is completed")
	err += _assert(completed_stars[0] == 3, "Order 1 awarded 3 stars")
	err += _assert(completed_score[0] == 300, "Order 1 awarded 300 points")

	# Case 2: 2 stars (>= 20% and < 50% time remaining)
	var order2 := Order.new()
	order2.initialize("ord_2", phone_data, null, 100.0)
	order2.start()
	order2.tick(65.0) # 35s remaining (35%)
	err += _assert(order2.get_stars_for_current_time() == 2, "35% time remaining qualifies for 2 stars")
	order2.complete()
	err += _assert(order2._calculate_stars() == 2, "Order 2 awarded 2 stars")
	err += _assert(order2._calculate_score(2) == 200, "Order 2 awarded 200 points")

	# Case 3: 1 star (< 20% time remaining)
	var order3 := Order.new()
	order3.initialize("ord_3", phone_data, null, 100.0)
	order3.start()
	order3.tick(90.0) # 10s remaining (10%)
	err += _assert(order3.get_stars_for_current_time() == 1, "10% time remaining qualifies for 1 star")
	order3.complete()
	err += _assert(order3._calculate_stars() == 1, "Order 3 awarded 1 star")
	err += _assert(order3._calculate_score(1) == 100, "Order 3 awarded 100 points")

	return err


## Test order timer reaching zero and triggering expiry
func test_order_expiry() -> int:
	print("Testing Order expiry...")
	var err: int = 0

	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var order := Order.new()
	order.initialize("ord_expire", phone_data, null, 10.0)

	var expired_signal_fired: Array[bool] = [false]
	order.order_expired.connect(func() -> void:
		expired_signal_fired[0] = true
	)

	var bus_expired_fired: Array[bool] = [false]
	var on_bus_expired = func(oid: String) -> void:
		if oid == "ord_expire":
			bus_expired_fired[0] = true
	SignalBus.order_expired.connect(on_bus_expired)

	order.start()
	order.tick(10.5) # Exceed total time

	err += _assert(order.is_expired, "Order marked as is_expired")
	err += _assert(order.time_remaining == 0.0, "time_remaining clamped to 0.0")
	err += _assert(expired_signal_fired[0], "order_expired signal fired")
	err += _assert(bus_expired_fired[0], "SignalBus.order_expired signal fired")
	err += _assert(order._calculate_stars() == 0, "Expired order yields 0 stars")

	SignalBus.order_expired.disconnect(on_bus_expired)
	return err


## Test OrderManager order spawning, device instantiation, and reception desk placement
func test_order_manager_spawning() -> int:
	print("Testing OrderManager order spawning...")
	var err: int = 0

	var mgr := OrderManager.new()
	var reception: ReceptionDesk = load("res://scenes/stations/ReceptionDesk.tscn").instantiate()
	add_child(reception)
	add_child(mgr)
	mgr.reception_desk = reception

	var spawned_orders: Array[Order] = []
	mgr.order_spawned.connect(func(o: Order) -> void:
		spawned_orders.append(o)
	)

	var order: Order = mgr.spawn_order()
	err += _assert(order != null, "Order successfully spawned")
	err += _assert(mgr.has_active_orders(), "OrderManager reports active orders")
	err += _assert(mgr.get_active_order_count() == 1, "Active order count is 1")
	err += _assert(spawned_orders.size() == 1, "order_spawned signal emitted once")
	err += _assert(order.device_instance != null, "Physical Device instantiated and linked to Order")
	err += _assert(reception.has_device(), "Device automatically placed onto ReceptionDesk")
	err += _assert(reception.placed_device == order.device_instance, "Reception desk holds the order's device instance")

	# Test spawning from OrderData resource
	var order_res: OrderData = load(ORDER_PHONE_RESOURCE)
	var order2: Order = mgr.spawn_order_from_data(order_res)
	err += _assert(order2 != null, "Order spawned from OrderData")
	err += _assert(mgr.get_active_order_count() == 2, "Active order count is now 2")

	if order.device_instance:
		order.device_instance.queue_free()
	if order2.device_instance:
		order2.device_instance.queue_free()
	reception.queue_free()
	mgr.queue_free()
	return err


## Test complete flow from delivery to OrderManager completion and scoring
func test_order_manager_delivery_integration() -> int:
	print("Testing OrderManager delivery integration and scoring...")
	var err: int = 0

	var mgr := OrderManager.new()
	var reception: ReceptionDesk = load("res://scenes/stations/ReceptionDesk.tscn").instantiate()
	var delivery: DeliveryCounter = load("res://scenes/stations/DeliveryCounter.tscn").instantiate()

	add_child(reception)
	add_child(delivery)
	add_child(mgr)

	mgr.reception_desk = reception
	mgr.delivery_counter = delivery
	delivery.order_manager = mgr

	var player := _create_test_player()
	var order: Order = mgr.spawn_order()
	var device: Device = order.device_instance

	err += _assert(device != null, "Spawned order has device instance")
	err += _assert(mgr.total_score == 0, "Initial score is 0")
	err += _assert(mgr.total_stars == 0, "Initial stars is 0")

	# Advance device state to TESTED to simulate completing repairs
	device.advance_state(RepairState.State.DIAGNOSED)
	device.advance_state(RepairState.State.DISASSEMBLED)
	device.advance_state(RepairState.State.PART_REPLACED)
	device.advance_state(RepairState.State.REASSEMBLED)
	device.advance_state(RepairState.State.SOFTWARE_INSTALLED)
	device.advance_state(RepairState.State.TESTED)

	# Take device from reception and give to player
	reception.remove_device()
	player.carry_system.pick_up(device)

	# Deliver device to DeliveryCounter
	delivery._on_interacted(player)

	err += _assert(order.is_completed, "Order marked completed upon delivery")
	err += _assert(not mgr.has_active_orders(), "No active orders remaining in OrderManager")
	err += _assert(mgr.completed_orders.size() == 1, "Completed orders count is 1")
	err += _assert(mgr.total_score > 0, "OrderManager total_score was updated (%d)" % mgr.total_score)
	err += _assert(mgr.total_stars == 3, "Order completed swiftly awarded 3 stars")

	if device:
		device.queue_free()
	player.queue_free()
	reception.queue_free()
	delivery.queue_free()
	mgr.queue_free()
	return err


## Test OrderManager expiry and all_orders_complete emission
func test_order_manager_expiry() -> int:
	print("Testing OrderManager expiry handling...")
	var err: int = 0

	var mgr := OrderManager.new()
	add_child(mgr)

	var all_complete_fired: Array[bool] = [false]
	mgr.all_orders_complete.connect(func() -> void:
		all_complete_fired[0] = true
	)

	var phone_data: DeviceData = load(PHONE_DATA_PATH)
	var order: Order = mgr.spawn_order(phone_data)
	order.time_limit = 2.0
	order.time_remaining = 2.0

	err += _assert(mgr.get_active_order_count() == 1, "1 active order spawned")

	# Tick physics to expire order
	mgr._physics_process(2.5)

	err += _assert(order.is_expired, "Order expired after timer ran out")
	err += _assert(mgr.get_active_order_count() == 0, "Active orders count is 0 after expiry")
	err += _assert(mgr.expired_orders.size() == 1, "Expired orders count is 1")
	err += _assert(all_complete_fired[0], "all_orders_complete emitted after last order expired")

	if order.device_instance:
		order.device_instance.queue_free()
	mgr.queue_free()
	return err
