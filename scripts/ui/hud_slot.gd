class_name HudSlot
extends Control
## Envanter kutucuğu: tuş numarası, ikon, adet. Adet değişince kısa parlama.

var kind := "food"
var key_text := "1"
var count := 0

var _flash := 0.0
var _box: StyleBoxFlat
var _first := true


func _init(p_kind: String, p_key: String) -> void:
	kind = p_kind
	key_text = p_key
	custom_minimum_size = Vector2(66, 66)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.04, 0.04, 0.05, 0.75)
	_box.set_border_width_all(1)
	_box.set_corner_radius_all(3)


func set_count(n: int) -> void:
	if n != count and not _first:
		_flash = 1.0
	_first = false
	count = n


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.2, 0.0)
	queue_redraw()


func _draw() -> void:
	var has := count > 0
	_box.border_color = Color(1, 1, 1, 0.12).lerp(UITheme.ACCENT.lightened(0.3), _flash)
	_box.bg_color = Color(0.04, 0.04, 0.05, 0.75).lerp(Color(UITheme.ACCENT, 0.5), _flash * 0.6)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var a := 1.0 if has else 0.28
	var col: Color = HudIcons.COLORS[kind]
	HudIcons.draw(self, kind, size * 0.5 + Vector2(0, -1), 30, Color(col, a))
	var font := get_theme_font("font", "Label")
	draw_string(font, Vector2(6, 16), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(0, size.y - 6), "%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 7, 16, Color(1, 1, 1, 0.95 if has else 0.35))
