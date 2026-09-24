// One shader for all 64 pieces. Colour and spots are the only two properties
// expressed in the material; shape, size, hollowness and spin all live in the
// mesh / node instead.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.90, 0.90, 0.88, 1.0);
uniform vec4 spot_color : source_color = vec4(0.09, 0.15, 0.45, 1.0);
// 0.0 = plain, 1.0 = spotted. Keeps one shader serving both variants.
uniform float spot_strength : hint_range(0.0, 1.0) = 0.0;
// Average spacing between spots, in local units.
uniform float spot_scale = 0.16;
uniform float spot_radius : hint_range(0.05, 0.5) = 0.28;
uniform float spot_softness : hint_range(0.0, 0.2) = 0.045;
// How much each spot may wander from its cell centre. 0.0 is a rigid grid.
uniform float spot_jitter : hint_range(0.0, 1.0) = 1.0;
// Fraction of cells that actually carry a spot - gaps break up the regularity.
uniform float spot_density : hint_range(0.0, 1.0) = 0.78;
// Spot radius varies by this much either way.
uniform float spot_size_variation : hint_range(0.0, 1.0) = 0.45;
uniform float piece_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float piece_specular : hint_range(0.0, 1.0) = 0.5;

// Model-space position and normal, so the pattern stays welded to the piece no
// matter how the node is scaled, placed or spun.
varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

vec2 hash22(vec2 p) {
	vec2 h = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(h) * 43758.5453123);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Scattered spots: one candidate per lattice cell, shoved off-centre by a hash
// of the cell so no grid shows through. The 3x3 sweep is what lets a spot
// straddle a cell boundary instead of being clipped by it.
float spot_field(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 offset = uv - cell;
	float coverage = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 id = cell + neighbor;
			if (hash12(id + 19.37) > spot_density) {
				continue;
			}
			vec2 centre = neighbor + mix(vec2(0.5), hash22(id), spot_jitter);
			float radius = spot_radius * (1.0 + spot_size_variation * (hash12(id + 5.11) * 2.0 - 1.0));
			float distance_to_spot = length(centre - offset);
			coverage = max(coverage,
				1.0 - smoothstep(radius - spot_softness, radius + spot_softness, distance_to_spot));
		}
	}
	return coverage;
}

void fragment() {
	// Triplanar projection: the spots stay round on a cube face, a frame bar
	// and a sphere alike, instead of being sliced by a single wrapped mapping.
	vec3 weight = pow(abs(v_normal), vec3(6.0));
	weight /= (weight.x + weight.y + weight.z);

	vec3 p = v_local / spot_scale;
	float spots = spot_field(p.yz) * weight.x
		+ spot_field(p.xz) * weight.y
		+ spot_field(p.xy) * weight.z;

	ALBEDO = mix(base_color.rgb, spot_color.rgb, spots * spot_strength);
	ROUGHNESS = piece_roughness;
	SPECULAR = piece_specular;
}
