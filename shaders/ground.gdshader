shader_type spatial;
render_mode diffuse_burley;
// Zemin: kuru/yeşil çim, toprak lekeleri, çamur, kamp çevresinde çiğnenmiş toprak.
// Dünya koordinatıyla örneklenir; tekrar eden desen görünmez.

uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_green : source_color = vec3(0.20, 0.26, 0.12);
uniform vec3 grass_dry : source_color = vec3(0.38, 0.36, 0.21);
uniform vec3 dirt : source_color = vec3(0.34, 0.27, 0.19);
uniform vec3 mud : source_color = vec3(0.19, 0.15, 0.11);
uniform vec2 camp_center = vec2(0.0);
uniform float camp_radius = 10.0;
uniform float macro_scale = 0.011;
uniform float detail_scale = 0.32;
uniform float normal_scale = 0.16;
uniform float normal_strength = 0.7;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float m1 = texture(macro_noise, p * macro_scale).r;
	float m2 = texture(macro_noise, p * macro_scale * 2.7 + vec2(0.37, 0.71)).r;
	float d = texture(detail_noise, p * detail_scale).r;
	float d2 = texture(detail_noise, p * detail_scale * 3.9 + vec2(0.13, 0.5)).r;
	float d3 = texture(detail_noise, p * detail_scale * 0.21).r;

	vec3 grass = mix(grass_green, grass_dry, smoothstep(0.3, 0.7, m2 + (d3 - 0.5) * 0.4));
	float dirt_mask = smoothstep(0.56, 0.68, m1 + (d - 0.5) * 0.22);
	float camp = 1.0 - smoothstep(camp_radius * 0.55, camp_radius * 1.2, length(p - camp_center) + (d3 - 0.5) * 6.0);
	dirt_mask = max(dirt_mask, camp);

	vec3 soil = mix(dirt, mud, smoothstep(0.45, 0.85, d2 * 0.6 + m2 * 0.4));
	vec3 col = mix(grass, soil, dirt_mask);
	col *= 0.78 + 0.44 * d;
	col *= 0.9 + 0.2 * d2;

	ALBEDO = col;
	ROUGHNESS = mix(0.97, 0.88, dirt_mask);
	NORMAL_MAP = texture(normal_noise, p * normal_scale).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
