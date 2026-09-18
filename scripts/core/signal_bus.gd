extends Node

## Global decoupled event bus for Overclocked
## Nodes emit and connect through SignalBus to maintain clean separation.

# Game Lifecycle Signals
signal game_state_changed(old_state: GameState.State, new_state: GameState.State)
signal level_loaded(level_id: String)
signal level_restarted
signal game_paused(is_paused: bool)

# Player Signals
signal player_joined(player_id: int)
signal player_left(player_id: int)
signal player_spawned(player_index: int, player: Node)
signal player_device_assigned(player_index: int, device_id: int)
signal player_bumped(bumper_index: int, bumped_index: int)

# Workshop & Interaction Signals
signal station_interacted(station_name: String, player_id: int)
signal station_occupied(station_name: String, player_id: int)
signal station_released(station_name: String)
signal station_freed(station_name: String)
signal item_picked_up(item_name: String, player_id: int)
signal item_dropped(item_name: String, player_id: int)
signal item_claimed(item_name: String, player_id: int, contested: bool)
signal item_claim_contested(item_name: String, claiming_player: int, contesting_player: int)


# Orders & Repair Pipeline Signals
signal order_spawned(order_id: String, device_type: String)
signal order_completed(order_id: String, score: int, stars: int)
signal order_expired(order_id: String)
signal device_repaired(device_name: String)
signal device_state_changed(device_name: String, old_state: String, new_state: String)
signal diagnosis_revealed(device_name: String, fault_name: String)

# HUD Signals
signal interaction_prompt_changed(prompt_text: String)
signal carried_item_changed(item_name: String)

# Round Flow Signals
signal round_started
signal round_ended(total_score: int, total_stars: int)

# Hazard Signals (Phase 3)
signal hazard_activated(hazard_name: String, hazard_type: String)
signal hazard_cleared(hazard_name: String)
signal hazard_expired(hazard_name: String)

# Parts Stock Signals (Phase 3D)
signal part_dispensed(component_id: String, remaining_stock: int)
signal part_out_of_stock(component_id: String)
signal part_restocked(component_id: String, new_stock: int)
