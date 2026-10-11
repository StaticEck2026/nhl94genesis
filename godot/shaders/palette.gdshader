shader_type canvas_item;
// Colours an index texture from tools/extract/assets.py: R = colour index * 17,
// G = palette line * 85, A = drawn. The palette is 16 x 4 CRAM colours (PaletteBank):
// line 0-1 rink, line 2 home team, line 3 away team. Away objects use line 3 where the
// art says line 2 (addframe2: away team, palette 2 -> 3).

uniform sampler2D palette : filter_nearest;
uniform bool away = false;
// Plane cells: colour 0 is transparent on the VDP. Set for the rink's high-priority
// layer, so sprites show through the near glass between its streaks and posts.
uniform bool zero_transparent = false;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	int idx = int(round(t.r * 15.0));
	int line = int(round(t.g * 3.0));
	if (zero_transparent && idx == 0) {
		discard;
	}
	if (away && line == 2) {
		line = 3;
	}
	vec4 c = texelFetch(palette, ivec2(idx, line), 0);
	COLOR = vec4(c.rgb, t.a * COLOR.a);
}
