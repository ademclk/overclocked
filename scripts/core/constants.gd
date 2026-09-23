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

# Bump Mechanic Configuration
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

# Hazard Configuration
const DEFAULT_OVERHEAT_TIME: float = 20.0       # Seconds before device overheats
const DEFAULT_SURGE_DURATION: float = 15.0       # Power surge duration
const DEFAULT_SPILL_SLOW_FACTOR: float = 0.45    # Player speed multiplier in spill
const DEFAULT_SPILL_CLEAR_TIME: float = 2.0      # Seconds to mop up a spill
const DEFAULT_SURGE_CLEAR_TIME: float = 3.0      # Seconds to fix a surge

# Tool Configuration
const DEFAULT_SCREWDRIVER_COUNT: int = 2

# Parts Stock Configuration
const DEFAULT_INITIAL_STOCK_PER_PART: int = 3

# Device Tier Configuration
const TIER_1_REPAIR_TIME_BASE: float = 60.0    ## Phone baseline
const TIER_2_REPAIR_TIME_BASE: float = 100.0   ## Console/Router baseline
const TIER_3_REPAIR_TIME_BASE: float = 180.0   ## Desktop baseline

# Two-Player Carry Configuration
const TWO_PLAYER_CARRY_REQUEST_TIMEOUT: float = 3.0   ## Seconds before request cancels
const TWO_PLAYER_CARRY_SPEED_MULTIPLIER: float = 0.6  ## Tethered movement speed
const ONE_PLAYER_HEAVY_CARRY_SPEED: float = 0.4       ## Lone player carrying heavy device
const TWO_PLAYER_CARRY_DISTANCE: float = 1.5          ## Max distance between both players

# Device Color Palette (matches device_color in DeviceData .tres files)
const DEVICE_COLOR_PHONE: Color = Color(0.85, 0.85, 0.88)
const DEVICE_COLOR_TABLET: Color = Color(0.3, 0.55, 0.75)
const DEVICE_COLOR_LAPTOP: Color = Color(0.15, 0.15, 0.18)
const DEVICE_COLOR_DESKTOP: Color = Color(0.1, 0.1, 0.12)
const DEVICE_COLOR_CONSOLE: Color = Color(0.08, 0.08, 0.08)
const DEVICE_COLOR_ROUTER: Color = Color(0.9, 0.9, 0.87)

# UI Scale & Readability
const UI_SCALE_REFERENCE_HEIGHT: int = 1080
const WORLD_LABEL_MIN_FONT_SIZE: int = 16
const WORLD_LABEL_MAX_FONT_SIZE: int = 28
const STATION_ICON_SIZE: Vector2 = Vector2(36, 36)
const INTERACTION_MENU_WIDTH: float = 360.0       ## Pixels at 1080p
const EXAMINATION_PANEL_HEIGHT_RATIO: float = 0.4  ## 40% of screen height

# Combo Streak & Game Feel
const COMBO_WINDOW_SECONDS: float = 10.0
const COMBO_TIERS: Array[float] = [1.0, 1.5, 2.0, 2.5, 3.0]
const RUSH_SPEED_BONUS: float = 0.7
const RUSH_FAILURE_CHANCE: float = 0.15
const RUSH_FAILURE_PENALTY: float = 3.0
const TOOL_DEFAULT_DURABILITY: int = 8
const MINIGAME_SKIP_PENALTY_TIER_1: float = 3.0
const MINIGAME_SKIP_PENALTY_TIER_2: float = 5.0
const MINIGAME_SKIP_PENALTY_TIER_3: float = 8.0

# Contextual Interaction System
const MENU_AUTO_CLOSE_DISTANCE: float = 2.4
const QUICK_ACTION_THRESHOLD: int = 1  ## Skip menu if only N valid options
