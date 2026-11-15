class_name Searchable
extends Node3D
## Aranabilir yer: ev kapısı, araba, çöp konteyneri, sandık.
## Oyuncu yanında E'yi basılı tutunca arama çubuğu dolar; bu sırada ses çıkar.
## Bir kez aranınca boşalır.

@export var table := "crate"
@export var label := "Ara"
@export var reach := 1.6
## true: açılınca "Hiçbir şey bulamadın" demez (kapı gibi)
@export var silent := false

signal opened

var searched := false
var search_time := 2.0
var noise_radius := 5.0


func _ready() -> void:
	add_to_group("searchables")
	var t: Dictionary = Items.LOOT.get(table, {})
	search_time = float(t.get("time", 2.0))
	noise_radius = float(t.get("noise", 5.0))


func prompt_text() -> String:
	return "%s  (basılı tut)" % label


## Aramayı bitirir ve bulunanları döndürür: [[id, adet], ...]
func open() -> Array:
	searched = true
	remove_from_group("searchables")
	opened.emit()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return Items.roll(table, rng, Settings.diff("loot"))


## Kayıttan yükleme: aranmış olarak işaretle (kapı açık kalsın vb.)
func restore_searched() -> void:
	searched = true
	remove_from_group("searchables")
	opened.emit()
