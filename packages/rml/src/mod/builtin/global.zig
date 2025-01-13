const std = @import("std");

const Rml = @import("../root.zig");


/// import a namespace into the current environment
pub const import = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            if (args.len != 1) try interpreter.abort(origin, error.InvalidArgumentCount, "expected 1 argument, found {}", .{args.len});

            const namespaceSym = try interpreter.castObj(Rml.Symbol, args[0]);

            const namespace: Rml.Object = Rml.getRml(interpreter).namespace_env.data.get(namespaceSym) orelse {
                try interpreter.abort(origin, error.UnboundSymbol, "namespace {} not found; available namespaces are: {any}", .{namespaceSym, Rml.getRml(interpreter).namespace_env.data.keys()});
            };

            const env = try interpreter.castObj(Rml.Env, namespace);

            const localEnv: *Rml.Env = interpreter.evaluation_env.data;

            var it = env.data.table.iterator();
            while (it.next()) |entry| {
                const slashSym = slashSym: {
                    const slashStr = try std.fmt.allocPrint(Rml.getRml(interpreter).blobAllocator(), "{}/{}", .{namespaceSym, entry.key_ptr.*});

                    break :slashSym try Rml.Obj(Rml.Symbol).wrap(Rml.getRml(interpreter), origin, try .create(Rml.getRml(interpreter), slashStr));
                };

                try localEnv.rebindCell(slashSym, entry.value_ptr.*);
            }

            return (try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{})).typeErase();
        }
    }.fun,
};

/// create a global variable binding
pub const global = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun (interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            Rml.log.interpreter.debug("global {}: {any}", .{origin, args});

            if (args.len < 1)
                try interpreter.abort(origin, error.InvalidArgumentCount,
                    "expected at least a name for global variable", .{});

            const nilObj = try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{});
            const equalSym = try Rml.Obj(Rml.Symbol).wrap(Rml.getRml(interpreter), origin, try .create(Rml.getRml(interpreter), "="));

            const patt, const offset = parse: {
                var diag: ?Rml.Diagnostic = null;
                const parseResult = Rml.Pattern.parse(&diag, args)
                    catch |err| {
                        if (err == error.SyntaxError) {
                            if (diag) |d| {
                                try interpreter.abort(origin, error.PatternError,
                                    "cannot parse global variable pattern: {}",
                                    .{d.formatter(error.SyntaxError)});
                            } else {
                                Rml.log.err("requested pattern parse diagnostic is null", .{});
                                try interpreter.abort(origin, error.PatternError,
                                    "cannot parse global variable pattern `{}`", .{args[0]});
                            }
                        }

                        return err;
                    };

                break :parse .{parseResult.value, parseResult.offset};
            };

            Rml.log.parser.debug("global variable pattern: {}", .{patt});

            const dom = Rml.object.pattern.patternBinders(patt.typeErase())
                catch |err| switch (err) {
                    error.BadDomain => {
                        try interpreter.abort(origin, error.SyntaxError,
                            "bad domain in pattern `{}`", .{patt});
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                };

            for (dom.keys()) |sym| {
                Rml.log.interpreter.debug("rebinding global variable {} = nil", .{sym});
                try Rml.getRml(interpreter).global_env.data.rebind(sym, nilObj.typeErase());
            }

            const obj =
                if (args.len - offset == 0) nilObj.typeErase()
                else obj: {
                    if (!Rml.equal(args[offset], equalSym.typeErase())) {
                        try interpreter.abort(origin, error.SyntaxError,
                            "expected `=` after global variable pattern", .{});
                    }

                    const body = args[offset + 1..];

                    if (body.len == 1) {
                        if (Rml.castObj(Rml.Block, body[0])) |bod| {
                            break :obj try interpreter.runProgram(
                                bod.data.kind == .paren,
                                bod.data.items(),
                            );
                        }
                    }

                    break :obj try interpreter.runProgram(false, body);
                };

            Rml.log.interpreter.debug("evaluating global variable {} = {}", .{patt, obj});

            const table = table: {
                var diag: ?Rml.Diagnostic = null;
                if (try patt.data.run(interpreter, &diag, origin, &.{obj})) |m| break :table m;

                if (diag) |d| {
                    try interpreter.abort(origin, error.PatternError,
                        "failed to match; {} vs {}:\n\t{}",
                        .{patt, obj, d.formatter(error.PatternError)});
                } else {
                    Rml.log.interpreter.err("requested pattern diagnostic is null", .{});
                    try interpreter.abort(origin, error.PatternError,
                        "failed to match; {} vs {}", .{patt, obj});
                }
            };

            var it = table.data.native_map.iterator();
            while (it.next()) |entry| {
                const sym = entry.key_ptr.*;
                const val = entry.value_ptr.*;

                Rml.log.interpreter.debug("setting global variable {} = {}", .{ sym, val });

                // TODO: deep copy into long term memory

                try Rml.getRml(interpreter).global_env.data.rebind(sym, val);
            }

            return nilObj.typeErase();
        }
    }.fun,
};


/// create a local variable binding
pub const local = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            Rml.log.interpreter.debug("local {}: {any}", .{origin, args});

            if (args.len < 1)
                try interpreter.abort(origin, error.InvalidArgumentCount,
                    "expected at least a name for local variable", .{});

            const nilObj = try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{});
            const equalSym = try Rml.Obj(Rml.Symbol).wrap(Rml.getRml(interpreter), origin, try .create(Rml.getRml(interpreter), "="));

            const patt, const offset = parse: {
                var diag: ?Rml.Diagnostic = null;
                const parseResult = Rml.Pattern.parse(&diag, args)
                    catch |err| {
                        if (err == error.SyntaxError) {
                            if (diag) |d| {
                                try interpreter.abort(origin, error.PatternError,
                                    "cannot parse local variable pattern: {}",
                                    .{d.formatter(error.SyntaxError)});
                            } else {
                                Rml.log.err("requested pattern parse diagnostic is null", .{});
                                try interpreter.abort(origin, error.PatternError,
                                    "cannot parse local variable pattern `{}`", .{args[0]});
                            }
                        }

                        return err;
                    };

                break :parse .{parseResult.value, parseResult.offset};
            };

            Rml.log.parser.debug("local variable pattern: {}", .{patt});

            const dom = patt.data.binders()
                catch |err| switch (err) {
                    error.BadDomain => {
                        try interpreter.abort(origin, error.SyntaxError,
                            "bad domain in pattern `{}`", .{patt});
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                };

            for (dom.keys()) |sym| {
                Rml.log.interpreter.debug("rebinding local variable {} = nil", .{sym});
                try interpreter.evaluation_env.data.rebind(sym, nilObj.typeErase());
            }

            const obj =
                if (args.len - offset == 0) nilObj.typeErase()
                else obj: {
                    if (!Rml.equal(args[offset], equalSym.typeErase())) {
                        try interpreter.abort(origin, error.SyntaxError,
                            "expected `=` after local variable pattern", .{});
                    }

                    const body = args[offset + 1..];

                    if (body.len == 1) {
                        if (Rml.castObj(Rml.Block, body[0])) |bod| {
                            break :obj try interpreter.runProgram(
                                bod.data.kind == .paren,
                                bod.data.items(),
                            );
                        }
                    }

                    break :obj try interpreter.runProgram(false, body);
                };

            Rml.log.interpreter.debug("evaluating local variable {} = {}", .{patt, obj});

            const table = table: {
                var diag: ?Rml.Diagnostic = null;
                if (try patt.data.run(interpreter, &diag, origin, &.{obj})) |m| break :table m;

                if (diag) |d| {
                    try interpreter.abort(origin, error.PatternError,
                        "failed to match; {} vs {}:\n\t{}",
                        .{patt, obj, d.formatter(error.PatternError)});
                } else {
                    Rml.log.interpreter.err("requested pattern diagnostic is null", .{});
                    try interpreter.abort(origin, error.PatternError,
                        "failed to match; {} vs {}", .{patt, obj});
                }
            };

            var it = table.data.native_map.iterator();
            while (it.next()) |entry| {
                const sym = entry.key_ptr.*;
                const val = entry.value_ptr.*;

                Rml.log.interpreter.debug("setting local variable {} = {}", .{ sym, val });

                try interpreter.evaluation_env.data.set(sym, val);
            }

            return nilObj.typeErase();
        }
    }.fun,
};

/// set the value of a variable associated with an existing binding in the current environment
pub const @"set!" = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun (interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            const sym = Rml.castObj(Rml.Symbol, args[0])
                orelse try interpreter.abort(origin, error.TypeError,
                    "expected symbol, found {s}", .{Rml.TypeId.name(args[0].getTypeId())});

            const value = try interpreter.eval(args[1]);

            try interpreter.evaluation_env.data.set(sym, value);

            const nil = try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{});
            return nil.typeErase();
        }
    }.fun,
};

/// create a function closure
pub const fun = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            Rml.log.parser.debug("fun {}: {any}", .{origin, args});

            if (args.len == 0) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 1 argument, found 0", .{});

            const rml = Rml.getRml(interpreter);

            var cases: std.ArrayListUnmanaged(Rml.object.procedure.Case) = .{};

            if (args.len == 1) {
                Rml.log.parser.debug("case fun", .{});
                const caseSet: Rml.Obj(Rml.Block) = try interpreter.castObj(Rml.Block, args[0]);
                Rml.log.parser.debug("case set {}", .{caseSet});

                var isCases = true;
                for (caseSet.data.items()) |obj| {
                    if (!Rml.isType(Rml.Block, obj)) {
                        isCases = false;
                        break;
                    }
                }

                if (isCases) {
                    Rml.log.parser.debug("isCases {any}", .{caseSet.data.array.items});
                    for (caseSet.data.array.items) |case| {
                        Rml.log.parser.debug("case {}", .{case});
                        const caseBlock = try interpreter.castObj(Rml.Block, case);

                        const c = try Rml.object.procedure.Case.parse(interpreter, caseBlock.getOrigin(), caseBlock.data.array.items);

                        try cases.append(rml.blobAllocator(), c);
                    }
                } else {
                    Rml.log.parser.debug("fun single case: {any}", .{caseSet.data.array.items});
                    const c = try Rml.object.procedure.Case.parse(interpreter, caseSet.getOrigin(), caseSet.data.array.items);

                    try cases.append(rml.blobAllocator(), c);
                }
            } else {
                Rml.log.parser.debug("fun single case: {any}", .{args});
                const c = try Rml.object.procedure.Case.parse(interpreter, origin, args);

                try cases.append(rml.blobAllocator(), c);
            }

            const env = try interpreter.evaluation_env.data.clone(origin);

            const out: Rml.Obj(Rml.Procedure) = try .wrap(rml, origin, Rml.Procedure {
                .function = .{
                    .env = env,
                    .cases = cases,
                },
            });

            Rml.log.parser.debug("fun done: {}", .{out});

            return out.typeErase();
        }
    }.fun,
};

/// create a macro closure
pub const macro = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            Rml.log.interpreter.debug("macro {}: {any}", .{origin, args});

            if (args.len == 0) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 1 argument, found 0", .{});

            const rml = Rml.getRml(interpreter);

            var cases: std.ArrayListUnmanaged(Rml.object.procedure.Case) = .{};

            if (args.len == 1) {
                Rml.log.interpreter.debug("case macro", .{});
                const caseSet: Rml.Obj(Rml.Block) = try interpreter.castObj(Rml.Block, args[0]);
                Rml.log.interpreter.debug("case set {}", .{caseSet});

                var isCases = true;
                for (caseSet.data.items()) |obj| {
                    if (!Rml.isType(Rml.Block, obj)) {
                        isCases = false;
                        break;
                    }
                }

                if (isCases) {
                    Rml.log.interpreter.debug("isCases {}", .{isCases});
                    for (caseSet.data.array.items) |case| {
                        Rml.log.interpreter.debug("case {}", .{case});
                        const caseBlock = try interpreter.castObj(Rml.Block, case);

                        const c = try Rml.object.procedure.Case.parse(interpreter, origin, caseBlock.data.array.items);

                        try cases.append(rml.blobAllocator(), c);
                    }
                } else {
                    Rml.log.interpreter.debug("isCases {}", .{isCases});
                    Rml.log.interpreter.debug("macro single case: {any}", .{caseSet.data.array.items});
                    const c = try Rml.object.procedure.Case.parse(interpreter, origin, caseSet.data.array.items);

                    try cases.append(rml.blobAllocator(), c);
                }
            } else {
                Rml.log.interpreter.debug("macro single case: {any}", .{args});
                const c = try Rml.object.procedure.Case.parse(interpreter, origin, args);
                try cases.append(rml.blobAllocator(), c);
            }

            const env = try interpreter.evaluation_env.data.clone(origin);

            const out: Rml.Obj(Rml.Procedure) = try .wrap(rml, origin, Rml.Procedure {
                .macro = .{
                    .env = env,
                    .cases = cases,
                },
            });

            return out.typeErase();
        }
    }.fun,
};

/// print any number of arguments followed by a new line
pub fn @"print-ln"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    const rml = Rml.getRml(interpreter);

    const stdout = std.io.getStdOut();
    const nativeWriter = stdout.writer();

    nativeWriter.print("{}: ", .{origin}) catch |err| return Rml.errorCast(err);

    for (args) |arg| {
        arg.getHeader().onFormat(nativeWriter.any())
            catch |err| return Rml.errorCast(err);
    }

    nativeWriter.writeAll("\n") catch |err| return Rml.errorCast(err);

    return (try Rml.Obj(Rml.Nil).wrap(rml, origin, .{})).typeErase();
}



/// print any number of arguments
pub fn print(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    const rml = Rml.getRml(interpreter);

    const stdout = std.io.getStdOut();
    const nativeWriter = stdout.writer();

    for (args) |arg| {
        arg.getHeader().onFormat(nativeWriter.any())
            catch |err| return Rml.errorCast(err);
    }

    return (try Rml.Obj(Rml.Nil).wrap(rml, origin, .{})).typeErase();
}



/// alias for `+`
pub const add = @"+";
/// sum any number of arguments of type `int | float | char`;
/// if only one argument is provided, return the argument's absolute value
pub fn @"+"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len == 0) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 1 argument, found 0", .{});

    var sum: Rml.Object = args[0];

    if (args.len == 1) {
        if (Rml.castObj(Rml.Int, sum)) |int| {
            return (try Rml.Obj(Rml.Int).wrap(int.getRml(), origin, @intCast(@abs(int.data.*)))).typeErase();
        } else if (Rml.castObj(Rml.Float, sum)) |float| {
            return (try Rml.Obj(Rml.Float).wrap(float.getRml(), origin, @abs(float.data.*))).typeErase();
        } if (Rml.castObj(Rml.Char, sum)) |char| {
            return (try Rml.Obj(Rml.Char).wrap(char.getRml(), origin, char.data.*)).typeErase();
        } else {
            try interpreter.abort(origin, error.TypeError, "expected int | float | char, found {s}", .{Rml.TypeId.name(sum.getTypeId())});
        }
    }

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a + b; }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return a + b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a + b; }
    });
}



/// alias for `-`
pub const sub = @"-";
/// subtract any number of arguments of type `int | float | char`;
/// if only one argument is provided, return the argument's negative value
pub fn @"-"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len == 0) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 1 argument, found 0", .{});

    var sum: Rml.Object = args[0];

    if (args.len == 1) {
        if (Rml.castObj(Rml.Int, sum)) |int| {
            return (try Rml.Obj(Rml.Int).wrap(int.getRml(), origin, -int.data.*)).typeErase();
        } else if (Rml.castObj(Rml.Float, sum)) |float| {
            return (try Rml.Obj(Rml.Float).wrap(float.getRml(), origin, -float.data.*)).typeErase();
        } if (Rml.castObj(Rml.Char, sum)) |char| { // TODO: ???
            return (try Rml.Obj(Rml.Char).wrap(char.getRml(), origin, char.data.*)).typeErase();
        } else {
            try interpreter.abort(origin, error.TypeError, "expected int | float | char, found {s}", .{Rml.TypeId.name(sum.getTypeId())});
        }
    }

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a - b; }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return a - b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a - b; }
    });
}


/// alias for `/`
pub const div = @"/";
/// divide any number of arguments of type `int | float | char`;
/// it is an error to provide less than two arguments
pub fn @"/"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return @divFloor(a, b); }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return a / b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return @divFloor(a, b); }
    });
}


/// alias for `*`
pub const mul = @"*";
/// multiply any number of arguments of type `int | float | char`;
/// it is an error to provide less than two arguments
pub fn @"*"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a * b; }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return a * b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a * b; }
    });
}


/// remainder division on any number of arguments of type `int | float | char`;
/// it is an error to provide less than two arguments
pub fn @"rem"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return @rem(a, b); }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return @rem(a, b); }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return @rem(a, b); }
    });
}


/// exponentiation on any number of arguments of type `int | float | char`;
/// it is an error to provide less than two arguments
pub fn pow(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return std.math.pow(Rml.Int, a, b); }
        pub fn float(a: Rml.Float, b: Rml.Float) Rml.Float { return std.math.pow(Rml.Float, a, b); }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return std.math.pow(Rml.Char, a, b); }
    });
}


/// bitwise NOT on an argument of type `int | char`
pub fn @"bit-not"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 1) try interpreter.abort(origin, error.InvalidArgumentCount, "expected 1 argument, found {}", .{args.len});

    if (Rml.castObj(Rml.Int, args[0])) |i| {
        return (try Rml.Obj(Rml.Int).wrap(i.getRml(), origin, ~i.data.*)).typeErase();
    } else if (Rml.castObj(Rml.Char, args[0])) |c| {
        return (try Rml.Obj(Rml.Char).wrap(c.getRml(), origin, ~c.data.*)).typeErase();
    } else {
        try interpreter.abort(origin, error.TypeError, "expected int | char, found {s}", .{Rml.TypeId.name(args[0].getTypeId())});
    }
}


/// bitwise AND on any number of arguments of type `int | char`;
/// it is an error to provide less than two arguments
pub fn @"bit-and"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a & b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a & b; }
    });
}

/// bitwise OR on any number of arguments of type `int | char`;
/// it is an error to provide less than two arguments
pub fn @"bit-or"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a | b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a | b; }
    });
}

/// bitwise XOR on any number of arguments of type `int | char`;
/// it is an error to provide less than two arguments
pub fn @"bit-xor"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected at least 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a ^ b; }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a ^ b; }
    });
}

/// bitwise right shift on two arguments of type `int | char`
pub fn @"bit-rshift"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a >> @intCast(b); }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a >> @intCast(b); }
    });
}

/// bitwise left shift on two arguments of type `int | char`
pub fn @"bit-lshift"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 2) try interpreter.abort(origin, error.InvalidArgumentCount, "expected 2 arguments, found {}", .{args.len});

    var sum: Rml.Object = args[0];

    return arithCastReduce(interpreter, origin, &sum, args[1..], struct {
        pub fn int(a: Rml.Int, b: Rml.Int) Rml.Int { return a << @intCast(b); }
        pub fn char(a: Rml.Char, b: Rml.Char) Rml.Char { return a << @intCast(b); }
    });
}


/// coerce an argument to type `bool`
pub fn @"truthy?"(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 1) {
        try interpreter.abort(origin, error.InvalidArgumentCount, "expected 1 argument, found {}", .{args.len});
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, Rml.coerceBool(args[0]))).typeErase();
}

/// logical NOT on an argument coerced to type `bool`
pub fn not(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 1) {
        try interpreter.abort(origin, error.InvalidArgumentCount, "expected 1 argument, found {}", .{args.len});
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, !Rml.coerceBool(args[0]))).typeErase();
}

/// short-circuiting logical AND on any number of arguments of any type;
/// returns the last succeeding argument or nil
pub const @"and" = Rml.Procedure {
    .native_macro = &struct{
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            if (args.len == 0) return (try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{})).typeErase();

            var a = try interpreter.eval(args[0]);

            if (!Rml.coerceBool(a)) {
                return (try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{})).typeErase();
            }

            for (args[1..]) |aN| {
                const b = try interpreter.eval(aN);

                if (!Rml.coerceBool(b)) return a;

                a = b;
            }

            return a;
        }
    }.fun,
};

/// short-circuiting logical OR on any number of arguments of any type;
/// returns the first succeeding argument or nil
pub const @"or" = Rml.Procedure {
    .native_macro = &struct{
        pub fn fun(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            for (args[0..]) |aN| {
                const a = try interpreter.eval(aN);

                if (Rml.coerceBool(a)) return a;
            }

            return (try Rml.Obj(Rml.Nil).wrap(Rml.getRml(interpreter), origin, .{})).typeErase();
        }
    }.fun,
};

/// alias for `==`
pub const @"eq?" = @"==";
/// determine if any number of values are equal; uses structural comparison
/// it is an error to provide less than two arguments
pub fn @"=="(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    const a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (!Rml.equal(a, b)) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}

/// alias for `!=`
pub const @"ne?" = @"!=";
/// determine if any number of values are not equal; uses structural comparison
/// it is an error to provide less than two arguments
pub fn @"!="(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    const a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (Rml.equal(a, b)) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}


/// alias for `<`
pub const @"lt?" = @"<";
/// determine if any number of values are in strictly increasing order
/// it is an error to provide less than two arguments
pub fn @"<"(
    interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object,
) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    var a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (Rml.compare(a, b) != .Less) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();

        a = b;
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}

/// alias for `<=`
pub const @"le?" = @"<=";
/// determine if any number of values are in increasing order, allowing for equality on adjacent values
/// it is an error to provide less than two arguments
pub fn @"<="(
    interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object,
) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    var a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (Rml.compare(a, b) == .Greater) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();

        a = b;
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}

/// alias for `>`
pub const @"gt?" = @">";
/// determine if any number of values are in strictly decreasing order
/// it is an error to provide less than two arguments
pub fn @">"(
    interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object,
) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    var a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (Rml.compare(a, b) != .Greater) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();

        a = b;
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}

/// alias for `>=`
pub const @"ge?" = @">=";
/// determine if any number of values are in decreasing order, allowing for equality on adjacent values
/// it is an error to provide less than two arguments
pub fn @">="(
    interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object,
) Rml.Result! Rml.Object {
    if (args.len < 2)
        try interpreter.abort(origin, error.InvalidArgumentCount,
        "expected at least 2 arguments, found {}", .{args.len});

    var a = args[0];

    for (args[1..]) |aN| {
        const b = aN;

        if (Rml.compare(a, b) == .Less) return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, false)).typeErase();

        a = b;
    }

    return (try Rml.Obj(Rml.Bool).wrap(Rml.getRml(interpreter), origin, true)).typeErase();
}


/// calls a function with a list of arguments
pub const @"apply" = Rml.Procedure {
    .native_macro = &struct {
        pub fn fun (interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
            if (args.len != 2)
                try interpreter.abort(origin, error.InvalidArgumentCount,
                "expected 2 arguments, found {}", .{args.len});

            const proc = try interpreter.castObj(Rml.Procedure, try interpreter.eval(args[0]));
            const argsArr = try Rml.coerceArray(try interpreter.eval(args[1]))
                orelse try interpreter.abort(origin, error.TypeError,
                    "expected array, found {s}", .{Rml.TypeId.name(args[1].getTypeId())});

            return proc.data.call(interpreter, origin, args[0], argsArr.data.items());
        }
    }.fun
};

/// generates a unique Symbol
pub fn gensym(interpreter: *Rml.Interpreter, origin: Rml.Origin, args: []const Rml.Object) Rml.Result! Rml.Object {
    if (args.len != 0) {
        try interpreter.abort(origin, error.InvalidArgumentCount, "expected 0 arguments, found {}", .{args.len});
    }

    const rml = Rml.getRml(interpreter);

    const sym = try rml.data.gensym(origin);

    return (try Rml.Obj(Rml.Symbol).wrap(rml, origin, .{.str = sym})).typeErase();
}




fn arithCastReduce(
    interpreter: *Rml.Interpreter,
    origin: Rml.Origin, acc: *Rml.Object, args: []const Rml.Object,
    comptime Ops: type,
) Rml.Result! Rml.Object {
    const offset = 1;
    comptime var expect: []const u8 = "";
    const decls = comptime std.meta.declarations(Ops);
    inline for (decls, 0..) |decl, i| comptime {
        expect = expect ++ decl.name;
        if (i < decls.len - 1) expect = expect ++ " | ";
    };
    for (args, 0..) |arg, i| {
        if (@hasDecl(Ops, "int") and Rml.isType(Rml.Int, acc.*)) {
            const int = Rml.forceObj(Rml.Int, acc.*);
            if (Rml.castObj(Rml.Int, arg)) |int2| {
                const int3: Rml.Obj(Rml.Int) = try .wrap(int2.getRml(), origin, @field(Ops, "int")(int.data.*, int2.data.*));
                acc.* = int3.typeErase();
            } else if (@hasDecl(Ops, "float") and Rml.isType(Rml.Float, arg)) {
                const float = Rml.forceObj(Rml.Float, arg);
                const float2: Rml.Obj(Rml.Float) = try .wrap(float.getRml(), origin, @field(Ops, "float")(@as(Rml.Float, @floatFromInt(int.data.*)), float.data.*));
                acc.* = float2.typeErase();
            } else if (Rml.castObj(Rml.Char, arg)) |char| {
                const int2: Rml.Obj(Rml.Int) = try .wrap(char.getRml(), origin, @field(Ops, "int")(int.data.*, @as(Rml.Int, @intCast(char.data.*))));
                acc.* = int2.typeErase();
            } else {
                try interpreter.abort(origin, error.TypeError, "expected " ++ expect ++ " for argument {}, found {s}", .{i + offset, Rml.TypeId.name(arg.getTypeId())});
            }
        } else if (@hasDecl(Ops, "float") and Rml.isType(Rml.Float, acc.*)) {
            const float = Rml.forceObj(Rml.Float, acc.*);

            if (Rml.castObj(Rml.Int, arg)) |int| {
                const float2: Rml.Obj(Rml.Float) = try .wrap(int.getRml(), origin, @field(Ops, "float")(float.data.*, @as(Rml.Float, @floatFromInt(int.data.*))));
                acc.* = float2.typeErase();
            } else if (Rml.castObj(Rml.Float, arg)) |float2| {
                const float3: Rml.Obj(Rml.Float) = try .wrap(float2.getRml(), origin, @field(Ops, "float")(float.data.*, float2.data.*));
                acc.* = float3.typeErase();
            } else if (Rml.castObj(Rml.Char, arg)) |char| {
                const float2: Rml.Obj(Rml.Float) = try .wrap(char.getRml(), origin, @field(Ops, "float")(float.data.*, @as(Rml.Float, @floatFromInt(char.data.*))));
                acc.* = float2.typeErase();
            } else {
                try interpreter.abort(origin, error.TypeError, "expected " ++ expect ++ " for argument {}, found {s}", .{i + offset, Rml.TypeId.name(arg.getTypeId())});
            }
        } else if (@hasDecl(Ops, "char") and Rml.isType(Rml.Char, acc.*)) {
            const char = Rml.forceObj(Rml.Char, acc.*);

            if (@hasDecl(Ops, "int") and Rml.isType(Rml.Int, arg)) {
                const int = Rml.forceObj(Rml.Int, arg);
                const int2: Rml.Obj(Rml.Int) = try .wrap(char.getRml(), origin, @field(Ops, "int")(@as(Rml.Int, @intCast(char.data.*)), int.data.*));
                acc.* = int2.typeErase();
            } else if (@hasDecl(Ops, "float") and Rml.isType(Rml.Float, arg)) {
                const float = Rml.forceObj(Rml.Float, arg);
                const float2: Rml.Obj(Rml.Float) = try .wrap(float.getRml(), origin, @field(Ops, "float")(@as(Rml.Float, @floatFromInt(char.data.*)), float.data.*));
                acc.* = float2.typeErase();
            } else if (Rml.castObj(Rml.Char, arg)) |char2| {
                const char3: Rml.Obj(Rml.Char) = try .wrap(char2.getRml(), origin, @field(Ops, "char")(char.data.*, char2.data.*));
                acc.* = char3.typeErase();
            } else {
                try interpreter.abort(origin, error.TypeError, "expected " ++ expect ++ " for argument {}, found {s}", .{i + offset, Rml.TypeId.name(arg.getTypeId())});
            }
        } else {
            try interpreter.abort(origin, error.TypeError, "expected " ++ expect ++ " for argument {}, found {s}", .{i, Rml.TypeId.name(acc.getTypeId())});
        }
    }

    return acc.*;
}
