const std = @import("std");
const lib = @import("root.zig");

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var ring = try lib.HashRing.init(alloc, 3);
    defer ring.deinit();

    try ring.addNode("node-a");
    try ring.addNode("node-b");

    const node = ring.getNode("foo:1") orelse return;
    std.debug.print("foo:1 -> {s}\n", .{node});
}
