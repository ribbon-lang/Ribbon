const std = @import("std");
const MiscUtils = @import("Utils").Misc;
const TextUtils = @import("Utils").Text;

const Rml = @import("root.zig");
const Ordering = Rml.Ordering;
const Error = Rml.Error;
const OOM = Rml.OOM;
const log = Rml.log;
const Weak = Rml.Weak;
const Wk = Rml.Wk;
const Object = Rml.Object;
const Origin = Rml.Origin;
const Obj = Rml.Obj;
const ptr = Rml.ptr;
const Symbol = Rml.Symbol;
const Writer = Rml.Writer;
const getObj = Rml.getObj;
const getTypeId = Rml.getTypeId;
const getRml = Rml.getRml;
const castObj = Rml.castObj;
const forceObj = Rml.forceObj;
const upgradeCast = Rml.upgradeCast;


pub const Cell = struct {
    value: Object,

    pub fn onDeinit(self: ptr(Cell)) void {
        self.value.deinit();
    }

    pub fn set(self: ptr(Cell), value: Object) void {
        self.value.deinit();
        self.value = value;
    }

    pub fn get(self: ptr(Cell)) Object {
        return self.value.clone();
    }
};
