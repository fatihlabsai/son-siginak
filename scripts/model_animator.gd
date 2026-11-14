class_name ModelAnimator
extends RefCounted
## Tripo 3D'den (veya başka yerden) gelen GLB modelin içindeki AnimationPlayer'ı bulur
## ve animasyon isimlerini anahtar kelimelere göre eşler.
## Örn. "Armature|Walk_Cycle" -> "walk", "zombie_attack_01" -> "attack".
## Böylece modeli değiştirdiğinde kod değiştirmen gerekmez.

const KEYWORDS := {
	"idle": ["idle", "breath"],
	"walk": ["walk"],
	"run": ["run", "sprint", "jog"],
	"attack": ["attack", "punch", "slash", "swing", "bite", "melee", "lunge"],
	"shoot": ["pistol", "shoot", "fire", "gun"],
	"hurt": ["hurt", "damage", "hit", "react"],
	"death": ["death", "die", "dead", "dying", "fall", "defeat"],
}
const LOOPING := ["idle", "walk", "run"]
const ONE_SHOTS := ["attack", "shoot", "hurt", "death"]

var anim_player: AnimationPlayer
var base_speed := 1.0
var _map := {}
var _current := ""


func setup(model_root: Node) -> void:
	var found := model_root.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	anim_player = found[0] as AnimationPlayer
	var names := anim_player.get_animation_list()
	for key in KEYWORDS:
		for anim_name in names:
			var low := String(anim_name).to_lower()
			var matched := false
			for kw in KEYWORDS[key]:
				if low.contains(kw):
					matched = true
					break
			if matched:
				_map[key] = anim_name
				break
	for key in LOOPING:
		if _map.has(key):
			var anim := anim_player.get_animation(_map[key])
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
	if not _map.has("run") and _map.has("walk"):
		_map["run"] = _map["walk"]


func describe() -> String:
	if anim_player == null:
		return "(AnimationPlayer bulunamadı)"
	return "eşleşen: %s | tümü: %s" % [str(_map), str(anim_player.get_animation_list())]


func play(key: String, blend := 0.2) -> void:
	if anim_player == null or not _map.has(key):
		return
	if _current == key and anim_player.is_playing():
		return
	anim_player.play(_map[key], blend)
	_current = key


## Tek seferlik animasyon (saldırı, ölüm...). Animasyon yoksa false döner,
## böylece çağıran taraf yer tutucu (placeholder) efekt oynatabilir.
func play_once(key: String, blend := 0.1) -> bool:
	if anim_player == null or not _map.has(key):
		return false
	anim_player.speed_scale = base_speed
	if anim_player.current_animation == _map[key]:
		anim_player.seek(0.0, true)
	else:
		anim_player.play(_map[key], blend)
	_current = key
	return true


## Animasyon hızını karakterin gerçek hızına göre ayarlar (ayak kaymasını azaltır).
## base_speed: modele özgü sabit çarpan (zombilerde rastgele çeşitlilik için).
func set_speed(speed_scale: float) -> void:
	if anim_player:
		anim_player.speed_scale = speed_scale * base_speed


func is_busy() -> bool:
	return anim_player != null and _current in ONE_SHOTS and anim_player.is_playing()
