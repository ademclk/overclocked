extends Node

## Global decoupled event bus for Overclocked
## Nodes emit and connect through SignalBus to maintain clean separation.

# Game Lifecycle Signals
signal game_state_changed(old_state: GameState.State, new_state: GameState.State)
signal level_loaded(level_id: String)
signal level_restarted()
signal game_paused(is_paused: bool)

# Player Signals
signal player_joined(player_id: int)
signal player_left(player_id: int)

# Workshop & Interaction Signals
signal station_interacted(station_name: String, player_id: int)
signal item_picked_up(item_name: String, player_id: int)
signal item_dropped(item_name: String, player_id: int)

# Orders & Repair Pipeline Signals
signal order_spawned(order_id: String, device_type: String)
signal order_completed(order_id: String, score: int, stars: int)
signal order_expired(order_id: String)
signal device_repaired(device_name: String)
