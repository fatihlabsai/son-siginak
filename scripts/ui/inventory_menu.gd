class_name InventoryMenu
extends Control
## Envanter ekranı (Tab). Oyun durmaz! Açıkken karakter yürümez ve saldırmaz.
## Sol: silahlar (kuşan / bırak), sağ: eşyalar (kullan / bırak), üstte taşıma yükü.

signal closed

var _player: Player
var _weight_label: Label
var _weight_bar: ProgressBar
var _weapons_box: VBoxContainer
var _items_box: VBoxContainer
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
	if event.is_action_pressed("inventory") or event.is_action_pressed("pad_menu") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
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
	panel.custom_minimum_size = Vector2(900, 560)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	vb.add_child(top)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	title_box.add_child(UITheme.label("ENVANTER", 42, UITheme.TEXT, UITheme.title_font()))
	title_box.add_child(UITheme.accent_line())
	var wbox := VBoxContainer.new()
	wbox.custom_minimum_size.x = 260
	top.add_child(wbox)
	_weight_label = UITheme.label("", 15, UITheme.TEXT_DIM)
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wbox.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(260, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.65, 0.45)
	_weight_bar.add_theme_stylebox_override("background", bg)
	_weight_bar.add_theme_stylebox_override("fill", fill)
	wbox.add_child(_weight_bar)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	_weapons_box = _column(cols, "SİLAHLAR")
	_items_box = _column(cols, "EŞYALAR")

	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	var hint := UITheme.label("Q: silah değiştir    1/2/3: ye / iç / tedavi    Tab: kapat", 14, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	_close_btn = _small_button("KAPAT", close)
	bottom.add_child(_close_btn)


func _column(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	col.add_child(UITheme.label(title, 13, UITheme.ACCENT.lightened(0.25), UITheme.spaced_font()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func _refresh() -> void:
	if not is_instance_valid(_player):
		return
	var inv := _player.inv
	var w := inv.total_weight()
	_weight_label.text = "Yük: %.1f / %.0f kg" % [w, inv.max_weight]
	_weight_bar.max_value = inv.max_weight
	_weight_bar.value = w
	for c in _weapons_box.get_children():
		c.queue_free()
	for c in _items_box.get_children():
		c.queue_free()

	# Silahlar (yumruk her zaman var)
	_weapons_box.add_child(_weapon_row(-1, "fists", -1, inv.equipped == -1))
	for i in inv.weapons.size():
		var wp: Dictionary = inv.weapons[i]
		_weapons_box.add_child(_weapon_row(i, wp.id, int(wp.durability), inv.equipped == i))

	# Eşyalar (tür sırasına göre)
	var order := ["food", "water", "medkit", "bandage", "molotov", "noisemaker", "pistol_ammo", "shells",
		"wood", "nails", "scrap", "cloth", "alcohol"]
	var any := false
	for id in order:
		if inv.count(id) > 0:
			_items_box.add_child(_item_row(id, inv.count(id)))
			any = true
	if not any:
		_items_box.add_child(UITheme.label("Çantan boş.", 16, UITheme.TEXT_DIM))


func _weapon_row(index: int, id: String, durability: int, equipped: bool) -> Control:
	var row := _row_base(id, equipped)
	var info := Items.info(id)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	var name_label := UITheme.label(info.get("name", id) + ("   (elinde)" if equipped else ""), 18, Color.WHITE if equipped else UITheme.TEXT)
	mid.add_child(name_label)
	var sub := ""
	if info.get("type", "") == "gun":
		sub = "%s: %d   ·   hasar %d" % [Items.item_name(info.ammo), _player.inv.count(info.ammo), int(info.damage) * int(info.pellets)]
	elif durability >= 0:
		var maxd := int(info.get("durability", 1))
		sub = "Dayanıklılık %d%%   ·   hasar %d" % [int(100.0 * durability / maxf(maxd, 1)), int(info.damage)]
	else:
		sub = "Hasar %d" % int(info.get("damage", 0))
	mid.add_child(UITheme.label(sub, 13, UITheme.TEXT_DIM))
	if not equipped:
		row.add_child(_small_button("KUŞAN", _player.inv.equip.bind(index)))
	if index >= 0:
		row.add_child(_small_button("BIRAK", _player.drop_weapon.bind(index)))
	return row


func _item_row(id: String, count: int) -> Control:
	var row := _row_base(id, false)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	mid.add_child(UITheme.label("%s  x%d" % [Items.item_name(id), count], 18))
	mid.add_child(UITheme.label("%.2f kg" % (Items.weight(id) * count), 13, UITheme.TEXT_DIM))
	var t: String = Items.info(id).get("type", "")
	if t in ["food", "water", "medkit", "bandage"]:
		row.add_child(_small_button("KULLAN", _player.use_item.bind(id)))
	var drop_count := count if t in ["ammo", "material", "throwable"] else 1
	row.add_child(_small_button("BIRAK", _player.drop_item.bind(id, drop_count)))
	return row


func _row_base(icon_id: String, highlight: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_icon.bind(icon, icon_id, highlight))
	row.add_child(icon)
	return row


func _draw_icon(icon: Control, icon_id: String, highlight: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.ACCENT, 0.35) if highlight else Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(3)
	icon.draw_style_box(sb, Rect2(Vector2.ZERO, icon.size))
	var col: Color = HudIcons.COLORS.get(icon_id, Color.WHITE)
	HudIcons.draw(icon, icon_id, icon.size * 0.5, 32, col)


func _small_button(text: String, cb: Callable) -> Button:
	var b := UITheme.menu_button(text, 15)
	b.custom_minimum_size = Vector2(0, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b
