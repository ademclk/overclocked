class_name Constants
extends RefCounted

## Global constants and project configuration for Overclocked

# Scale Conventions (1 unit = 1 meter)
const UNIT_SCALE: float = 1.0
const CHARACTER_HEIGHT: float = 1.8
const WORKBENCH_SIZE: Vector3 = Vector3(1.5, 0.9, 0.7)
const DEBUG_ROOM_SIZE: Vector2 = Vector2(10.0, 8.0)

# Player Limits
const MIN_PLAYERS: int = 1
const MAX_PLAYERS: int = 4

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
