class_name PlayerInventory
extends RefCounted
## Oyuncunun envanteri: yığılabilir eşyalar (adet), silahlar (her biri ayrı, dayanıklılıklı),
## kuşanılan silah ve taşıma ağırlığı.

signal changed

var items := {}          # id -> adet
var weapons: Array = []  # [{"id": "knife", "durability": 60}, ...]
var equipped := -1       # weapons dizisinde indeks; -1 = yumruk
var max_weight := 25.0


func count(id: String) -> int:
	return int(items.get(id, 0))


func total_weight() -> float:
	var w := 0.0
	for id in items:
		w += Items.weight(id) * int(items[id])
	for wp in weapons:
		w += Items.weight(wp.id)
	return w


## Bu eşyadan kaç tane daha taşınabilir.
func room_for(id: String) -> int:
	var per := Items.weight(id)
	if per <= 0.0:
		return 9999
	return maxi(0, int(floor((max_weight - total_weight()) / per + 0.0001)))


## Eşya ekler, sığan adedi döndürür. Silahlar için durability verilebilir (-1 = yeni).
func add(id: String, amount := 1, durability := -1) -> int:
	if Items.info(id).is_empty():
		return 0
	var fits := mini(amount, room_for(id))
	if fits <= 0:
		return 0
	if Items.is_weapon(id):
		for i in fits:
			var d: int = durability if durability >= 0 else int(Items.info(id).get("durability", -1))
			weapons.append({"id": id, "durability": d})
	else:
		items[id] = count(id) + fits
	changed.emit()
	return fits


func remove(id: String, amount := 1) -> bool:
	if count(id) < amount:
		return false
	items[id] = count(id) - amount
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true


func current_id() -> String:
	if equipped >= 0 and equipped < weapons.size():
		return weapons[equipped].id
	return "fists"


func current_entry() -> Dictionary:
	if equipped >= 0 and equipped < weapons.size():
		return weapons[equipped]
	return {"id": "fists", "durability": -1}


func current_info() -> Dictionary:
	return Items.info(current_id())


## Sıradaki silaha geç (en sonda yumruğa döner).
func cycle() -> void:
	if weapons.is_empty():
		equipped = -1
	else:
		equipped += 1
		if equipped >= weapons.size():
			equipped = -1
	changed.emit()


func equip(index: int) -> void:
	equipped = clampi(index, -1, weapons.size() - 1)
	changed.emit()


## Kuşanılı yakın dövüş silahını aşındırır. Kırılırsa adını döndürür, yoksa "".
func wear_current(amount := 1) -> String:
	if equipped < 0:
		return ""
	var wp: Dictionary = weapons[equipped]
	if int(wp.durability) < 0:
		return ""
	wp.durability = int(wp.durability) - amount
	var broken := ""
	if wp.durability <= 0:
		broken = Items.item_name(wp.id)
		weapons.remove_at(equipped)
		equipped = -1
	changed.emit()
	return broken


## Silahı envanterden çıkarır ve kaydını döndürür.
func take_weapon(index: int) -> Dictionary:
	if index < 0 or index >= weapons.size():
		return {}
	var wp: Dictionary = weapons[index]
	weapons.remove_at(index)
	if equipped == index:
		equipped = -1
	elif equipped > index:
		equipped -= 1
	changed.emit()
	return wp
