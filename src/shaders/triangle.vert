#version 460

layout(binding = 0) uniform UniformBufferObject {
    layout(row_major) mat4 model;
    layout(row_major) mat4 view;
    layout(row_major) mat4 proj;
} ubo;

layout(location = 0) in vec2 in_position;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_tex_coord;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_color;
layout(location = 2) out vec2 out_tex_coord;

void main()
{
    mat4 mvp = mat4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
    mvp *= ubo.proj;
    mvp *= ubo.view;
    mvp *= ubo.model;

    gl_Position = mvp * vec4(in_position, 0, 1.0);

    out_color     = vec4(in_color, 0.0);
    out_uv        = (in_position + 1.0) * 0.5;
    out_tex_coord = in_tex_coord;
}
