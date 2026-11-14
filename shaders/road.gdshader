shader_type spatial;
render_mode diffuse_burley;
// Eski asfalt: renk dalgalanması, yamalar, çatlaklar, kenarlara doğru toprak.

uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D crack_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 asphalt : source_color = vec3(0.13, 0.13, 0.14);
uniform vec3 asphalt_worn : source_color = vec3(0.18, 0.18, 0.18);
uniform vec3 edge_dirt : source_color = vec3(0.32, 0.27, 0.2);
uniform int axis = 0;            // 0: yol Z boyunca uzanır, 1: X boyunca
uniform float half_width = 4.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float d = texture(detail_noise, p * 0.7).r;
	float d2 = texture(detail_noise, p * 0.07).r;
	float d3 = texture(detail_noise, p * 2.3).r;

	vec3 col = mix(asphalt, asphalt_worn, smoothstep(0.2, 1.0, d2));
	col *= 0.9 + 0.22 * d3;

	// Çatlaklar: hücresel gürültünün hücre sınırları
	float c = texture(crack_noise, p * 0.11).r;
	float crack = (1.0 - smoothstep(0.0, 0.035, c)) * smoothstep(0.42, 0.62, d2);
	col = mix(col, vec3(0.04), crack * 0.85);

	// Kenarlarda dökülen asfalt / toprak (kavşakta diğer yolun içinde kenar yok)
	float across = axis == 0 ? abs(wpos.x) : abs(wpos.z);
	float other = axis == 0 ? abs(wpos.z) : abs(wpos.x);
	float edge = smoothstep(half_width * 0.62, half_width * 0.98, across + (d - 0.5) * 1.2);
	edge *= smoothstep(half_width * 0.9, half_width * 1.1, other);
	col = mix(col, edge_dirt * (0.75 + 0.4 * d), edge * 0.9);

	ALBEDO = col;
	ROUGHNESS = 0.92 - crack * 0.15;
	NORMAL_MAP = texture(normal_noise, p * 0.45).rgb;
	NORMAL_MAP_DEPTH = 0.45 + crack * 1.5;
}
