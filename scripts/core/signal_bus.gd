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
signal player_device_assigned(player_index: int, device_id: int)

# Workshop & Interaction Signals
signal station_interacted(station_name: String, player_id: int)
signal station_occupied(station_name: String, player_id: int)
signal station_released(station_name: String)
signal item_picked_up(item_name: String, player_id: int)
signal item_dropped(item_name: String, player_id: int)
signal item_claimed(item_name: String, player_id: int, contested: bool)

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
