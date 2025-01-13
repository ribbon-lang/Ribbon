const std = @import("std");

const Rml = @import("../root.zig");



pub const ProcedureKind = enum {
    macro,
    function,
    native_macro,
    native_function,
};

pub const Case = union(enum) {
    @"else": Rml.Obj(Rml.Block),

    pattern: struct {
        scrutinizer: Rml.Obj(Rml.Pattern),
        body: Rml.Obj(Rml.Block),
    },

    pub fn body(self: Case) Rml.Obj(Rml.Block) {
        return switch (self) {
            .@"else" => |block| block,
            .pattern => |pat| pat.body,
        };
    }

    pub fn parse(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Case {
        Rml.log.parser.debug("parseCase {}:{any}", .{origin,args});

        if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount,
            "expected at least 2 arguments, found {}", .{args.len});

        var offset: usize = 1;

        const case = if (Rml.object.isExactSymbol("else", args[0])) elseCase: {
            break :elseCase Rml.object.procedure.Case { .@"else" = try Rml.Obj(Rml.Block).wrap(Rml.getRml(interpreter), origin, try .create(Rml.getRml(interpreter), .doc, &.{})) };
        } else patternCase: {
            var diag: ?Rml.Diagnostic = null;
            const parseResult = Rml.Pattern.parse(&diag, args)
                catch |err| {
                    if (err == error.SyntaxError) {
                        if (diag) |d| {
                            try interpreter.abort(origin, error.PatternError,
                                "cannot parse pattern starting with syntax object `{}`: {}", .{args[0], d.formatter(error.SyntaxError)});
                        } else {
                            Rml.log.parser.err("requested pattern parse diagnostic is null", .{});
                            try interpreter.abort(origin, error.PatternError,
                                "cannot parse pattern `{}`", .{args[0]});
                        }
                    }

                    return err;
                };

            Rml.log.parser.debug("pattern parse result: {}", .{parseResult});
            offset = parseResult.offset;

            break :patternCase Case {
                .pattern = .{
                    .scrutinizer = parseResult.value,
                    .body = try Rml.Obj(Rml.Block).wrap(Rml.getRml(interpreter), origin, try .create(Rml.getRml(interpreter), .doc, &.{})),
                },
            };
        };

        const content = case.body();

        for (args[offset..]) |arg| {
            try content.data.append(arg);
        }

        Rml.log.interpreter.debug("case body: {any}", .{content});

        return case;
    }
};

pub const ProcedureBody = struct {
    env: Rml.Obj(Rml.Env),
    cases: std.ArrayListUnmanaged(Case),
};

pub const Procedure = union(ProcedureKind) {
    macro: ProcedureBody,
    function: ProcedureBody,
    native_macro: Rml.bindgen.NativeFunction,
    native_function: Rml.bindgen.NativeFunction,

    pub fn onInit(_: *Procedure) Rml.OOM! void {
        return;
    }

    pub fn onCompare(self: *Procedure, other: Rml.Object) Rml.Ordering {
        return Rml.compare(Rml.getHeader(self).type_id, other.getTypeId());
    }

    pub fn onFormat(self: *Procedure, writer: std.io.AnyWriter) anyerror! void {
        return writer.print("[{s}-{x}]", .{@tagName(self.*), @intFromPtr(self)});
    }

    pub fn call(self: *Procedure, interpreter: *Rml.Interpreter, callOrigin: Rml.Origin, blame: Rml.Object, args: []const Rml.Object) Rml.Result! Rml.Object {
        switch (self.*) {
            .macro => |macro| {
                Rml.log.interpreter.debug("calling macro {}", .{macro});

                var errors: Rml.String = try .create(Rml.getRml(self), "");

                const writer = errors.writer();

                var result: ?Rml.Object = null;

                for (macro.cases.items) |case| switch (case) {
                    .@"else" => |caseData| {
                        result = try interpreter.runProgram(false, caseData.data.items());
                        break;
                    },
                    .pattern => |caseData| {
                        var diag: ?Rml.Diagnostic = null;
                        const table: ?Rml.Obj(Rml.object.map.Table) = try caseData.scrutinizer.data.run(interpreter, &diag, callOrigin, args);
                        if (table) |tbl| {
                            const oldEnv = interpreter.evaluation_env;
                            defer interpreter.evaluation_env = oldEnv;

                            interpreter.evaluation_env = env: {
                                const env: Rml.Obj(Rml.Env) = try macro.env.data.clone(callOrigin);
                                try env.data.copyFromTable(&tbl.data.native_map);

                                break :env env;
                            };

                            result = try interpreter.runProgram(false, caseData.body.data.items());
                            break;
                        } else if (diag) |d| {
                            writer.print("failed to match; {} vs {any}:\n\t{}", .{ caseData.scrutinizer, args, d.formatter(error.PatternError)})
                                catch |err| return Rml.errorCast(err);
                        } else {
                            Rml.log.interpreter.err("requested pattern diagnostic is null", .{});
                            writer.print("failed to match; {} vs {any}", .{ caseData.scrutinizer, args})
                                catch |err| return Rml.errorCast(err);
                        }
                    },
                };

                if (result) |res| {
                    return try interpreter.eval(res);
                } else {
                    try interpreter.abort(callOrigin, error.PatternError, "{} failed; no matching case found for input {any}", .{blame, args});
                }
            },
            .function => |func| {
                Rml.log.interpreter.debug("calling func {}", .{func});

                const eArgs = try interpreter.evalAll(args);
                var errors: Rml.object.string.String = try .create(Rml.getRml(self), "");

                const writer = errors.writer();

                Rml.log.interpreter.debug("calling func {any}", .{func.cases});
                for (func.cases.items) |case| switch (case) {
                    .@"else" => |caseData| {
                        Rml.log.interpreter.debug("calling else case {}", .{caseData});
                        return interpreter.runProgram(false, caseData.data.items());
                    },
                    .pattern => |caseData| {
                        Rml.log.interpreter.debug("calling pattern case {}", .{caseData});
                        var diag: ?Rml.Diagnostic = null;
                        const result: ?Rml.Obj(Rml.object.map.Table) = try caseData.scrutinizer.data.run(interpreter, &diag, callOrigin, eArgs);
                        if (result) |res| {
                            const oldEnv = interpreter.evaluation_env;
                            defer interpreter.evaluation_env = oldEnv;

                            interpreter.evaluation_env = env: {
                                const env: Rml.Obj(Rml.Env) = try func.env.data.clone(callOrigin);

                                try env.data.copyFromTable(&res.data.native_map);

                                break :env env;
                            };

                            return interpreter.runProgram(false, caseData.body.data.items());
                        } else if (diag) |d| {
                            writer.print("failed to match; {} vs {any}:\n\t{}", .{ caseData.scrutinizer, eArgs, d.formatter(error.PatternError)})
                                catch |err| return Rml.errorCast(err);
                        } else {
                            Rml.log.interpreter.err("requested pattern diagnostic is null", .{});
                            writer.print("failed to match; {} vs {any}", .{ caseData.scrutinizer, eArgs})
                                catch |err| return Rml.errorCast(err);
                        }
                    },
                };

                try interpreter.abort(callOrigin, error.PatternError, "{} failed; no matching case found for input {any}", .{blame, eArgs});
            },
            .native_macro => |func| {
                Rml.log.interpreter.debug("calling native macro {x}", .{@intFromPtr(func)});

                return func(interpreter, callOrigin, args);
            },
            .native_function => |func| {
                Rml.log.interpreter.debug("calling native func {x}", .{@intFromPtr(func)});

                const eArgs = try interpreter.evalAll(args);

                return func(interpreter, callOrigin, eArgs);
            },
        }
    }
};