# Resources Directory

This directory contains Godot custom Resource files (`.tres`).

## Conventions
- Use **snake_case** for resource files (e.g. `phone_battery_dead.tres`).
- Resources are instances of custom classes extending `Resource` (defined in `res://scripts/`).

## Folders
- `devices/`: `DeviceData` resource definitions (names, base stats, compatible parts).
- `faults/`: `FaultData` resource definitions (symptoms, required replacement parts, tools needed).
- `orders/`: `OrderData` templates (duration, payouts, difficulty curve).
- `themes/`: UI Theme resources (`.tres`) for fonts, button styles, colors.
