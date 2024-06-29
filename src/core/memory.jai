#if OS == .WINDOWS {
    #scope_export

    MemoryAllocationType :: enum_flags u32 {
        reserve :: Windows.MEM_RESERVE;
        commit  :: Windows.MEM_COMMIT;
    }

    MemoryProtection :: enum_flags u32 {
        rw        :: Windows.PAGE_READWRITE;
        no_access :: Windows.PAGE_NOACCESS;
    }

    // @Todo: proper return value
    os_allocate_memory :: (
        base            : *void,
        size            : s64,
        alignment       : s64 = 0,
        protection      : MemoryProtection,
        allocation_type : MemoryAllocationType
    ) -> []u8 {
        assert(base == null || alignment == 0, "MEM_ADDRESS_REQUIREMENTS is requied to be be filled with 0's when base is not null");
        assert(alignment == 0 || is_power_of_2(alignment));

        address_requirements := MEM_ADDRESS_REQUIREMENTS.{
            LowestStartingAddress = null,
            HighestEndingAddress  = null,
            Alignment             = xx alignment,
        };

        param := MEM_EXTENDED_PARAMETER.{
            Type    = .MemExtendedParameterAddressRequirements,
            Pointer = *address_requirements,
        };

        memory_base := VirtualAlloc2(
            Process            = null,
            BaseAddress        = base,
            Size               = xx size,
            AllocationType     = xx allocation_type,
            PageProtection     = xx protection,
            ExtendedParameters = *param,
            ParameterCount     = 1
        );

        if memory_base then return .{size, xx memory_base};
                       else return .{   0,           null};
    }

    // @Todo: proper return value
    os_protect_memory :: (base : *void, size : s64, protection : MemoryProtection) -> (success : bool, effective_range : []u8) #deprecated "does not return system error" {
        system_info : Windows.SYSTEM_INFO = ---;
        Windows.GetSystemInfo(*system_info);

        //
        // Apply protection granularity.
        //

        page_size : s64 = system_info.dwPageSize;

        base &= ~(page_size - 1);
        size  = (size + page_size - 1) & ~(page_size - 1);

        if size == 0 then size = page_size;

        //
        // Protect effective range.
        //

        old_protect : Windows.DWORD;
        return success         = cast(bool) Windows.VirtualProtect(base, cast(u64) size, cast(u32) protection, *old_protect),
               effective_range = .{size, base};
    }

    // @Todo: proper return value
    os_release_memory :: (memory : []u8) -> bool {
        return cast(bool) Windows.VirtualFree(memory.data, cast(u64) memory.count, Windows.MEM_RELEASE);
    }

    // @Todo: proper return value
    os_release_memory :: (base : *void, size : s64) -> bool {
        assert(size > 0);
        return cast(bool) Windows.VirtualFree(base, cast(u64) size, Windows.MEM_RELEASE);
    }

    os_release_memory :: (data : *$T) -> bool {
        return cast(bool) Windows.VirtualFree(data, size_of(T), Windows.MEM_RELEASE);
    }

    #scope_file

    Windows :: #import "Windows";
    mincore :: #system_library,no_dll "mincore";

    // @Todo: create Windows module
    VirtualAlloc2 :: (
        Process             : Windows.HANDLE,          // [in, optional]
        BaseAddress         : *void,                   // [in, optional]
        Size                : Windows.SIZE_T,          // [in]
        AllocationType      : u32,                     // [in]
        PageProtection      : u32,                     // [in]
        ExtendedParameters  : *MEM_EXTENDED_PARAMETER, // [in, out, optional]
        ParameterCount      : u32                      // [in]
    ) -> *void #foreign mincore;

    // @Todo: create Windows module
    MEM_ADDRESS_REQUIREMENTS :: struct {
        LowestStartingAddress : *void;
        HighestEndingAddress  : *void;
        Alignment             : Windows.SIZE_T;
    }

    // @Todo: create Windows module
    MEM_EXTENDED_PARAMETER :: struct {
        Type : MEM_EXTENDED_PARAMETER_TYPE;

        union {
            ULong64 : u64;
            Pointer : *void;
            Size    : Windows.SIZE_T;
            Handle  : Windows.HANDLE;
            ULong   : u32;
        };
    }

    MEM_EXTENDED_PARAMETER_TYPE :: enum u64 {
        MemExtendedParameterInvalidType         :: 0;
        MemExtendedParameterAddressRequirements :: 1;
        MemExtendedParameterNumaNode            :: 2;
        MemExtendedParameterPartitionHandle     :: 3;
        MemExtendedParameterUserPhysicalHandle  :: 4;
        MemExtendedParameterAttributeFlags      :: 5;
        MemExtendedParameterImageMachine        :: 6;
        MemExtendedParameterMax;
    }

    #import "core/assert";
    #import "core/math";
}