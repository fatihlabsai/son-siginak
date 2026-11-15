class_name PhoneScreen
extends SubViewport
## Telefon ekranı: kapalı / gelen arama ("Caleb") / hoparlörde konuşma / arama bitti.

var _state := "off"
var _root: Control
var _bg: ColorRect
var _name: Label
var _sub: Label
var _timer: Label
var _btns: Control
var _t := 0.0


func _ready() -> void:
	size = Vector2i(200, 426)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_root = Control.new()
	_root.size = Vector2(200, 426)
	add_child(_root)
	_bg = ColorRect.new()
	_bg.size = Vector2(200, 426)
	_bg.color = Color(0.02, 0.02, 0.03)
	_root.add_child(_bg)
	_sub = _lbl("", 15, Color(0.75, 0.78, 0.85), 70)
	_name = _lbl("", 34, Color.WHITE, 92)
	_timer = _lbl("", 16, Color(0.75, 0.78, 0.85), 140)
	_btns = _Buttons.new()
	_btns.size = Vector2(200, 426)
	_root.add_child(_btns)
	set_state("off")


func _lbl(t: String, s: int, c: Color, y: float) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(200, 40)
	_root.add_child(l)
	return l


func set_state(s: String) -> void:
	_state = s
	_t = 0.0
	match s:
		"off":
			_bg.color = Color(0.02, 0.02, 0.03)
			_name.text = ""
			_sub.text = ""
			_timer.text = ""
			_btns.set("mode", 0)
		"incoming":
			_bg.color = Color(0.1, 0.13, 0.2)
			_name.text = "Caleb"
			_sub.text = "incoming call"
			_timer.text = ""
			_btns.set("mode", 1)
		"speaker":
			_bg.color = Color(0.08, 0.1, 0.14)
			_name.text = "Caleb"
			_sub.text = "speaker"
			_btns.set("mode", 2)
		"ended":
			_bg.color = Color(0.08, 0.08, 0.1)
			_sub.text = "call ended"
			_btns.set("mode", 0)
	_btns.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _state == "speaker":
		_timer.text = "%02d:%02d" % [int(_t) / 60, int(_t) % 60]
	if _state == "incoming":
		_btns.set("pulse", 0.5 + 0.5 * sin(_t * 6.0))
		_btns.queue_redraw()


class _Buttons extends Control:
	var mode := 0
	var pulse := 0.0
	func _draw() -> void:
		if mode == 1:
			draw_circle(Vector2(55, 360), 24 + pulse * 4, Color(0.85, 0.2, 0.2))
			draw_circle(Vector2(145, 360), 24 + pulse * 4, Color(0.2, 0.75, 0.3))
		elif mode == 2:
			for i in 3:
				for j in 2:
					draw_circle(Vector2(50 + i * 50, 250 + j * 60), 19, Color(1, 1, 1, 0.15 if not (i == 1 and j == 0) else 0.8))
			draw_circle(Vector2(100, 370), 24, Color(0.85, 0.2, 0.2))
