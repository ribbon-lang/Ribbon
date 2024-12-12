const std = @import("std");

const Rml = @import("root.zig");
const Ordering = Rml.Ordering;
const Error = Rml.Error;
const OOM = Rml.OOM;
const ptr = Rml.ptr;
const Obj = Rml.Obj;
const Object = Rml.Object;
const Writer = Rml.Writer;
const getObj = Rml.getObj;
const getTypeId = Rml.getTypeId;
const getRml = Rml.getRml;
const forceObj = Rml.forceObj;

pub const Array = TypedArray(Rml.object.ObjData);
pub const ArrayUnmanaged = TypedArrayUnmanaged(Rml.object.ObjData);

pub fn TypedArray (comptime T: type) type {
    const Unmanaged = TypedArrayUnmanaged(T);

    return struct {
        const Self = @This();

        unmanaged: Unmanaged = .{},

        pub fn onCompare(self: ptr(Self), other: Object) Ordering {
            var ord = Rml.compare(getTypeId(self), other.getTypeId());
            if (ord == .Equal) {
                const otherObj = forceObj(Self, other);
                defer otherObj.deinit();
                ord = Rml.compare(self.unmanaged, otherObj.data.unmanaged);
            }
            return ord;
        }

        pub fn onFormat(self: ptr(Self), writer: Obj(Writer)) Error! void {
            try writer.data.print("{}", .{self.unmanaged});
        }

        pub fn onDeinit(self: ptr(Self)) void {
            const rml = getRml(self);

            self.unmanaged.deinit(rml);
        }

        /// Length of the array.
        /// Pointers to elements in this slice are invalidated by various functions of this ArrayList in accordance with the respective documentation.
        /// In all cases, "invalidated" means that the memory has been passed to an allocator's resize or free function.
        pub fn length(self: *const Self) usize {
            return self.unmanaged.length();
        }

        /// Contents of the array.
        pub fn items(self: *const Self) []Obj(T) {
            return self.unmanaged.items();
        }

        /// Get an element of the array.
        pub fn get(self: *const Self, index: usize) ?Obj(T) {
            return self.unmanaged.get(index);
        }

        /// Extend the array by 1 element.
        /// Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append(self: ptr(Self), val: Obj(T)) OOM! void {
            try self.unmanaged.append(getRml(self), val);
        }

        /// Append the slice of items to the array. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn appendSlice(self: ptr(Self), slice: []const Obj(T)) OOM! void {
            try self.unmanaged.appendSlice(getRml(self), slice);
        }
    };
}

pub fn TypedArrayUnmanaged (comptime T: type) type {
    return struct {
        const Self = @This();

        native_array: NativeArray = .{},

        const NativeArray = std.ArrayListUnmanaged(Obj(T));

        pub fn compare(self: Self, other: Self) Ordering {
            return Rml.compare(self.native_array.items, other.native_array.items);
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) anyerror! void {
            for (self.native_array.items, 0..) |obj, i| {
                try obj.format(fmt, opts, writer);
                if (i < self.native_array.items.len - 1) try writer.writeAll(" ");
            }
        }

        pub fn deinit(self: *Self, rml: *Rml) void {
            for (self.native_array.items) |obj| {
                obj.deinit();
            }

            self.native_array.deinit(rml.storage.object);
        }

        pub fn clone(self: *const Self, rml: *Rml) OOM! Self {
            return Self{ .native_array = try self.native_array.clone(rml.storage.object) };
        }

        /// Length of the array.
        pub fn length(self: *const Self) usize {
            return self.native_array.items.len;
        }

        /// Contents of the array.
        /// Pointers to elements in this slice are invalidated by various functions of this ArrayList in accordance with the respective documentation.
        /// In all cases, "invalidated" means that the memory has been passed to an allocator's resize or free function.
        pub fn items(self: *const Self) []Obj(T) {
            return self.native_array.items;
        }

        /// Get an element of the array.
        pub fn get(self: *const Self, index: usize) ?Obj(T) {
            return if (index < self.native_array.items.len) self.native_array.items[index].clone()
            else null;
        }

        /// Extend the array by 1 element.
        /// Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append(self: *Self, rml: *Rml, val: Obj(T)) OOM! void {
            try self.native_array.append(rml.storage.object, val);
        }

        /// Append the slice of items to the array. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn appendSlice(self: *Self, rml: *Rml, slice: []const Obj(T)) OOM! void {
            try self.native_array.appendSlice(rml.storage.object, slice);
        }
    };
}
