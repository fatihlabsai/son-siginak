extends CanvasLayer
## Oyun içi arayüz.
##  Sol alt  : durum çubukları (sağlık, dayanıklılık, tokluk, su) + durum etiketleri
##  Sağ alt  : silah / mermi kartı + envanter kutucukları
##  Sağ üst  : gün, saat, gün-gece şeridi, öldürme sayısı
##  Sol üst  : kontrol ipuçları (H ile aç/kapa)
##  Üst orta : bildirimler
##  Dünyada  : eşyanın üstünde [E] etkileşim balonu
## Ayrıca duraklatma menüsü, ölüm ekranı ve geçiş kararmaları.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const HELP_ROWS := [
	["WASD", "Yürü"], ["Shift", "Koş"], ["Sol tık", "Vur"], ["Sağ tık + Sol tık", "Ateş et"],
	["Q", "Silah değiştir"], ["E", "Al  /  basılı tut: ara, onar"], ["Tab", "Envanter"], ["B", "İnşa (barikat, tuzak)"], ["F", "Fener"],
	["1 2 3 4", "Ye / İç / Kit / Bandaj"], ["C", "Üretim"], ["G", "Fırlat (Z: değiştir)"], ["Esc", "Menü"],
]

var _root: Control
var _stats := {}
var _tags := {}
var _slots := {}
var _ammo_label: Label
var _day_label: Label
var _time_label: Label
var _night_tag: Control
var _kills_label: Label
var _sky_icon: Control
var _clock_bar: Control
var _help_panel: Control
var _help_hint: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0
var _prompt: VBoxContainer
var _prompt_label: Label
var _prompt_bar: ProgressBar
var _weapon_name: Label
var _weapon_icon: Control
var _dur_bar: ProgressBar
var _card_id := ""
var _inventory: InventoryMenu
var _crafting: CraftingMenu
var _build_panel: PanelContainer
var _build_cards: Array[PanelContainer] = []
var _build_costs: Array[Label] = []
var _hp_layer: Control
var _vignette: TextureRect
var _hurt := 0.0

var _pause_panel: Control
var _pause_buttons: VBoxContainer
var _death_panel: Control
var _death_stats: Label
var _death_buttons: VBoxContainer
var _settings: SettingsMenu
var _save_note: Label
var _fade: ColorRect
var _game_over := false
var _leaving := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_build_vignette()
	_build_vitals()
	_build_inventory()
	_build_clock()
	_build_objective()
	_build_help()
	_build_toast()
	_build_prompt()
	_build_build_panel()
	_build_menus()

	var p := Game.player
	if p:
		p.message.connect(show_message)
		p.hurt.connect(_on_player_hurt)
		p.died.connect(_on_player_died)
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()
	create_tween().tween_property(_fade, "color:a", 0.0, 1.0)


# ------------------------------------------------------------------
# Her kare
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_objective(delta)
	var p := Game.player
	if is_instance_valid(p):
		_stats["health"].set_value(p.health / p.max_health)
		_stats["stamina"].set_value(p.stamina / p.max_stamina)
		_stats["hunger"].set_value(p.hunger / 100.0)
		_stats["thirst"].set_value(p.thirst / 100.0)
		_tags["hungry"].visible = p.hunger < 25.0
		_tags["thirsty"].visible = p.thirst < 25.0
		_tags["tired"].visible = p.stamina < 15.0
		_tags["hurt"].visible = p.health < 30.0 and not p.is_dead

		_slots["food"].set_count(p.inv.count("food"))
		_slots["water"].set_count(p.inv.count("water"))
		_slots["medkit"].set_count(p.inv.count("medkit"))
		_slots["bandage"].set_count(p.inv.count("bandage"))
		var th := p.current_throwable()
		_slots["throw"].kind = th if th != "" else p.throw_id
		_slots["throw"].set_count(p.inv.count(_slots["throw"].kind))
		_tags["heavy"].visible = p.inv.total_weight() > p.inv.max_weight * 0.9
		_update_weapon_card(p)
		_update_build_panel(p)
		_hp_layer.queue_redraw()

		_update_prompt(p)

		var low := 0.0
		if p.health < 40.0 and not p.is_dead:
			low = (1.0 - p.health / 40.0) * (0.55 + 0.25 * sin(Time.get_ticks_msec() / 180.0))
		_hurt = maxf(_hurt - delta * 1.4, 0.0)
		_vignette.modulate.a = clampf(maxf(_hurt, low), 0.0, 1.0)

	var h := int(Game.hour)
	var m := int((Game.hour - h) * 60.0)
	_day_label.text = "GÜN %d" % Game.day
	_time_label.text = "%02d:%02d" % [h, m]
	_night_tag.visible = Game.is_night()
	_kills_label.text = "%d ÖLDÜRÜLEN" % Game.kills
	_sky_icon.queue_redraw()
	_clock_bar.queue_redraw()

	_toast_timer -= delta
	_toast.modulate.a = clampf(_toast_timer * 2.0, 0.0, 1.0)


func show_message(text: String, duration := 3.0) -> void:
	_toast_label.text = text
	_toast_timer = duration
	_toast.offset_top = 64
	create_tween().tween_property(_toast, "offset_top", 78.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_weapon_card(p: Player) -> void:
	var id := p.inv.current_id()
	var info := Items.info(id)
	if id != _card_id:
		_card_id = id
		_weapon_name.text = String(info.get("name", id)).to_upper()
		_weapon_icon.queue_redraw()
	if info.get("type", "") == "gun":
		var n := p.inv.count(info.ammo)
		_ammo_label.text = str(n)
		_ammo_label.add_theme_color_override("font_color", UITheme.ACCENT.lightened(0.3) if n == 0 else UITheme.TEXT)
		_dur_bar.visible = false
		_ammo_label.visible = true
	else:
		_ammo_label.visible = false
		var e := p.inv.current_entry()
		var maxd := float(info.get("durability", -1))
		_dur_bar.visible = maxd > 0
		if maxd > 0:
			_dur_bar.value = 100.0 * float(e.durability) / maxd


func _update_prompt(p: Player) -> void:
	var cam := get_viewport().get_camera_3d()
	var target: Node3D = null
	var text := ""
	var progress := -1.0
	if p.searching:
		target = p.searching
		text = "Aranıyor..."
		progress = p.search_progress
	elif is_instance_valid(p.repairing):
		target = p.repairing
		text = "Onarılıyor...  (tahta: %d)" % p.inv.count("wood")
		progress = p.repair_progress
	elif is_instance_valid(p.nearby_pickup):
		target = p.nearby_pickup
		text = p.nearby_pickup.display_name()
	elif is_instance_valid(p.nearby_search):
		target = p.nearby_search
		text = p.nearby_search.prompt_text()
	elif is_instance_valid(p.nearby_repair):
		target = p.nearby_repair
		text = "Onar  (1 tahta, basılı tut)"
	if target == null or cam == null or p.is_dead or Game.ui_open or p.build.active:
		_prompt.visible = false
		return
	var world := target.global_position + Vector3.UP * 0.9
	if cam.is_position_behind(world):
		_prompt.visible = false
		return
	_prompt.visible = true
	_prompt_label.text = text
	_prompt_bar.visible = progress >= 0.0
	_prompt_bar.value = progress * 100.0
	var screen := cam.unproject_position(world)
	_prompt.reset_size()
	_prompt.position = screen - Vector2(_prompt.size.x * 0.5, _prompt.size.y)


# ------------------------------------------------------------------
# Olaylar
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or is_instance_valid(_settings) or is_instance_valid(_inventory) or is_instance_valid(_crafting):
		return
	if Game.cutscene_active:
		return
	if event.is_action_pressed("inventory") and not _game_over and not get_tree().paused:
		_open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("craft") and not _game_over and not get_tree().paused:
		_open_crafting()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_help"):
		Settings.show_help = not Settings.show_help
		Settings.apply()
		Settings.save_settings()
	elif event.is_action_pressed("pause") and not _game_over:
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and _game_over and _death_panel.visible:
		_restart()


func _open_inventory() -> void:
	if not is_instance_valid(Game.player) or Game.player.is_dead:
		return
	_inventory = InventoryMenu.new()
	_inventory.setup(Game.player)
	_inventory.closed.connect(_on_inventory_closed)
	_root.add_child(_inventory)
	_root.move_child(_fade, -1)
	Game.ui_open = true


func _on_inventory_closed() -> void:
	Game.ui_open = false


func _open_crafting() -> void:
	if not is_instance_valid(Game.player) or Game.player.is_dead:
		return
	if Game.player.build.active:
		Game.player.build.set_active(false)
	_crafting = CraftingMenu.new()
	_crafting.setup(Game.player)
	_crafting.closed.connect(_on_inventory_closed)
	_root.add_child(_crafting)
	_root.move_child(_fade, -1)
	Game.ui_open = true


func _on_settings_changed() -> void:
	_help_panel.visible = Settings.show_help
	_help_hint.visible = not Settings.show_help


func _on_player_hurt(_amount: float) -> void:
	_hurt = 1.0


func _on_player_died() -> void:
	_game_over = true
	if is_instance_valid(_inventory):
		_inventory.close()
	await get_tree().create_timer(1.6).timeout
	_death_stats.text = "%d. günde düştün   ·   %d zombi öldürdün   ·   kayıt silindi" % [Game.day, Game.kills]
	_death_panel.visible = true
	_death_panel.modulate.a = 0.0
	create_tween().tween_property(_death_panel, "modulate:a", 1.0, 0.8)
	_focus_first(_death_buttons)
	get_tree().paused = true


# ------------------------------------------------------------------
# HUD parçaları
# ------------------------------------------------------------------

func _build_vignette() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0, 0, 0), Color(0.5, 0, 0, 0.05), Color(0.45, 0, 0, 0.85)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	# Alt kenarda hafif karartma: alt köşelerdeki arayüz her zeminde okunur
	var g2 := Gradient.new()
	g2.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)])
	var t2 := GradientTexture2D.new()
	t2.gradient = g2
	t2.fill_from = Vector2(0, 0)
	t2.fill_to = Vector2(0, 1)
	var bottom := TextureRect.new()
	bottom.texture = t2
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(bottom, Vector4(0, 1, 1, 1), Vector4(0, -190, 0, 0))
	_root.add_child(bottom)


func _build_vitals() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(box, Vector4(0, 1, 0, 1), Vector4(28, -170, 330, -24))
	box.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(box)

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.custom_minimum_size.y = 24
	box.add_child(tags)
	for def in [["hurt", "AĞIR YARALI"], ["hungry", "AÇ"], ["thirsty", "SUSUZ"], ["tired", "BİTKİN"], ["heavy", "AĞIR YÜK"]]:
		var tag := _tag(def[1], Color(UITheme.ACCENT, 0.85))
		tag.visible = false
		tags.add_child(tag)
		_tags[def[0]] = tag

	for def in [["health", 0.3], ["stamina", 0.15], ["hunger", 0.25], ["thirst", 0.25]]:
		var s := HudStat.new(def[0], def[1])
		box.add_child(s)
		_stats[def[0]] = s
	(_stats["stamina"] as HudStat).fade_when_full = true


func _build_inventory() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(row, Vector4(1, 1, 1, 1), Vector4(-760, -98, -28, -28))
	_root.add_child(row)

	for def in [["food", "1"], ["water", "2"], ["medkit", "3"], ["bandage", "4"]]:
		var slot := HudSlot.new(def[0], def[1])
		row.add_child(slot)
		_slots[def[0]] = slot
	var tgap := Control.new()
	tgap.custom_minimum_size.x = 6
	row.add_child(tgap)
	var tslot := HudSlot.new("molotov", "G")
	tslot.tooltip_text = "Z: değiştir"
	row.add_child(tslot)
	_slots["throw"] = tslot

	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	row.add_child(gap)

	# Silah kartı
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.75)
	sb.border_width_left = 3
	sb.border_color = UITheme.ACCENT
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(210, 66)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	_weapon_icon = Control.new()
	_weapon_icon.custom_minimum_size = Vector2(54, 54)
	_weapon_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_icon.draw.connect(_draw_weapon_icon)
	hb.add_child(_weapon_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vb.add_child(name_row)
	_weapon_name = UITheme.label("", 11, UITheme.TEXT_DIM, UITheme.spaced_font())
	_weapon_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_weapon_name)
	name_row.add_child(_key_badge("Q", 11))
	_ammo_label = UITheme.label("0", 34, UITheme.TEXT, UITheme.title_font())
	vb.add_child(_ammo_label)
	_dur_bar = ProgressBar.new()
	_dur_bar.show_percentage = false
	_dur_bar.custom_minimum_size = Vector2(110, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.75, 0.55)
	_dur_bar.add_theme_stylebox_override("background", bg)
	_dur_bar.add_theme_stylebox_override("fill", fill)
	var dur_margin := MarginContainer.new()
	dur_margin.add_theme_constant_override("margin_top", 12)
	dur_margin.add_child(_dur_bar)
	vb.add_child(dur_margin)


func _draw_weapon_icon() -> void:
	var id := _card_id if _card_id != "" else "fists"
	var col: Color = HudIcons.COLORS.get(id, Color.WHITE)
	HudIcons.draw(_weapon_icon, id, _weapon_icon.size * 0.5, 46, col)


# ------------------------------------------------------------------
# Görev satırı (sağ üst, saatin altında)
# ------------------------------------------------------------------

var _obj_box: VBoxContainer
var _obj_label: Label
var _obj_text := ""
var _obj_timer := 0.0
var _camp_reached := false


func _build_objective() -> void:
	_obj_box = VBoxContainer.new()
	_obj_box.add_theme_constant_override("separation", 0)
	_obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_obj_box, Vector4(1, 0, 1, 0), Vector4(-380, 150, -28, 220))
	_root.add_child(_obj_box)
	var t := UITheme.label("GÖREV", 12, UITheme.ACCENT.lightened(0.35), UITheme.spaced_font())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_obj_box.add_child(t)
	_obj_label = UITheme.label("", 19, UITheme.TEXT)
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shadow(_obj_label)
	_obj_box.add_child(_obj_label)
	_obj_box.modulate.a = 0.0


func _current_objective() -> String:
	var lv := Game.level
	var p := Game.player
	if not is_instance_valid(lv) or not is_instance_valid(p) or not Game.nav_ready:
		return ""
	if get_tree().get_nodes_in_group("barricades").size() > 0:
		return ""
	if not lv.shelter_bag_searched():
		return "Çantanı kontrol et (E basılı tut)"
	if not lv.shelter_door_open():
		return "Sığınaktan çık"
	if not _camp_reached and p.global_position.distance_to(lv.campfire_position()) < 11.0:
		_camp_reached = true
	if not _camp_reached:
		return "Kavşaktaki kampa git. Yolda su bul."
	return "Kampın girişlerini kapat (B: barikat kur)"


func _update_objective(delta: float) -> void:
	_obj_timer -= delta
	if _obj_timer > 0.0:
		return
	_obj_timer = 0.4
	var t := _current_objective() if not Game.cutscene_active else ""
	if t == _obj_text:
		return
	var was := _obj_text
	_obj_text = t
	var tw := create_tween()
	if was != "":
		tw.tween_property(_obj_box, "modulate:a", 0.0, 0.3)
	if t != "":
		tw.tween_callback(func(): _obj_label.text = t)
		tw.tween_property(_obj_box, "modulate:a", 1.0, 0.5)
		if was != "":
			Audio.ui("click", -10.0)


func _build_clock() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(box, Vector4(1, 0, 1, 0), Vector4(-300, 22, -28, 160))
	_root.add_child(box)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	_night_tag = _tag("GECE", Color(0.2, 0.28, 0.6, 0.85))
	_night_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_night_tag)
	_sky_icon = Control.new()
	_sky_icon.custom_minimum_size = Vector2(30, 30)
	_sky_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sky_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_icon.draw.connect(_draw_sky_icon)
	top.add_child(_sky_icon)
	_day_label = UITheme.label("GÜN 1", 40, UITheme.TEXT, UITheme.title_font())
	_day_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_day_label.add_theme_constant_override("shadow_offset_y", 2)
	top.add_child(_day_label)

	_time_label = UITheme.label("09:00", 20, UITheme.TEXT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shadow(_time_label)
	box.add_child(_time_label)

	_clock_bar = Control.new()
	_clock_bar.custom_minimum_size = Vector2(200, 8)
	_clock_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_clock_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_bar.draw.connect(_draw_clock_bar)
	box.add_child(_clock_bar)

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	_kills_label = UITheme.label("0 ÖLDÜRÜLEN", 12, UITheme.TEXT_DIM, UITheme.spaced_font())
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shadow(_kills_label)
	box.add_child(_kills_label)


func _draw_sky_icon() -> void:
	var night := Game.is_night()
	var col := Color(0.75, 0.82, 1.0) if night else Color(1.0, 0.82, 0.4)
	HudIcons.draw(_sky_icon, "moon" if night else "sun", _sky_icon.size * 0.5, 28, col)


## Günün akışı: gece kısımları lacivert, gündüz kehribar, beyaz çizgi = şimdi.
func _draw_clock_bar() -> void:
	var w := _clock_bar.size.x
	var h := _clock_bar.size.y
	_clock_bar.draw_rect(Rect2(-1, -1, w + 2, h + 2), Color(0, 0, 0, 0.6))
	var segs := [[0.0, 6.0, Color(0.15, 0.2, 0.42)], [6.0, 20.0, Color(0.75, 0.55, 0.25)], [20.0, 24.0, Color(0.15, 0.2, 0.42)]]
	for s in segs:
		var x0: float = s[0] / 24.0 * w
		var x1: float = s[1] / 24.0 * w
		_clock_bar.draw_rect(Rect2(x0, 0, x1 - x0, h), Color(s[2], 0.75))
	var x := Game.hour / 24.0 * w
	_clock_bar.draw_rect(Rect2(x - 1.5, -3, 3, h + 6), Color.WHITE)


func _build_help() -> void:
	_help_panel = VBoxContainer.new()
	_help_panel.add_theme_constant_override("separation", 5)
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_help_panel, Vector4(0, 0, 0, 0), Vector4(28, 26, 340, 300))
	_root.add_child(_help_panel)
	var title := UITheme.label("KONTROLLER", 11, UITheme.TEXT_DIM, UITheme.spaced_font())
	_shadow(title)
	_help_panel.add_child(title)
	for r in HELP_ROWS:
		_help_panel.add_child(_key_row(r[0], r[1]))
	_help_panel.add_child(_key_row("H", "Bu listeyi gizle"))

	_help_hint = _key_row("H", "Kontroller")
	_anchor(_help_hint, Vector4(0, 0, 0, 0), Vector4(28, 26, 300, 56))
	_help_hint.modulate.a = 0.7
	_root.add_child(_help_hint)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.78)
	sb.border_width_left = 3
	sb.border_color = UITheme.ACCENT
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 78
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_toast_label = UITheme.label("", 19, UITheme.TEXT)
	_toast.add_child(_toast_label)


func _build_prompt() -> void:
	_prompt = VBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 4)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_root.add_child(_prompt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_prompt.add_child(row)
	row.add_child(_key_badge("E", 16))
	_prompt_label = UITheme.label("", 17, Color.WHITE)
	_shadow(_prompt_label)
	row.add_child(_prompt_label)
	_prompt_bar = ProgressBar.new()
	_prompt_bar.show_percentage = false
	_prompt_bar.custom_minimum_size = Vector2(150, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.92, 0.9, 0.86)
	_prompt_bar.add_theme_stylebox_override("background", bg)
	_prompt_bar.add_theme_stylebox_override("fill", fill)
	_prompt_bar.visible = false
	_prompt.add_child(_prompt_bar)


## İnşa modu paneli (alt orta) + hasarlı barikatların can çubukları (dünyada).
func _build_build_panel() -> void:
	_hp_layer = Control.new()
	_hp_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_layer.draw.connect(_draw_hp_bars)
	_root.add_child(_hp_layer)

	_build_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.82)
	sb.border_width_top = 3
	sb.border_color = UITheme.ACCENT
	sb.set_content_margin_all(12)
	_build_panel.add_theme_stylebox_override("panel", sb)
	_build_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel.anchor_left = 0.5
	_build_panel.anchor_right = 0.5
	_build_panel.anchor_top = 1.0
	_build_panel.anchor_bottom = 1.0
	_build_panel.offset_top = -250
	_build_panel.offset_bottom = -120
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_panel.visible = false
	_root.add_child(_build_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_build_panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := UITheme.label("İNŞA", 13, UITheme.ACCENT.lightened(0.3), UITheme.spaced_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.label("Sol tık: kur    R: döndür    Sağ tık / B: çık", 13, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	for i in BuildMode.OPTIONS.size():
		var opt: Dictionary = BuildMode.OPTIONS[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(210, 0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		cv.add_child(name_row)
		name_row.add_child(_key_badge(str(i + 1), 11))
		name_row.add_child(UITheme.label(opt.name, 16, Color.WHITE))
		var cost := UITheme.label("", 13, UITheme.TEXT_DIM)
		cv.add_child(cost)
		var desc := UITheme.label(opt.desc, 12, UITheme.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 190
		cv.add_child(desc)
		_build_cards.append(card)
		_build_costs.append(cost)


func _update_build_panel(p: Player) -> void:
	_build_panel.visible = p.build.active
	if not p.build.active:
		return
	for i in _build_cards.size():
		var opt: Dictionary = BuildMode.OPTIONS[i]
		var sb := StyleBoxFlat.new()
		var selected := i == p.build.index
		sb.bg_color = Color(1, 1, 1, 0.1) if selected else Color(1, 1, 1, 0.03)
		sb.border_width_left = 4 if selected else 0
		sb.border_color = UITheme.ACCENT
		sb.set_content_margin_all(8)
		_build_cards[i].add_theme_stylebox_override("panel", sb)
		var parts: Array[String] = []
		var ok := true
		for id in opt.cost:
			var have := p.inv.count(id)
			var need := int(opt.cost[id])
			ok = ok and have >= need
			parts.append("%s %d/%d" % [Items.item_name(id), have, need])
		_build_costs[i].text = "  ".join(parts)
		_build_costs[i].add_theme_color_override("font_color", Color(0.6, 0.85, 0.55) if ok else Color(0.95, 0.45, 0.4))


func _draw_hp_bars() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(Game.player):
		return
	var pp := Game.player.global_position
	for node in get_tree().get_nodes_in_group("barricades"):
		var b := node as Barricade
		if b == null or b.hp >= b.max_hp:
			continue
		if b.global_position.distance_to(pp) > 30.0:
			continue
		var world := b.global_position + Vector3.UP * 1.3
		if cam.is_position_behind(world):
			continue
		var s := cam.unproject_position(world)
		var w := 70.0
		var r := b.hp_ratio()
		_hp_layer.draw_rect(Rect2(s.x - w * 0.5 - 1, s.y - 1, w + 2, 7), Color(0, 0, 0, 0.7))
		var col := Color(0.4, 0.85, 0.35).lerp(Color(0.95, 0.25, 0.15), 1.0 - r)
		_hp_layer.draw_rect(Rect2(s.x - w * 0.5, s.y, w * r, 5), col)


# ------------------------------------------------------------------
# Küçük yardımcılar
# ------------------------------------------------------------------

func _key_badge(text: String, size := 13) -> PanelContainer:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.9, 0.86, 0.95)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 2
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(UITheme.label(text, size, Color(0.08, 0.08, 0.08)))
	return badge


func _key_row(key: String, action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_key_badge(key))
	var l := UITheme.label(action, 14, UITheme.TEXT)
	_shadow(l)
	row.add_child(l)
	return row


func _tag(text: String, bg: Color) -> PanelContainer:
	var tag := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	tag.add_theme_stylebox_override("panel", sb)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(UITheme.label(text, 12, Color.WHITE, UITheme.spaced_font()))
	return tag


func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


## anchors: (sol, üst, sağ, alt) — offsets: (sol, üst, sağ, alt)
func _anchor(c: Control, a: Vector4, o: Vector4) -> void:
	c.anchor_left = a.x
	c.anchor_top = a.y
	c.anchor_right = a.z
	c.anchor_bottom = a.w
	c.offset_left = o.x
	c.offset_top = o.y
	c.offset_right = o.z
	c.offset_bottom = o.w


# ------------------------------------------------------------------
# Duraklatma / ölüm menüleri
# ------------------------------------------------------------------

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_panel.visible = paused
	if paused:
		_save_note.text = ("Son kayıt: " + Game.save_summary()) if Game.has_save() else "Henüz kayıt yok. Şafakta otomatik kaydedilir."
		_focus_first(_pause_buttons)


func _open_settings() -> void:
	_pause_panel.visible = false
	_settings = SettingsMenu.new()
	_root.add_child(_settings)
	_root.move_child(_fade, -1)
	_settings.closed.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	_pause_panel.visible = true
	_focus_first(_pause_buttons)


func _restart() -> void:
	await _fade_out()
	get_tree().paused = false
	Game.reset_run()
	get_tree().reload_current_scene()


func _to_main_menu() -> void:
	await _fade_out()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _quit_game() -> void:
	await _fade_out()
	get_tree().quit()


func _manual_save() -> void:
	if Game.save_game():
		_save_note.text = "Kaydedildi  ·  " + Game.save_summary()
	else:
		_save_note.text = "Şu an kaydedilemiyor."


func _save_and_menu() -> void:
	Game.save_game()
	_to_main_menu()


func _save_and_quit() -> void:
	Game.save_game()
	_quit_game()


func _fade_out() -> void:
	_leaving = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	await tw.finished


func _focus_first(box: Control) -> void:
	for c in box.get_children():
		if c is Button:
			(c as Button).call_deferred("grab_focus")
			return


func _build_menus() -> void:
	_pause_panel = _menu_overlay(Color(0, 0, 0, 0.62))
	var pv := _pause_panel.get_node("Box") as VBoxContainer
	pv.add_child(UITheme.label("DURAKLATILDI", 64, UITheme.TEXT, UITheme.title_font()))
	pv.add_child(UITheme.accent_line(120, 4))
	_pause_buttons = VBoxContainer.new()
	_pause_buttons.add_theme_constant_override("separation", 4)
	pv.add_child(_pause_buttons)
	_menu_btn(_pause_buttons, "DEVAM ET", _set_paused.bind(false))
	_menu_btn(_pause_buttons, "KAYDET", _manual_save)
	_menu_btn(_pause_buttons, "AYARLAR", _open_settings)
	_menu_btn(_pause_buttons, "KAYDET VE ANA MENÜ", _save_and_menu)
	_menu_btn(_pause_buttons, "KAYDET VE ÇIK", _save_and_quit)
	_save_note = UITheme.label("", 15, UITheme.TEXT_DIM)
	pv.add_child(_save_note)

	_death_panel = _menu_overlay(Color(0.12, 0.0, 0.0, 0.72))
	var dv := _death_panel.get_node("Box") as VBoxContainer
	dv.add_child(UITheme.label("ÖLDÜN", 110, UITheme.ACCENT.lightened(0.15), UITheme.title_font()))
	_death_stats = UITheme.label("", 20, UITheme.TEXT_DIM)
	dv.add_child(_death_stats)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	dv.add_child(gap)
	_death_buttons = VBoxContainer.new()
	_death_buttons.add_theme_constant_override("separation", 4)
	dv.add_child(_death_buttons)
	_menu_btn(_death_buttons, "YENİDEN BAŞLA", _restart)
	_menu_btn(_death_buttons, "ANA MENÜ", _to_main_menu)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


func _menu_overlay(color: Color) -> Control:
	var overlay := ColorRect.new()
	overlay.color = color
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	_root.add_child(overlay)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = 110
	box.offset_top = -170
	box.offset_right = 560
	overlay.add_child(box)
	return overlay


func _menu_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := UITheme.menu_button(text, 28)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
