class_name Crafting
extends RefCounted
## Üretim tarifleri. "camp": true olanlar sadece kamp ateşinin yanında yapılabilir.
## needs: tüketilen eşyalar (silahlar da olabilir, örn. "bat").
## gives: üretilen eşya; "repair" özel: elindeki yakın dövüş silahını onarır.

const CAMP_RADIUS := 7.0

const RECIPES := [
	{"id": "bandage", "name": "Bandaj", "needs": {"cloth": 2}, "gives": "bandage", "count": 1, "camp": false,
		"desc": "Canı 20 yeniler. Hafif ve hızlı. [4] ile kullan."},
	{"id": "molotov", "name": "Molotof", "needs": {"alcohol": 1, "cloth": 1}, "gives": "molotov", "count": 1, "camp": false,
		"desc": "Fırlatınca yere yanan bir alev bırakır. Sürülere karşı etkili ama çok gürültülü."},
	{"id": "noisemaker", "name": "Gürültücü", "needs": {"scrap": 1, "nails": 3}, "gives": "noisemaker", "count": 1, "camp": false,
		"desc": "Fırlatınca 12 saniye ses çıkarır; zombileri oraya çeker, senden uzaklaştırır."},
	{"id": "nail_bat", "name": "Çivili sopa", "needs": {"bat": 1, "nails": 8}, "gives": "nail_bat", "count": 1, "camp": true,
		"desc": "Beyzbol sopasına çivi çak: hasar 38 → 55, daha dayanıklı."},
	{"id": "repair", "name": "Silah onarımı", "needs": {"scrap": 2, "nails": 2}, "gives": "repair", "count": 1, "camp": true,
		"desc": "Elindeki yakın dövüş silahının dayanıklılığını %50 yeniler."},
]


static func near_camp(player: Player) -> bool:
	if not is_instance_valid(Game.level):
		return false
	return Game.level.campfire_position().distance_to(player.global_position) <= CAMP_RADIUS


## Oyuncunun elinde kaç tane var (silahlar dahil).
static func have(player: Player, id: String) -> int:
	if Items.is_weapon(id):
		var n := 0
		for w in player.inv.weapons:
			if w.id == id:
				n += 1
		return n
	return player.inv.count(id)


## Üretilemiyorsa nedenini döndürür, üretilebiliyorsa "".
static func blocker(player: Player, r: Dictionary) -> String:
	if r.camp and not near_camp(player):
		return "Kamp ateşinin yanında yapılmalı"
	for id in r.needs:
		if have(player, id) < int(r.needs[id]):
			return "Malzeme eksik"
	if r.gives == "repair":
		var e := player.inv.current_entry()
		var maxd := int(Items.info(e.id).get("durability", -1))
		if maxd <= 0:
			return "Elinde onarılacak yakın dövüş silahı yok"
		if int(e.durability) >= maxd:
			return "Silahın zaten sağlam"
	return ""


static func craft(player: Player, r: Dictionary) -> bool:
	if blocker(player, r) != "":
		return false
	# Malzemeleri harca (silahlarda elindekini değil, en yıpranmış olanı kullan)
	for id in r.needs:
		var n := int(r.needs[id])
		if Items.is_weapon(id):
			for k in n:
				var idx := _worst_weapon_index(player, id)
				player.inv.take_weapon(idx)
		else:
			player.inv.remove(id, n)
	if r.gives == "repair":
		var e := player.inv.current_entry()
		var maxd := int(Items.info(e.id).get("durability", -1))
		e.durability = mini(maxd, int(e.durability) + maxd / 2)
		player.inv.changed.emit()
	else:
		var got := player.inv.add(r.gives, int(r.count))
		if got < int(r.count) and is_instance_valid(Game.level):
			Game.level.spawn_pickup(r.gives, player.global_position, false, int(r.count) - got)
		if Items.is_weapon(r.gives) and got > 0:
			player.inv.equip(player.inv.weapons.size() - 1)
	Audio.play_2d("hit", -8.0)
	Game.make_noise(player.global_position, 4.0)
	return true


static func _worst_weapon_index(player: Player, id: String) -> int:
	var best := -1
	var best_d := 1 << 30
	for i in player.inv.weapons.size():
		var w: Dictionary = player.inv.weapons[i]
		if w.id == id and int(w.durability) < best_d:
			best_d = int(w.durability)
			best = i
	return best
