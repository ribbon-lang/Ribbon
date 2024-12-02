import { TMGrammarScope } from "vscode-grammar";
import * as Strings from "./Strings.js";

const patterns: Record<string, Record<string, TMGrammarScope>> = {
    keywords: {},
    standard: {},
};


patterns.standard["comment.line.ribbon"] = {
    match: /;.*\n/,
};

patterns.standard["comment.line.shebang.ribbon"] = {
    match: /\A(#!).*$\n?/,
    captures: { 1: { name: "comment.line.operator.ribbon" } },
};


const rx = (r: RegExp): string => r.toString().replace(/^\/|\/$/g, '')
const filter = (s: string, f: string): string => s.replace(f, "")
const cat = (...s: any[]): string => s.reduce((a, b) => `${a}${b}`, "")
const lit = (...s: any[]): string => `(${s.reduce((a, b) => a != ""? `${a}|${b}` : `${b}`, "")})`
const zeroOrMore = (...s: any[]): string => `${cat(...s)}*`
const oneOrMore = (...s: any[]): string => `${cat(...s)}+`
const group = (...s: any[]): string => `(${cat(...s)})`
const optional = (...s: any[]): string => `${cat(...s)}?`
const posBehind = (...s: any[]): string => `(?<=${cat(...s)})`
const posAhead = (...s: any[]): string => `(?=${cat(...s)})`
const posWrap = (a: any, b: any, c: any = a): string => `(?<=${a})${b}(?=${c})`
const negBehind = (...s: any[]): string => `(?<!${cat(...s)})`
const negAhead = (...s: any[]): string => `(?!${cat(...s)})`
const negWrap = (a: any, b: any, c: any = a): string => `(?<!${a})${b}(?!${c})`
const set = (...s: any[]): string => `[${cat(...s)}]`
const end = "$"
const SINGLE_QUOTE = "'"
const OP_TEXT = "?!@$%^&*\\-+=\\/:><|."
const OP_TEXT_SQ = OP_TEXT + SINGLE_QUOTE
const ALPHA = "a-zA-Z_"
const NUM = "0-9"
const ALPHANUM = ALPHA + NUM
const SYMBOL = ALPHA + NUM + OP_TEXT
const SYMBOL_SQ = SYMBOL + SINGLE_QUOTE
const SPECIAL_ID_START = ",#`'"
const FORWARD_SLASH = "\\/"


const onlyPathBehind = negBehind(set(filter(SYMBOL, FORWARD_SLASH)));

const pathSegment = group(cat(
    zeroOrMore(set(OP_TEXT.replace(FORWARD_SLASH, ""))),
    set(ALPHA),
    zeroOrMore(set(SYMBOL_SQ.replace(FORWARD_SLASH, ""))),
));

const identifier = group(cat(
    zeroOrMore(set(SPECIAL_ID_START)),
    zeroOrMore(set(OP_TEXT)),
    set(ALPHA),
    zeroOrMore(set(ALPHANUM + OP_TEXT_SQ)),
));

patterns.standard["keyword.operator.ribbon"] = {
    match: negWrap(set(ALPHANUM), cat(
        optional(set("'`")),
        set(OP_TEXT),
        negAhead(set(SINGLE_QUOTE)),
        zeroOrMore(set(OP_TEXT_SQ)),
    )),
}

patterns.standard["identifier.ribbon"] = {
    match: identifier,
    captures: { 1: { patterns: [{ include: "#keywords" }] } }
};

patterns.standard["quote.ribbon"] = {
    match: /\'\(/
};
patterns.standard["quasiquote.ribbon"] = {
    match: /\`\(/
};

patterns.keywords["identifier.path.ribbon"] = {
    match: cat(
        onlyPathBehind,
        oneOrMore(
            group(
                pathSegment,
                group(set(FORWARD_SLASH)),
            ),
        ),
        optional(pathSegment),
        end,
    ),
    captures: {
        3: { name: "identifier.path.separator.ribbon" },
        4: { patterns: [{ include: "#keywords" }] },
    },
};

patterns.standard["identifier.escape.ribbon"] = {
    match: cat(
        set(","),
        optional(set("@")),
    ),
};

patterns.keywords["identifier.escape.ribbon"] = {
    match: cat(
        set(","),
        optional(set("@")),
        identifier,
        end,
    ),
    captures: {
        1: { patterns: [{ include: "#keywords" }] },
    },
};

patterns.keywords["identifier.quoted.ribbon"] = {
    match: cat(
        set("'`"),
        identifier,
        end,
    ),
    captures: {
        1: { patterns: [{ include: "#keywords" }] },
    },
};

patterns.keywords["identifier.reader.ribbon"] = {
    match: cat(
        set("#"),
        identifier,
        end,
    ),
    captures: {
        1: { patterns: [{ include: "#keywords" }] },
    },
};

patterns.keywords["predicate.ribbon"] = {
    match: cat(identifier, set("?"), end),
};

patterns.keywords["conversion.ribbon"] = {
    match: cat(identifier, "<\\-", identifier, end),
};

patterns.keywords["assignment.ribbon"] = {
    match: cat(identifier, set("!"), end),
};

patterns.keywords["mutable.ribbon"] = {
    match: cat(set("*"), identifier, set("*")),
};

patterns.keywords["keyword.operator.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Operators),
        end,
    ),
};

patterns.keywords["keyword.effectful.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Effectful),
        end,
    ),
};

patterns.keywords["keyword.special.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Special),
        end,
    ),
};

patterns.keywords["keyword.control.ribbon"] = {
    match: group(
        zeroOrMore(set(SYMBOL)),
        lit(...Strings.ControlFlow),
        zeroOrMore(set(SYMBOL)),
    )
};

patterns.keywords["object.language.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Object),
        end,
    ),
};

patterns.keywords["constant.language.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Constant),
        end,
    ),
};

patterns.keywords["keyword.module.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Module),
        end,
    ),
};

patterns.keywords["keyword.definition.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Definition),
        end,
    ),
};

patterns.keywords["keyword.ribbon"] = {
    match: cat(
        onlyPathBehind,
        lit(...Strings.Keywords),
        end,
    ),
};



patterns.standard["constant.numeric.decimal.ribbon"] = {
    match: /(?<![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])([0-9][0-9_]*)([eE][\-+]?[0-9][0-9_]*)?(?![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])/
};

patterns.standard["constant.numeric.hexadecimal.ribbon"] = {
    match: /(?<![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])0x[a-fA-F0-9][a-fA-F0-9_]+(?![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])/
};

patterns.standard["constant.numeric.binary.ribbon"] = {
    match: /(?<![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])0b[0-1][0-1_]+(?![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])/
};

patterns.standard["constant.character.ribbon"] = {
    match: /(?<![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])'((\\')|(\\[^']+)|[^'])'(?![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])/,
    captures:
    {
        1:
        {
            patterns: [
                {
                    name: "constant.character.escape.ribbon",
                    match: /(\\[\\0'\"abefnrtv])|(\\u\{[a-fA-F0-9]{1,6}\})|(\\x[a-fA-F0-9]{2})/
                },
                {
                    name: "invalid.illegal.escape.ribbon",
                    match: /\\[^\\0'\"abefnrtv]/
                }
            ]
        }
    }
}

patterns.standard["constant.string.ribbon"] = {
    match: /(?<![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])"((\\")|(\\[^"]+)|[^"])*"(?![a-zA-Z0-9?!@$%^&*\-+=\/:><|.])/,
    captures: {
        1: {
            patterns: [
                {
                    name: "constant.string.escape.ribbon",
                    match: /(\\[\\0'\"abefnrtv])|(\\u\{[a-fA-F0-9]{1,6}\})|(\\x[a-fA-F0-9]{2})/
                },
                {
                    name: "invalid.illegal.escape.ribbon",
                    match: /\\[^\\0'\"abefnrtv]/
                },
                {
                    name: "constant.string.escape.ribbon",
                    begin: /\$\{/,
                    end: /\}/,
                    patterns: [{ "include": "#standard" }]
                }
            ]
        }
    }
}


function exportPatterns(pats) {
    const patterns = [];

    for (const key in pats) {
        console.log(key);
        console.log(pats[key]);
        patterns.push({
            name: key,
            ...pats[key],
        });
    }

    return { patterns };
}

export const standard: TMGrammarScope = exportPatterns(patterns.standard);
export const keywords: TMGrammarScope = exportPatterns(patterns.keywords);
