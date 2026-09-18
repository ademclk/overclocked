class_name Constants
extends RefCounted

## Global constants and project configuration for Overclocked

# Scale Conventions (1 unit = 1 meter)
const UNIT_SCALE: float = 1.0
const CHARACTER_HEIGHT: float = 1.8
const WORKBENCH_SIZE: Vector3 = Vector3(1.5, 0.9, 0.7)
const DEBUG_ROOM_SIZE: Vector2 = Vector2(16.0, 12.0)

# Player Limits
const MIN_PLAYERS: int = 1
const MAX_PLAYERS: int = 4

# Player Identity & Colors (P1: Blue, P2: Red, P3: Green, P4: Yellow)
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # P1 — Blue
	Color(1.0, 0.35, 0.25),  # P2 — Red
	Color(0.3, 0.85, 0.35),  # P3 — Green
	Color(1.0, 0.75, 0.1),   # P4 — Yellow
]
const PLAYER_COLOR_NAMES: Array[String] = ["Blue", "Red", "Green", "Yellow"]

# Keyboard split action mapping for P1 (P0 uses WASD by default)
const KB_PLAYER1_INTERACT_KEY: int = KEY_KP_1
const KB_PLAYER1_PICKUP_KEY: int = KEY_KP_2
const KB_PLAYER1_DROP_KEY: int = KEY_KP_3

# Bump Mechanic Configuration (Phase 2I)
const BUMP_SPEED_THRESHOLD: float = 4.0   # Combined speed threshold for bumping
const BUMP_STUN_DURATION: float = 0.3     # Seconds of stumble
const BUMP_COOLDOWN: float = 1.0          # Seconds between bumps

# Physics Collision Layers (1-based index and bitmasks)
# Layer 1: World / Environment geometry (walls, static boundaries)
const COLLISION_LAYER_WORLD: int = 1
const COLLISION_MASK_WORLD: int = 1 << (COLLISION_LAYER_WORLD - 1)

# Layer 2: Player characters
const COLLISION_LAYER_PLAYERS: int = 2
const COLLISION_MASK_PLAYERS: int = 1 << (COLLISION_LAYER_PLAYERS - 1)

# Layer 3: Workshop stations (workbench, diagnostic, shelf, delivery)
const COLLISION_LAYER_STATIONS: int = 3
const COLLISION_MASK_STATIONS: int = 1 << (COLLISION_LAYER_STATIONS - 1)

# Layer 4: Interactable items / components / devices
const COLLISION_LAYER_ITEMS: int = 4
const COLLISION_MASK_ITEMS: int = 1 << (COLLISION_LAYER_ITEMS - 1)

# Layer 5: Workshop hazards (fires, spills, sparks)
const COLLISION_LAYER_HAZARDS: int = 5
const COLLISION_MASK_HAZARDS: int = 1 << (COLLISION_LAYER_HAZARDS - 1)

# Input Configuration
const DEFAULT_ANALOG_DEADZONE: float = 0.2

# Gameplay Defaults
const DEFAULT_INTERACTION_DISTANCE: float = 1.6
const DEFAULT_PLAYER_MOVE_SPEED: float = 6.0
const DEFAULT_ORDER_TIMEOUT_SECONDS: float = 60.0

# Hazard Configuration (Phase 3)
const DEFAULT_OVERHEAT_TIME: float = 20.0       # Seconds before device overheats
const DEFAULT_SURGE_DURATION: float = 15.0       # Power surge duration
const DEFAULT_SPILL_SLOW_FACTOR: float = 0.45    # Player speed multiplier in spill
const DEFAULT_SPILL_CLEAR_TIME: float = 2.0      # Seconds to mop up a spill
const DEFAULT_SURGE_CLEAR_TIME: float = 3.0      # Seconds to fix a surge

# Tool Configuration (Phase 3C)
const DEFAULT_SCREWDRIVER_COUNT: int = 2

