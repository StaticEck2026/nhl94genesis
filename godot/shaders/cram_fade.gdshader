shader_type canvas_item;
// cramfade (L44101) as a post-process. Every colour on screen is a CRAM colour: three
// 3-bit levels, drawn as level / 7. A fade moves each component one level at a time
// toward its target, red, green and blue in turn:
//   from black toward the screen: level = min(target, steps_in)
//   from the screen toward black: level = max(level - steps_out, 0)
// steps_* hold the steps each component has taken so far (x red, y green, z blue).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 steps_in = vec3(8.0);
uniform vec3 steps_out = vec3(0.0);

void fragment() {
	vec3 level = floor(texture(screen_tex, SCREEN_UV).rgb * 7.0 + 0.5);
	level = max(min(level, steps_in) - steps_out, vec3(0.0));
	COLOR = vec4(level / 7.0, 1.0);
}
