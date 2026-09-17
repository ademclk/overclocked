# Scenes Directory

This directory contains Godot scene files (`.tscn`).

## Naming & Organization
- Use **PascalCase** for scene files (e.g. `PlayerCharacter.tscn`, `WorkbenchStation.tscn`).
- Scripts live in parallel under `res://scripts/` (e.g. `scripts/players/player_character.gd`).

## Folders
- `main/`: Game entry points (`Main.tscn`), orchestrators, camera rig.
- `workshop/`: Workshop level layouts (`Workshop_Debug.tscn`, chapter maps).
- `devices/`: Repairable electronic devices (`Phone.tscn`, `Laptop.tscn`).
- `components/`: Loose parts and items (`Screen.tscn`, `SSD.tscn`).
- `stations/`: Interactive workshop stations (`Workbench.tscn`, `DiagnosticBench.tscn`).
- `characters/`: Playable character scenes (`PlayerCharacter.tscn`).
- `customers/`: Customer NPC scenes.
- `ui/`: Menus, HUD, order board, score screens.
