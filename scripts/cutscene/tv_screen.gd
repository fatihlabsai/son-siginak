class_name TvScreen
extends SubViewport
## Yerel kanalın hava durumu yayını: harita, sıcaklıklar ve alttan akan haber bandı.

const TICKER := "BREAKING  •  County officials ask drivers to avoid the North River crossing until further notice  •  Winds NW 10-15 mph  •  More at 6  •  "

var _ticker: Label
var _clock: Label
var _t := 0.0


func _ready() -> void:
	size = Vector2i(640, 360)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transparent_bg = false
	var root := Control.new()
	root.size = Vector2(640, 360)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.2, 0.42)
	bg.size = Vector2(640, 360)
	root.add_child(bg)
	var map := _Map.new()
	map.position = Vector2(30, 70)
	map.size = Vector2(380, 220)
	root.add_child(map)
	var title := _lbl("LOCAL WEATHER", 26, Color.WHITE)
	title.position = Vector2(30, 18)
	root.add_child(title)
	var ch := _lbl("CHANNEL 7", 18, Color(1, 0.85, 0.3))
	ch.position = Vector2(520, 22)
	root.add_child(ch)
	var temps := [["TODAY", "68°"], ["TONIGHT", "42°"], ["TOMORROW", "65°"]]
	for i in temps.size():
		var box := ColorRect.new()
		box.color = Color(0.05, 0.1, 0.25, 0.85)
		box.position = Vector2(440, 75 + i * 72)
		box.size = Vector2(170, 62)
		root.add_child(box)
		var a := _lbl(temps[i][0], 16, Color(0.75, 0.85, 1.0))
		a.position = box.position + Vector2(12, 8)
		root.add_child(a)
		var b := _lbl(temps[i][1], 34, Color.WHITE)
		b.position = box.position + Vector2(100, 6)
		root.add_child(b)
	var band := ColorRect.new()
	band.color = Color(0.7, 0.08, 0.06)
	band.position = Vector2(0, 312)
	band.size = Vector2(640, 48)
	root.add_child(band)
	_ticker = _lbl(TICKER + TICKER, 22, Color.WHITE)
	_ticker.position = Vector2(640, 322)
	root.add_child(_ticker)
	_clock = _lbl("2:32 PM", 18, Color.WHITE)
	_clock.position = Vector2(530, 285)
	root.add_child(_clock)


func _lbl(t: String, s: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", c)
	var f := UITheme.title_font() if s >= 26 else null
	if f:
		l.add_theme_font_override("font", f)
	return l


func _process(delta: float) -> void:
	_t += delta
	_ticker.position.x -= 90.0 * delta
	if _ticker.position.x < -_ticker.size.x * 0.5:
		_ticker.position.x += _ticker.size.x * 0.5


class _Map extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.3, 0.2))
		var land := PackedVector2Array([Vector2(20, 30), Vector2(160, 10), Vector2(300, 40), Vector2(360, 120),
			Vector2(330, 200), Vector2(180, 210), Vector2(60, 190), Vector2(10, 110)])
		draw_colored_polygon(land, Color(0.3, 0.5, 0.28))
		# Nehir
		var river := PackedVector2Array([Vector2(0, 70), Vector2(80, 80), Vector2(150, 60), Vector2(230, 85), Vector2(380, 70)])
		draw_polyline(river, Color(0.35, 0.6, 0.95), 6.0)
		# Kuzey köprüsü işareti
		draw_circle(Vector2(150, 62), 9, Color(0.95, 0.2, 0.15))
		draw_line(Vector2(144, 56), Vector2(156, 68), Color.WHITE, 3)
		draw_line(Vector2(156, 56), Vector2(144, 68), Color.WHITE, 3)
		# Güneş ve bulut simgeleri
		draw_circle(Vector2(250, 140), 18, Color(1, 0.85, 0.2))
		draw_circle(Vector2(100, 150), 14, Color(0.95, 0.95, 0.95))
		draw_circle(Vector2(118, 145), 18, Color(0.95, 0.95, 0.95))
		draw_circle(Vector2(136, 152), 13, Color(0.95, 0.95, 0.95))
