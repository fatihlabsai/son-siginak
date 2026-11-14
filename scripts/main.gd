extends Node3D
## Ana sahne: gün / gece ışıklandırması ve atmosfer.

const DAY_SKY := Color(0.42, 0.46, 0.48)
const NIGHT_SKY := Color(0.02, 0.025, 0.04)

@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _moon_q: Quaternion


func _ready() -> void:
	_moon_q = Basis.from_euler(Vector3(deg_to_rad(-55.0), deg_to_rad(150.0), 0.0)).get_rotation_quaternion()
	_update_lighting()
	_apply_quality()
	Settings.changed.connect(_apply_quality)
	Audio.stop_world_sounds()
	Audio.play_music("", 2.0)
	Audio.set_ambience("heartbeat", -60.0)


func _apply_quality() -> void:
	Settings.apply_to_world(sun, world_env.environment)


func _process(_delta: float) -> void:
	_update_lighting()


func _update_lighting() -> void:
	var h := Game.hour
	var daylight := smoothstep(5.0, 7.5, h) * (1.0 - smoothstep(18.5, 21.0, h))
	var day_t := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var elevation := lerpf(12.0, 168.0, day_t)
	var sun_q := Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(-35.0), 0.0)).get_rotation_quaternion()
	sun.quaternion = _moon_q.slerp(sun_q, daylight)

	var dusk := 1.0 - absf(daylight - 0.5) * 2.0
	var sun_col := Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.55, 0.3), dusk * 0.7)
	sun.light_color = Color(0.5, 0.6, 0.9).lerp(sun_col, daylight)
	sun.light_energy = lerpf(0.18, 1.15, daylight)

	var env := world_env.environment
	env.background_color = NIGHT_SKY.lerp(DAY_SKY, daylight)
	env.ambient_light_color = Color(0.35, 0.4, 0.6).lerp(Color(0.6, 0.62, 0.6), daylight)
	env.ambient_light_energy = lerpf(0.15, 0.5, daylight)
	env.fog_light_color = env.background_color
	env.fog_density = lerpf(0.018, 0.006, daylight)
	_update_audio(daylight)


var _night_music := false

## Gündüz rüzgâr, gece cırcır böcekleri + kasvetli müzik.
func _update_audio(daylight: float) -> void:
	if is_instance_valid(Game.player) and Game.player.is_dead:
		return
	Audio.set_ambience("wind", lerpf(-14.0, -18.0, daylight))
	Audio.set_ambience("crickets", lerpf(-14.0, -60.0, daylight))
	var night := Game.is_night()
	if night != _night_music:
		_night_music = night
		Audio.play_music("theme" if night else "", 6.0, -14.0)
