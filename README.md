# zig-hashring

A small consistent hashing ring implementation

## example

```zig
const std = @import("std");
const hr = @import('zig_hashring"");

pub fn main() !void {
    var ring = try hr.HashRing.init(std.heap.page_allocator, 3);
    defer ring.deinit();

    try ring.addNode("node-a");
    try ring.addNode("node-b");
    try ring.addNode("node-c");

    const owner = ring.getNode("foo:1") orelse return;
    std.debug.print("foo:1 -> {s}\n", .{owner});
}
```
