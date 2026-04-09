const std = @import("std");

const Node = struct {
    name: []const u8,
};

const Weight = struct {
    hash: u64,
    node_index: usize,
};

const HashRingError = error{DuplicateNode};

fn lessThan(_: void, a: Weight, b: Weight) bool {
    return a.hash < b.hash;
}

pub const HashRing = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    weights: std.ArrayList(Weight),

    pub fn init(a: std.mem.Allocator) HashRing {
        return .{
            .alloc = a,
            .nodes = std.ArrayList(Node).empty,
            .weights = std.ArrayList(Weight).empty,
        };
    }

    pub fn deinit(self: *HashRing) void {
        for (self.nodes.items) |node| {
            self.alloc.free(node.name);
        }
        self.nodes.deinit(self.alloc);
        self.weights.deinit(self.alloc);
    }

    fn hasNode(self: *const HashRing, node: []const u8) bool {
        for (self.nodes.items) |n| {
            if (std.mem.eql(u8, n.name, node)) return true;
        }
        return false;
    }

    pub fn addNode(self: *HashRing, node: []const u8) !void {
        if (self.hasNode(node)) return HashRingError.DuplicateNode;

        const copy_node = try self.alloc.dupe(u8, node);
        errdefer self.alloc.free(copy_node);
        try self.nodes.append(
            self.alloc,
            .{
                .name = copy_node,
            },
        );
        errdefer _ = self.nodes.pop();
        const w: Weight = .{
            .hash = hashBytes(copy_node),
            .node_index = self.nodes.items.len - 1,
        };
        try self.weights.append(self.alloc, w);

        std.sort.block(Weight, self.weights.items, {}, lessThan);
    }

    pub fn getNode(self: *const HashRing, key: []const u8) ?[]const u8 {
        if (self.weights.items.len == 0) return null;

        const key_hash = hashBytes(key);

        var left: usize = 0;
        var right: usize = self.weights.items.len;
        while (left < right) {
            const mid = left + (right - left) / 2;
            if (self.weights.items[mid].hash < key_hash) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        const idx: usize = if (left == self.weights.items.len) 0 else left;
        return self.nodes.items[self.weights.items[idx].node_index].name;
    }

    pub fn removeNode(self: *HashRing, node: []const u8) !void {
        var new_nodes = std.ArrayList(Node).empty;
        errdefer {
            for (new_nodes.items) |n| self.alloc.free(n.name);
            new_nodes.deinit(self.alloc);
        }
        var new_weights = std.ArrayList(Weight).empty;
        errdefer new_weights.deinit(self.alloc);
        for (self.nodes.items) |n| {
            if (std.mem.eql(u8, n.name, node)) continue;
            const copy_name = try self.alloc.dupe(u8, n.name);
            errdefer self.alloc.free(copy_name);

            try new_nodes.append(self.alloc, .{ .name = copy_name });
            errdefer _ = new_nodes.pop();

            const w: Weight = .{
                .hash = hashBytes(node),
                .node_index = new_nodes.items.len - 1,
            };
            try new_weights.append(self.alloc, w);
        }
        std.sort.block(Weight, new_weights.items, {}, struct {
            fn lessThan(_: void, a: Weight, b: Weight) bool {
                return a.hash < b.hash;
            }
        }.lessThan);
        for (self.nodes.items) |n| {
            self.alloc.free(n.name);
        }
        self.nodes.deinit(self.alloc);
        self.weights.deinit(self.alloc);
        self.nodes = new_nodes;
        self.weights = new_weights;
    }
};

fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

pub fn main() void {}

const testing = std.testing;

test "addNode adds nodes" {
    var ring = HashRing.init(testing.allocator);
    defer ring.deinit();

    try ring.addNode("node-a");
    try ring.addNode("node-b");
    try ring.addNode("node-c");

    try testing.expectEqual(@as(usize, 3), ring.nodes.items.len);
    try testing.expectEqual(@as(usize, 3), ring.weights.items.len);

    for (ring.weights.items[0 .. ring.weights.items.len - 1], 0..) |w, i| {
        try testing.expect(w.hash < ring.weights.items[i + 1].hash);
    }

    try testing.expectError(HashRingError.DuplicateNode, ring.addNode("node-a"));
    try testing.expectEqual(@as(usize, 3), ring.weights.items.len);
}

test "addNode copies node name" {
    var ring = HashRing.init(testing.allocator);
    defer ring.deinit();

    var buf = [_]u8{ 'n', 'o', 'd', 'e', '-', 'a' };
    try ring.addNode(buf[0..]);

    buf[5] = 'b';
    try testing.expectEqualStrings("node-a", ring.nodes.items[0].name);
    try testing.expectEqualStrings("node-b", buf[0..]);
}

test "getNode returns nodes or null" {
    var ring = HashRing.init(testing.allocator);
    defer ring.deinit();

    try testing.expect(ring.getNode("foo:1") == null);

    try ring.addNode("node-a");
    try testing.expectEqualStrings("node-a", ring.getNode("foo:1").?);
    try testing.expectEqualStrings("node-a", ring.getNode("foo:2").?);

    try ring.addNode("node-b");
    try ring.addNode("node-c");

    const n1 = ring.getNode("bar:3").?;
    const n2 = ring.getNode("bar:3").?;
    try testing.expectEqualStrings(n1, n2);
}

test "weights are sorted" {
    var ring = HashRing.init(testing.allocator);
    defer ring.deinit();

    try ring.addNode("node-b");
    try ring.addNode("node-c");
    try ring.addNode("node-a");

    var i: usize = 1;
    while (i < ring.weights.items.len) : (i += 1) {
        try testing.expect(ring.weights.items[i - 1].hash <= ring.weights.items[i].hash);
    }
}

test "removeNode removes nodes" {
    var ring = HashRing.init(testing.allocator);
    defer ring.deinit();

    try ring.addNode("node-a");
    try ring.addNode("node-b");
    try ring.addNode("node-c");

    try ring.removeNode("node-b");

    try testing.expectEqual(@as(usize, 2), ring.nodes.items.len);
    try testing.expectEqual(@as(usize, 2), ring.weights.items.len);

    for (ring.nodes.items) |n| {
        try testing.expect(!std.mem.eql(u8, n.name, "node-b"));
    }

    try ring.removeNode("node-z");
    try testing.expectEqual(@as(usize, 2), ring.nodes.items.len);

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&buf, "foo:{d}", .{i});
        const got = ring.getNode(key).?;
        try testing.expect(!std.mem.eql(u8, got, "node-b"));
    }
}
