class_name SettingsMenu
extends Control
## Ayarlar paneli. Hem ana menüden hem oyun içi duraklatma menüsünden açılır.
## Değişiklikler anında uygulanır, kapatınca kaydedilir.

signal closed

var _first_focus: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	vb.add_child(UITheme.label("AYARLAR", 44, UITheme.TEXT, UITheme.title_font()))
	vb.add_child(UITheme.accent_line())

	_section(vb, "GÖRÜNTÜ")
	_first_focus = _check(vb, "Tam ekran", "fullscreen")
	_check(vb, "Dikey senkronizasyon (V-Sync)", "vsync")
	_option(vb, "Grafik kalitesi", "quality", Settings.QUALITY_NAMES)
	_slider(vb, "Çözünürlük ölçeği", "render_scale", 50, 100, 0.01, "%d%%")
	_option(vb, "Kare hızı sınırı", "fps_limit", Settings.FPS_NAMES)

	_section(vb, "SES")
	_slider(vb, "Ana ses", "master_volume", 0, 100, 0.01, "%d%%")
	_slider(vb, "Müzik", "music_volume", 0, 100, 0.01, "%d%%")
	_slider(vb, "Efektler ve ortam", "sfx_volume", 0, 100, 0.01, "%d%%")

	_section(vb, "OYNANIŞ")
	_check(vb, "Kan efektleri", "blood")
	_check(vb, "Kontrol ipuçlarını göster", "show_help")
	_slider(vb, "Kamera uzaklığı", "camera_zoom", 10, 34, 1.0, "%d")

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	vb.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	vb.add_child(buttons)
	var defaults := UITheme.menu_button("VARSAYILANLAR", 20)
	defaults.custom_minimum_size.x = 0
	defaults.pressed.connect(_on_defaults)
	buttons.add_child(defaults)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(fill)
	var back := UITheme.menu_button("GERİ", 20)
	back.custom_minimum_size.x = 0
	back.pressed.connect(close)
	buttons.add_child(back)

	if _first_focus:
		_first_focus.call_deferred("grab_focus")


func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_defaults() -> void:
	Settings.reset_defaults()
	for c in get_children():
		c.queue_free()
	call_deferred("_build")


# --- Satır oluşturucular ---

func _section(parent: Control, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	parent.add_child(spacer)
	parent.add_child(UITheme.label(text, 14, UITheme.ACCENT.lightened(0.25), UITheme.spaced_font()))


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UITheme.label(text, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _check(parent: Control, text: String, key: String) -> CheckButton:
	var row := _row(parent, text)
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get(key)
	cb.toggled.connect(_on_value.bind(key))
	row.add_child(cb)
	return cb


func _option(parent: Control, text: String, key: String, items: Array) -> OptionButton:
	var row := _row(parent, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 200
	for item in items:
		ob.add_item(item)
	ob.selected = Settings.get(key)
	ob.item_selected.connect(_on_value.bind(key))
	row.add_child(ob)
	return ob


func _slider(parent: Control, text: String, key: String, min_v: float, max_v: float, mult: float, fmt: String) -> HSlider:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 1
	s.custom_minimum_size = Vector2(200, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(Settings.get(key)) / mult
	var value_label := UITheme.label(fmt % s.value, 16, UITheme.TEXT_DIM)
	value_label.custom_minimum_size.x = 48
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(_on_slider.bind(key, mult, value_label, fmt))
	row.add_child(s)
	row.add_child(value_label)
	return s


func _on_value(value: Variant, key: String) -> void:
	Settings.set(key, value)
	Settings.apply()
	Audio.ui("ui_click", -6.0)


func _on_slider(value: float, key: String, mult: float, value_label: Label, fmt: String) -> void:
	value_label.text = fmt % value
	Settings.set(key, value * mult)
	Settings.apply()
