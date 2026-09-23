extends Node

func _ready() -> void:
	print("--- STARTING HAZARD RESOLUTION TEST ---")
	var panel_scene = load("res://scenes/ui/HazardResolutionPanel.tscn")
	var panel: HazardResolutionPanel = panel_scene.instantiate() as HazardResolutionPanel
	add_child(panel)
	
	var player_scene = load("res://scenes/characters/PlayerCharacter.tscn")
	var player: PlayerCharacter = player_scene.instantiate() as PlayerCharacter
	add_child(player)
	
	var hazard_scene = load("res://scenes/hazards/FloorSpillHazard.tscn")
	var hazard: FloorSpillHazard = hazard_scene.instantiate() as FloorSpillHazard
	hazard.spill_type = FloorSpillHazard.SpillType.SCREWS
	add_child(hazard)
	hazard.activate()
	
	panel.open_hazard_panel(player, hazard)
	print("Panel open: ", panel.is_open(), " Player locked: ", player.is_movement_locked())
	
	# Simulate all 5 screw steps via hotspots or _on_screw_gathered
	for i in range(5):
		panel._step_completed(i)
	
	print("After 5 steps, cleared_steps=", panel._cleared_steps, " total=", panel._total_steps)
	print("Player locked right after 5 steps: ", player.is_movement_locked())
	
	# Wait 1.0 second
	await get_tree().create_timer(1.0).timeout
	
	print("After 1.0s wait:")
	print("Panel open: ", panel.is_open(), " Player locked: ", player.is_movement_locked())
	
	get_tree().quit()
