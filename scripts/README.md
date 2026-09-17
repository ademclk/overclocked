# Scripts Directory

This directory contains GDScript code files (`.gd`).

## Conventions
- Use **snake_case** for script files (e.g. `player_character.gd`, `game_manager.gd`).
- Use static typing everywhere (`var speed: float = 5.0`, `func do_work() -> void:`).
- Use `class_name` when a type needs to be referenced across the codebase.

## Folders
- `core/`: Autoloads (`GameManager`, `SignalBus`), state machine, constants.
- `devices/`: Device controller and fault logic.
- `repair/`: Repair pipeline state machine and actions.
- `orders/`: Customer orders, queue management, scoring, and timers.
- `players/`: Player controller, movement, input mapping, carry/inventory.
- `stations/`: BaseStation and station-specific behavior (workbench, diagnostic, shelf, etc.).
- `ai/`: Customer spawning, pathing, and patience logic.
- `utils/`: Reusable math, helper functions, debug utilities.
