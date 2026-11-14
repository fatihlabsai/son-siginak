extends SceneTree
## Oyunun bütün seslerini sıfırdan sentezleyip assets/audio altına WAV olarak yazar.
## Çalıştırma (tek seferlik):
##   Godot_console.exe --headless --path <proje> -s res://tools/generate_audio.gd
## Herhangi bir dosyayı gerçek bir kayıtla değiştirmek istersen aynı isimle üzerine koyman yeterli.

const SR := 22050
const SFX := "res://assets/audio/sfx/"
const MUSIC := "res://assets/audio/music/"

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261114
	for d in [SFX, MUSIC]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))

	for i in 3: _save(SFX + "gunshot_%d.wav" % i, gunshot(), 0.95)
	for i in 6: _save(SFX + "footstep_%d.wav" % i, footstep(), 0.8)
	for i in 3: _save(SFX + "swing_%d.wav" % i, swing(), 0.8)
	for i in 3: _save(SFX + "hit_%d.wav" % i, hit(), 0.9)
	for i in 6: _save(SFX + "groan_%d.wav" % i, groan(), 0.85)
	for i in 3: _save(SFX + "zombie_attack_%d.wav" % i, zombie_attack(), 0.9)
	for i in 2: _save(SFX + "zombie_death_%d.wav" % i, zombie_death(), 0.85)
	for i in 3: _save(SFX + "player_hurt_%d.wav" % i, player_hurt(), 0.85)
	_save(SFX + "pickup_0.wav", pickup(), 0.6)
	_save(SFX + "ammo_pickup_0.wav", ammo_pickup(), 0.7)
	_save(SFX + "eat_0.wav", eat(), 0.8)
	_save(SFX + "drink_0.wav", drink(), 0.8)
	_save(SFX + "bandage_0.wav", bandage(), 0.75)
	_save(SFX + "empty_click_0.wav", empty_click(), 0.8)
	_save(SFX + "flashlight_0.wav", flashlight(), 0.6)
	_save(SFX + "ui_hover_0.wav", ui_hover(), 0.35)
	_save(SFX + "ui_click_0.wav", ui_click(), 0.55)
	_save(SFX + "heartbeat_0.wav", heartbeat(), 0.9)
	_save(SFX + "wind_0.wav", make_loop(wind(12.0), 1.5), 0.7)
	_save(SFX + "crickets_0.wav", make_loop(crickets(8.0), 1.0), 0.5)
	_save(SFX + "fire_0.wav", make_loop(fire(6.0), 1.0), 0.75)
	_save(SFX + "horde_0.wav", horde(), 0.9)
	_save(MUSIC + "theme.wav", theme(), 0.7)
	_save(MUSIC + "death.wav", death_sting(), 0.75)
	print("Ses üretimi tamam.")
	quit()


# ------------------------------------------------------------------
# Ses efektleri
# ------------------------------------------------------------------

func gunshot() -> PackedFloat32Array:
	var n := int(SR * 0.9)
	var out := _buf(n)
	var lp := Biquad.new("lp", 2200.0, 0.7)
	var phase := 0.0
	var tone := rng.randf_range(0.9, 1.1)
	for i in n:
		var t := float(i) / SR
		var crack := _noise() * exp(-t * 70.0)
		var body := lp.process(_noise()) * exp(-t * 10.0)
		var f := (52.0 + 110.0 * exp(-t * 28.0)) * tone
		phase += f / SR
		var thump := sin(TAU * phase) * exp(-t * 13.0)
		out[i] = crack * 0.8 + body * 0.9 + thump * 1.1
	out = reverb(out, 0.35, 0.82)
	return _soft_clip(out, 1.6)


func footstep() -> PackedFloat32Array:
	var n := int(SR * 0.14)
	var out := _buf(n)
	var lp := Biquad.new("lp", rng.randf_range(500.0, 1100.0), 0.8)
	var f0 := rng.randf_range(70.0, 95.0)
	var gain := rng.randf_range(0.7, 1.0)
	for i in n:
		var t := float(i) / SR
		var env := minf(t / 0.003, 1.0) * exp(-t * 42.0)
		out[i] = (lp.process(_noise()) * 0.9 + sin(TAU * f0 * t) * exp(-t * 55.0) * 0.6) * env * gain
	return out


func swing() -> PackedFloat32Array:
	var dur := rng.randf_range(0.22, 0.3)
	var n := int(SR * dur)
	var out := _buf(n)
	var bp := Biquad.new("bp", 400.0, 1.4)
	for i in n:
		var p := float(i) / n
		bp.set_freq(400.0 + 2200.0 * sin(PI * p))
		var env := pow(sin(PI * p), 2.0)
		out[i] = bp.process(_noise()) * env
	return out


func hit() -> PackedFloat32Array:
	var n := int(SR * 0.35)
	var out := _buf(n)
	var bp := Biquad.new("bp", rng.randf_range(1200.0, 1900.0), 1.2)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		phase += (60.0 + 70.0 * exp(-t * 30.0)) / SR
		var thump := sin(TAU * phase) * exp(-t * 22.0)
		var crunch := bp.process(_noise()) * exp(-t * 35.0)
		out[i] = thump * 1.0 + crunch * 1.4
	return reverb(out, 0.15, 0.7)


## Ses tellerini taklit eden basit kaynak-filtre sentezi (zombi/insan sesleri).
func voice(dur: float, f0: float, f1: float, formants: Array, rasp: float, breath: float, wobble: float, attack := 0.15) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := _buf(n)
	var filters: Array[Biquad] = []
	var gains: Array[float] = []
	for fm in formants:
		filters.append(Biquad.new("bp", fm[0], fm[1]))
		gains.append(fm[2])
	var lp := Biquad.new("lp", 3000.0, 0.7)
	var phase := 0.0
	var drift := 0.0
	var rasp_f := rng.randf_range(24.0, 38.0)
	for i in n:
		var t := float(i) / SR
		var p := float(i) / n
		var env := smoothstep(0.0, attack, p) * (1.0 - smoothstep(0.7, 1.0, p))
		drift = drift * 0.999 + _noise() * 0.001
		var f := lerpf(f0, f1, p) * (1.0 + wobble * sin(TAU * 5.3 * t) + drift * 3.0)
		phase += f / SR
		var saw := 2.0 * fmod(phase, 1.0) - 1.0
		var am := 1.0 - rasp * (0.5 + 0.5 * sin(TAU * rasp_f * t + 3.0 * sin(TAU * 7.0 * t)))
		var src := saw * am + _noise() * breath
		var s := 0.0
		for k in filters.size():
			s += filters[k].process(src) * gains[k]
		out[i] = lp.process(s) * env
	return out


func groan() -> PackedFloat32Array:
	var f := rng.randf_range(68.0, 105.0)
	var v := voice(rng.randf_range(0.9, 1.7), f, f * rng.randf_range(0.7, 0.95),
		[[rng.randf_range(380.0, 520.0), 5.0, 1.0], [rng.randf_range(750.0, 950.0), 7.0, 0.55], [2500.0, 9.0, 0.12]],
		rng.randf_range(0.35, 0.65), rng.randf_range(0.25, 0.45), 0.04)
	return reverb(v, 0.2, 0.75)


func zombie_attack() -> PackedFloat32Array:
	var f := rng.randf_range(120.0, 160.0)
	var v := voice(rng.randf_range(0.5, 0.7), f, f * 0.65,
		[[650.0, 4.0, 1.0], [1100.0, 6.0, 0.7], [2600.0, 8.0, 0.25]], 0.75, 0.6, 0.06, 0.08)
	return _soft_clip(reverb(v, 0.15, 0.7), 1.4)


func zombie_death() -> PackedFloat32Array:
	var v := voice(1.5, rng.randf_range(95.0, 115.0), 42.0,
		[[450.0, 5.0, 1.0], [800.0, 7.0, 0.5], [2400.0, 9.0, 0.1]], 0.6, 0.35, 0.08, 0.05)
	# Gırtlaktan gelen fokurtu
	for i in v.size():
		var t := float(i) / SR
		v[i] *= 0.65 + 0.35 * sin(TAU * 11.0 * t)
	return reverb(v, 0.25, 0.78)


func player_hurt() -> PackedFloat32Array:
	var f := rng.randf_range(135.0, 160.0)
	return voice(rng.randf_range(0.22, 0.3), f, f * 0.8,
		[[520.0, 5.0, 1.0], [1450.0, 7.0, 0.5], [2500.0, 9.0, 0.2]], 0.2, 0.35, 0.02, 0.05)


func pickup() -> PackedFloat32Array:
	var n := int(SR * 0.22)
	var out := _buf(n)
	for i in n:
		var t := float(i) / SR
		var a := _tri(660.0 * t) * exp(-t * 30.0)
		var t2 := t - 0.07
		var b := _tri(990.0 * t2) * exp(-t2 * 25.0) if t2 > 0.0 else 0.0
		out[i] = a * 0.7 + b * 0.8
	return out


func ammo_pickup() -> PackedFloat32Array:
	var n := int(SR * 0.3)
	var out := _buf(n)
	var partials := [2100.0, 3170.0, 4420.0, 5310.0]
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for start in [0.0, 0.07, 0.12]:
			var tt: float = t - start
			if tt < 0.0:
				continue
			for k in partials.size():
				s += sin(TAU * partials[k] * (1.0 + start) * tt) * exp(-tt * (40.0 + k * 15.0)) / (k + 1)
		out[i] = s
	return out


func eat() -> PackedFloat32Array:
	var n := int(SR * 0.7)
	var out := _buf(n)
	var bp := Biquad.new("bp", 2400.0, 0.9)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for start in [0.0, 0.2, 0.42]:
			var tt: float = t - start
			if tt >= 0.0:
				s += exp(-tt * 28.0) * (0.6 + 0.4 * _noise())
		out[i] = bp.process(_noise()) * s
	return out


func drink() -> PackedFloat32Array:
	var n := int(SR * 0.75)
	var out := _buf(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var k := fmod(t, 0.24)
		var env := sin(PI * clampf(k / 0.11, 0.0, 1.0)) if k < 0.11 else 0.0
		phase += (180.0 + 380.0 * (k / 0.11)) / SR
		out[i] = sin(TAU * phase) * env * 0.8 + _noise() * env * 0.05
	return out


func bandage() -> PackedFloat32Array:
	var n := int(SR * 0.55)
	var out := _buf(n)
	var hp := Biquad.new("hp", 1500.0, 0.7)
	var grain := 0.0
	for i in n:
		var p := float(i) / n
		if rng.randf() < 0.02:
			grain = rng.randf_range(0.3, 1.0)
		grain *= 0.995
		out[i] = hp.process(_noise()) * grain * sin(PI * p)
	return out


func empty_click() -> PackedFloat32Array:
	var n := int(SR * 0.08)
	var out := _buf(n)
	var hp := Biquad.new("hp", 3000.0, 0.7)
	for i in n:
		var t := float(i) / SR
		out[i] = hp.process(_noise()) * exp(-t * 220.0) + sin(TAU * 2600.0 * t) * exp(-t * 110.0) * 0.5
	return out


func flashlight() -> PackedFloat32Array:
	var n := int(SR * 0.09)
	var out := _buf(n)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * 1900.0 * t) * exp(-t * 160.0)
		var t2 := t - 0.035
		if t2 > 0.0:
			s += sin(TAU * 1500.0 * t2) * exp(-t2 * 160.0) * 0.8
		out[i] = s
	return out


func ui_hover() -> PackedFloat32Array:
	var n := int(SR * 0.05)
	var out := _buf(n)
	for i in n:
		var t := float(i) / SR
		out[i] = sin(TAU * 1250.0 * t) * exp(-t * 100.0)
	return out


func ui_click() -> PackedFloat32Array:
	var n := int(SR * 0.16)
	var out := _buf(n)
	for i in n:
		var t := float(i) / SR
		out[i] = (sin(TAU * 520.0 * t) * 0.7 + sin(TAU * 780.0 * t) * 0.4) * exp(-t * 32.0) + _noise() * exp(-t * 400.0) * 0.3
	return out


func heartbeat() -> PackedFloat32Array:
	var n := int(SR * 1.0)
	var out := _buf(n)
	var lp := Biquad.new("lp", 180.0, 0.7)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for beat in [[0.0, 1.0], [0.28, 0.7]]:
			var tt: float = t - beat[0]
			if tt >= 0.0:
				s += sin(TAU * (48.0 + 30.0 * exp(-tt * 25.0)) * tt) * exp(-tt * 16.0) * beat[1]
		out[i] = lp.process(s)
	return out


func wind(dur: float) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := _buf(n)
	var bp := Biquad.new("bp", 400.0, 0.8)
	var brown := 0.0
	for i in n:
		var t := float(i) / SR
		brown = clampf(brown + _noise() * 0.06, -1.0, 1.0) * 0.998
		bp.set_freq(330.0 + 220.0 * sin(TAU * t / dur * 2.0) + 90.0 * sin(TAU * t / dur * 5.0))
		var amp := 0.6 + 0.4 * sin(TAU * t / dur * 3.0 + 1.0)
		out[i] = bp.process(brown + _noise() * 0.15) * amp
	return out


func crickets(dur: float) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := _buf(n)
	for c in 3:
		var freq := rng.randf_range(3900.0, 4700.0)
		var gain := rng.randf_range(0.4, 1.0)
		var t0 := rng.randf_range(0.0, 0.7)
		while t0 < dur - 0.3:
			for pulse in 3:
				var start := int((t0 + pulse * 0.05) * SR)
				var length := int(0.028 * SR)
				for k in length:
					if start + k < n:
						var env := sin(PI * float(k) / length)
						out[start + k] += sin(TAU * freq * float(k) / SR) * env * gain
			t0 += rng.randf_range(0.55, 0.95)
	return out


func fire(dur: float) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := _buf(n)
	var lp := Biquad.new("lp", 220.0, 0.7)
	var hp := Biquad.new("hp", 1200.0, 0.7)
	var pop := 0.0
	for i in n:
		if rng.randf() < 25.0 / SR:
			pop = rng.randf_range(0.3, 1.0)
		pop *= 0.985
		out[i] = lp.process(_noise()) * 0.5 + hp.process(_noise()) * pop
	return out


func horde() -> PackedFloat32Array:
	var dur := 5.0
	var n := int(SR * dur)
	var out := _buf(n)
	var lp := Biquad.new("lp", 200.0, 1.5)
	var freqs := [55.0, 58.27, 82.41, 87.31]
	var phases := [0.0, 0.0, 0.0, 0.0]
	for i in n:
		var p := float(i) / n
		lp.set_freq(180.0 + 1100.0 * sin(PI * p))
		var s := 0.0
		for k in freqs.size():
			phases[k] += freqs[k] / SR
			s += 2.0 * fmod(phases[k], 1.0) - 1.0
		out[i] = lp.process(s * 0.3) * sin(PI * pow(p, 0.6))
	# Uzaktan gelen inilti kalabalığı
	for g in 5:
		var v := groan()
		var offset := int(rng.randf_range(0.2, 2.8) * SR)
		for k in v.size():
			if offset + k < n:
				out[offset + k] += v[k] * 0.35
	return reverb(out, 0.4, 0.86)


func death_sting() -> PackedFloat32Array:
	var dur := 4.5
	var n := int(SR * dur)
	var out := _buf(n)
	var ratios := [1.0, 2.76, 5.4, 8.93]
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for k in ratios.size():
			s += sin(TAU * 65.4 * ratios[k] * t) * exp(-t * (0.8 + k * 0.9)) / (k + 1)
		var drone := sin(TAU * (65.4 - 12.0 * t / dur) * t) * 0.3 * (1.0 - t / dur)
		out[i] = s + drone
	return reverb(out, 0.45, 0.88)


## Karanlık ambiyans müziği (48 sn, kusursuz döngü).
func theme() -> PackedFloat32Array:
	var loop := 48.0
	var tail := 4.0
	var n := int(SR * (loop + tail))
	var out := _buf(n)
	var chords := [
		[146.83, 174.61, 220.0],    # Dm
		[116.54, 146.83, 174.61],   # Bb
		[98.0, 116.54, 146.83],     # Gm
		[110.0, 138.59, 164.81],    # A
	]
	var lp := Biquad.new("lp", 600.0, 0.9)
	var dphase := [0.0, 0.0, 0.0]
	var dfreq := [73.42, 73.62, 110.0]
	for i in n:
		var t := float(i) / SR
		var tl := fmod(t, loop)
		# Bas drone
		var drone := 0.0
		for k in 3:
			dphase[k] += dfreq[k] / SR
			drone += 2.0 * fmod(dphase[k], 1.0) - 1.0
		lp.set_freq(420.0 + 300.0 * sin(TAU * tl / 24.0))
		var s := lp.process(drone * 0.22)
		# Akor pedi (her 12 sn değişir, yumuşak geçiş)
		var ci := int(tl / 12.0) % 4
		var cp := fmod(tl, 12.0) / 12.0
		var env := smoothstep(0.0, 0.25, cp) * (1.0 - smoothstep(0.8, 1.0, cp))
		for f in chords[ci]:
			s += _tri(f * t) * 0.09 * env
		out[i] = s
	# Çan notaları
	var bell_notes := [293.66, 349.23, 392.0, 440.0, 523.25, 587.33]
	var tb := 1.5
	while tb < loop:
		if rng.randf() < 0.7:
			var f: float = bell_notes[rng.randi() % bell_notes.size()]
			var start := int(tb * SR)
			var length := int(3.0 * SR)
			for k in length:
				if start + k >= n:
					break
				var tt := float(k) / SR
				out[start + k] += (sin(TAU * f * tt) + 0.4 * sin(TAU * f * 2.76 * tt) * exp(-tt * 3.0)) * exp(-tt * 1.6) * 0.12
		tb += 3.0
	out = reverb(out, 0.45, 0.87)
	# Kuyruğu başa ekleyip döngüyü kapat
	var ln := int(SR * loop)
	var result := _buf(ln)
	for i in ln:
		result[i] = out[i]
	for i in n - ln:
		result[i] += out[ln + i]
	return result


# ------------------------------------------------------------------
# Yardımcılar
# ------------------------------------------------------------------

## Sonu başına yumuşakça bindirerek kusursuz döngü yapar.
func make_loop(x: PackedFloat32Array, fade_sec: float) -> PackedFloat32Array:
	var f := int(fade_sec * SR)
	var ln := x.size() - f
	var out := _buf(ln)
	for i in ln:
		out[i] = x[i]
	for i in f:
		var a := float(i) / f
		out[i] = x[i] * a + x[ln + i] * (1.0 - a)
	return out


## Schroeder yankısı: 4 tarak + 2 tümgeçiren filtre.
func reverb(x: PackedFloat32Array, wet: float, fb: float) -> PackedFloat32Array:
	var extra := int(SR * 1.2)
	var n := x.size() + extra
	var dry := _buf(n)
	for i in x.size():
		dry[i] = x[i]
	var wet_sum := _buf(n)
	for d in [557, 593, 641, 677]:
		var buf := _buf(d)
		var idx := 0
		var damp := 0.0
		for i in n:
			var y := buf[idx]
			damp = y * 0.6 + damp * 0.4
			buf[idx] = dry[i] + damp * fb
			idx = (idx + 1) % d
			wet_sum[i] += y
	for d in [113, 277]:
		var buf := _buf(d)
		var idx := 0
		for i in n:
			var bv := buf[idx]
			var y := -wet_sum[i] * 0.5 + bv
			buf[idx] = wet_sum[i] + bv * 0.5
			idx = (idx + 1) % d
			wet_sum[i] = y
	var out := _buf(n)
	for i in n:
		out[i] = dry[i] * (1.0 - wet * 0.5) + wet_sum[i] * 0.25 * wet
	# Sondaki sessizliği kırp
	var last := n - 1
	while last > x.size() and absf(out[last]) < 0.0005:
		last -= 1
	out.resize(last + 1)
	return out


func _soft_clip(x: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	for i in x.size():
		x[i] = tanh(x[i] * drive)
	return x


func _buf(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	return b


func _noise() -> float:
	return rng.randf() * 2.0 - 1.0


func _tri(phase: float) -> float:
	var p := fmod(phase, 1.0)
	return 4.0 * absf(p - 0.5) - 1.0


func _save(path: String, x: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in x:
		m = maxf(m, absf(v))
	var g := peak / m if m > 0.0 else 1.0
	# Başta/sonda tık olmasın diye çok kısa yumuşatma
	var fade := mini(64, x.size() / 4)
	var bytes := PackedByteArray()
	bytes.resize(x.size() * 2)
	for i in x.size():
		var v := x[i] * g
		if i >= x.size() - fade:
			v *= float(x.size() - i) / fade
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	wav.save_to_wav(path)
	print("  ", path.get_file(), "  ", snappedf(x.size() / float(SR), 0.01), " sn")


class Biquad:
	const RATE := 22050.0
	var type := "lp"
	var q := 0.7
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(p_type: String, freq: float, p_q: float) -> void:
		type = p_type
		q = p_q
		set_freq(freq)

	func set_freq(freq: float) -> void:
		var w0 := TAU * clampf(freq, 20.0, RATE * 0.45) / RATE
		var cs := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		match type:
			"lp":
				b0 = (1.0 - cs) / 2.0
				b1 = 1.0 - cs
				b2 = (1.0 - cs) / 2.0
			"hp":
				b0 = (1.0 + cs) / 2.0
				b1 = -(1.0 + cs)
				b2 = (1.0 + cs) / 2.0
			_:
				b0 = alpha
				b1 = 0.0
				b2 = -alpha
		a1 = -2.0 * cs
		a2 = 1.0 - alpha
		b0 /= a0
		b1 /= a0
		b2 /= a0
		a1 /= a0
		a2 /= a0

	func process(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y
