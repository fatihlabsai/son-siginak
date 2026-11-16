class_name MapView
extends Control
## Harita: köşedeki mini harita (oyuncu ortada) ya da M ile açılan tam harita.
## Ekranla aynı yöne döndürülür (izometrik kamera 45°): ekranda "yukarı" haritada da yukarı.

var full := false
var radius := 34.0   # mini haritada görünen yarıçap (m)

const BG := Color(0.12, 0.15, 0.11, 0.88)
const ROAD := Color(0.36, 0.36, 0.34)
const BUILDING := Color(0.55, 0.5, 0.42)
const YARD := Color(0.42, 0.42, 0.4)
const CAMP := Color(0.85, 0.55, 0.2)

var _r := Vector2(0.7071, -0.7071)   # dünya (x, z) -> ekran sağı
var _f := Vector2(-0.7071, -0.7071)  # dünya (x, z) -> ekran yukarısı
var _center := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _to_screen(w: Vector2) -> Vector2:
	var d := w - _center
	return size * 0.5 + Vector2(d.dot(_r), -d.dot(_f)) * _scale


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_to_screen(r.position), _to_screen(Vector2(r.end.x, r.position.y)),
		_to_screen(r.end), _to_screen(Vector2(r.position.x, r.end.y))])


func _draw() -> void:
	var lv := Game.level
	var p := Game.player
	if not is_instance_valid(lv) or not is_instance_valid(p):
		return
	var hs := lv.map_half_size
	var pp := Vector2(p.global_position.x, p.global_position.z)
	if full:
		_center = Vector2.ZERO
		_scale = minf(size.x, size.y) / (hs * 2.0 * 1.42)
	else:
		_center = pp
		_scale = minf(size.x, size.y) * 0.5 / radius
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_colored_polygon(_rect_poly(Rect2(-hs, -hs, hs * 2, hs * 2)), Color(0.2, 0.26, 0.17))
	# Yollar
	draw_colored_polygon(_rect_poly(Rect2(-4, -hs, 8, hs * 2)), ROAD)
	draw_colored_polygon(_rect_poly(Rect2(-hs, -4, hs * 2, 8)), ROAD)
	# Bakım sahası ve binalar
	if lv.has_method("yard_rect"):
		draw_colored_polygon(_rect_poly(lv.yard_rect()), YARD)
	for r in lv.map_buildings:
		var rr: Rect2 = r
		draw_colored_polygon(_rect_poly(rr), BUILDING)
		draw_polyline(_closed(_rect_poly(rr)), BUILDING.darkened(0.4), 1.0)
	# Sığınak
	var sc := lv.shelter_center
	draw_colored_polygon(_rect_poly(Rect2(sc.x - 2.8, sc.z - 2.35, 5.6, 4.7)), Color(0.3, 0.32, 0.3))
	# Kamp: barikat çemberi + ateş
	var cp := _to_screen(Vector2.ZERO)
	draw_polyline(_closed(_rect_poly(Rect2(-9, -9, 18, 18))), CAMP.darkened(0.2), 2.0)
	var cf := lv.campfire_position()
	draw_circle(_to_screen(Vector2(cf.x, cf.z)), maxf(3.0, 1.2 * _scale), CAMP)
	# Oyuncunun kurduğu barikatlar
	for b in get_tree().get_nodes_in_group("barricades"):
		var bp := (b as Node3D).global_position
		draw_circle(_to_screen(Vector2(bp.x, bp.z)), maxf(2.0, 0.6 * _scale), Color(0.75, 0.6, 0.4))
	# Zombiler (mini haritada yakındakiler, tam haritada sadece 40 m içindekiler)
	for z in get_tree().get_nodes_in_group("zombies"):
		var zp := (z as Node3D).global_position
		var zv := Vector2(zp.x, zp.z)
		if zv.distance_to(pp) > 40.0:
			continue
		draw_circle(_to_screen(zv), 3.0 if not full else 2.5, Color(0.85, 0.15, 0.12))
	# Hikâye hedefi (mini haritada kenara sabitlenir)
	var hud := get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("story_target"):
		var tg: Vector3 = hud.story_target()
		if tg != Vector3.INF:
			var tp := _to_screen(Vector2(tg.x, tg.z))
			var r := Rect2(Vector2(10, 10), size - Vector2(20, 20))
			if not full and not r.has_point(tp):
				var c := size * 0.5
				var d := tp - c
				var k := minf(absf((size.x * 0.5 - 10) / maxf(absf(d.x), 0.01)), absf((size.y * 0.5 - 10) / maxf(absf(d.y), 0.01)))
				tp = c + d * k
			var pulse := 1.0 + 0.2 * sin(Time.get_ticks_msec() / 200.0)
			draw_circle(tp, 7.0 * pulse, Color(1.0, 0.85, 0.2, 0.35))
			_star(tp, 6.0, Color(1.0, 0.85, 0.2))
	# Oyuncu oku
	var face := p.get_facing()
	var fd := Vector2(face.x, face.z)
	var dir := Vector2(fd.dot(_r), -fd.dot(_f)).normalized()
	var o := _to_screen(pp)
	var s := 8.0 if not full else 9.0
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([o + dir * s, o - dir * s * 0.6 + side * s * 0.6, o - dir * s * 0.3, o - dir * s * 0.6 - side * s * 0.6]), Color.WHITE)
	if full:
		_label(cp + Vector2(10, -10), "KAMP")
		_label(_to_screen(Vector2(sc.x, sc.z)) + Vector2(10, -10), "SIĞINAK")
		if lv.house_center != Vector3.INF:
			_label(_to_screen(Vector2(lv.house_center.x, lv.house_center.z)) + Vector2(10, -10), "EV")
		if lv.school_center != Vector3.INF:
			_label(_to_screen(Vector2(lv.school_center.x, lv.school_center.z)) + Vector2(10, -10), "LİSE")
	# Çerçeve
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.18), false, 1.5)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out


func _label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85))
