#scope_file

Vector2 :: Math.Vector2;
Vector3 :: Math.Vector3;
Matrix4 :: Math.Matrix4;

#import "Math";

#scope_module

Vertex :: struct {
    pos       : Vector2;
    color     : Vector3;
    tex_coord : Vector2;
}

get_vertex_binding_description :: () -> VkVertexInputBindingDescription {
    return .{
        binding   = 0,
        stride    = size_of(Vertex),
        inputRate = .VK_VERTEX_INPUT_RATE_VERTEX,
    };
}

get_vertex_attribute_descriptions :: () -> [3]VkVertexInputAttributeDescription {
    // @Todo: some sort of reflection magic in future?
    return .[
        .{binding = 0, location = 0, format = .VK_FORMAT_\  R32G32_SFLOAT, offset = cast(u32) offset_of(Vertex, #code pos      )},
        .{binding = 0, location = 1, format = .VK_FORMAT_R32G32B32_SFLOAT, offset = cast(u32) offset_of(Vertex, #code color    )},
        .{binding = 0, location = 2, format = .VK_FORMAT_\  R32G32_SFLOAT, offset = cast(u32) offset_of(Vertex, #code tex_coord)},
    ];
}

UniformBufferObject :: struct {
    model : Matrix4 #align 16;
    view  : Matrix4 #align 16;
    proj  : Matrix4 #align 16;
}

perspective_lh :: (fov : float, aspect_ratio : float, near : float, far : float) -> Matrix4 {
    tan :: (a : float) -> float { return Math.sin(a) / Math.cos(a); }

    return .{
        1.0 / (aspect_ratio * tan(fov / 2.0)),                0,                   0,                           0,
                                            0, 1 / tan(fov / 2),                   0,                           0,
                                            0,                0, -far / (near - far), (far * near) / (near - far),
                                            0,                0,                   1,                           0,
    };
}

look_at_matrix_lh :: (eye : Vector3, target : Vector3, up_vector : Vector3) -> Matrix4 {
    forward := Math.normalize(target - eye);
    right   := Math.cross_product(up_vector, forward);
    up      := Math.cross_product(forward, right);

    translation_x := Math.dot_product(eye, right);
    translation_y := Math.dot_product(eye, up);
    translation_z := Math.dot_product(eye, forward);

    return .{
          right.x,   right.y,   right.z, -translation_x,
             up.x,      up.y,      up.z, -translation_y,
        forward.x, forward.y, forward.z, -translation_z,
                0,         0,         0,              1,
    };
}
