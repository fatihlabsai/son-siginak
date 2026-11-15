class_name CutsceneUI
extends CanvasLayer
## Ara sahne katmanı: sinema şeritleri, alt yazı, ortadaki büyük yazı, kararma
## ve "geçmek için tekrar bas" ipucu. Esc / Space / Enter iki kez basılınca skip_requested.

signal skip_requested

const BAR_H := 0.11   # ekran yüksekliğinin oranı

var _top: ColorRect
var _bottom: ColorRect
var _sub_box: VBoxContainer
var _sub_name: Label
var _sub_text: Label
var _caption: Label
var _fade: ColorRect
var _skip_hint: Label
var _skip_armed := 0.0
var _sub_token := 0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	_top = _bar(root, true)
	_bottom = _bar(root, false)

	_sub_box = VBoxContainer.new()
	_sub_box.alignment = BoxContainer.ALIGNMENT_END
	_sub_box.anchor_left = 0.1
	_sub_box.anchor_right = 0.9
	_sub_box.anchor_top = 1.0
	_sub_box.anchor_bottom = 1.0
	_sub_box.offset_top = -190
	_sub_box.offset_bottom = -26
	_sub_box.add_theme_constant_override("separation", 2)
	_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sub_box)
	_sub_name = UITheme.label("", 15, UITheme.ACCENT.lightened(0.35), UITheme.spaced_font())
	_sub_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_box.add_child(_sub_name)
	_sub_text = UITheme.label("", 26, Color(0.97, 0.95, 0.9))
	_sub_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub_text.add_theme_constant_override("shadow_offset_x", 2)
	_sub_text.add_theme_constant_override("shadow_offset_y", 2)
	_sub_box.add_child(_sub_text)
	_sub_box.modulate.a = 0.0

	_caption = UITheme.label("", 44, UITheme.TEXT, UITheme.title_font())
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	root.add_child(_caption)   # kararmanın üstünde

	_skip_hint = UITheme.label("Geçmek için tekrar bas", 14, Color(1, 1, 1, 0.55))
	_skip_hint.anchor_left = 1.0
	_skip_hint.anchor_right = 1.0
	_skip_hint.offset_left = -300
	_skip_hint.offset_right = -30
	_skip_hint.offset_top = 22
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.modulate.a = 0.0
	root.add_child(_skip_hint)


func _bar(root: Control, top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = 1.0
	if top:
		r.anchor_bottom = 0.0
	else:
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
	root.add_child(r)
	return r


func _process(delta: float) -> void:
	_skip_armed = maxf(_skip_armed - delta, 0.0)
	_skip_hint.modulate.a = minf(_skip_armed * 2.0, 1.0)
	var h := get_viewport().get_visible_rect().size.y * BAR_H * _bars
	_top.offset_bottom = h
	_bottom.offset_top = -h


var _bars := 0.0

func bars(on: bool, dur := 1.0) -> void:
	create_tween().tween_property(self, "_bars", 1.0 if on else 0.0, dur).set_trans(Tween.TRANS_SINE)


func fade_to(alpha: float, dur := 1.0) -> Tween:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, dur)
	return tw


func set_black(alpha: float) -> void:
	_fade.color.a = alpha


## Alt yazı: konuşan adı + metin. dur sonra kendiliğinden kaybolur.
func subtitle(speaker: String, text: String, dur: float) -> void:
	_sub_token += 1
	var token := _sub_token
	_sub_name.text = speaker.to_upper()
	_sub_name.visible = speaker != ""
	_sub_text.text = text
	create_tween().tween_property(_sub_box, "modulate:a", 1.0, 0.15)
	await get_tree().create_timer(dur, true).timeout
	if token == _sub_token:
		create_tween().tween_property(_sub_box, "modulate:a", 0.0, 0.25)


func clear_subtitle() -> void:
	_sub_token += 1
	_sub_box.modulate.a = 0.0


## Ortada büyük yazı (örn. "Altı gün sonra").
func caption(text: String, dur: float) -> void:
	_caption.text = text
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.8)
	tw.tween_interval(maxf(dur - 1.6, 0.1))
	tw.tween_property(_caption, "modulate:a", 0.0, 0.8)
	await tw.finished


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if _skip_armed > 0.0:
			_skip_armed = 0.0
			skip_requested.emit()
		else:
			_skip_armed = 2.5
