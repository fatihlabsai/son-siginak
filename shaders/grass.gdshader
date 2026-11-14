shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Çim öbekleri: iki çapraz dörtgen üzerinde kodla çizilen yapraklar, rüzgârda sallanır.
// Örnek rengi (MultiMesh instance color) öbeğin tonunu belirler.

uniform vec3 base_col : source_color = vec3(0.12, 0.15, 0.07);
uniform float wind_strength = 0.1;
uniform float blades = 7.0;

varying float seed;
varying vec3 tint;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	seed = hash(origin.x * 12.9898 + origin.z * 78.233);
	tint = COLOR.rgb;
	float h = 1.0 - UV.y;
	float sway = sin(TIME * 1.6 + origin.x * 0.3 + origin.z * 0.23) * wind_strength * h * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	float h = 1.0 - UV.y;
	float u = UV.x * blades;
	float idx = floor(u);
	float r = hash(idx * 3.17 + seed * 91.7);
	float blade_h = 0.45 + 0.55 * r;
	float center = 0.5 + (hash(idx + seed * 13.1) - 0.5) * 0.5 + h * (r - 0.5) * 0.6;
	float dist = abs(fract(u) - center) * 2.0;
	float width = (1.0 - h / blade_h) * 0.85;
	if (h > blade_h || dist > width) {
		discard;
	}
	vec3 col = mix(base_col, tint, smoothstep(0.0, 0.9, h / blade_h));
	col *= 0.85 + 0.3 * r;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	// Yumuşak ışık: yaprakları yukarı bakıyormuş gibi aydınlat
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
