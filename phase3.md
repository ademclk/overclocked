# Phase 3 — Chaos Systems

> **Goal:** The workshop fights back. Emergent chaos creates "the signature moment."
> **Estimated Duration:** ~2–3 weeks
> **Exit Criteria:** A 4-player session feels chaotic — orders stacking, hazards popping, players yelling at each other about screwdrivers.

---

## Table of Contents

- [Phase Dependencies — What Phase 2 Provides](#phase-dependencies--what-phase-2-provides)
- [3A — Multiple Simultaneous Orders](#3a--multiple-simultaneous-orders)
- [3B — Workshop Hazards](#3b--workshop-hazards)
- [3C — Tool System](#3c--tool-system)
- [3D — Component Variety & Parts Stock](#3d--component-variety--parts-stock)
- [3E — Integration & Wiring](#3e--integration--wiring)
- [Best Practices & Guidelines](#best-practices--guidelines)
- [Phase 3 Checklist (Summary)](#phase-3-checklist-summary)

---

## Phase Dependencies — What Phase 2 Provides

Before starting Phase 3, confirm these Phase 2 deliverables are working **end-to-end with 2+ players**:

| System | File | What It Provides to Phase 3 |
|--------|------|----------------------------|
| MultiplayerInput | `scripts/core/multiplayer_input.gd` | Per-player input routing — Phase 3 doesn't touch input at all |
| PlayerCharacter | `scripts/players/player_character.gd` | `player_index`, `carry_system`, `interaction_system`, `stun()`, bump mechanic |
| CarrySystem | `scripts/players/carry_system.gd` | `pick_up()`, `drop_item()`, `place_on_station()`, `is_carrying()`, `can_pick_up()`, `get_held_item()` |
| Carriable | `scripts/interfaces/carriable.gd` | `item_type` field (supports `"device"`, `"part"`, `"tool"`), claim system, `try_claim()` |
| OrderManager | `scripts/orders/order_manager.gd` | `spawn_order()`, `active_orders`, `device_database`, reception desk auto-wiring |
| Order | `scripts/orders/order.gd` | Timer, star thresholds, `tick()`, `complete()`, `expire()` |
| BaseStation | `scripts/stations/base_station.gd` | `StationState` enum, occupancy system, processing timer, `can_player_interact()` |
| WorkbenchStation | `scripts/stations/workbench_station.gd` | Multi-step repair (disassemble → install → reassemble) |
| PartsShelf | `scripts/stations/parts_shelf.gd` | `_get_needed_part()`, `_create_part_instance()`, `available_parts` |
| Device | `scripts/devices/device.gd` | `current_repair_state`, `advance_state()`, `try_install_component()` |
| RepairState | `scripts/devices/repair_state.gd` | State machine, `TRANSITIONS`, `can_transition()` |
| Constants | `scripts/core/constants.gd` | `COLLISION_LAYER_HAZARDS = 5`, `COLLISION_MASK_HAZARDS` already defined |
| SignalBus | `scripts/core/signal_bus.gd` | `order_spawned`, `order_completed`, `order_expired`, `round_started`, `round_ended` |
| WorkshopDebug | `scripts/workshop/workshop_debug.gd` | `start_round()`, `order_manager`, `get_all_stations()`, debug hotkeys |
| HUD | `scripts/ui/hud.gd` | Order panel, score display, interaction prompts, multi-player carried items |

### Critical Phase 2 Assumptions That Phase 3 Builds On

> [!IMPORTANT]
> Phase 3 adds new systems (order spawner, hazards, tools, stock limits) that integrate with existing Phase 2 systems. The existing systems are NOT refactored — Phase 3 adds NEW nodes and scripts that plug into the existing signal bus and station architecture.

| Assumption | Location | How Phase 3 Extends It |
|-----------|----------|----------------------|
| `OrderManager` spawns one order manually | `order_manager.gd:50` | New `OrderSpawner` node calls `spawn_order()` on a configurable timer |
| `PartsShelf` has infinite stock | `parts_shelf.gd:44-59` | Add stock tracking — limited `_current_stock` dictionary per component type |
| No hazard system exists | (none) | New `scripts/hazards/` directory with `base_hazard.gd` + specific hazard scripts |
| No tool requirement on stations | `workbench_station.gd` | Workbench requires a screwdriver in-hand or on-bench for disassembly/reassembly |
| `Carriable.item_type` supports `"tool"` | `carriable.gd:9` | New tool items use `item_type = "tool"` — carry system already handles them |
| Collision layer 5 reserved for hazards | `constants.gd:52-54` | Hazard `Area3D` nodes use `COLLISION_LAYER_HAZARDS` to slow/affect players |

---

## 3A — Multiple Simultaneous Orders

### Tasks

- [x] 🎯 Create `scripts/orders/order_spawner.gd` — configurable automatic order generation
- [x] 🎯 Configurable spawn rate: time between orders, min/max intervals
- [x] 🎯 Max active orders cap: prevent infinite queue buildup
- [x] 🎯 Stacking pressure: orders pile up faster than players can handle
- [x] 🎯 Priority orders: impatient customers with shorter timers and higher rewards
- [x] 🎯 Wire `OrderSpawner` into `WorkshopDebug` and round flow
- [x] 🎯 HUD: order panel shows multiple orders simultaneously with individual timers
- [x] 💡 Difficulty ramping: order rate increases over the round duration
- [x] 💡 Order variety: different device types per order (pulls from full `device_database`)

### The Core Problem

Phase 1-2 spawns **one** order at round start. The player completes it and that's it. This creates zero time pressure after the first delivery. Phase 3 needs a continuous stream of orders that creates escalating chaos — by mid-round, there should be 3-4 active orders with devices at different pipeline stages scattered across the workshop.

### Order Spawner Architecture

The `OrderSpawner` is a **separate Node** from `OrderManager`. The spawner decides **when** and **what** to spawn. The manager handles **how** to spawn and track it. This separation lets different levels use different spawner configurations without touching the manager.

```
OrderSpawner (Node) ← scripts/orders/order_spawner.gd
│   Exported:
│     spawn_interval: float = 25.0   # Seconds between orders
│     min_interval: float = 12.0     # Fastest possible spawn rate
│     max_active_orders: int = 5     # Queue cap
│     priority_chance: float = 0.15  # 15% chance of priority order
│     ramp_enabled: bool = true      # Speed up over time
│     ramp_factor: float = 0.92      # Multiply interval each spawn
│   References:
│     order_manager: OrderManager
```

### OrderSpawner Script — `order_spawner.gd`

```gdscript
class_name OrderSpawner
extends Node

## Automatic order generation with configurable rate, pressure ramping,
## and priority order injection. Plugs into OrderManager.

signal spawn_rate_changed(new_interval: float)

@export_group("Timing")
@export var spawn_interval: float = 25.0       ## Seconds between order spawns
@export var min_interval: float = 12.0          ## Floor — never spawns faster than this
@export var initial_delay: float = 5.0          ## Delay before first auto-spawn
@export var ramp_enabled: bool = true           ## Whether spawn rate increases over time
@export var ramp_factor: float = 0.92           ## Multiply interval by this each spawn

@export_group("Queue Limits")
@export var max_active_orders: int = 5          ## Won't spawn if active >= max
@export var max_total_orders: int = 0           ## 0 = unlimited. Total orders per round

@export_group("Priority Orders")
@export var priority_chance: float = 0.15       ## Probability of an order being "priority"
@export var priority_time_multiplier: float = 0.6  ## Priority orders get 60% of normal time
@export var priority_score_multiplier: float = 1.5 ## Priority orders give 150% score

@export_group("References")
@export var order_manager: OrderManager = null

var _spawn_timer: float = 0.0
var _current_interval: float = 25.0
var _total_spawned: int = 0
var _is_active: bool = false
var _initial_delay_timer: float = 0.0


func _ready() -> void:
    _current_interval = spawn_interval
    _discover_order_manager()


func _physics_process(delta: float) -> void:
    if not _is_active or not order_manager:
        return

    # Handle initial delay
    if _initial_delay_timer > 0.0:
        _initial_delay_timer -= delta
        return

    _spawn_timer += delta
    if _spawn_timer >= _current_interval:
        _spawn_timer = 0.0
        _try_spawn_order()


## Starts automatic order spawning
func start() -> void:
    _is_active = true
    _spawn_timer = 0.0
    _initial_delay_timer = initial_delay
    _current_interval = spawn_interval
    _total_spawned = 0


## Stops automatic order spawning
func stop() -> void:
    _is_active = false
    _spawn_timer = 0.0


## Returns whether the spawner is currently active
func is_spawning() -> bool:
    return _is_active


## Returns the current spawn interval (may differ from base due to ramping)
func get_current_interval() -> float:
    return _current_interval


## Returns total orders spawned this round
func get_total_spawned() -> int:
    return _total_spawned


func _try_spawn_order() -> void:
    if not order_manager:
        return

    # Check queue cap
    if order_manager.get_active_order_count() >= max_active_orders:
        return  # Queue full — skip this spawn cycle

    # Check total cap
    if max_total_orders > 0 and _total_spawned >= max_total_orders:
        stop()
        return

    # Determine if this is a priority order
    var is_priority: bool = randf() < priority_chance

    # Spawn the order
    var order: Order = order_manager.spawn_order()
    if order:
        _total_spawned += 1

        if is_priority:
            _apply_priority(order)

        # Ramp up spawn rate for next order
        if ramp_enabled:
            _current_interval = maxf(min_interval, _current_interval * ramp_factor)
            spawn_rate_changed.emit(_current_interval)


func _apply_priority(order: Order) -> void:
    order.time_limit *= priority_time_multiplier
    order.time_remaining = order.time_limit
    order.base_score = int(order.base_score * priority_score_multiplier)
    order.is_priority = true  # New field — see Order changes below


func _discover_order_manager() -> void:
    if order_manager:
        return
    var parent := get_parent()
    if parent:
        for child in parent.get_children():
            if child is OrderManager:
                order_manager = child as OrderManager
                return
    var tree := get_tree()
    if tree:
        for node in tree.get_nodes_in_group("order_managers"):
            if node is OrderManager:
                order_manager = node as OrderManager
                return
```

### Order Changes — Priority Support

```gdscript
# Add to scripts/orders/order.gd

## Whether this is a priority/impatient customer order
var is_priority: bool = false

## Base score BEFORE star multiplier
var base_score: int = 100
```

> [!NOTE]
> The `base_score` field already exists in `Order` (see `_calculate_score()`). Just add the `is_priority` bool flag. The priority visual distinction (HUD color, exclamation icon) is handled in the HUD update below.

### HUD Changes — Multiple Orders Display

The existing `OrderPanel` already uses a `VBoxContainer` with `OrderEntry` children. The change is:

1. **Support N order entries** (not just 1). When `order_spawned` fires, add a new entry. When `order_completed` or `order_expired` fires, remove it.
2. **Priority order styling**: priority orders get a red/orange tint and a "!" prefix on the device name.
3. **Timer urgency colors**: green > 50%, yellow 20–50%, red < 20%, flashing red < 10%.

```gdscript
# Add to scripts/ui/hud.gd — order tracking for multiple orders

## Creates a new order entry row in the order panel
func _add_order_entry(order: Order) -> void:
    var entry: HBoxContainer = _order_entry_template.duplicate() as HBoxContainer
    entry.name = "Order_%s" % order.order_id
    entry.visible = true

    var name_label: Label = entry.get_node("DeviceName") as Label
    var timer_bar: ProgressBar = entry.get_node("TimerBar") as ProgressBar

    var display_name: String = order.get_device_name()
    if order.is_priority:
        display_name = "⚡ " + display_name
        # Tint the entry red-orange for visual urgency
        entry.modulate = Color(1.0, 0.7, 0.3)

    name_label.text = display_name
    timer_bar.max_value = order.time_limit
    timer_bar.value = order.time_remaining

    order_panel.add_child(entry)
    _order_entries[order.order_id] = {"entry": entry, "order": order}


## Removes an order entry when completed or expired
func _remove_order_entry(order: Order) -> void:
    if order.order_id in _order_entries:
        var entry_data: Dictionary = _order_entries[order.order_id]
        var entry: HBoxContainer = entry_data["entry"]
        if entry and is_instance_valid(entry):
            entry.queue_free()
        _order_entries.erase(order.order_id)


## Updates all active order timers each frame
func _update_order_timers() -> void:
    for order_id: String in _order_entries:
        var entry_data: Dictionary = _order_entries[order_id]
        var order: Order = entry_data["order"]
        var entry: HBoxContainer = entry_data["entry"]
        if not order or not entry or not is_instance_valid(entry):
            continue

        var timer_bar: ProgressBar = entry.get_node("TimerBar") as ProgressBar
        if timer_bar:
            timer_bar.value = order.time_remaining

            # Color based on urgency
            var ratio: float = order.get_time_ratio()
            if ratio > 0.5:
                timer_bar.modulate = Color(0.3, 0.9, 0.3)   # Green
            elif ratio > 0.2:
                timer_bar.modulate = Color(1.0, 0.85, 0.2)   # Yellow
            elif ratio > 0.1:
                timer_bar.modulate = Color(1.0, 0.3, 0.2)    # Red
            else:
                # Flashing red for critical urgency
                var flash: float = sin(Time.get_ticks_msec() * 0.01) * 0.5 + 0.5
                timer_bar.modulate = Color(1.0, flash * 0.3, flash * 0.2)
```

### Implementation Notes

- **The `OrderSpawner` is a Node, not an autoload.** Add it as a child of the workshop scene alongside `OrderManager`. It has a direct reference to the manager and calls `spawn_order()` on a timer. When the round ends, call `spawner.stop()`.
- **Max active orders = 5 is the sweet spot.** With 4 players, 5 active orders means there's always more work than hands. With 2 players, 5 orders is near-impossible to keep up with — which is the intended difficulty. This value comes from the level configuration (Phase 5), so it's `@export`.
- **Priority orders are the "oh no" moment.** A 15% chance per spawn means roughly 1 in 7 orders is priority. Priority orders have 60% of the normal time limit and 150% score reward. They create the "DROP WHAT YOU'RE DOING" urgency that drives co-op communication.
- **Spawn rate ramping creates escalating pressure.** Starting at 25s between orders and multiplying by 0.92 each spawn: spawn 1 at 25s, spawn 2 at 23s, spawn 3 at 21.2s, ..., eventually hitting the 12s floor. The first minute is manageable; the third minute is chaos.
- **The `max_total_orders` cap is for level design.** Some levels might want exactly 8 orders total (finish them all for 3 stars). Set `max_total_orders = 8` and the spawner auto-stops after 8. Set to 0 for unlimited (time-based rounds).

> [!WARNING]
> **Do NOT spawn orders faster than players can physically pick them up from the reception desk.** If orders spawn every 5 seconds but it takes 3 seconds to walk to the desk, the desk overflows. The `min_interval = 12.0` ensures at least 12 seconds between spawns, which is enough for a player to pick up, walk away, and come back. The `max_active_orders` cap is the safety net.

> [!TIP]
> For Phase 3 testing, use these spawner settings for a good 2-player session: `spawn_interval = 30.0`, `min_interval = 18.0`, `max_active_orders = 4`, `priority_chance = 0.1`, `ramp_factor = 0.95`. This is relaxed enough to be playable but pressured enough to feel chaotic.

---

## 3B — Workshop Hazards

### Tasks

- [x] 🎯 Create `scripts/hazards/base_hazard.gd` — base class for all workshop hazards
- [x] 🎯 Create `scripts/hazards/hazard_manager.gd` — spawns and tracks active hazards
- [x] 🎯 **Overheating Device** — device left too long on workbench overheats, must be cooled
- [x] 🎯 **Power Surge** — random event, disables a station temporarily
- [x] 🎯 **Spilled Coffee / Dropped Screws** — floor hazard, slows players walking through
- [ ] 💡 **Battery Fire** — emergency event, requires fire extinguisher before it spreads
- [ ] 💡 **Cable Tangle** — blocks a path until cleared

### Hazard Architecture Overview

Hazards are **Area3D nodes** that affect players or stations within their collision zone. They use collision layer 5 (`COLLISION_LAYER_HAZARDS`), which is already reserved in `constants.gd`.

```
Hazard System Architecture:

HazardManager (Node)
├── Tracks active hazards, manages spawn cooldowns
├── Listens to round flow signals (start/stop)
└── Configurable hazard pool per level

BaseHazard (Area3D)
├── CollisionShape3D          ← Hazard effect zone
├── HazardVisual (Node3D)     ← Visual representation
│   └── MeshInstance3D        ← Placeholder mesh (colored plane/shape)
├── HazardLabel (Label3D)     ← "⚠ SPILL" or "⚡ SURGE"
└── WarningIndicator (Node3D) ← Pre-spawn warning (flashing marker)
```

### Base Hazard — `base_hazard.gd`

```gdscript
class_name BaseHazard
extends Area3D

## Base class for all workshop hazards in Overclocked.
## Hazards are Area3D nodes that affect players or stations within their zone.
## Subclasses override _apply_effect() and _remove_effect() for specific behavior.

signal hazard_activated(hazard: BaseHazard)
signal hazard_cleared(hazard: BaseHazard)
signal hazard_expired(hazard: BaseHazard)

enum HazardState {
    INACTIVE,      ## Not yet visible or active
    WARNING,       ## Flashing warning before activation (1-2 seconds)
    ACTIVE,        ## Hazard is live and affecting players/stations
    CLEARING,      ## Being cleared by a player (interaction in progress)
    CLEARED,       ## Cleared by player action — about to be freed
}

@export var hazard_name: String = "Hazard"
@export var hazard_type: String = "generic"
@export var duration: float = 0.0              ## 0 = permanent until cleared, >0 = auto-expires
@export var warning_duration: float = 1.5      ## Seconds of warning flash before activation
@export var clear_time: float = 1.0            ## Seconds of interact-to-clear
@export var can_be_cleared: bool = true         ## Whether players can interact to remove it
@export var affects_players: bool = true        ## Whether it slows/stuns players
@export var affects_stations: bool = false      ## Whether it disables stations
@export var player_speed_multiplier: float = 1.0  ## Applied while player is in zone (0.5 = half speed)

var current_state: HazardState = HazardState.INACTIVE
var _active_timer: float = 0.0
var _warning_timer: float = 0.0
var _clear_timer: float = 0.0
var _affected_players: Array[PlayerCharacter] = []
var _affected_station: BaseStation = null
var _clearing_player: PlayerCharacter = null

@onready var hazard_visual: Node3D = get_node_or_null("HazardVisual") as Node3D
@onready var hazard_label: Label3D = get_node_or_null("HazardLabel") as Label3D
@onready var warning_indicator: Node3D = get_node_or_null("WarningIndicator") as Node3D
@onready var interaction_zone: Interactable = get_node_or_null("InteractionZone") as Interactable


func _ready() -> void:
    add_to_group("hazards")
    collision_layer = Constants.COLLISION_MASK_HAZARDS
    collision_mask = Constants.COLLISION_MASK_PLAYERS

    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)

    if interaction_zone and can_be_cleared:
        interaction_zone.interacted.connect(_on_clear_interacted)
        interaction_zone.interaction_prompt = "Clear %s" % hazard_name

    _set_visual_state()


func _physics_process(delta: float) -> void:
    match current_state:
        HazardState.WARNING:
            _warning_timer -= delta
            _flash_warning(delta)
            if _warning_timer <= 0.0:
                activate()

        HazardState.ACTIVE:
            if duration > 0.0:
                _active_timer += delta
                if _active_timer >= duration:
                    expire()
            _process_active_effects(delta)

        HazardState.CLEARING:
            _clear_timer += delta
            if _clear_timer >= clear_time:
                clear()


## Begins the warning phase before the hazard activates
func spawn_with_warning() -> void:
    current_state = HazardState.WARNING
    _warning_timer = warning_duration
    visible = true
    if warning_indicator:
        warning_indicator.visible = true
    if hazard_visual:
        hazard_visual.visible = false
    _set_visual_state()


## Immediately activates the hazard (skip warning)
func activate() -> void:
    current_state = HazardState.ACTIVE
    _active_timer = 0.0
    monitoring = true
    if warning_indicator:
        warning_indicator.visible = false
    if hazard_visual:
        hazard_visual.visible = true
    _set_visual_state()
    _on_activated()
    hazard_activated.emit(self)
    SignalBus.hazard_activated.emit(hazard_name, hazard_type)


## Called when the hazard expires naturally (timer ran out)
func expire() -> void:
    _cleanup_effects()
    current_state = HazardState.CLEARED
    hazard_expired.emit(self)
    SignalBus.hazard_expired.emit(hazard_name)
    queue_free()


## Called when a player successfully clears the hazard
func clear() -> void:
    _cleanup_effects()
    current_state = HazardState.CLEARED
    hazard_cleared.emit(self)
    SignalBus.hazard_cleared.emit(hazard_name)
    queue_free()


## Starts the clearing interaction (player holds interact)
func start_clearing(player: PlayerCharacter) -> void:
    if current_state != HazardState.ACTIVE or not can_be_cleared:
        return
    current_state = HazardState.CLEARING
    _clearing_player = player
    _clear_timer = 0.0


## Cancels an in-progress clear (player walked away)
func cancel_clearing() -> void:
    if current_state == HazardState.CLEARING:
        current_state = HazardState.ACTIVE
        _clearing_player = null
        _clear_timer = 0.0


## Override in subclasses: what happens when hazard activates
func _on_activated() -> void:
    pass


## Override in subclasses: per-frame effect while active
func _process_active_effects(_delta: float) -> void:
    pass


## Override in subclasses: apply effect when player enters zone
func _apply_effect(player: PlayerCharacter) -> void:
    if affects_players and player_speed_multiplier != 1.0:
        player.move_speed *= player_speed_multiplier


## Override in subclasses: remove effect when player leaves zone
func _remove_effect(player: PlayerCharacter) -> void:
    if affects_players and player_speed_multiplier != 1.0:
        player.move_speed = Constants.DEFAULT_PLAYER_MOVE_SPEED


func _cleanup_effects() -> void:
    for player in _affected_players:
        if is_instance_valid(player):
            _remove_effect(player)
    _affected_players.clear()
    monitoring = false


func _on_body_entered(body: Node3D) -> void:
    if current_state != HazardState.ACTIVE:
        return
    if body is PlayerCharacter:
        var player := body as PlayerCharacter
        if not _affected_players.has(player):
            _affected_players.append(player)
            _apply_effect(player)


func _on_body_exited(body: Node3D) -> void:
    if body is PlayerCharacter:
        var player := body as PlayerCharacter
        if _affected_players.has(player):
            _affected_players.erase(player)
            _remove_effect(player)


func _on_clear_interacted(player: PlayerCharacter) -> void:
    if current_state == HazardState.ACTIVE:
        start_clearing(player)
    # For instant-clear hazards (clear_time = 0), clear immediately
    if clear_time <= 0.0:
        clear()


func _flash_warning(_delta: float) -> void:
    if warning_indicator:
        var flash: float = sin(Time.get_ticks_msec() * 0.015) * 0.5 + 0.5
        warning_indicator.visible = flash > 0.3


func _set_visual_state() -> void:
    if hazard_label:
        hazard_label.text = "⚠ %s" % hazard_name.to_upper()
        hazard_label.visible = current_state in [HazardState.ACTIVE, HazardState.CLEARING]
```

### Hazard Manager — `hazard_manager.gd`

```gdscript
class_name HazardManager
extends Node

## Manages hazard spawning, tracking, and difficulty-scaled events.
## Added as a child of the workshop scene alongside OrderManager.

signal hazard_spawned(hazard: BaseHazard)

@export_group("Timing")
@export var first_hazard_delay: float = 30.0     ## Seconds into round before first hazard
@export var spawn_interval: float = 20.0         ## Seconds between hazard spawn attempts
@export var min_interval: float = 10.0           ## Fastest hazard spawn rate
@export var ramp_factor: float = 0.95            ## Interval multiplier each spawn
@export var max_active_hazards: int = 3          ## Won't spawn if this many are active

@export_group("Hazard Pool")
@export var floor_hazard_scene: PackedScene = null   ## Spill / screws
@export var surge_hazard_scene: PackedScene = null   ## Power surge
@export var fire_hazard_scene: PackedScene = null    ## Battery fire (💡)

@export_group("Spawn Locations")
@export var floor_hazard_positions: Array[Marker3D] = []
@export var surge_target_stations: Array[BaseStation] = []

var _active_hazards: Array[BaseHazard] = []
var _spawn_timer: float = 0.0
var _current_interval: float = 20.0
var _initial_delay_timer: float = 0.0
var _is_active: bool = false


func _ready() -> void:
    add_to_group("hazard_managers")
    _current_interval = spawn_interval


func _physics_process(delta: float) -> void:
    if not _is_active:
        return

    # Handle initial delay
    if _initial_delay_timer > 0.0:
        _initial_delay_timer -= delta
        return

    # Clean up freed hazards
    _active_hazards = _active_hazards.filter(func(h: BaseHazard) -> bool: return is_instance_valid(h))

    _spawn_timer += delta
    if _spawn_timer >= _current_interval:
        _spawn_timer = 0.0
        _try_spawn_hazard()


## Starts the hazard system (call when round starts)
func start() -> void:
    _is_active = true
    _spawn_timer = 0.0
    _initial_delay_timer = first_hazard_delay
    _current_interval = spawn_interval


## Stops hazard spawning and clears all active hazards
func stop() -> void:
    _is_active = false
    for hazard in _active_hazards:
        if is_instance_valid(hazard):
            hazard.expire()
    _active_hazards.clear()


func _try_spawn_hazard() -> void:
    if _active_hazards.size() >= max_active_hazards:
        return

    # Pick a random hazard type weighted by what's available
    var hazard_type: String = _pick_hazard_type()

    match hazard_type:
        "floor":
            _spawn_floor_hazard()
        "surge":
            _spawn_power_surge()
        "fire":
            _spawn_battery_fire()

    # Ramp up spawn rate
    _current_interval = maxf(min_interval, _current_interval * ramp_factor)


func _pick_hazard_type() -> String:
    var options: Array[String] = []
    if floor_hazard_scene:
        options.append("floor")
        options.append("floor")  # Double weight — most common
    if surge_hazard_scene:
        options.append("surge")
    if fire_hazard_scene:
        options.append("fire")
    if options.is_empty():
        return ""
    return options[randi() % options.size()]


func _spawn_floor_hazard() -> void:
    if not floor_hazard_scene or floor_hazard_positions.is_empty():
        return

    var pos_marker: Marker3D = floor_hazard_positions[randi() % floor_hazard_positions.size()]
    var hazard: BaseHazard = floor_hazard_scene.instantiate() as BaseHazard
    if not hazard:
        return

    get_parent().add_child(hazard)
    hazard.global_position = pos_marker.global_position
    hazard.spawn_with_warning()

    _active_hazards.append(hazard)
    hazard.hazard_cleared.connect(_on_hazard_removed.bind(hazard))
    hazard.hazard_expired.connect(_on_hazard_removed.bind(hazard))
    hazard_spawned.emit(hazard)


func _spawn_power_surge() -> void:
    if not surge_hazard_scene or surge_target_stations.is_empty():
        return

    # Pick a random station that isn't already surged
    var available: Array[BaseStation] = surge_target_stations.filter(
        func(s: BaseStation) -> bool:
            return is_instance_valid(s) and not _is_station_surged(s)
    )
    if available.is_empty():
        return

    var target_station: BaseStation = available[randi() % available.size()]
    var hazard: BaseHazard = surge_hazard_scene.instantiate() as BaseHazard
    if not hazard:
        return

    get_parent().add_child(hazard)
    hazard.global_position = target_station.global_position + Vector3(0, 1.5, 0)
    hazard.set_meta("target_station", target_station)
    hazard.spawn_with_warning()

    _active_hazards.append(hazard)
    hazard.hazard_cleared.connect(_on_hazard_removed.bind(hazard))
    hazard.hazard_expired.connect(_on_hazard_removed.bind(hazard))
    hazard_spawned.emit(hazard)


func _spawn_battery_fire() -> void:
    # 💡 Nice-to-have — implement in later Phase 3 iteration
    pass


func _is_station_surged(station: BaseStation) -> bool:
    for hazard in _active_hazards:
        if is_instance_valid(hazard) and hazard.has_meta("target_station"):
            if hazard.get_meta("target_station") == station:
                return true
    return false


func _on_hazard_removed(hazard: BaseHazard) -> void:
    _active_hazards.erase(hazard)
```

### Specific Hazard Implementations

#### 3B-1: Overheating Device — `overheating_hazard.gd`

This is NOT a floor hazard — it's a **device state event**. When a device sits on the workbench in `DISASSEMBLED` or `PART_REPLACED` state for too long, it overheats. The player must pick it up and carry it to a "cool-down zone" (or just wait while holding it).

```gdscript
class_name OverheatingHazard
extends Node

## Tracks devices on workbenches and triggers overheating if left too long.
## Attached to the WorkshopDebug (or level root), monitors all workbenches.

signal device_overheating(device: Device, station: BaseStation)
signal device_cooled(device: Device)

@export var overheat_time: float = 20.0         ## Seconds before a device overheats
@export var overheat_penalty_time: float = 5.0  ## Extra seconds added to repair time on overheat
@export var warning_threshold: float = 0.75     ## Start warning at 75% of overheat time

## Tracks each device on a workbench: {device_instance_id: {timer, device, station}}
var _device_timers: Dictionary = {}


func _ready() -> void:
    # Listen for devices being placed on and removed from stations
    var stations: Array[Node] = get_tree().get_nodes_in_group("stations")
    for station_node: Node in stations:
        if station_node is WorkbenchStation:
            var wb := station_node as WorkbenchStation
            wb.device_accepted.connect(_on_device_placed.bind(wb))
            wb.device_removed.connect(_on_device_removed.bind(wb))


func _physics_process(delta: float) -> void:
    var to_remove: Array[int] = []
    for device_id: int in _device_timers:
        var data: Dictionary = _device_timers[device_id]
        var device: Device = data["device"] as Device
        var station: BaseStation = data["station"] as BaseStation

        if not is_instance_valid(device) or not is_instance_valid(station):
            to_remove.append(device_id)
            continue

        # Only tick overheat for vulnerable states
        if device.current_repair_state not in [
            RepairState.State.DISASSEMBLED,
            RepairState.State.PART_REPLACED
        ]:
            to_remove.append(device_id)
            continue

        data["timer"] += delta

        # Warning phase — visual feedback on device
        if data["timer"] >= overheat_time * warning_threshold and not data.get("warned", false):
            data["warned"] = true
            _apply_overheat_warning(device)

        # Overheat triggered
        if data["timer"] >= overheat_time:
            _trigger_overheat(device, station)
            to_remove.append(device_id)

    for device_id in to_remove:
        _device_timers.erase(device_id)


func _on_device_placed(device: Carriable, station: WorkbenchStation) -> void:
    if device is Device:
        var dev := device as Device
        if dev.current_repair_state in [
            RepairState.State.DISASSEMBLED,
            RepairState.State.PART_REPLACED
        ]:
            _device_timers[dev.get_instance_id()] = {
                "timer": 0.0,
                "device": dev,
                "station": station,
                "warned": false,
            }


func _on_device_removed(device: Carriable, _station: WorkbenchStation) -> void:
    if device:
        _device_timers.erase(device.get_instance_id())
        if device is Device:
            _remove_overheat_warning(device as Device)


func _trigger_overheat(device: Device, station: BaseStation) -> void:
    # Visual: device turns red, smoke effect placeholder
    _apply_overheat_effect(device)

    # Penalty: add extra time needed (device must be picked up and put back)
    device_overheating.emit(device, station)
    SignalBus.hazard_activated.emit("Overheat", "device_overheat")


func _apply_overheat_warning(device: Device) -> void:
    # Make device visually pulse orange to warn the player
    var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
    if mesh and mesh.material_override is StandardMaterial3D:
        var mat := mesh.material_override as StandardMaterial3D
        mat.emission_enabled = true
        mat.emission = Color(1.0, 0.6, 0.0)
        mat.emission_energy_multiplier = 1.0


func _remove_overheat_warning(device: Device) -> void:
    var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
    if mesh and mesh.material_override is StandardMaterial3D:
        var mat := mesh.material_override as StandardMaterial3D
        mat.emission_enabled = false


func _apply_overheat_effect(device: Device) -> void:
    var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
    if mesh and mesh.material_override is StandardMaterial3D:
        var mat := mesh.material_override as StandardMaterial3D
        mat.emission_enabled = true
        mat.emission = Color(1.0, 0.15, 0.05)
        mat.emission_energy_multiplier = 2.5
```

#### 3B-2: Power Surge — `power_surge_hazard.gd`

```gdscript
class_name PowerSurgeHazard
extends BaseHazard

## Disables a target station for the hazard's duration.
## The station cannot process devices or be interacted with while surged.
## Players can clear the surge by interacting with the hazard (holding interact for clear_time).

var _target_station: BaseStation = null
var _original_can_interact: bool = true


func _ready() -> void:
    hazard_name = "Power Surge"
    hazard_type = "surge"
    duration = 15.0              # Auto-expires after 15 seconds if not cleared
    warning_duration = 2.0       # 2 second warning flash
    clear_time = 3.0             # 3 seconds of holding interact to clear
    can_be_cleared = true
    affects_players = false
    affects_stations = true
    super._ready()


func _on_activated() -> void:
    _target_station = get_meta("target_station", null) as BaseStation
    if _target_station and is_instance_valid(_target_station):
        _disable_station(_target_station)


func _process_active_effects(_delta: float) -> void:
    # Visual: sparking effect on the station (label flashes)
    if hazard_label:
        var spark: float = sin(Time.get_ticks_msec() * 0.02) * 0.5 + 0.5
        hazard_label.modulate = Color(0.3 + spark * 0.7, 0.6 + spark * 0.4, 1.0)


func clear() -> void:
    if _target_station and is_instance_valid(_target_station):
        _enable_station(_target_station)
    super.clear()


func expire() -> void:
    if _target_station and is_instance_valid(_target_station):
        _enable_station(_target_station)
    super.expire()


func _disable_station(station: BaseStation) -> void:
    if station.interaction_zone:
        station.interaction_zone.is_interactable = false
    # Visual: dim the station
    if station.station_label:
        station.station_label.text = "⚡ %s [OFFLINE]" % station.station_name.to_upper()
        station.station_label.modulate = Color(0.5, 0.5, 0.7)


func _enable_station(station: BaseStation) -> void:
    if station.interaction_zone:
        station.interaction_zone.is_interactable = true
    # Restore visual
    if station.station_label:
        station.station_label.text = station.station_name.to_upper()
        station.station_label.modulate = Color.WHITE
```

#### 3B-3: Floor Spill — `floor_spill_hazard.gd`

```gdscript
class_name FloorSpillHazard
extends BaseHazard

## Floor hazard that slows players walking through it.
## Spawns as a circular patch on the floor. Players move at half speed while inside.
## Can be cleared by interacting with it (mopping / sweeping).

@export var spill_radius: float = 1.2
@export var spill_color: Color = Color(0.35, 0.2, 0.08, 0.7)  # Coffee brown


func _ready() -> void:
    hazard_name = "Spill"
    hazard_type = "floor"
    duration = 0.0                # Permanent until cleared
    warning_duration = 1.0
    clear_time = 2.0             # 2 seconds to mop up
    can_be_cleared = true
    affects_players = true
    affects_stations = false
    player_speed_multiplier = 0.45  # 45% speed — noticeably slow but not immobile
    super._ready()

    # Configure the collision shape to match spill radius
    var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
    if shape:
        var sphere := SphereShape3D.new()
        sphere.radius = spill_radius
        shape.shape = sphere


func _on_activated() -> void:
    # Create spill visual (flat disc on floor)
    if hazard_visual:
        var mesh_inst := MeshInstance3D.new()
        mesh_inst.name = "SpillMesh"
        var disc := CylinderMesh.new()
        disc.top_radius = spill_radius
        disc.bottom_radius = spill_radius
        disc.height = 0.02
        mesh_inst.mesh = disc

        var mat := StandardMaterial3D.new()
        mat.albedo_color = spill_color
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mesh_inst.material_override = mat

        hazard_visual.add_child(mesh_inst)
```

### New Signals to Add to `SignalBus`

```gdscript
# Add to scripts/core/signal_bus.gd

# Hazard Signals (Phase 3)
signal hazard_activated(hazard_name: String, hazard_type: String)
signal hazard_cleared(hazard_name: String)
signal hazard_expired(hazard_name: String)
```

### New Constants

```gdscript
# Add to scripts/core/constants.gd

# Hazard Configuration (Phase 3)
const DEFAULT_OVERHEAT_TIME: float = 20.0       # Seconds before device overheats
const DEFAULT_SURGE_DURATION: float = 15.0       # Power surge duration
const DEFAULT_SPILL_SLOW_FACTOR: float = 0.45    # Player speed multiplier in spill
const DEFAULT_SPILL_CLEAR_TIME: float = 2.0      # Seconds to mop up a spill
const DEFAULT_SURGE_CLEAR_TIME: float = 3.0      # Seconds to fix a surge
```

### Scene Tree — `FloorSpillHazard.tscn`

```
FloorSpillHazard (Area3D) ← scripts/hazards/floor_spill_hazard.gd
├── CollisionShape3D               ← SphereShape3D (radius: 1.2)
├── HazardVisual (Node3D)          ← Visual container
│   └── (SpillMesh created at runtime)
├── HazardLabel (Label3D)          ← "⚠ SPILL"
│   position: (0, 0.8, 0)
├── WarningIndicator (Node3D)      ← Flashing marker pre-spawn
│   └── MeshInstance3D             ← Small flashing diamond/exclamation
└── InteractionZone (Interactable) ← For clearing the hazard
    └── CollisionShape3D           ← SphereShape3D (radius: 1.5)
```

### Implementation Notes

- **Hazards use collision layer 5.** Players already have `COLLISION_MASK_HAZARDS` in their mask... wait, no they don't. You need to add `Constants.COLLISION_MASK_HAZARDS` to `PlayerCharacter`'s collision mask in `_ready()`. The layer is defined in `constants.gd` but not yet applied. Actually, since hazards are `Area3D` (not physics bodies), they use `body_entered`/`body_exited` signals to detect players. The player's `CharacterBody3D` enters the hazard's `Area3D` zone. The hazard's collision layer is `COLLISION_LAYER_HAZARDS` and its mask is `COLLISION_MASK_PLAYERS` — the player does NOT need to mask hazards; the Area3D handles detection.
- **Power surges disable station interaction zones.** Setting `station.interaction_zone.is_interactable = false` prevents the `Interactable.can_interact()` check from succeeding. The player's `InteractionSystem` won't find it as a valid focus. When the surge clears, restore `is_interactable = true`.
- **The `OverheatingHazard` is NOT an Area3D.** It's a pure logic node (`extends Node`) that monitors workbench timers. It doesn't have a physical collision zone — overheating is tracked per-device, not per-floor-area. The visual feedback is applied directly to the device mesh.
- **Floor spills are permanent until cleared.** `duration = 0.0` means no auto-expire. Players MUST interact to clear them. This creates prioritization decisions: "Do I stop to mop this spill or keep repairing?"
- **Power surges auto-expire after 15 seconds.** Players CAN clear them faster (3 seconds of interact), but if everyone is busy, the surge resolves itself. This prevents soft-locks where no one bothers to clear a surge on a rarely-used station.
- **Warning phase prevents unfair "gotcha" moments.** Every hazard has 1-2 seconds of flashing warning before activation. Players can see where a spill is about to appear and route around it. This is a fairness constraint — chaos should be reactable, not random death.

> [!CAUTION]
> **Do NOT put hazard spawns on the reception desk or delivery counter.** These are the entry/exit points of the repair pipeline. Blocking them creates frustrating dead ends where orders can't be started or completed. Hazards should affect MID-pipeline stations (workbench, diagnostic, software) and floor areas BETWEEN stations.

> [!TIP]
> **For Phase 3 testing, start with floor spills only.** They're the simplest hazard — slow a player, interact to clear. Get the base hazard system working with spills before adding power surges (which interact with the station system) or overheating (which requires device monitoring). Build complexity incrementally.

---

## 3C — Tool System

### Tasks

- [x] 🎯 Create `scripts/tools/tool_item.gd` — tool as a `Carriable` with `item_type = "tool"`
- [x] 🎯 Create Screwdriver tool scene — required for workbench disassembly/reassembly
- [x] 🎯 Limited tool quantity: workshop starts with N screwdrivers (not infinite)
- [x] 🎯 Tools can be left anywhere — creates "WHO TOOK MY SCREWDRIVER?" moments
- [x] 🎯 Workbench requires screwdriver: `can_player_interact()` checks for tool in hand
- [x] 💡 Additional tools: thermal paste applicator, soldering iron, ESD wrist strap
- [x] 💡 Wrong tool penalty: using the wrong tool wastes time

### Tool Design Philosophy

Tools are **shared scarce resources** that create co-op coordination challenges. In a 4-player game with 2 screwdrivers and 1 workbench, players must pass tools around, remember where they left them, and communicate. The tools themselves are simple Carriable items — no new systems, just clever constraints.

### Tool Item — `tool_item.gd`

```gdscript
class_name ToolItem
extends Carriable

## A reusable tool (screwdriver, soldering iron, etc.) that players carry.
## Tools are not consumed — they persist across repairs. Limited quantity per workshop.

@export var tool_id: String = "screwdriver"
@export var tool_display_name: String = "Screwdriver"
@export var tool_color: Color = Color(0.8, 0.1, 0.15)  # Red handle


func _ready() -> void:
    item_type = "tool"
    item_name = tool_display_name
    add_to_group("tools")
    super._ready()
    _setup_tool_visual()


func _setup_tool_visual() -> void:
    # Only create visual if no mesh child exists
    if get_node_or_null("MeshInstance3D"):
        return

    var mesh_inst := MeshInstance3D.new()
    mesh_inst.name = "MeshInstance3D"

    # Screwdriver: elongated box
    var box := BoxMesh.new()
    match tool_id:
        "screwdriver":
            box.size = Vector3(0.05, 0.25, 0.05)
        "soldering_iron":
            box.size = Vector3(0.04, 0.28, 0.04)
        "thermal_paste":
            box.size = Vector3(0.08, 0.12, 0.04)
        _:
            box.size = Vector3(0.06, 0.2, 0.06)

    mesh_inst.mesh = box

    var mat := StandardMaterial3D.new()
    mat.albedo_color = tool_color
    mesh_inst.material_override = mat

    add_child(mesh_inst)
```

### Scene Tree — `Screwdriver.tscn`

```
Screwdriver (Node3D) ← scripts/tools/tool_item.gd
├── MeshInstance3D              ← BoxMesh (0.05, 0.25, 0.05) — red handle
├── InteractionZone (Interactable)  ← For picking up off the ground
│   └── CollisionShape3D       ← SphereShape3D (radius: 0.5)
```

> [!NOTE]
> `ToolItem` extends `Carriable`, which already has `setup_interaction_zone()`. The tool's interaction zone allows players to pick it up from the ground, workbench, or wherever it was left. No new interaction code needed — the existing `CarrySystem.pick_up()` handles tools identically to parts and devices.

### Workbench Integration — Tool Requirement

The critical change: the workbench now checks if the player is carrying the right tool (or if a tool is already on the bench) before allowing disassembly and reassembly.

```gdscript
# Changes to scripts/stations/workbench_station.gd

@export var requires_tool: bool = true
@export var required_tool_id: String = "screwdriver"

## Checks if a player has the required tool available for workbench operations
func _has_required_tool(player: PlayerCharacter) -> bool:
    if not requires_tool:
        return true

    # Check 1: Is the player carrying the right tool?
    if player.carry_system and player.carry_system.is_carrying():
        var held: Carriable = player.carry_system.get_held_item()
        if held is ToolItem and (held as ToolItem).tool_id == required_tool_id:
            return true

    # Check 2: Is there a tool on the workbench?
    # (Tool sits next to the device — tracked separately from placed_device)
    if _bench_tool != null and is_instance_valid(_bench_tool):
        if _bench_tool is ToolItem and (_bench_tool as ToolItem).tool_id == required_tool_id:
            return true

    return false


## New property: tool currently sitting on the workbench
var _bench_tool: ToolItem = null


## Updated interaction: place tool on bench if carrying one and bench has a device
func _try_place_tool(player: PlayerCharacter) -> bool:
    if not player.carry_system or not player.carry_system.is_carrying():
        return false

    var held: Carriable = player.carry_system.get_held_item()
    if held is ToolItem and placed_device != null and _bench_tool == null:
        var tool: ToolItem = held as ToolItem
        player.carry_system.place_on_station(self)

        # Parent tool to bench but don't treat it as the "placed device"
        _bench_tool = tool
        if tool.get_parent():
            tool.get_parent().remove_child(tool)
        if device_slot:
            device_slot.add_child(tool)
            tool.position = Vector3(0.3, 0.0, 0.0)  # Offset from device
        return true

    return false


## Pick up the bench tool (when no device to pick up, or device is in non-tool state)
func _try_pick_up_tool(player: PlayerCharacter) -> bool:
    if _bench_tool and player.carry_system and player.carry_system.can_pick_up():
        var tool: ToolItem = _bench_tool
        _bench_tool = null
        if tool.get_parent():
            tool.get_parent().remove_child(tool)
        player.carry_system.pick_up(tool)
        return true
    return false
```

### Updated Workbench `_on_interacted()` Flow

The workbench interaction becomes richer. Here's the updated decision tree:

```
Player interacts with Workbench:
│
├── Player carrying a TOOL, bench has a device, no bench tool
│   → Place tool on bench (tool stays, device stays)
│
├── Player carrying a DEVICE (DIAGNOSED), bench is empty
│   → Place device on bench
│   → IF has_required_tool: auto-start disassembly
│   → ELSE: show prompt "Needs screwdriver"
│
├── Player carrying a PART, device on bench in DISASSEMBLED state
│   → Install part (no tool needed for part install)
│
├── Player has empty hands, device is DISASSEMBLED, tool on bench
│   → Prompt "Needs replacement part" (don't pick up device yet)
│
├── Player has empty hands, device is PART_REPLACED, has_required_tool
│   → Start reassembly
│
├── Player has empty hands, device is PART_REPLACED, NO tool
│   → Show prompt "Needs screwdriver to reassemble"
│
├── Processing COMPLETE, player has empty hands
│   → Pick up device
│
├── Player has empty hands, bench has tool but no device
│   → Pick up tool
│
└── Otherwise → no action
```

### Tool Spawning in Workshop

```gdscript
# Add to workshop_debug.gd — tool spawning during round setup

@export var screwdriver_count: int = 2   ## Number of screwdrivers in the workshop
@export var tool_scene: PackedScene = null

var _workshop_tools: Array[ToolItem] = []

## Call during start_round() after station setup
func _spawn_tools() -> void:
    if not tool_scene:
        # Create tools programmatically if no scene provided
        for i in range(screwdriver_count):
            var tool := ToolItem.new()
            tool.tool_id = "screwdriver"
            tool.tool_display_name = "Screwdriver"
            tool.name = "Screwdriver_%d" % (i + 1)
            tool.setup_interaction_zone()
            add_child(tool)

            # Place tools on or near the workbench at round start
            var pos := _get_tool_spawn_position(i)
            tool.global_position = pos
            _workshop_tools.append(tool)


func _get_tool_spawn_position(index: int) -> Vector3:
    # Place tools near the workbench area, spaced apart
    var base_pos: Vector3 = get_workbench_position() + Vector3(0.5, 0.9, 0.0)
    return base_pos + Vector3(0.3 * index, 0.0, 0.0)
```

### Implementation Notes

- **Tools are Carriable items with `item_type = "tool"`.** The carry system already handles them. No new carry logic. `pick_up()`, `drop_item()`, `place_on_station()` all work with tools out of the box.
- **Tool scarcity is the chaos multiplier.** 2 screwdrivers for 4 players and 5 active orders means 2 players can work at workbenches while 2 do diagnosis/software/delivery. If a player forgets where they left the screwdriver, the whole team's throughput drops. This is the "WHO TOOK MY SCREWDRIVER?!" design moment from the plan.
- **Tools are NOT consumed.** Unlike parts (which are `queue_free()`'d after installation), tools persist the entire round. A screwdriver is used for disassembly, then sits on the bench, then used for reassembly, then carried to the next device. Tools circulate.
- **The bench tool is tracked separately from the placed device.** `placed_device` is the device being repaired. `_bench_tool` is the screwdriver sitting next to it. They're independent — the tool can be picked up while a device is still on the bench (e.g., to lend it to another player).
- **Start Phase 3 without tool requirements, then add them.** Set `@export var requires_tool: bool = true` on workbenches. For testing, you can set it to `false` to disable tool checks while building other Phase 3 features. Enable it once the tool item and spawning work.

> [!WARNING]
> **Do NOT make tools required for diagnosis or software installation.** Only the workbench (disassembly/reassembly) needs a screwdriver. If every station needs a tool, the game becomes a tool-passing simulator instead of a repair game. One tool constraint (workbench) is enough to create scarcity; two is annoying; three is unplayable.

> [!CAUTION]
> **Do NOT let tools be destroyed or permanently lost.** If a tool falls "off the map" or gets stuck inside geometry, the round becomes unwinnable. Tools should have floor collision and never clip through the ground. Add a `_process()` check: if a tool's Y position drops below -1.0, teleport it to its spawn position.

---

## 3D — Component Variety & Parts Stock

### Tasks

- [ ] 🎯 Parts shelf limited stock: finite parts per component type per round
- [ ] 🎯 Wrong part detection: installing wrong component wastes time, doesn't advance state
- [ ] 🎯 Visual stock indicator on parts shelf (shows remaining count)
- [ ] 🎯 Player must identify correct part from diagnosis info
- [ ] 💡 Parts delivery mid-round: a delivery box arrives, must be carried and unpacked
- [ ] 💡 Parts shelf restocking via delivery boxes

### Parts Stock System

The `PartsShelf` currently auto-dispenses the exact correct part with infinite supply. Phase 3 changes this:

1. **Limited stock per component type.** The shelf starts with N of each part.
2. **Player chooses which part to take.** Multiple interact presses cycle through available parts (or the shelf has labeled sections).
3. **Wrong part feedback.** If the player installs the wrong part, the workbench rejects it with a time penalty.

```gdscript
# Changes to scripts/stations/parts_shelf.gd

## Stock tracking: component_id → remaining count
var _stock: Dictionary = {}

@export var initial_stock_per_part: int = 3    ## Starting stock for each component type
@export var stock_display_label: Label3D = null ## Shows remaining stock

signal stock_changed(component_id: String, remaining: int)
signal stock_depleted(component_id: String)


## Initialize stock for all available parts
func _init_stock() -> void:
    _stock.clear()
    for part: ComponentData in available_parts:
        _stock[part.component_id] = initial_stock_per_part
    _update_stock_display()


## Override: check stock before dispensing
func _on_interacted(player: PlayerCharacter) -> void:
    # Don't call super — we replace the entire interaction
    SignalBus.station_interacted.emit(station_name, player.player_index if player else 0)

    if not player or not player.carry_system or not player.carry_system.can_pick_up():
        return

    var needed: ComponentData = _get_needed_part()
    if not needed:
        return

    # Check stock
    var remaining: int = _stock.get(needed.component_id, 0)
    if remaining <= 0:
        # Out of stock — visual/audio feedback
        _flash_out_of_stock()
        return

    # Dispense part and decrement stock
    _stock[needed.component_id] = remaining - 1
    stock_changed.emit(needed.component_id, remaining - 1)

    if remaining - 1 <= 0:
        stock_depleted.emit(needed.component_id)

    var part: Carriable = _create_part_instance(needed)
    if not part:
        return

    if get_parent():
        get_parent().add_child(part)
    else:
        add_child(part)

    player.carry_system.pick_up(part)
    _update_stock_display()


## Returns current stock for a given component
func get_stock(component_id: String) -> int:
    return _stock.get(component_id, 0)


## Restocks a specific component (e.g., from a delivery box)
func restock(component_id: String, amount: int = 1) -> void:
    if component_id in _stock:
        _stock[component_id] += amount
    else:
        _stock[component_id] = amount
    stock_changed.emit(component_id, _stock[component_id])
    _update_stock_display()


func _update_stock_display() -> void:
    if not stock_display_label:
        stock_display_label = get_node_or_null("StockLabel") as Label3D
    if not stock_display_label:
        return

    var lines: Array[String] = []
    for part: ComponentData in available_parts:
        var count: int = _stock.get(part.component_id, 0)
        var status: String = "%d" % count if count > 0 else "OUT"
        lines.append("%s: %s" % [part.component_name, status])

    stock_display_label.text = "\n".join(lines)


func _flash_out_of_stock() -> void:
    if station_label:
        station_label.text = "OUT OF STOCK"
        station_label.modulate = Color(1.0, 0.2, 0.2)
        # Reset after brief flash
        var tween := create_tween()
        tween.tween_interval(1.0)
        tween.tween_callback(func() -> void:
            if station_label:
                station_label.text = station_name.to_upper()
                station_label.modulate = Color.WHITE
        )
```

### Wrong Part Detection — Workbench Update

The workbench's `try_install_component()` on `Device` already validates part matching. When the wrong part is installed, the device rejects it. The workbench should provide clear feedback:

```gdscript
# In workbench_station.gd — when player carries a part to a bench with a disassembled device

func _try_install_part(player: PlayerCharacter, device: Device) -> bool:
    if not player.carry_system or not player.carry_system.is_carrying():
        return false

    var held: Carriable = player.carry_system.get_held_item()
    if held.item_type != "part":
        return false

    var component: ComponentData = held.get_meta("component_data", null)
    if not component:
        return false

    # Try to install — Device.try_install_component() validates the match
    if device.try_install_component(component):
        # Correct part — consume it and advance
        player.carry_system.get_held_item()  # Reference only
        held.queue_free()
        device.advance_state(RepairState.State.PART_REPLACED)
        return true
    else:
        # WRONG PART — reject with feedback
        _flash_wrong_part()
        SignalBus.hazard_activated.emit("Wrong Part", "wrong_part")
        return false


func _flash_wrong_part() -> void:
    if station_label:
        station_label.text = "✗ WRONG PART"
        station_label.modulate = Color(1.0, 0.2, 0.2)
        var tween := create_tween()
        tween.tween_interval(1.5)
        tween.tween_callback(func() -> void:
            if station_label:
                station_label.text = station_name.to_upper()
                station_label.modulate = Color.WHITE
        )
```

### Parts Delivery Box (💡 Nice-to-Have)

```gdscript
class_name DeliveryBox
extends Carriable

## A delivery box that arrives mid-round containing restocking parts.
## Must be carried to the Parts Shelf and "unpacked" via interaction.

@export var contained_parts: Dictionary = {}  ## component_id → quantity

func _ready() -> void:
    item_type = "delivery"
    item_name = "Parts Box"
    add_to_group("delivery_boxes")
    super._ready()


## Called when the box is "unpacked" at a parts shelf
func unpack_at_shelf(shelf: PartsShelf) -> void:
    for component_id: String in contained_parts:
        var qty: int = contained_parts[component_id]
        shelf.restock(component_id, qty)
    queue_free()  # Box is consumed
```

### Implementation Notes

- **Initial stock of 3 per part type is a starting balance point.** With 5 max orders, some orders might share the same fault (2 cracked screens), requiring 2 screen parts. Starting with 3 means the first few repairs have parts, but later ones might run out. This creates urgency around part management.
- **Wrong part detection already exists in `Device.try_install_component()`.** It checks `component.component_id == assigned_fault.broken_component.component_id`. Phase 3 just adds the visual "WRONG PART" feedback on the workbench and prevents the part from being consumed on failure.
- **The player keeps the wrong part.** When a wrong part is rejected, the part stays in the player's carry system. They must drop it (or return it to the shelf) and get the correct one. The part is NOT consumed.
- **Parts delivery boxes are a 💡 stretch goal.** They add a mini-logistics layer: a box appears at the reception desk mid-round, a player must carry it to the parts shelf and interact to unpack. This creates a "do I stop repairing to restock?" decision. Implement only after base stock tracking works.

> [!WARNING]
> **Do NOT make the parts shelf require interaction to cycle through parts.** The shelf should auto-detect the needed part from diagnosed devices (the existing `_get_needed_part()` behavior). If there's ambiguity (multiple devices needing different parts), the shelf should give the part for the FIRST diagnosed device. Players don't want to play an inventory management minigame — they want to grab and go.

---

## 3E — Integration & Wiring

### Tasks

- [ ] 🎯 Add `OrderSpawner` node to `Workshop_Debug.tscn`
- [ ] 🎯 Add `HazardManager` node to `Workshop_Debug.tscn`
- [ ] 🎯 Add `OverheatingHazard` node to `Workshop_Debug.tscn`
- [ ] 🎯 Create hazard scene files (`FloorSpillHazard.tscn`, `PowerSurgeHazard.tscn`)
- [ ] 🎯 Create `Screwdriver.tscn` tool scene
- [ ] 🎯 Wire `OrderSpawner` → `OrderManager` → round flow
- [ ] 🎯 Wire `HazardManager` → round flow (start/stop)
- [ ] 🎯 Update `WorkshopDebug.start_round()` to start spawner + hazard manager
- [ ] 🎯 Add hazard spawn position markers to workshop scene
- [ ] 🎯 Update HUD for multiple orders display
- [ ] 🎯 Update `PartsShelf` with stock system
- [ ] 🎯 Update `WorkbenchStation` with tool requirement
- [ ] 🎯 Add Phase 3 signals to `SignalBus`
- [ ] 🎯 Add Phase 3 constants to `Constants`
- [ ] 🎯 Spawn 2 screwdrivers at round start
- [ ] 🎯 Test: 3+ orders active simultaneously with independent timers
- [ ] 🎯 Test: floor spill spawns, slows player, can be cleared
- [ ] 🎯 Test: power surge disables station, auto-expires or player-clears
- [ ] 🎯 Test: device overheats on workbench after timeout
- [ ] 🎯 Test: workbench requires screwdriver for disassembly/reassembly
- [ ] 🎯 Test: parts shelf runs out of stock
- [ ] 🎯 Test: wrong part rejected at workbench
- [ ] 💡 Test: delivery box restocks parts shelf
- [ ] 💡 Add debug hotkeys for Phase 3 systems

### Updated Workshop Scene Tree

```
Workshop_Debug (Node3D) ← workshop_debug.gd
├── ... (existing stations, floor, walls, spawn points)
│
├── OrderManager (Node) ← order_manager.gd            [EXISTING]
├── OrderSpawner (Node) ← order_spawner.gd             [NEW — Phase 3]
│
├── HazardManager (Node) ← hazard_manager.gd           [NEW — Phase 3]
├── OverheatingHazard (Node) ← overheating_hazard.gd   [NEW — Phase 3]
│
├── HazardSpawnPoints (Node3D)                          [NEW — Phase 3]
│   ├── FloorHazardPos1 (Marker3D)  ← Between workbench and diagnostic
│   ├── FloorHazardPos2 (Marker3D)  ← Between parts shelf and software station
│   ├── FloorHazardPos3 (Marker3D)  ← Center of workshop
│   └── FloorHazardPos4 (Marker3D)  ← Near delivery counter
│
├── Tools (Node3D)                                      [NEW — Phase 3]
│   ├── Screwdriver_1 (Node3D) ← tool_item.gd
│   └── Screwdriver_2 (Node3D) ← tool_item.gd
```

### Updated `WorkshopDebug.start_round()`

```gdscript
# Add to workshop_debug.gd

@onready var order_spawner: OrderSpawner = get_node_or_null("OrderSpawner") as OrderSpawner
@onready var hazard_manager: HazardManager = get_node_or_null("HazardManager") as HazardManager
@onready var overheating_hazard: OverheatingHazard = get_node_or_null("OverheatingHazard") as OverheatingHazard

func start_round() -> void:
    # ... existing round start logic ...

    # Phase 3: Start order spawner
    if order_spawner:
        if not order_spawner.order_manager:
            order_spawner.order_manager = order_manager
        order_spawner.start()

    # Phase 3: Start hazard manager
    if hazard_manager:
        hazard_manager.start()

    # Phase 3: Spawn tools
    _spawn_tools()

    # Phase 3: Initialize parts stock
    if parts_shelf:
        parts_shelf._init_stock()

    SignalBus.round_started.emit()
```

### File Organization — Phase 3 Changes

```
scripts/
├── core/
│   ├── constants.gd              ← UPDATE: add hazard constants, tool constants
│   ├── signal_bus.gd             ← UPDATE: add hazard signals (hazard_activated, etc.)
│   └── (everything else unchanged)
├── hazards/                       ← NEW directory (Phase 3)
│   ├── base_hazard.gd            ← NEW: BaseHazard base class
│   ├── hazard_manager.gd         ← NEW: HazardManager spawner/tracker
│   ├── floor_spill_hazard.gd     ← NEW: Floor spill (slows players)
│   ├── power_surge_hazard.gd     ← NEW: Power surge (disables station)
│   └── overheating_hazard.gd     ← NEW: Device overheat monitor
├── tools/                         ← NEW directory (Phase 3)
│   └── tool_item.gd              ← NEW: ToolItem carriable
├── orders/
│   ├── order.gd                  ← UPDATE: add is_priority, base_score fields
│   ├── order_manager.gd          ← UNCHANGED
│   └── order_spawner.gd          ← NEW: Automatic order spawning
├── stations/
│   ├── parts_shelf.gd            ← UPDATE: stock tracking, limited dispense
│   ├── workbench_station.gd      ← UPDATE: tool requirement, wrong part feedback
│   └── (other stations unchanged)
├── ui/
│   └── hud.gd                    ← UPDATE: multiple order entries, priority styling
└── workshop/
    └── workshop_debug.gd         ← UPDATE: spawn tools, wire spawner + hazard manager

scenes/
├── hazards/                       ← NEW directory (Phase 3)
│   ├── FloorSpillHazard.tscn     ← NEW
│   └── PowerSurgeHazard.tscn     ← NEW
├── tools/                         ← NEW directory (Phase 3)
│   └── Screwdriver.tscn          ← NEW
└── workshop/
    └── Workshop_Debug.tscn       ← UPDATE: add OrderSpawner, HazardManager, tool spawn points
```

### Debug Tools to Add

```gdscript
# Add to workshop_debug.gd — Phase 3 debug hotkeys

# F12: Spawn a floor spill hazard at a random position
KEY_F12:
    if hazard_manager:
        hazard_manager._spawn_floor_hazard()
        print("[Debug F12] Spawned floor spill hazard")

# Shift+F12: Spawn a power surge on a random station
# (Use a different key combo or extend the existing debug input handler)

# Ctrl+F6: Force spawn a priority order
# Ctrl+F7: Toggle tool requirement on workbenches
# Ctrl+F8: Restock all parts
```

### Testing Matrix

| Test Case | Expected Result | Critical? |
|-----------|----------------|-----------|
| Round starts → orders auto-spawn every ~25s | Multiple orders appear on reception desk and HUD | 🎯 |
| 5 orders active → spawner pauses | No new orders until one is completed/expired | 🎯 |
| Priority order spawns with ⚡ prefix | HUD shows orange tint, shorter timer, higher score | 🎯 |
| Spawn rate ramps over time | Orders come faster in the second half of the round | 🎯 |
| Floor spill spawns → player walks through it | Player moves at ~45% speed inside spill zone | 🎯 |
| Player interacts with spill for 2s | Spill is cleared, player speed restored | 🎯 |
| Power surge hits workbench | Workbench interaction zone disabled, "OFFLINE" label | 🎯 |
| Power surge auto-expires after 15s | Workbench re-enabled, surge visual removed | 🎯 |
| Player clears surge in 3s | Workbench re-enabled early | 🎯 |
| Device sits on workbench for 20s in DISASSEMBLED state | Device turns red (overheat), warning at 15s | 🎯 |
| Player picks up overheated device | Overheat timer resets, visual clears | 🎯 |
| Player tries workbench disassembly without screwdriver | Prompt shows "Needs screwdriver", action blocked | 🎯 |
| Player carries screwdriver + interacts with bench | Disassembly proceeds normally | 🎯 |
| Screwdriver left on ground, another player picks it up | Claim system works, tool transferred | 🎯 |
| Parts shelf starts with 3 of each part | Stock display shows counts | 🎯 |
| Player takes all 3 screens | Shelf shows "OUT" for screens, other parts still available | 🎯 |
| Player installs wrong part at workbench | "WRONG PART" flash, part NOT consumed, device state unchanged | 🎯 |
| 2 players simultaneously repairing different devices | Both pipelines work independently with tool sharing | 🎯 |
| Delivery box arrives → carried to shelf → unpacked | Shelf restocked | 💡 |
| 4-player chaos test: 4 orders, 2 spills, 1 surge, 2 screwdrivers | Game runs without crashes, playable chaos | 🎯 |

---

## Best Practices & Guidelines

### Architecture Principles for Phase 3

1. **New systems are NEW NODES, not modifications to existing nodes.** `OrderSpawner`, `HazardManager`, `OverheatingHazard` are separate nodes added to the workshop scene. They communicate via signals and direct references — they don't inherit from or replace existing systems. This keeps Phase 1-2 systems stable.

2. **Hazards are self-contained entities.** Each hazard node manages its own lifecycle: warning → active → cleared/expired. It self-destructs via `queue_free()`. The `HazardManager` spawns them and tracks references, but doesn't drive their behavior. This means hazards work correctly even if the manager is removed.

3. **Scarcity drives co-op, not complexity.** Tools and parts stock are simple counters and checks. The gameplay depth comes from the scarcity constraint (2 screwdrivers, 3 parts), not from complex mechanics. Don't add tool durability, part crafting, or inventory puzzles. Keep the systems simple; the chaos comes from the combination.

4. **Every chaos system must be toggle-able via `@export`.** Level designers (Phase 5) need per-level control: `OrderSpawner.max_active_orders = 3`, `HazardManager.max_active_hazards = 0` (no hazards on tutorial levels), `WorkbenchStation.requires_tool = false` (early levels). All Phase 3 parameters are `@export` so they can be configured per workshop scene.

5. **Existing Phase 1-2 single-player code MUST still work.** If the `OrderSpawner` is not in the scene, the workshop falls back to Phase 1 behavior (manual `spawn_order()`). If `HazardManager` is missing, no hazards spawn. If `requires_tool = false` on the workbench, tools aren't needed. Phase 3 is additive, not destructive.

### Common Phase 3 Mistakes to Avoid

> [!CAUTION]
> **Don't make hazards unfair.** Every hazard must have a warning phase (1-2 seconds of visual warning). Instant hazards with no warning feel random and frustrating. Players should be able to SEE a spill forming and choose to dodge or deal with it.

> [!CAUTION]
> **Don't disable the reception desk or delivery counter with hazards.** These are the entry/exit of the pipeline. Blocking them means orders can't be started or completed, which creates unwinnable states. Surges should target mid-pipeline stations only: diagnostic, workbench, software.

> [!CAUTION]
> **Don't let tools clip through geometry or get permanently lost.** Add a safety check: if a tool's Y position drops below -1.0, teleport it back to its spawn position. If a tool is inside a wall, move it to the nearest valid floor position. A lost tool = an unwinnable round.

> [!WARNING]
> **Don't modify the repair pipeline (RepairState).** The state machine (RECEIVED → ... → DELIVERED) is unchanged in Phase 3. Overheating doesn't add new states. Power surges don't skip states. Wrong parts don't change states. Phase 3 adds constraints around the existing pipeline (tool required, stock limits, hazard interruptions) but doesn't alter the pipeline itself.

> [!WARNING]
> **Don't make the order spawner too aggressive for testing.** Start with relaxed settings (30s interval, max 3 orders) and tune after playtesting. An overly aggressive spawner makes the game unplayable before you can test hazard and tool interactions. Balance comes in Phase 9 — Phase 3 is about mechanics, not difficulty.

> [!WARNING]
> **Don't add hazard damage or player death.** Overclocked is a co-op comedy game, not a survival game. Hazards slow players, disable stations, and waste time. They never kill players, destroy devices, or end the round. The penalty for hazards is TIME — fewer orders completed, fewer stars earned.

> [!WARNING]
> **Don't build all hazards at once.** Start with floor spills (simplest: Area3D + speed debuff), then power surges (adds station disabling), then overheating (adds per-device monitoring). Each builds on the previous. Battery fires and cable tangles are 💡 stretch goals for the end of Phase 3.

### Suggested Build Order

| Day | Focus | What You Build |
|-----|-------|----------------|
| 1 | Order Spawner | `OrderSpawner` script + wire to `WorkshopDebug`, test multi-order flow |
| 2 | HUD Updates | Multiple order entries, priority styling, timer urgency colors |
| 3 | Base Hazard System | `BaseHazard`, `HazardManager`, `FloorSpillHazard` scene + script |
| 4 | Floor Spill Testing | Hazard spawning, warning phase, player slow effect, clearing |
| 5 | Power Surge | `PowerSurgeHazard`, station disabling, auto-expire, player clearing |
| 6 | Overheating | `OverheatingHazard`, workbench timer monitoring, visual feedback |
| 7 | Tool System | `ToolItem`, `Screwdriver.tscn`, workbench tool requirement |
| 8 | Parts Stock | `PartsShelf` stock tracking, limited dispense, stock display, wrong part feedback |
| 9 | Integration | Wire everything together, hazard spawn points, full round flow |
| 10 | Testing & Polish | 4-player chaos test, debug hotkeys, edge case fixes, balance tuning |

### Hazard Placement Guidelines

```
Workshop layout (top-down, approximate positions):

    [Reception]         [Diagnostic]
        ●                   ●
            ■ floor_pos_1
    [Parts Shelf]       [Workbench]
        ●       ■           ●
            floor_pos_3
                    ■ floor_pos_2
    [Software]          [Delivery]
        ●                   ●
                ■ floor_pos_4

Legend:
  ●  = Station (can be surge target)
  ■  = Floor hazard spawn position

Rules:
  - Floor hazards spawn BETWEEN stations (on walkways), not ON stations
  - Power surges target: Diagnostic, Workbench, Software (NOT Reception, NOT Delivery)
  - At least 2 meters between any hazard spawn point and station interaction zone
  - No hazard spawn points in player spawn area
```

---

## Phase 3 Checklist (Summary)

### 3A — Multiple Simultaneous Orders
- [ ] 🎯 `OrderSpawner` with configurable spawn interval, ramp, and queue cap
- [ ] 🎯 Priority orders with shorter timers and higher score
- [ ] 🎯 Max 5 active orders (configurable per level)
- [ ] 🎯 HUD shows all active orders with individual timer bars
- [ ] 🎯 Timer urgency colors (green → yellow → red → flashing)
- [ ] 🎯 Priority order visual distinction (⚡ prefix, orange tint)
- [ ] 💡 Spawn rate ramps over round duration
- [ ] 💡 `max_total_orders` cap for fixed-order levels

### 3B — Workshop Hazards
- [ ] 🎯 `BaseHazard` base class with warning → active → cleared lifecycle
- [ ] 🎯 `HazardManager` spawner with timing, caps, and hazard pool
- [ ] 🎯 **Floor Spill**: slows players to 45% speed, cleared by interact (2s)
- [ ] 🎯 **Power Surge**: disables station for 15s, clearable in 3s, auto-expires
- [ ] 🎯 **Overheating Device**: device on workbench 20s → overheats, must pick up
- [ ] 🎯 Warning phase (1-2s flashing) before every hazard activates
- [ ] 🎯 Hazard collision on layer 5 (`COLLISION_LAYER_HAZARDS`)
- [ ] 🎯 New signals: `hazard_activated`, `hazard_cleared`, `hazard_expired`
- [ ] 💡 **Battery Fire**: emergency event, requires fire extinguisher
- [ ] 💡 **Cable Tangle**: blocks path until cleared

### 3C — Tool System
- [x] 🎯 `ToolItem` extends `Carriable` with `item_type = "tool"`, `tool_id`
- [x] 🎯 Screwdriver scene + script — red handle, small mesh
- [x] 🎯 Workshop spawns 2 screwdrivers at round start
- [x] 🎯 Workbench requires screwdriver for disassembly and reassembly
- [x] 🎯 Tools persist (not consumed) — reusable across repairs
- [x] 🎯 Tools can be left anywhere, picked up by any player
- [x] 🎯 Workbench tracks `_bench_tool` separately from `placed_device`
- [x] 💡 Additional tools: thermal paste, soldering iron
- [x] 💡 Wrong tool penalty: using wrong tool type wastes time

### 3D — Component Variety & Parts Stock
- [ ] 🎯 `PartsShelf` stock tracking: `initial_stock_per_part = 3`
- [ ] 🎯 Stock display on shelf (Label3D showing counts)
- [ ] 🎯 Out-of-stock feedback when part unavailable
- [ ] 🎯 Wrong part rejected at workbench with visual feedback
- [ ] 🎯 Wrong part NOT consumed (stays in player's carry system)
- [ ] 💡 `DeliveryBox` item: carry to shelf + interact to restock
- [ ] 💡 Mid-round delivery box spawns at reception desk

### 3E — Integration & Testing
- [ ] 🎯 All new nodes added to `Workshop_Debug.tscn`
- [ ] 🎯 Round flow starts/stops spawner + hazard manager
- [ ] 🎯 Hazard spawn positions placed in workshop layout
- [ ] 🎯 New `scripts/hazards/` and `scripts/tools/` directories created
- [ ] 🎯 Phase 3 signals added to `SignalBus`
- [ ] 🎯 Phase 3 constants added to `Constants`
- [ ] 🎯 Debug hotkeys for Phase 3 systems
- [ ] 🎯 Full 4-player chaos test: orders + hazards + tools + stock
- [ ] 🎯 Single-player regression: Phase 1-2 behavior unchanged when Phase 3 nodes absent
- [ ] 🎯 2-player test: both repair independently with tool sharing

---

> **When this phase is done, open Phase 4.**
> The next file will detail device roster expansion (tablet, laptop, desktop PC, game console, router) with per-device fault variety, multi-fault devices, and the content that keeps each round feeling fresh. Phase 3 gives you the chaos engine; Phase 4 gives it fuel.
