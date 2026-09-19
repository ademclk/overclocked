extends Node

## Test suite for Multiple Simultaneous Orders & OrderSpawner
## Tests OrderSpawner lifecycle, timing, queue caps, difficulty ramping,
## priority orders, HUD multiple order rows, and ReceptionDesk queueing.

const PHONE_DATA_PATH: String = "res://resources/devices/phone.tres"
const HUD_SCENE_PATH: String = "res://scenes/ui/HUD.tscn"


func _ready() -> void:
	print("=========================================================")
	print("--- RUNNING PHASE 3A ORDER SPAWNER & MULTI-ORDER TESTS ---")
	print("=========================================================")
	var failures: int = 0

	failures += test_order_spawner_configuration_and_defaults()
	failures += test_order_spawner_initial_delay_and_timing()
	failures += test_order_spawner_queue_cap_and_resumption()
	failures += test_order_spawner_difficulty_ramping()
	failures += test_priority_orders()
	failures += test_max_total_orders_cap()
	failures += test_hud_multiple_orders_and_priority_display()
	failures += test_reception_desk_incoming_queue()

	print("=========================================================")
	print("--- PHASE 3A TESTS COMPLETED ---")
	if failures == 0:
		print("--- ALL PHASE 3A TESTS PASSED SUCCESSFULLY! ---")
		print("=========================================================")
		get_tree().quit(0)
	else:
		printerr("Phase 3A tests FAILED with %d error(s)." % failures)
		print("=========================================================")
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> int:
	if condition:
		print("  [PASS] %s" % message)
		return 0
	else:
		printerr("  [FAIL] %s" % message)
		return 1


## 1. Test OrderSpawner default values and lifecycle controls
func test_order_spawner_configuration_and_defaults() -> int:
	print("\n[1] Testing OrderSpawner configuration and lifecycle...")
	var err: int = 0

	var spawner := OrderSpawner.new()
	add_child(spawner)

	err += _assert(spawner.spawn_interval == 25.0, "Default spawn_interval is 25.0s")
	err += _assert(spawner.min_interval == 12.0, "Default min_interval is 12.0s")
	err += _assert(spawner.initial_delay == 5.0, "Default initial_delay is 5.0s")
	err += _assert(spawner.ramp_enabled == true, "Default ramp_enabled is true")
	err += _assert(is_equal_approx(spawner.ramp_factor, 0.92), "Default ramp_factor is 0.92")
	err += _assert(spawner.max_active_orders == 5, "Default max_active_orders is 5")
	err += _assert(spawner.max_total_orders == 0, "Default max_total_orders is 0 (unlimited)")
	err += _assert(is_equal_approx(spawner.priority_chance, 0.15), "Default priority_chance is 0.15")
	err += _assert(is_equal_approx(spawner.priority_time_multiplier, 0.6), "Default priority_time_multiplier is 0.6")
	err += _assert(is_equal_approx(spawner.priority_score_multiplier, 1.5), "Default priority_score_multiplier is 1.5")
	err += _assert(not spawner.is_spawning(), "Spawner is initially not spawning")

	spawner.start()
	err += _assert(spawner.is_spawning(), "Spawner is_spawning() is true after start()")
	err += _assert(spawner.get_current_interval() == 25.0, "Current interval matches spawn_interval")
	err += _assert(spawner.get_total_spawned() == 0, "Total spawned is initially 0")

	spawner.stop()
	err += _assert(not spawner.is_spawning(), "Spawner is_spawning() is false after stop()")

	spawner.queue_free()
	return err


## 2. Test initial delay and timer progression
func test_order_spawner_initial_delay_and_timing() -> int:
	print("\n[2] Testing initial delay and periodic timer ticks...")
	var err: int = 0

	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	spawner.initial_delay = 3.0
	spawner.spawn_interval = 10.0
	spawner.ramp_enabled = false
	spawner.start()

	# Tick during initial delay: should not spawn
	spawner._physics_process(2.0)
	err += _assert(mgr.get_active_order_count() == 0, "No orders spawned during initial delay")
	err += _assert(spawner.get_initial_delay_remaining() <= 1.0, "Initial delay ticked down")

	# Finish initial delay + tick part of spawn interval: still no spawn
	spawner._physics_process(1.1)
	spawner._physics_process(5.0)
	err += _assert(mgr.get_active_order_count() == 0, "No orders spawned halfway through spawn interval")

	# Tick remaining spawn interval: triggers spawn!
	spawner._physics_process(5.0)
	err += _assert(mgr.get_active_order_count() == 1, "Order spawned after spawn interval elapsed")
	err += _assert(spawner.get_total_spawned() == 1, "Spawner total_spawned incremented to 1")

	# Clean up spawned devices
	for ord in mgr.active_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	return err


## 3. Test max_active_orders queue cap and resumption
func test_order_spawner_queue_cap_and_resumption() -> int:
	print("\n[3] Testing max active orders queue cap and resumption...")
	var err: int = 0

	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	spawner.max_active_orders = 3
	spawner.ramp_enabled = false

	# Spawn up to cap
	var o1: Order = spawner.try_spawn_order()
	var o2: Order = spawner.try_spawn_order()
	var o3: Order = spawner.try_spawn_order()

	err += _assert(o1 != null and o2 != null and o3 != null, "Spawned 3 orders up to cap")
	err += _assert(mgr.get_active_order_count() == 3, "Active orders count is 3")

	# Attempt 4th spawn: should be rejected
	var o4: Order = spawner.try_spawn_order()
	err += _assert(o4 == null, "4th spawn rejected due to max_active_orders cap")
	err += _assert(mgr.get_active_order_count() == 3, "Active count remains at 3")

	# Complete one order to free a queue slot
	mgr.complete_order(o1)
	err += _assert(mgr.get_active_order_count() == 2, "Active count reduced to 2 after completion")

	# Attempt spawn again: should now succeed!
	var o5: Order = spawner.try_spawn_order()
	err += _assert(o5 != null, "Spawn succeeds after slot freed in queue")
	err += _assert(mgr.get_active_order_count() == 3, "Active orders count back at cap (3)")

	for ord in mgr.active_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	for ord in mgr.completed_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	return err


## 4. Test difficulty ramping (spawn rate increases over time)
func test_order_spawner_difficulty_ramping() -> int:
	print("\n[4] Testing difficulty ramping and min_interval floor...")
	var err: int = 0

	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	spawner.spawn_interval = 20.0
	spawner.min_interval = 14.0
	spawner.ramp_enabled = true
	spawner.ramp_factor = 0.8
	spawner.max_active_orders = 10
	spawner.start()

	var rate_signal_received: Array[float] = []
	spawner.spawn_rate_changed.connect(func(new_rate: float) -> void:
		rate_signal_received.append(new_rate)
	)

	# Spawn 1: interval becomes 20.0 * 0.8 = 16.0
	spawner.try_spawn_order()
	err += _assert(is_equal_approx(spawner.get_current_interval(), 16.0), "Spawn 1 reduced interval to 16.0s")
	err += _assert(rate_signal_received.size() == 1 and is_equal_approx(rate_signal_received[0], 16.0), "spawn_rate_changed signal fired with 16.0s")

	# Spawn 2: 16.0 * 0.8 = 12.8, but floor is 14.0 -> should clamp to 14.0
	spawner.try_spawn_order()
	err += _assert(is_equal_approx(spawner.get_current_interval(), 14.0), "Spawn 2 clamped interval to min_interval (14.0s)")

	# Spawn 3: remains at 14.0 floor
	spawner.try_spawn_order()
	err += _assert(is_equal_approx(spawner.get_current_interval(), 14.0), "Spawn 3 stayed at min_interval floor (14.0s)")

	for ord in mgr.active_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	return err


## 5. Test Priority Orders (shorter timers, higher scores, is_priority flag)
func test_priority_orders() -> int:
	print("\n[5] Testing priority orders mechanics...")
	var err: int = 0

	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	spawner.priority_time_multiplier = 0.6
	spawner.priority_score_multiplier = 1.5

	# Standard order
	var normal_order: Order = spawner.try_spawn_order(false)
	err += _assert(normal_order != null, "Spawned normal order")
	err += _assert(not normal_order.is_priority, "Normal order has is_priority == false")
	var normal_time: float = normal_order.time_limit
	var normal_score: int = normal_order.base_score

	# Priority order
	var priority_order: Order = spawner.try_spawn_order(true)
	err += _assert(priority_order != null, "Spawned forced priority order")
	err += _assert(priority_order.is_priority, "Priority order has is_priority == true")
	err += _assert(is_equal_approx(priority_order.time_limit, normal_time * 0.6), "Priority order time limit is 60 percent of normal (%.1f vs %.1f)" % [priority_order.time_limit, normal_time])
	err += _assert(priority_order.base_score == int(round(normal_score * 1.5)), "Priority order base score is 150 percent of normal (%d vs %d)" % [priority_order.base_score, normal_score])

	# Complete priority order at 3 stars: score should be base_score * 3
	mgr.complete_order(priority_order)
	err += _assert(mgr.total_score == priority_order.base_score * 3, "Total score awarded priority multiplier (%d pts)" % mgr.total_score)

	for ord in mgr.active_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	for ord in mgr.completed_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	return err


## 6. Test max_total_orders round quota
func test_max_total_orders_cap() -> int:
	print("\n[6] Testing max_total_orders round quota...")
	var err: int = 0

	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	spawner.max_total_orders = 2
	spawner.start()

	var o1: Order = spawner.try_spawn_order()
	var o2: Order = spawner.try_spawn_order()
	err += _assert(o1 != null and o2 != null, "Spawned 2 total orders")
	err += _assert(spawner.get_total_spawned() == 2, "Total spawned reached max_total_orders")

	# Next spawn attempt should stop spawner and return null
	var o3: Order = spawner.try_spawn_order()
	err += _assert(o3 == null, "Spawner refused spawn after max_total_orders reached")
	err += _assert(not spawner.is_spawning(), "Spawner auto-stopped after reaching quota")

	for ord in mgr.active_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	return err


## 7. Test HUD simultaneous multiple orders & priority order styling
func test_hud_multiple_orders_and_priority_display() -> int:
	print("\n[7] Testing HUD multiple orders display and urgency color coding...")
	var err: int = 0

	var hud_scene: PackedScene = load(HUD_SCENE_PATH)
	var hud: HUD = hud_scene.instantiate() as HUD
	var mgr := OrderManager.new()
	var spawner := OrderSpawner.new()
	add_child(hud)
	add_child(mgr)
	add_child(spawner)

	spawner.order_manager = mgr
	hud.setup(null, mgr)

	# Spawn 1 regular and 1 priority order
	var ord1: Order = spawner.try_spawn_order(false)
	var ord2: Order = spawner.try_spawn_order(true)

	hud._update_active_orders()

	err += _assert(hud._order_entries.size() == 2, "HUD tracks 2 simultaneous order entries")
	err += _assert(hud._order_entries.has(ord1) and hud._order_entries.has(ord2), "Both orders present in HUD entries")

	var entry1: HBoxContainer = hud._order_entries[ord1]
	var entry2: HBoxContainer = hud._order_entries[ord2]

	var name1: Label = entry1.get_node_or_null("DeviceName") as Label
	var name2: Label = entry2.get_node_or_null("DeviceName") as Label

	err += _assert(name1 != null and not name1.text.contains("⚡"), "Regular order entry does not have priority lightning symbol")
	err += _assert(entry1.modulate == Color.WHITE, "Regular order entry has standard white modulate")

	err += _assert(name2 != null and name2.text.contains("⚡"), "Priority order entry displays '⚡' prefix")
	err += _assert(entry2.modulate == Color(1.0, 0.7, 0.3), "Priority order entry has urgency red-orange modulate")

	# Test urgency timers: >50% green, 20-50% yellow, 10-20% red
	var bar1: ProgressBar = entry1.get_node_or_null("TimerBar") as ProgressBar
	ord1.time_limit = 100.0
	ord1.time_remaining = 80.0
	hud._update_active_orders()
	err += _assert(bar1.modulate == HUD.COLOR_TIMER_HEALTHY, "Timer bar healthy (>50%)")

	ord1.time_remaining = 35.0
	hud._update_active_orders()
	err += _assert(bar1.modulate == HUD.COLOR_TIMER_WARNING, "Timer bar warning (20-50%)")

	ord1.time_remaining = 15.0
	hud._update_active_orders()
	err += _assert(bar1.modulate == HUD.COLOR_TIMER_CRITICAL, "Timer bar critical (10-20%)")

	# Test order completion removes row from HUD
	mgr.complete_order(ord1)
	hud._update_active_orders()
	err += _assert(hud._order_entries.size() == 1, "Completing ord1 left 1 entry in HUD")
	err += _assert(not hud._order_entries.has(ord1), "Completed order entry removed from HUD")
	err += _assert(hud._order_entries.has(ord2), "Remaining order entry persists in HUD")

	mgr.complete_order(ord2)
	hud._update_active_orders()
	err += _assert(hud._order_entries.is_empty(), "Completing ord2 cleared all HUD entries")

	for ord in mgr.completed_orders:
		if ord.device_instance:
			ord.device_instance.queue_free()
	spawner.queue_free()
	mgr.queue_free()
	hud.queue_free()
	return err


## 8. Test ReceptionDesk incoming device queueing
func test_reception_desk_incoming_queue() -> int:
	print("\n[8] Testing ReceptionDesk incoming device queueing...")
	var err: int = 0

	var desk_scene: PackedScene = load("res://scenes/stations/ReceptionDesk.tscn")
	var desk: ReceptionDesk = desk_scene.instantiate() as ReceptionDesk
	add_child(desk)

	var dev_scene: PackedScene = load("res://scenes/devices/Device.tscn")
	var dev1: Device = dev_scene.instantiate() as Device
	var dev2: Device = dev_scene.instantiate() as Device
	var dev3: Device = dev_scene.instantiate() as Device
	dev1.item_name = "Device 1"
	dev2.item_name = "Device 2"
	dev3.item_name = "Device 3"

	# Spawn first device
	desk.spawn_incoming_device(dev1)
	err += _assert(desk.placed_device == dev1, "First device placed directly onto ReceptionDesk")
	err += _assert(desk.get_incoming_queue_count() == 0, "Queue count is 0 with only 1 device")

	# Spawn second and third devices while first is still on desk
	desk.spawn_incoming_device(dev2)
	desk.spawn_incoming_device(dev3)
	err += _assert(desk.placed_device == dev1, "First device remains placed on desk")
	err += _assert(desk.get_incoming_queue_count() == 2, "2 additional devices queued behind first")

	# Remove first device (simulates player picking it up)
	var removed1: Carriable = desk.remove_device()
	err += _assert(removed1 == dev1, "remove_device() returned Device 1")
	err += _assert(desk.placed_device == dev2, "Device 2 automatically advanced to desk slot")
	err += _assert(desk.get_incoming_queue_count() == 1, "Queue count reduced to 1")

	# Remove second device
	var removed2: Carriable = desk.remove_device()
	err += _assert(removed2 == dev2, "remove_device() returned Device 2")
	err += _assert(desk.placed_device == dev3, "Device 3 automatically advanced to desk slot")
	err += _assert(desk.get_incoming_queue_count() == 0, "Queue count now 0")

	# Remove third device
	var removed3: Carriable = desk.remove_device()
	err += _assert(removed3 == dev3, "remove_device() returned Device 3")
	err += _assert(desk.placed_device == null, "Desk is now empty")

	dev1.queue_free()
	dev2.queue_free()
	dev3.queue_free()
	desk.queue_free()
	return err
