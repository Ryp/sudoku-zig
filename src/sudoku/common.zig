// I'm putting stuff I couldn't find a better place for here
const std = @import("std");

pub const u32_2 = @Vector(2, u32);
pub const i32_2 = @Vector(2, i32);

// I borrowed this name from HLSL
pub fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    std.debug.assert(type_info.vector.child == bool);
    std.debug.assert(type_info.vector.len > 1);

    return @reduce(.And, vector);
}
