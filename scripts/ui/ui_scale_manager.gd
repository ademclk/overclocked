extends Node

## Manages UI scale factor based on viewport resolution.
## Ensures all UI and text meets minimum readability standards across resolutions.

signal scale_factor_changed(new_factor: float)

var current_scale_factor: float = 1.0


func _ready() -> void:
	_update_scale()
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	_update_scale()


func _update_scale() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var vp_height: float = float(vp.get_visible_rect().size.y)
	if vp_height <= 0.0:
		vp_height = float(Constants.UI_SCALE_REFERENCE_HEIGHT)
	var new_factor: float = clampf(vp_height / float(Constants.UI_SCALE_REFERENCE_HEIGHT), 0.75, 2.5)
	if not is_equal_approx(new_factor, current_scale_factor):
		current_scale_factor = new_factor
		scale_factor_changed.emit(current_scale_factor)


func get_scaled_font_size(base_size: int) -> int:
	return maxi(Constants.WORLD_LABEL_MIN_FONT_SIZE, int(round(base_size * current_scale_factor)))
