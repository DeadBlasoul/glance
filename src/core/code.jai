code_to_string :: ($code : Code) -> string #must {
    Basic.assert(#compile_time, "This function should be run only at compile time.");

    builder : Basic.String_Builder;
    builder.allocator = Basic.temporary_allocator;

    root := Compiler.compiler_get_nodes(code);
    Program_Print.print_expression(*builder, root);

    return Basic.builder_to_string(*builder);
}

offset_of :: ($T: Type, $identifier : Code) -> s64 #must #expand {
    base : *T = null;
    return cast(*u8) (*base.#insert identifier) - cast(*u8) (base);
}
