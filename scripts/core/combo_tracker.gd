extends Node

## Tracks consecutive repair streaks and calculates combo multiplier.
## Multiplier decays if repairs are not chained within the combo window.

signal combo_changed(multiplier: float, streak: int)
signal combo_broken()

const COMBO_WINDOW: float = Constants.COMBO_WINDOW_SECONDS
const COMBO_TIERS: Array[float] = Constants.COMBO_TIERS

var _last_completion_time: float = -100.0
var _current_streak: int = 0


func _ready() -> void:
	if SignalBus:
		SignalBus.order_completed.connect(_on_order_completed)
		SignalBus.order_expired.connect(_on_order_expired)


func _process(_delta: float) -> void:
	if _current_streak > 0:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_completion_time > COMBO_WINDOW:
			reset_combo()


func on_repair_completed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _last_completion_time > 0.0 and (now - _last_completion_time <= COMBO_WINDOW):
		_current_streak = mini(_current_streak + 1, COMBO_TIERS.size() - 1)
	else:
		_current_streak = 1
	_last_completion_time = now
	var mult := get_multiplier()
	combo_changed.emit(mult, _current_streak)
	SignalBus.combo_updated.emit(mult, _current_streak)


func on_repair_failed() -> void:
	reset_combo()


func reset_combo() -> void:
	if _current_streak > 0:
		_current_streak = 0
		_last_completion_time = -100.0
		combo_broken.emit()
		SignalBus.combo_broken.emit()
		SignalBus.combo_updated.emit(1.0, 0)


func get_multiplier() -> float:
	var index := clampi(_current_streak, 0, COMBO_TIERS.size() - 1)
	return COMBO_TIERS[index]


func get_streak() -> int:
	return _current_streak


func get_time_remaining() -> float:
	if _current_streak <= 0:
		return 0.0
	var now: float = Time.get_ticks_msec() / 1000.0
	return maxf(0.0, COMBO_WINDOW - (now - _last_completion_time))


func _on_order_completed(_order_id: String, _score: int, _stars: int) -> void:
	on_repair_completed()


func _on_order_expired(_order_id: String) -> void:
	on_repair_failed()
