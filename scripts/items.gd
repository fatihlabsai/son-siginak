class_name Items
extends RefCounted
## Eşya veritabanı ve yağma tabloları. Denge ayarları burada.
##
## type: "melee" | "gun" | "food" | "water" | "medkit" | "ammo" | "material"
## weight: kg (taşıma sınırı Player.max_weight)

const DB := {
	# --- Yakın dövüş ---
	"fists": {"name": "Yumruk", "type": "melee", "damage": 12.0, "range": 1.4, "cooldown": 0.5,
		"stamina": 5.0, "noise": 2.5, "knockback": 2.0, "arc": 0.5, "targets": 1, "durability": -1, "weight": 0.0},
	"knife": {"name": "Bıçak", "type": "melee", "damage": 30.0, "range": 1.6, "cooldown": 0.35,
		"stamina": 4.0, "noise": 1.5, "knockback": 1.0, "arc": 0.6, "targets": 1, "durability": 60, "weight": 0.4},
	"bat": {"name": "Beyzbol sopası", "type": "melee", "damage": 38.0, "range": 2.1, "cooldown": 0.7,
		"stamina": 9.0, "noise": 4.0, "knockback": 6.0, "arc": 0.25, "targets": 3, "durability": 45, "weight": 1.2},
	"axe": {"name": "Yangın baltası", "type": "melee", "damage": 70.0, "range": 2.0, "cooldown": 1.05,
		"stamina": 14.0, "noise": 4.0, "knockback": 3.5, "arc": 0.35, "targets": 2, "durability": 35, "weight": 2.5},
	# --- Ateşli ---
	"pistol": {"name": "Tabanca", "type": "gun", "damage": 75.0, "pellets": 1, "spread": 0.025,
		"range": 28.0, "cooldown": 0.4, "noise": 32.0, "ammo": "pistol_ammo", "weight": 1.0},
	"shotgun": {"name": "Av tüfeği", "type": "gun", "damage": 24.0, "pellets": 7, "spread": 0.16,
		"range": 15.0, "cooldown": 1.0, "noise": 45.0, "ammo": "shells", "weight": 3.5},
	# --- Tüketilebilir ---
	"food": {"name": "Konserve", "type": "food", "weight": 0.4},
	"water": {"name": "Su şişesi", "type": "water", "weight": 0.5},
	"medkit": {"name": "İlk yardım kiti", "type": "medkit", "weight": 0.3},
	# --- Mermi ---
	"pistol_ammo": {"name": "Tabanca mermisi", "type": "ammo", "weight": 0.02},
	"shells": {"name": "Fişek", "type": "ammo", "weight": 0.05},
	# --- Malzeme (barikat için) ---
	"wood": {"name": "Tahta", "type": "material", "weight": 1.0},
	"nails": {"name": "Çivi", "type": "material", "weight": 0.05},
	"scrap": {"name": "Hurda metal", "type": "material", "weight": 0.6},
}

## Yağma tabloları: [eşya, ağırlık(olasılık), en az, en çok]. "" = boş çıktı.
const LOOT := {
	"house": {"rolls": [3, 5], "time": 3.5, "noise": 9.0, "items": [
		["food", 25, 1, 2], ["water", 25, 1, 2], ["medkit", 8, 1, 1], ["pistol_ammo", 12, 4, 10],
		["shells", 5, 2, 5], ["knife", 4, 1, 1], ["bat", 4, 1, 1], ["axe", 2, 1, 1], ["pistol", 2, 1, 1],
		["shotgun", 1, 1, 1], ["wood", 10, 1, 3], ["nails", 8, 3, 8], ["", 12, 0, 0]]},
	"car": {"rolls": [1, 3], "time": 2.5, "noise": 6.0, "items": [
		["water", 15, 1, 1], ["food", 10, 1, 1], ["pistol_ammo", 15, 3, 8], ["shells", 6, 2, 4],
		["bat", 5, 1, 1], ["pistol", 3, 1, 1], ["scrap", 15, 1, 2], ["", 30, 0, 0]]},
	"dumpster": {"rolls": [1, 2], "time": 2.0, "noise": 6.0, "items": [
		["food", 25, 1, 1], ["water", 10, 1, 1], ["scrap", 20, 1, 2], ["wood", 10, 1, 2],
		["knife", 3, 1, 1], ["", 35, 0, 0]]},
	"crate": {"rolls": [1, 3], "time": 1.5, "noise": 4.0, "items": [
		["food", 15, 1, 2], ["water", 15, 1, 2], ["medkit", 10, 1, 1], ["pistol_ammo", 15, 4, 10],
		["shells", 8, 2, 5], ["nails", 15, 4, 10], ["wood", 15, 1, 2], ["axe", 3, 1, 1], ["", 10, 0, 0]]},
	"zombie": {"rolls": [1, 1], "time": 0.0, "noise": 0.0, "items": [
		["food", 15, 1, 1], ["water", 15, 1, 1], ["pistol_ammo", 20, 2, 5], ["shells", 6, 1, 2],
		["medkit", 6, 1, 1], ["knife", 3, 1, 1], ["", 40, 0, 0]]},
}


static func info(id: String) -> Dictionary:
	return DB.get(id, {})


static func item_name(id: String) -> String:
	return info(id).get("name", id)


static func is_weapon(id: String) -> bool:
	var t: String = info(id).get("type", "")
	return t == "melee" or t == "gun"


static func weight(id: String) -> float:
	return float(info(id).get("weight", 0.0))


## Bir yağma tablosundan rastgele eşyalar üretir: [[id, adet], ...]
static func roll(table: String, rng: RandomNumberGenerator, loot_mult := 1.0) -> Array:
	var t: Dictionary = LOOT.get(table, {})
	if t.is_empty():
		return []
	var rolls: int = rng.randi_range(t.rolls[0], t.rolls[1])
	rolls = maxi(1, int(round(rolls * loot_mult)))
	var total := 0
	for e in t.items:
		total += int(e[1])
	var out := []
	for r in rolls:
		var pick := rng.randi() % total
		for e in t.items:
			pick -= int(e[1])
			if pick < 0:
				if e[0] != "":
					out.append([e[0], rng.randi_range(e[2], e[3])])
				break
	return out
