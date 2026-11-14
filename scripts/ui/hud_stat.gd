class_name HudStat
extends Control
## İkonlu ince durum çubuğu. Hasar alınca beyaz "iz" yavaşça erir,
## kritik seviyede ikon ve çubuk nabız gibi atar.

var kind := "health"
var color := Color.RED
var value := 1.0
var critical := 0.25
var fade_when_full := false

var _ghost := 1.0
var _t := 0.0


func _init(p_kind: String, p_critical := 0.25) -> void:
	kind = p_kind
	color = HudIcons.COLORS[p_kind]
	critical = p_critical
	custom_minimum_size = Vector2(270, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	if value > _ghost:
		_ghost = value


func _process(delta: float) -> void:
	_t += delta
	_ghost = move_toward(_ghost, value, delta * 0.3)
	if fade_when_full:
		var target := 0.25 if value >= 0.999 else 1.0
		modulate.a = move_toward(modulate.a, target, delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var crit := value <= critical
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var icol := color.lerp(Color.WHITE, 0.45 * pulse) if crit else color
	HudIcons.draw(self, kind, Vector2(12, size.y * 0.5), 20, icol)

	var x0 := 32.0
	var w := size.x - x0
	var h := 8.0
	var y := size.y * 0.5 - h * 0.5
	draw_rect(Rect2(x0 - 1, y - 1, w + 2, h + 2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x0, y, w, h), Color(1, 1, 1, 0.06))
	if _ghost > value:
		draw_rect(Rect2(x0 + w * value, y, w * (_ghost - value), h), Color(1, 1, 1, 0.5))
	var fill := color.lerp(Color(1, 0.25, 0.2), 0.6 * pulse) if crit else color
	draw_rect(Rect2(x0, y, w * value, h), fill)
	draw_rect(Rect2(x0, y, w * value, 2), Color(1, 1, 1, 0.2))
	for i in range(1, 4):
		var x := x0 + w * i / 4.0
		draw_line(Vector2(x, y), Vector2(x, y + h), Color(0, 0, 0, 0.55), 1.0)
