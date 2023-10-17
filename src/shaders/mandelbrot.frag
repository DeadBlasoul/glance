#version 460

#define MANDELBROT 0

#if MANDELBROT
    #extension GL_EXT_control_flow_attributes : require

    layout( push_constant ) uniform constants
    {
        float inv_window_scale;
        float time;
    };
#endif

layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec2 in_tex_coord;

layout(binding = 1) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 out_color;

#define USE_DOUBLE 0

#if USE_DOUBLE
    #define vec2 dvec2
    // #define vec4 dvec4
    #define zoom_t double
#else
    #define zoom_t float
#endif

vec2 comp_mul(vec2 z, vec2 c) {
    vec2 r;

    r.x = z.x * z.x - z.y * z.y;
    r.y = z.x * z.y + z.y * z.x;

    return r + c;
}

void main() {
    const vec4 OUTPUT_COLOR = vec4(0.0, 1, 1, 0.);

#if MANDELBROT
    const int max_iterations = int(time * 10);
    // const int max_iterations = 750;

    const vec2 window_scaling = {1.0, inv_window_scale};
    vec2 xy = uv * 2 - 1;
    xy.y *= -1;

    // const vec2  zoom_point = {-0.761574,-0.0847596};
     const vec2  zoom_point = {-0.77568377,-0.13646737};
    // const vec2   zoom_point = {-0.10109636384562, 0.95628651080914};
    //const vec2   zoom_point = {-1.315180982097868, 0.073481649996795};
    const zoom_t zoom       = 1. / (zoom_t(time) * zoom_t(time));
    // const zoom_t zoom       = 1. / pow(1.2, time);

    vec2 z = vec2(xy * window_scaling * zoom + zoom_point);
    vec2 c = vec2(z);

    for (int i = 0; i < max_iterations; ++i) {
        z = comp_mul(z, c);

        [[branch]]
        if (length(z) > 2.0) {
            zoom_t distance = zoom_t(i) / max_iterations;
            out_color = OUTPUT_COLOR * float(distance);
            return;
        }
    }

    out_color = OUTPUT_COLOR;
#else
    // out_color = vec4((in_color * texture(tex_sampler, in_tex_coord * 1)).rgb, 1.0);
    out_color = vec4(texture(tex_sampler, in_tex_coord * 1).rgb, 1.0);
    // out_color = in_color;
#endif
}
