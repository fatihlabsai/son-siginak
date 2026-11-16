class_name NoteView
extends Control
## Bulunan bir notu ya da belgeyi okuma ekranı. E / Esc / Enter ile kapanır.

signal closed

var title := ""
var body := ""
var footer := ""
var handwritten := true
var _paper: PanelContainer


func setup(p_title: String, p_body: String, p_footer := "", p_handwritten := true) -> NoteView:
	title = p_title
	body = p_body
	footer = p_footer
	handwritten = p_handwritten
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_paper = PanelContainer.new()
	_paper.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.9, 0.82) if handwritten else Color(0.96, 0.96, 0.94)
	sb.set_content_margin_all(42)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	_paper.add_theme_stylebox_override("panel", sb)
	center.add_child(_paper)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_paper.add_child(vb)
	var ink := Color(0.12, 0.16, 0.38) if handwritten else Color(0.12, 0.12, 0.12)
	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 26)
		t.add_theme_color_override("font_color", ink)
		if not handwritten:
			t.add_theme_font_override("font", UITheme.title_font())
		vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 476
	b.add_theme_font_size_override("font_size", 21 if handwritten else 18)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_constant_override("line_spacing", 6)
	vb.add_child(b)
	if footer != "":
		var f := Label.new()
		f.text = footer
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		f.add_theme_font_size_override("font_size", 21)
		f.add_theme_color_override("font_color", ink)
		vb.add_child(f)
	var hint := UITheme.label("E / Esc: kapat", 14, Color(1, 1, 1, 0.55))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -100
	hint.offset_right = 100
	hint.offset_top = -48
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	# Hafif eğik kâğıt, yumuşak beliriş
	_paper.pivot_offset = _paper.size * 0.5
	_paper.rotation = deg_to_rad(-1.5 if handwritten else 0.6)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()
