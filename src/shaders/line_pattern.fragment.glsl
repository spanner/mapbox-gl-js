#include "_prelude_fog.fragment.glsl"
#include "_prelude_lighting.glsl"

uniform lowp float u_device_pixel_ratio;
uniform vec2 u_texsize;
uniform mediump float u_tile_units_to_pixels;
uniform highp vec2 u_trim_offset;

uniform sampler2D u_image;

in vec2 v_normal;
in vec2 v_width2;
in float v_linesofar;
in float v_gamma_scale;
in float v_width;
#ifdef RENDER_LINE_TRIM_OFFSET
in highp vec4 v_uv;
#endif

#ifdef LINE_JOIN_NONE
in vec2 v_pattern_data; // [pos_in_segment, segment_length];
#endif

#pragma mapbox: define lowp vec4 pattern
#pragma mapbox: define lowp float pixel_ratio
#pragma mapbox: define lowp float blur
#pragma mapbox: define lowp float opacity

void main() {
    #pragma mapbox: initialize mediump vec4 pattern
    #pragma mapbox: initialize lowp float pixel_ratio

    #pragma mapbox: initialize lowp float blur
    #pragma mapbox: initialize lowp float opacity

    vec2 pattern_tl = pattern.xy;
    vec2 pattern_br = pattern.zw;

    vec2 display_size = (pattern_br - pattern_tl) / pixel_ratio;

    float aspect = display_size.y / v_width;
    float pattern_size_x = display_size.x / (u_tile_units_to_pixels * aspect);

    // Calculate the distance of the pixel from the line in pixels.
    float dist = length(v_normal) * v_width2.x;

    // Calculate the antialiasing fade factor. This is either when fading in
    // the line in case of an offset line (v_width2.y) or when fading out
    // (v_width2.x)
    float blur2 = (blur + 1.0 / u_device_pixel_ratio) * v_gamma_scale;
    float alpha = clamp(min(dist - (v_width2.y - blur2), v_width2.x - dist) / blur2, 0.0, 1.0);

    float pattern_x = v_linesofar / pattern_size_x;

    float x = fract(pattern_x);
    float y = 0.5 * v_normal.y + 0.5;

    vec2 texel_size = 1.0 / u_texsize;

    vec2 tl = pattern_tl * texel_size - texel_size;
    vec2 br = pattern_br * texel_size + texel_size;
    vec2 pos = mix(tl, br, vec2(x, y));
    float lod_pos_x = mix(tl.x, br.x, pattern_x);
    vec4 color = textureLodCustom(u_image, pos, vec2(lod_pos_x, pos.y));

#ifdef RENDER_LINE_TRIM_OFFSET
    // v_uv[2] and v_uv[3] are specifying the original clip range that the vertex is located in.
    highp float start = v_uv[2];
    highp float end = v_uv[3];
    highp float trim_start = u_trim_offset[0];
    highp float trim_end = u_trim_offset[1];
    // v_uv.x is the relative prorgress based on each clip. Calculate the absolute progress based on
    // the whole line by combining the clip start and end value.
    highp float line_progress = (start + (v_uv.x) * (end - start));
    // Mark the pixel to be transparent when:
    // 1. trim_offset range is valid
    // 2. line_progress is within trim_offset range

    // Nested conditionals fixes the issue
    // https://github.com/mapbox/mapbox-gl-js/issues/12013
    if (trim_end > trim_start) {
        if (line_progress <= trim_end && line_progress >= trim_start) {
            color = vec4(0, 0, 0, 0);
        }
    }
#endif

#ifdef LINE_JOIN_NONE
    // v_pattern_data = { x = pos_in_segment, y = segment_length }
    // v_linesofar and v_pattern_data.x is offset in vertex shader based on segment overlap (v_pattern_data.x can be
    // negative). v_pattern_data.y is not modified because we can't access overlap info for other end of the segment.
    // All units are tile units.
    // Distance from segment start point to start of first pattern instance
    float segment_phase = pattern_size_x - mod((v_linesofar - v_pattern_data.x), pattern_size_x);
    // Step is used to check if we can fit an extra pattern cycle when considering the segment overlap at the corner
    float visible_start = segment_phase - step(pattern_size_x * 0.5, segment_phase) * pattern_size_x;
    float visible_end = floor((v_pattern_data.y - segment_phase) / pattern_size_x) * pattern_size_x + segment_phase;
    visible_end += step(pattern_size_x * 0.5, v_pattern_data.y - visible_end) * pattern_size_x;

    if (v_pattern_data.x < visible_start || v_pattern_data.x >= visible_end) {
        color = vec4(0.0);
    }
#endif

#ifdef LIGHTING_3D_MODE
    color = apply_lighting_ground(color);
#endif
#ifdef FOG
    color = fog_dither(fog_apply_premultiplied(color, v_fog_pos));
#endif

    color *= (alpha * opacity);

#ifdef INDICATOR_CUTOUT
    color = applyCutout(color);
#endif

    glFragColor = color;

#ifdef OVERDRAW_INSPECTOR
    glFragColor = vec4(1.0);
#endif

    HANDLE_WIREFRAME_DEBUG;
}
