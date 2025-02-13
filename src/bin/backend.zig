const std = @import("std");
const Rir = @import("Rir");
const Rvm = @import("Rvm");
const RbcGenerator = @import("RbcGenerator");

const log = std.log.scoped(.rir_main);

pub const std_options = std.Options{
    .log_level = .debug,
};

test {
    std.debug.print("backend-test\n", .{});
    try main();
}

const n: i64 = 12;
const expected: i64 = calc: {
    break :calc nativeFib(n);
};

fn nativeFib(i: i64) i64 {
    return if (i < 2) i else nativeFib(i - 1) + nativeFib(i - 2);
}

pub fn main() !void {
    log.info("starting rir", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    log.info("created gpa", .{});

    var ir = try Rir.init(allocator);
    defer ir.deinit();

    log.info("created ir {}", .{ir});

    const module = try ir.createModule(try ir.internName("test-module"));

    log.info("created module {}", .{module});

    const Nil = try ir.createTypeFromNative(void, null, null);
    const S32 = try ir.createTypeFromNative(i32, null, null);

    log.info("created S32 {}", .{S32});

    { // struct
        const Foo = try ir.createType(try ir.internName("Foo"), Rir.TypeInfo{ .Struct = Rir.StructTypeInfo{
            .fields = &.{
                Rir.StructField{
                    .name = try ir.internName("x"),
                    .type = S32,
                },
                Rir.StructField{
                    .name = try ir.internName("y"),
                    .type = S32,
                },
            },
        } });

        log.info("created Foo {}", .{Foo});

        const FOO = try module.createGlobal(try ir.internName("FOO"), Foo);

        FOO.mutability = .mutable;
        FOO.initial_value = try ir.allocator.dupe(u8, &.{
            0x01, 0x01, 0x00, 0x00, // x
            0x01, 0x00, 0x00, 0x00, // y
        });
    }

    log.info("struct test complete", .{});

    { // incr
        const one = try module.createGlobal(try ir.internName("one"), S32);
        try one.initializerFromNative(@as(i32, 1));

        const Incr = try ir.createTypeFromNative(fn (i32) i32, null, &.{try ir.internName("n")});
        const incr = try module.createFunction(try ir.internName("incr"), Incr);

        const arg = try incr.getArgument(0);

        const entry = incr.getEntryBlock();
        try entry.ref_local(arg);
        try entry.ref_global(one);
        try entry.add();
        try entry.ret();
    }

    log.info("incr test complete", .{});

    const fib = fib: {
        const Fib = try ir.createTypeFromNative(fn (i32) i32, null, &.{try ir.internName("n")});
        const func = try module.createFunction(try ir.internName("fib"), Fib);

        const arg = try func.getArgument(0);

        const entry = func.getEntryBlock();
        const thenBlock = try func.createBlock(entry, try ir.internName("then"));
        const elseBlock = try func.createBlock(entry, try ir.internName("else"));

        try entry.ref_local(arg);
        try entry.im(@as(i32, 2));
        try entry.lt();
        try entry.ref_block(thenBlock);
        try entry.ref_block(elseBlock);
        try entry.@"if"(Nil);

        try thenBlock.ref_local(arg);
        try thenBlock.ret();

        try elseBlock.ref_local(arg);
        try elseBlock.im(@as(i32, 1));
        try elseBlock.sub();
        try elseBlock.ref_function(func);
        try elseBlock.call(1);

        try elseBlock.ref_local(arg);
        try elseBlock.im(@as(i32, 2));
        try elseBlock.sub();
        try elseBlock.ref_function(func);
        try elseBlock.call(1);

        try elseBlock.add();
        try elseBlock.ret();

        break :fib func;
    };

    log.info("fib test complete: {}", .{fib});

    { // formatting
        var text = std.ArrayList(u8).init(allocator);
        defer text.deinit();

        const writer = text.writer();

        var formatter = try Rir.Formatter.init(ir, writer.any());
        defer formatter.deinit();

        log.info("got formatter", .{});

        // formatter.setFlag(.show_ids, true);
        // formatter.setFlag(.show_indices, true);
        // formatter.setFlag(.show_op_code_bytes, true);
        // formatter.setFlag(.show_op_data_bytes, true);

        try formatter.writeAll("```rir\n");
        try formatter.fmt(ir);
        try formatter.writeAll("```\n");

        std.debug.print("{s}", .{text.items});
    }

    log.info("formatting complete", .{});

    var program = program: { // codegen
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var gen = try RbcGenerator.init(arena.allocator(), ir);

        const exports = [_]RbcGenerator.Export{
            .@"export"(fib),
        };

        const program = try gen.generate(allocator, &exports);

        std.debug.print("{}", .{program});

        break :program program;
    };
    defer program.deinit(allocator);

    log.info("codegen complete", .{});

    log.info("starting rvm", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    log.info("created arena", .{});

    const rvm = try Rvm.init(arena.allocator());
    // defer program.deinit(arena.allocator());

    const fiber = try Rvm.Fiber.init(rvm, &program);
    defer fiber.deinit();

    const start = std.time.nanoTimestamp();

    const result = try fiber.invoke(i64, program.main, .{n});

    const end = std.time.nanoTimestamp();

    const time = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_s;

    try std.io.getStdOut().writer().print("result: {} (in {d:.3}s)\n", .{ result, time });
    try std.testing.expectEqual(expected, result);
}
