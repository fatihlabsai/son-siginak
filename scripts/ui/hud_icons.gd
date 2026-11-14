class_name HudIcons
extends RefCounted
## Arayüz ikonları kodla çiziliyor (ikon dosyası gerekmiyor).
## c: merkez, s: boyut (px), col: renk.

const COLORS := {
	"health": Color(0.85, 0.16, 0.14),
	"stamina": Color(0.95, 0.78, 0.25),
	"hunger": Color(0.85, 0.5, 0.2),
	"thirst": Color(0.3, 0.62, 0.95),
	"food": Color(0.85, 0.5, 0.2),
	"water": Color(0.3, 0.62, 0.95),
	"medkit": Color(0.92, 0.92, 0.9),
	"ammo": Color(0.9, 0.75, 0.35),
	"pistol_ammo": Color(0.9, 0.75, 0.35),
	"shells": Color(0.9, 0.9, 0.9),
	"knife": Color(0.85, 0.87, 0.9),
	"bat": Color(0.85, 0.75, 0.6),
	"axe": Color(0.85, 0.85, 0.85),
	"pistol": Color(0.8, 0.82, 0.85),
	"shotgun": Color(0.75, 0.77, 0.8),
	"fists": Color(0.85, 0.7, 0.6),
	"wood": Color(0.9, 0.9, 0.9),
	"nails": Color(0.75, 0.77, 0.8),
	"scrap": Color(0.9, 0.9, 0.9),
}


static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color, shadow := true) -> void:
	if shadow:
		_draw_shape(ci, kind, c + Vector2(1.5, 1.5), s, Color(0, 0, 0, 0.55 * col.a))
	_draw_shape(ci, kind, c, s, col)


static func _draw_shape(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	match kind:
		"health":
			var r := s * 0.25
			ci.draw_circle(c + Vector2(-r * 0.95, -r * 0.45), r, col)
			ci.draw_circle(c + Vector2(r * 0.95, -r * 0.45), r, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 1.93, -r * 0.25), c + Vector2(r * 1.93, -r * 0.25), c + Vector2(0, s * 0.44)]), col)
		"stamina":
			ci.draw_colored_polygon(_pts(c, s, [
				Vector2(0.12, -0.5), Vector2(-0.3, 0.06), Vector2(-0.02, 0.06),
				Vector2(-0.14, 0.5), Vector2(0.3, -0.1), Vector2(0.03, -0.1)]), col)
		"hunger", "food":
			# Konserve kutusu
			ci.draw_rect(Rect2(c + Vector2(-0.27, -0.3) * s, Vector2(0.54, 0.72) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.27, -0.06) * s, Vector2(0.54, 0.22) * s), col.darkened(0.45))
			ci.draw_rect(Rect2(c + Vector2(-0.3, -0.38) * s, Vector2(0.6, 0.1) * s), col.lightened(0.25))
		"thirst", "water":
			ci.draw_circle(c + Vector2(0, 0.14) * s, s * 0.3, col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, -0.5), Vector2(-0.27, 0.04), Vector2(0.27, 0.04)]), col)
		"medkit":
			ci.draw_rect(Rect2(c + Vector2(-0.42, -0.3) * s, Vector2(0.84, 0.66) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.14, -0.44) * s, Vector2(0.28, 0.16) * s), col.darkened(0.3))
			var red := Color(0.8, 0.12, 0.1, col.a)
			ci.draw_rect(Rect2(c + Vector2(-0.07, -0.2) * s, Vector2(0.14, 0.46) * s), red)
			ci.draw_rect(Rect2(c + Vector2(-0.23, -0.04) * s, Vector2(0.46, 0.14) * s), red)
		"ammo":
			for i in 3:
				var o := c + Vector2((i - 1) * 0.3, 0.05) * s
				ci.draw_rect(Rect2(o + Vector2(-0.1, -0.12) * s, Vector2(0.2, 0.5) * s), col.darkened(0.15))
				ci.draw_colored_polygon(_pts(o, s, [Vector2(-0.1, -0.12), Vector2(0.1, -0.12), Vector2(0, -0.42)]), col)
		"knife", "bat", "axe", "pistol", "shotgun", "fists", "wood", "nails", "scrap", "shells", "pistol_ammo":
			_draw_item(ci, kind, c, s, col)
		"sun":
			ci.draw_circle(c, s * 0.22, col)
			for i in 8:
				var d := Vector2.RIGHT.rotated(i * TAU / 8.0)
				ci.draw_line(c + d * s * 0.32, c + d * s * 0.47, col, maxf(1.5, s * 0.07))
		"moon":
			var pts := PackedVector2Array()
			var r := s * 0.42
			for i in 25:
				var a := lerpf(deg_to_rad(60), deg_to_rad(300), i / 24.0)
				pts.append(c + Vector2.RIGHT.rotated(a) * r)
			var c2 := c + Vector2(r * 0.45, 0)
			var r2 := r * 0.8
			for i in 25:
				var a := lerpf(deg_to_rad(240), deg_to_rad(120), i / 24.0)
				pts.append(c2 + Vector2.RIGHT.rotated(a) * r2)
			ci.draw_colored_polygon(pts, col)


## Silah ve malzeme ikonları: birim karede (-0.5..0.5) çizilir, sonra döndürülüp ölçeklenir.
static func _draw_item(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var rot := 0.0
	if kind in ["knife", "bat", "axe"]:
		rot = -PI / 4.0
	ci.draw_set_transform(c, rot, Vector2(s, s))
	var dark := Color(col.darkened(0.55), col.a)
	match kind:
		"knife":
			ci.draw_rect(Rect2(-0.48, -0.065, 0.36, 0.13), dark)
			ci.draw_rect(Rect2(-0.13, -0.11, 0.05, 0.22), col.darkened(0.2))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.08, -0.07), Vector2(0.4, -0.05), Vector2(0.5, 0.03), Vector2(-0.08, 0.07)]), col)
		"bat":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.5, -0.04), Vector2(0.05, -0.065), Vector2(0.5, -0.1),
				Vector2(0.5, 0.1), Vector2(0.05, 0.065), Vector2(-0.5, 0.04)]), Color(0.75, 0.55, 0.32, col.a))
			ci.draw_rect(Rect2(-0.5, -0.045, 0.2, 0.09), dark)
		"axe":
			ci.draw_rect(Rect2(-0.5, -0.035, 0.95, 0.07), Color(0.6, 0.42, 0.25, col.a))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(0.24, -0.04), Vector2(0.42, -0.04), Vector2(0.5, -0.3), Vector2(0.18, -0.26)]), Color(0.8, 0.15, 0.12, col.a))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(0.27, 0.04), Vector2(0.39, 0.04), Vector2(0.33, 0.18)]), Color(0.6, 0.6, 0.6, col.a))
		"pistol":
			ci.draw_rect(Rect2(-0.42, -0.22, 0.86, 0.17), col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.34, -0.05), Vector2(-0.1, -0.05), Vector2(-0.02, 0.36), Vector2(-0.26, 0.38)]), dark)
			ci.draw_arc(Vector2(0.04, 0.0), 0.08, 0.0, PI, 8, dark, 0.03)
		"shotgun":
			ci.draw_rect(Rect2(-0.1, -0.08, 0.6, 0.06), col)
			ci.draw_rect(Rect2(0.1, -0.02, 0.26, 0.06), Color(0.55, 0.38, 0.22, col.a))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.5, 0.02), Vector2(-0.1, -0.08), Vector2(-0.1, 0.04), Vector2(-0.5, 0.15)]), Color(0.55, 0.38, 0.22, col.a))
		"fists":
			ci.draw_circle(Vector2(0, 0.06), 0.26, col)
			for i in 4:
				ci.draw_rect(Rect2(-0.25 + i * 0.13, -0.32, 0.11, 0.2), col)
		"wood":
			ci.draw_rect(Rect2(-0.45, -0.22, 0.9, 0.16), Color(0.65, 0.47, 0.3, col.a))
			ci.draw_rect(Rect2(-0.4, 0.02, 0.85, 0.16), Color(0.55, 0.4, 0.25, col.a))
		"nails":
			for i in 4:
				var x := -0.3 + i * 0.2
				ci.draw_line(Vector2(x, -0.3), Vector2(x + 0.05, 0.32), col, 0.05)
				ci.draw_rect(Rect2(x - 0.06, -0.33, 0.12, 0.05), col)
		"scrap":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.4, -0.2), Vector2(0.3, -0.3), Vector2(0.45, 0.1), Vector2(0.0, 0.32), Vector2(-0.45, 0.15)]), Color(0.6, 0.62, 0.65, col.a))
		"shells":
			for i in 2:
				var x := -0.2 + i * 0.26
				ci.draw_rect(Rect2(x - 0.09, -0.32, 0.18, 0.46), Color(0.8, 0.15, 0.12, col.a))
				ci.draw_rect(Rect2(x - 0.1, 0.14, 0.2, 0.14), Color(0.85, 0.7, 0.3, col.a))
		"pistol_ammo":
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_shape(ci, "ammo", c, s, col)
			return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _pts(c: Vector2, s: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(c + (p as Vector2) * s)
	return out
