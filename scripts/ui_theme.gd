class_name UITheme
extends RefCounted
## Menülerin ve HUD'un ortak görünümü: koyu paneller, kan kırmızısı vurgu, sade yazılar.

const ACCENT := Color(0.72, 0.1, 0.08)
const TEXT := Color(0.9, 0.87, 0.82)
const TEXT_DIM := Color(0.62, 0.6, 0.56)

static var _theme: Theme
static var _title_font: Font
static var _spaced_font: Font


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	t.default_font = font
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)

	# Butonlar: normalde sade yazı, üzerine gelince solda kırmızı çizgi + koyu kırmızı zemin
	var normal := _box(Color(0, 0, 0, 0))
	var hover := _box(Color(ACCENT, 0.22))
	hover.border_width_left = 4
	hover.border_color = ACCENT
	var pressed := _box(Color(ACCENT, 0.4))
	pressed.border_width_left = 4
	pressed.border_color = ACCENT
	# Açma/kapama düğmeleri: kutu yok, odaktayken altında ince kırmızı çizgi
	var cb_focus := _box(Color(0, 0, 0, 0))
	cb_focus.border_width_bottom = 2
	cb_focus.border_color = ACCENT
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", normal)
	t.set_stylebox("focus", "CheckButton", cb_focus)

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, hover)
		t.set_stylebox("disabled", type, normal)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(0.4, 0.4, 0.4))

	# OptionButton açılır listesi
	var popup := _box(Color(0.07, 0.07, 0.08, 0.98))
	popup.border_color = Color(1, 1, 1, 0.1)
	popup.set_border_width_all(1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.35)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# Paneller
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.045, 0.045, 0.05, 0.94)
	panel.border_color = Color(1, 1, 1, 0.07)
	panel.set_border_width_all(1)
	panel.border_width_top = 3
	panel.border_color = Color(1, 1, 1, 0.07)
	panel.set_corner_radius_all(2)
	panel.set_content_margin_all(28)
	t.set_stylebox("panel", "PanelContainer", panel)

	# Kaydırıcılar
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	_theme = t
	return t


## Başlıklar için kalın, sıkışık yazı tipi (Windows'ta Impact).
static func title_font() -> Font:
	if _title_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Impact", "Bahnschrift", "Arial Black"])
		_title_font = f
	return _title_font


## Harf aralığı açılmış küçük başlık yazısı.
static func spaced_font() -> Font:
	if _spaced_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = 5
		_spaced_font = fv
	return _spaced_font


static func clear() -> void:
	_theme = null
	_title_font = null
	_spaced_font = null


static func _box(color: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


## Ortak yardımcılar
static func label(text: String, size := 18, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func menu_button(text: String, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(320, 0)
	b.focus_mode = Control.FOCUS_ALL
	# Fare üzerine gelince klavye odağını da oraya taşı (tek vurgu görünsün)
	b.mouse_entered.connect(b.grab_focus)
	# Odaklanınca yazı hafifçe sağa kayar
	var t := get_theme()
	var boxes: Array[StyleBoxFlat] = []
	for state in ["normal", "focus", "hover", "pressed", "hover_pressed"]:
		var sb := (t.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		b.add_theme_stylebox_override(state, sb)
		boxes.append(sb)
	b.focus_entered.connect(_slide.bind(b, boxes, 34.0))
	b.focus_exited.connect(_slide.bind(b, boxes, 18.0))
	b.focus_entered.connect(Audio.ui.bind("ui_hover", -12.0))
	b.pressed.connect(Audio.ui.bind("ui_click", -4.0))
	return b


static func _slide(b: Button, boxes: Array[StyleBoxFlat], to: float) -> void:
	if not b.is_inside_tree():
		return
	var tw := b.create_tween().set_parallel()
	for sb in boxes:
		tw.tween_property(sb, "content_margin_left", to, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func accent_line(width := 110.0, height := 4.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = ACCENT
	r.custom_minimum_size = Vector2(width, height)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
