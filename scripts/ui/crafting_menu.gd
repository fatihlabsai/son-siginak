class_name CraftingMenu
extends Control
## Üretim ekranı (C). Oyun durmaz; açıkken karakter yürümez ve saldırmaz.
## Her tarif: ikon, ad, açıklama, gereken malzemeler (elindeki/gereken) ve ÜRET düğmesi.

signal closed

var _player: Player
var _list: VBoxContainer
var _camp_label: Label
var _close_btn: Button


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	_build()
	if _player:
		_player.inv.changed.connect(_refresh)
	_refresh()
	_close_btn.call_deferred("grab_focus")


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("craft") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 580)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tb)
	tb.add_child(UITheme.label("ÜRETİM", 42, UITheme.TEXT, UITheme.title_font()))
	tb.add_child(UITheme.accent_line())
	_camp_label = UITheme.label("", 15, UITheme.TEXT_DIM)
	_camp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(_camp_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	var hint := UITheme.label("Malzemeleri evlerden, arabalardan ve çöplerden topla.    C: kapat", 14, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	_close_btn = _small_button("KAPAT", close)
	bottom.add_child(_close_btn)


func _refresh() -> void:
	if not is_instance_valid(_player):
		return
	var at_camp := Crafting.near_camp(_player)
	_camp_label.text = "Kamp ateşinin yanındasın" if at_camp else "Kampta değilsin (bazı tarifler kapalı)"
	_camp_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.55) if at_camp else UITheme.TEXT_DIM)
	for c in _list.get_children():
		c.queue_free()
	for r in Crafting.RECIPES:
		_list.add_child(_recipe_row(r))


func _recipe_row(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var icon_id: String = r.gives if r.gives != "repair" else "scrap"
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_icon.bind(icon, icon_id))
	row.add_child(icon)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	var title: String = r.name + ("   · kampta" if r.camp else "")
	mid.add_child(UITheme.label(title, 19, Color.WHITE))
	var desc := UITheme.label(r.desc, 13, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(desc)
	var needs := HBoxContainer.new()
	needs.add_theme_constant_override("separation", 14)
	mid.add_child(needs)
	for id in r.needs:
		var h := Crafting.have(_player, id)
		var n := int(r.needs[id])
		var l := UITheme.label("%s %d/%d" % [Items.item_name(id), h, n], 14,
			Color(0.6, 0.85, 0.55) if h >= n else Color(0.95, 0.45, 0.4))
		needs.add_child(l)

	var reason := Crafting.blocker(_player, r)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 150
	row.add_child(right)
	if reason == "":
		right.add_child(_small_button("ÜRET", _on_craft.bind(r)))
	else:
		var l := UITheme.label(reason, 12, UITheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(l)
	return card


func _on_craft(r: Dictionary) -> void:
	if Crafting.craft(_player, r):
		_player.message.emit("%s yapıldı." % r.name if r.gives != "repair" else "Silah onarıldı.")
	_refresh()


func _draw_icon(icon: Control, icon_id: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(3)
	icon.draw_style_box(sb, Rect2(Vector2.ZERO, icon.size))
	var col: Color = HudIcons.COLORS.get(icon_id, Color.WHITE)
	HudIcons.draw(icon, icon_id, icon.size * 0.5, 38, col)


func _small_button(text: String, cb: Callable) -> Button:
	var b := UITheme.menu_button(text, 16)
	b.custom_minimum_size = Vector2(0, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b
