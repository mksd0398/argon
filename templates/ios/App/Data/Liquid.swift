import Foundation

// Argon's own Liquid: exactly the subset of the screens v2 spec, no dependency, the same as Liquid.kt on Android. Shared
// cases in contract/fixtures/liquid/cases.json (which liquidjs, Shopify's semantics, also passes) check both. It never
// fails: an unknown filter makes its output empty, an unknown tag renders nothing, and a syntax error renders the text
// with every Liquid tag taken out.

enum Liquid {
    /// `template` rendered over `context` (the screen's objects, `ScreenContext`). Dates are formatted in `timeZone`;
    /// `money` uses `shop.currency`. Text without `{{` or `{%` comes back as it is.
    static func render(_ template: String, _ context: [String: JSONValue], timeZone: TimeZone = .current) -> String {
        if !template.contains("{{") && !template.contains("{%") { return template }
        do {
            var parser = Parser(tokens: try tokenize(template))
            let nodes = try parser.document()
            let renderer = Renderer(context: context, timeZone: timeZone)
            return try renderer.render(nodes)
        } catch {
            // never a crash: the text without its Liquid; reported, with the template's start, so a store's broken
            // Liquid shows up in App health
            CrashReports.record(error, "liquid: \(template.prefix(120))")
            return withoutLiquid(template)
        }
    }

    /// `template` with every `{{ }}` and `{% %}` removed, and an unterminated one removed to the end.
    static func withoutLiquid(_ template: String) -> String {
        let closed = template.replacingOccurrences(of: #"(?s)\{\{.*?\}\}|\{%.*?%\}"#, with: "", options: .regularExpression)
        return closed.replacingOccurrences(of: #"(?s)(\{\{|\{%).*$"#, with: "", options: .regularExpression)
    }
}

private struct SyntaxError: Error {}

// What one render may do: a template that nests, loops or grows past these (a merchant's mistake) renders as its text
// without Liquid, as a syntax error does. The same limits on Android.
private let maxSteps = 100_000
private let maxOutput = 256 * 1024
private let maxDepth = 64

private struct UnknownFilter: Error {}

// MARK: Tokens

private enum Token {
    case text(String)
    case output(String)
    case tag(name: String, markup: String)
}

private func tokenize(_ source: String) throws -> [Token] {
    var tokens: [Token] = []
    var rest = source[...]
    // the previous tag ended with `-`: the text after it loses its leading whitespace
    var trimNext = false
    func addText(_ text: Substring, trimEnd: Bool) {
        var piece = text
        if trimNext { piece = piece.drop { $0.isWhitespace } }
        if trimEnd { while let last = piece.last, last.isWhitespace { piece = piece.dropLast() } }
        if !piece.isEmpty { tokens.append(.text(String(piece))) }
    }
    while true {
        guard let open = nextOpening(rest) else {
            addText(rest, trimEnd: false)
            break
        }
        let isOutput = rest[rest.index(after: open.lowerBound)] == "{"
        var inner = rest[open.upperBound...]
        let trimBefore = inner.first == "-"
        if trimBefore { inner = inner.dropFirst() }
        guard let close = inner.range(of: isOutput ? "}}" : "%}") else { throw SyntaxError() }
        var markup = inner[..<close.lowerBound]
        let trimAfter = markup.last == "-"
        if trimAfter { markup = markup.dropLast() }
        addText(rest[..<open.lowerBound], trimEnd: trimBefore)
        trimNext = trimAfter
        rest = inner[close.upperBound...]
        let body = markup.trimmingCharacters(in: .whitespacesAndNewlines)
        if isOutput {
            tokens.append(.output(body))
            continue
        }
        let name = String(body.prefix { !$0.isWhitespace })
        if name == "raw" || name == "comment" {
            // their insides are not Liquid: up to the end tag, as written (raw) or dropped (comment)
            guard let end = rest.range(of: #"\{%-?\s*end\#(name)\s*-?%\}"#, options: .regularExpression) else { throw SyntaxError() }
            if name == "raw" {
                let text = rest[..<end.lowerBound]
                if !text.isEmpty { tokens.append(.text(String(text))) }
            }
            trimNext = rest[end].hasSuffix("-%}")
            rest = rest[end.upperBound...]
            continue
        }
        tokens.append(.tag(name: name, markup: String(body.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return tokens
}

/// Where the next `{{` or `{%` in `text` is; nil when there is none. One pass from the start: looking for each of the
/// two through the whole rest would be quadratic on a long template.
private func nextOpening(_ text: Substring) -> Range<Substring.Index>? {
    var at = text.startIndex
    while let brace = text[at...].firstIndex(of: "{") {
        let next = text.index(after: brace)
        if next == text.endIndex { return nil }
        if text[next] == "{" || text[next] == "%" { return brace..<text.index(after: next) }
        at = next
    }
    return nil
}

// MARK: Expressions

private enum Lexeme: Equatable {
    case string(String)
    case number(JSONValue)
    case word(String)
    case dot, open, close, pipe, colon, comma
    case op(String)
}

private func lex(_ text: String) throws -> [Lexeme] {
    var out: [Lexeme] = []
    let chars = Array(text)
    var i = 0
    func isWordStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "-" || c == "?" }
    while i < chars.count {
        let c = chars[i]
        if c.isWhitespace {
            i += 1
        } else if c == "'" || c == "\"" {
            guard let end = chars[(i + 1)...].firstIndex(of: c) else { throw SyntaxError() }
            out.append(.string(String(chars[(i + 1)..<end])))
            i = end + 1
        } else if c.isNumber || (c == "-" && i + 1 < chars.count && chars[i + 1].isNumber) {
            var j = i + 1
            var dot = false
            while j < chars.count {
                if chars[j].isNumber {
                    j += 1
                } else if chars[j] == ".", !dot, j + 1 < chars.count, chars[j + 1].isNumber {
                    dot = true
                    j += 1
                } else {
                    break
                }
            }
            let literal = String(chars[i..<j])
            if dot, let value = Double(literal) {
                out.append(.number(.double(value)))
            } else if let value = Int(literal) {
                out.append(.number(.int(value)))
            } else {
                throw SyntaxError()
            }
            i = j
        } else if isWordStart(c) {
            var j = i + 1
            while j < chars.count, isWord(chars[j]) { j += 1 }
            out.append(.word(String(chars[i..<j])))
            i = j
        } else {
            let two = i + 1 < chars.count ? String(chars[i...(i + 1)]) : ""
            if ["==", "!=", "<>", "<=", ">="].contains(two) {
                out.append(.op(two == "<>" ? "!=" : two))
                i += 2
                continue
            }
            switch c {
            case ".": out.append(.dot)
            case "[": out.append(.open)
            case "]": out.append(.close)
            case "|": out.append(.pipe)
            case ":": out.append(.colon)
            case ",": out.append(.comma)
            case "<", ">": out.append(.op(String(c)))
            default: throw SyntaxError()
            }
            i += 1
        }
    }
    return out
}

/// A value: a literal, or a variable with its lookups.
private indirect enum Expr {
    case literal(JSONValue)
    case variable(String, [Lookup])

    enum Lookup {
        case key(String)
        case index(Expr)
    }
}

/// An expression with its filters.
private struct Filtered {
    let value: Expr
    let filters: [(name: String, args: [Expr])]
}

private indirect enum Condition {
    case value(Expr)
    case compare(Expr, String, Expr)
    case and(Condition, Condition)
    case or(Condition, Condition)
    case not(Condition)
}

/// Reads expressions from lexemes.
private struct Reader {
    let items: [Lexeme]
    var at = 0
    // how deep the value being read is (`a[b[c]]`): bounded by `maxDepth`
    private var depth = 0

    init(_ text: String) throws {
        items = try lex(text)
    }

    /// `text` as an expression with its filters.
    static func filtered(_ text: String) throws -> Filtered {
        var reader = try Reader(text)
        return try reader.filtered()
    }

    var done: Bool { at >= items.count }
    var peek: Lexeme? { at < items.count ? items[at] : nil }

    mutating func next() -> Lexeme? {
        defer { at += 1 }
        return peek
    }

    mutating func take(_ lexeme: Lexeme) -> Bool {
        if peek == lexeme {
            at += 1
            return true
        }
        return false
    }

    mutating func word() throws -> String {
        guard case let .word(name)? = next() else { throw SyntaxError() }
        return name
    }

    mutating func value() throws -> Expr {
        depth += 1
        defer { depth -= 1 }
        if depth > maxDepth { throw SyntaxError() }
        switch next() {
        case let .string(text)?: return .literal(.string(text))
        case let .number(number)?: return .literal(number)
        case let .word(name)?:
            switch name {
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "nil", "null": return .literal(.null)
            default: break
            }
            var lookups: [Expr.Lookup] = []
            while true {
                if take(.dot) {
                    lookups.append(.key(try word()))
                } else if take(.open) {
                    lookups.append(.index(try value()))
                    guard take(.close) else { throw SyntaxError() }
                } else {
                    break
                }
            }
            return .variable(name, lookups)
        case .open?:
            // `[ "key" ]` at the start: a lookup on the whole context
            let key = try value()
            guard take(.close) else { throw SyntaxError() }
            return .variable("", [.index(key)])
        default:
            throw SyntaxError()
        }
    }

    mutating func filtered() throws -> Filtered {
        let base = try value()
        var filters: [(name: String, args: [Expr])] = []
        while take(.pipe) {
            let name = try word()
            var args: [Expr] = []
            if take(.colon) {
                repeat {
                    // a named argument (`allow_false: true`) is read for its value
                    if case .word(_)? = peek, at + 1 < items.count, items[at + 1] == .colon { at += 2 }
                    args.append(try value())
                } while take(.comma)
            }
            filters.append((name, args))
        }
        guard done else { throw SyntaxError() }
        return Filtered(value: base, filters: filters)
    }

    /// `a == b and c or d`: `and` and `or` group from the right, as Liquid's do.
    mutating func condition(_ terms: Int = 1) throws -> Condition {
        if terms > maxDepth { throw SyntaxError() }
        let left = try comparison()
        if case .word("and")? = peek {
            at += 1
            return .and(left, try condition(terms + 1))
        }
        if case .word("or")? = peek {
            at += 1
            return .or(left, try condition(terms + 1))
        }
        guard done else { throw SyntaxError() }
        return left
    }

    private mutating func comparison() throws -> Condition {
        let left = try value()
        if case let .op(op)? = peek {
            at += 1
            return .compare(left, op, try value())
        }
        if case .word("contains")? = peek {
            at += 1
            return .compare(left, "contains", try value())
        }
        return .value(left)
    }
}

// MARK: Parsing

private indirect enum LiquidNode {
    case text(String)
    case output(Filtered?)
    case branch([(Condition, [LiquidNode])], otherwise: [LiquidNode])
    case loop(name: String, items: Expr, limit: Expr?, offset: Expr?, reversed: Bool, body: [LiquidNode], otherwise: [LiquidNode])
    case assign(String, Filtered)
    case capture(String, [LiquidNode])
}

private struct Parser {
    let tokens: [Token]
    var at = 0
    // the blocks open around the tag being read: bounded by `maxDepth`
    private var depth = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func document() throws -> [LiquidNode] {
        let (nodes, end, _) = try block(until: [])
        if end != nil { throw SyntaxError() }
        return nodes
    }

    /// Nodes up to one of the tags `until`: the nodes, that tag's name and its markup (nil at the end of the tokens,
    /// which is a syntax error inside a block).
    private mutating func block(until enders: Set<String>) throws -> ([LiquidNode], String?, String) {
        var nodes: [LiquidNode] = []
        while at < tokens.count {
            let token = tokens[at]
            at += 1
            switch token {
            case let .text(text):
                nodes.append(.text(text))
            case let .output(markup):
                // `{{ }}` is nothing
                nodes.append(.output(markup.isEmpty ? nil : try Reader.filtered(markup)))
            case let .tag(name, markup):
                if enders.contains(name) { return (nodes, name, markup) }
                if let node = try tag(name, markup) { nodes.append(node) }
            }
        }
        if !enders.isEmpty { throw SyntaxError() }
        return (nodes, nil, "")
    }

    private mutating func tag(_ name: String, _ markup: String) throws -> LiquidNode? {
        if ["if", "unless", "for", "capture"].contains(name) {
            depth += 1
            if depth > maxDepth { throw SyntaxError() }
        }
        defer { if ["if", "unless", "for", "capture"].contains(name) { depth -= 1 } }
        switch name {
        case "if", "unless":
            let end = "end" + name
            var current = try condition(markup)
            if name == "unless" { current = .not(current) }
            var branches: [(Condition, [LiquidNode])] = []
            while true {
                let (body, ender, rest) = try block(until: ["elsif", "else", end])
                branches.append((current, body))
                if ender == "elsif" {
                    current = try condition(rest)
                    continue
                }
                var otherwise: [LiquidNode] = []
                if ender == "else" { otherwise = try block(until: [end]).0 }
                return .branch(branches, otherwise: otherwise)
            }
        case "for":
            var reader = try Reader(markup)
            let variable = try reader.word()
            guard try reader.word() == "in" else { throw SyntaxError() }
            let items = try reader.value()
            var limit: Expr? = nil, offset: Expr? = nil, reversed = false
            while !reader.done {
                let option = try reader.word()
                if option == "reversed" {
                    reversed = true
                    continue
                }
                guard option == "limit" || option == "offset", reader.take(.colon) else { throw SyntaxError() }
                if option == "limit" { limit = try reader.value() } else { offset = try reader.value() }
                _ = reader.take(.comma)
            }
            let (body, ender, _) = try block(until: ["else", "endfor"])
            let otherwise = try (ender == "else" ? block(until: ["endfor"]).0 : [])
            return .loop(name: variable, items: items, limit: limit, offset: offset, reversed: reversed, body: body, otherwise: otherwise)
        case "assign":
            guard let equals = markup.firstIndex(of: "=") else { throw SyntaxError() }
            let variable = markup[..<equals].trimmingCharacters(in: .whitespaces)
            guard isName(variable) else { throw SyntaxError() }
            return .assign(variable, try Reader.filtered(String(markup[markup.index(after: equals)...])))
        case "capture":
            let variable = markup.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            guard isName(variable) else { throw SyntaxError() }
            return .capture(variable, try block(until: ["endcapture"]).0)
        case "elsif", "else", "endif", "endunless", "endfor", "endcapture":
            // outside the block they belong to
            throw SyntaxError()
        default:
            // render, section, form, paginate, ...: nothing
            return nil
        }
    }

    private func condition(_ markup: String) throws -> Condition {
        var reader = try Reader(markup)
        return try reader.condition()
    }

    private func isName(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}

// MARK: Rendering

private final class Renderer {
    let context: [String: JSONValue]
    let timeZone: TimeZone
    // `assign` and `capture`, then the loop variables, innermost last
    var variables: [String: JSONValue] = [:]
    var loops: [[String: JSONValue]] = []
    // the work done so far: each tag, output and loop turn is a step (`maxSteps`)
    private var steps = 0

    init(context: [String: JSONValue], timeZone: TimeZone) {
        self.context = context
        self.timeZone = timeZone
    }

    /// Throws past the work budget or the output cap.
    func render(_ nodes: [LiquidNode]) throws -> String {
        var out = ""
        for node in nodes {
            try step()
            if out.utf8.count > maxOutput { throw SyntaxError() }
            switch node {
            case let .text(text):
                out += text
            case let .output(filtered):
                if let filtered = filtered { out += text(try apply(filtered) ?? .null) }
            case let .branch(branches, otherwise):
                if let taken = branches.first(where: { truthy(test($0.0)) }) {
                    out += try render(taken.1)
                } else {
                    out += try render(otherwise)
                }
            case let .loop(name, items, limit, offset, reversed, body, otherwise):
                var list = evaluate(items).array ?? []
                let from = offset.flatMap { integer(evaluate($0)) } ?? 0
                list = Array(list.dropFirst(max(from, 0)))
                if let count = limit.flatMap({ integer(evaluate($0)) }) { list = Array(list.prefix(max(count, 0))) }
                if reversed { list.reverse() }
                if list.isEmpty {
                    out += try render(otherwise)
                    continue
                }
                for (index, item) in list.enumerated() {
                    try step()
                    let forloop: JSONValue = .object([
                        "index": .int(index + 1), "index0": .int(index), "rindex": .int(list.count - index),
                        "rindex0": .int(list.count - index - 1), "first": .bool(index == 0), "last": .bool(index == list.count - 1),
                        "length": .int(list.count),
                    ])
                    loops.append([name: item, "forloop": forloop])
                    out += try render(body)
                    loops.removeLast()
                }
            case let .assign(name, filtered):
                variables[name] = try apply(filtered) ?? .null
            case let .capture(name, body):
                variables[name] = .string(try render(body))
            }
        }
        if out.utf8.count > maxOutput { throw SyntaxError() }
        return out
    }

    private func step() throws {
        steps += 1
        if steps > maxSteps { throw SyntaxError() }
    }

    // MARK: Values

    /// The filtered value; nil when a filter is unknown (its output is then empty). Throws when a filter's result is over
    /// the output cap.
    private func apply(_ filtered: Filtered) throws -> JSONValue? {
        var value = evaluate(filtered.value)
        for filter in filtered.filters {
            do {
                value = try self.filter(filter.name, value, filter.args.map { evaluate($0) })
            } catch is UnknownFilter {
                return nil
            }
            if case let .string(text) = value, text.utf8.count > maxOutput { throw SyntaxError() }
        }
        return value
    }

    private func evaluate(_ expr: Expr) -> JSONValue {
        switch expr {
        case let .literal(value):
            return value
        case let .variable(name, lookups):
            var value: JSONValue
            if name.isEmpty {
                value = .object(context)
            } else if let local = loops.last(where: { $0[name] != nil })?[name] {
                value = local
            } else {
                value = variables[name] ?? context[name] ?? .null
            }
            for lookup in lookups {
                switch lookup {
                case let .key(key): value = member(value, key)
                case let .index(index): value = element(value, evaluate(index))
                }
            }
            return value
        }
    }

    private func member(_ value: JSONValue, _ key: String) -> JSONValue {
        if case let .object(map) = value, let found = map[key] { return found }
        switch key {
        case "size": return size(value)
        case "first": return value.array?.first ?? .null
        case "last": return value.array?.last ?? .null
        default: return .null
        }
    }

    private func element(_ value: JSONValue, _ index: JSONValue) -> JSONValue {
        switch (value, index) {
        case let (.array(list), .int(i)):
            let at = i < 0 ? list.count + i : i
            return list.indices.contains(at) ? list[at] : .null
        case let (.object, .string(key)):
            return member(value, key)
        default:
            return .null
        }
    }

    private func size(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .array(list): return .int(list.count)
        case let .string(text): return .int(text.count)
        case let .object(map): return .int(map.count)
        default: return .int(0)
        }
    }

    private func truthy(_ value: JSONValue) -> Bool {
        switch value {
        case .null, .bool(false): return false
        default: return true
        }
    }

    private func test(_ condition: Condition) -> JSONValue {
        switch condition {
        case let .value(expr): return evaluate(expr)
        case let .not(inner): return .bool(!truthy(test(inner)))
        case let .and(a, b): return .bool(truthy(test(a)) && truthy(test(b)))
        case let .or(a, b): return .bool(truthy(test(a)) || truthy(test(b)))
        case let .compare(left, op, right): return .bool(compare(evaluate(left), op, evaluate(right)))
        }
    }

    private func compare(_ a: JSONValue, _ op: String, _ b: JSONValue) -> Bool {
        switch op {
        case "==": return equal(a, b)
        case "!=": return !equal(a, b)
        case "contains":
            switch a {
            case let .string(text): return b.string.map { text.contains($0) } ?? (b.number.map { text.contains(self.text(.double($0))) } ?? false)
            case let .array(list): return list.contains { equal($0, b) }
            case let .object(map): return b.string.map { map[$0] != nil } ?? false
            default: return false
            }
        default:
            let order: ComparisonResult
            if let x = a.number, let y = b.number {
                order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            } else if let x = a.string, let y = b.string {
                order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            } else {
                return false
            }
            switch op {
            case "<": return order == .orderedAscending
            case ">": return order == .orderedDescending
            case "<=": return order != .orderedDescending
            case ">=": return order != .orderedAscending
            default: return false
            }
        }
    }

    private func equal(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if let x = a.number, let y = b.number { return x == y }
        return a == b
    }

    /// A value as output: nil is empty, a whole number has no decimal point, a list is its items one after another.
    func text(_ value: JSONValue) -> String {
        switch value {
        case .null: return ""
        case let .bool(flag): return flag ? "true" : "false"
        case let .int(number): return String(number)
        case let .double(number):
            if number.isFinite, number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
            return String(number)
        case let .string(text): return text
        case let .array(list): return list.map { text($0) }.joined()
        case .object: return ""
        }
    }

    /// A value as a number: integers stay integers; text is read as a number; anything else is 0.
    private func numeric(_ value: JSONValue) -> JSONValue {
        switch value {
        case .int, .double: return value
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed) { return .int(number) }
            if let number = Double(trimmed) { return .double(number) }
            return .int(0)
        default: return .int(0)
        }
    }

    private func integer(_ value: JSONValue) -> Int? {
        switch numeric(value) {
        case let .int(number): return number
        case let .double(number): return clampedInt(number)
        default: return nil
        }
    }

    private func double(_ value: JSONValue) -> Double { numeric(value).number ?? 0 }

    /// Integer arithmetic for two integers, else on doubles.
    private func arithmetic(_ a: JSONValue, _ b: JSONValue, _ ints: (Int, Int) -> (Int, Bool), _ doubles: (Double, Double) -> Double) -> JSONValue {
        if case let .int(x) = numeric(a), case let .int(y) = numeric(b) {
            let (result, overflow) = ints(x, y)
            if !overflow { return .int(result) }
        }
        return .double(doubles(double(a), double(b)))
    }

    // MARK: Filters

    private func filter(_ name: String, _ value: JSONValue, _ args: [JSONValue]) throws -> JSONValue {
        func arg(_ index: Int) -> JSONValue { index < args.count ? args[index] : .null }
        func argText(_ index: Int, _ fallback: String = "") -> String { index < args.count ? text(args[index]) : fallback }
        let input = text(value)
        switch name {
        case "append": return .string(input + argText(0))
        case "prepend": return .string(argText(0) + input)
        case "upcase": return .string(input.uppercased())
        case "downcase": return .string(input.lowercased())
        case "capitalize": return .string(input.prefix(1).uppercased() + input.dropFirst().lowercased())
        case "strip": return .string(input.trimmingCharacters(in: .whitespacesAndNewlines))
        case "lstrip": return .string(String(input.drop { $0.isWhitespace }))
        case "rstrip": return .string(String(input.reversed().drop { $0.isWhitespace }.reversed()))
        case "strip_html":
            let blocks = input.replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>|<!--.*?-->"#, with: "", options: .regularExpression)
            return .string(blocks.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression))
        case "escape", "escape_once":
            return .string(input.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;"))
        case "truncate":
            let length = max(args.isEmpty ? 50 : integer(arg(0)) ?? 50, 0)
            let ellipsis = argText(1, "...")
            if input.count <= length { return .string(input) }
            return .string(String(input.prefix(max(length - ellipsis.count, 0))) + ellipsis)
        case "truncatewords":
            let count = max(args.isEmpty ? 15 : integer(arg(0)) ?? 15, 1)
            let words = input.split(whereSeparator: { $0.isWhitespace })
            if words.count <= count { return .string(input) }
            return .string(words.prefix(count).joined(separator: " ") + argText(1, "..."))
        case "replace": return .string(input.replacingOccurrences(of: argText(0), with: argText(1)))
        case "replace_first", "remove_first":
            let target = argText(0)
            guard !target.isEmpty, let found = input.range(of: target) else { return .string(input) }
            return .string(input.replacingCharacters(in: found, with: name == "replace_first" ? argText(1) : ""))
        case "remove":
            let target = argText(0)
            return .string(target.isEmpty ? input : input.replacingOccurrences(of: target, with: ""))
        case "split":
            let separator = argText(0)
            var parts = separator.isEmpty ? input.map { String($0) } : input.components(separatedBy: separator)
            while parts.last == "" { parts.removeLast() }
            return .array(parts.map { .string($0) })
        case "join":
            guard let list = value.array else { return .string(input) }
            return .string(list.map { text($0) }.joined(separator: argText(0, " ")))
        case "first": return value.array?.first ?? .null
        case "last": return value.array?.last ?? .null
        case "size": return size(value)
        case "default":
            switch value {
            case .null, .bool(false): return arg(0)
            case let .string(text) where text.isEmpty: return arg(0)
            case let .array(list) where list.isEmpty: return arg(0)
            default: return value
            }
        case "plus": return arithmetic(value, arg(0), { $0.addingReportingOverflow($1) }, +)
        case "minus": return arithmetic(value, arg(0), { $0.subtractingReportingOverflow($1) }, -)
        case "times": return arithmetic(value, arg(0), { $0.multipliedReportingOverflow(by: $1) }, *)
        case "divided_by":
            if double(arg(0)) == 0 { return .null }
            // integer by integer is integer division, rounded down (as Ruby's)
            return arithmetic(value, arg(0), floorDivide, /)
        case "modulo":
            if double(arg(0)) == 0 { return .null }
            return arithmetic(value, arg(0), floorModulo, { x, y in x - y * (x / y).rounded(.down) })
        case "round":
            let places = min(args.isEmpty ? 0 : integer(arg(0)) ?? 0, 15)
            if case let .int(number) = numeric(value) { return .int(number) }
            let number = double(value)
            if places <= 0 { return whole(number.rounded()) }
            let scale = pow(10, Double(places))
            return .double((number * scale).rounded() / scale)
        case "ceil": return whole(double(value).rounded(.up))
        case "floor": return whole(double(value).rounded(.down))
        case "abs":
            switch numeric(value) {
            // Int.min has no Int opposite
            case let .int(number): return number == .min ? .double(-Double(number)) : .int(abs(number))
            case let .double(number): return .double(abs(number))
            default: return .int(0)
            }
        case "date":
            guard !args.isEmpty, let date = self.date(value) else { return value }
            return .string(strftime(date, argText(0)))
        case "money", "money_with_currency":
            let currency = context["shop"]?["currency"]?.string ?? ""
            let amount = grouped(double(value))
            if let symbol = moneySymbols[currency] { return .string(symbol + amount) }
            return .string(currency.isEmpty ? amount : "\(amount) \(currency)")
        case "money_without_currency": return .string(grouped(double(value)))
        case "handleize", "handle":
            let words = input.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            return .string(words.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
        case "url_encode":
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'() ")
            let encoded = input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
            return .string(encoded.replacingOccurrences(of: " ", with: "+"))
        case "newline_to_br": return .string(input.replacingOccurrences(of: "\n", with: "<br />\n"))
        case "pluralize": return double(value) == 1 ? arg(0) : arg(1)
        default: throw UnknownFilter()
        }
    }

    // MARK: Dates and money

    private func date(_ value: JSONValue) -> Date? {
        switch value {
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == "now" || trimmed == "today" { return Date() }
            if let seconds = Double(trimmed) { return date(.double(seconds)) }
            return parseISODate(text)
        case let .int(seconds): return date(.double(Double(seconds)))
        // seconds since 1970, within a few million years of it
        case let .double(seconds): return abs(seconds) < 1e14 ? Date(timeIntervalSince1970: seconds) : nil
        default: return nil
        }
    }

    private func strftime(_ date: Date, _ format: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let year = c.year ?? 0, month = c.month ?? 1, day = c.day ?? 1, hour = c.hour ?? 0, weekday = c.weekday ?? 1
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        var out = ""
        var chars = format.makeIterator()
        while let ch = chars.next() {
            guard ch == "%" else {
                out.append(ch)
                continue
            }
            guard let code = chars.next() else {
                out.append("%")
                break
            }
            switch code {
            case "Y": out += String(year)
            case "y": out += two(year % 100)
            case "m": out += two(month)
            case "d": out += two(day)
            case "e": out += day < 10 ? " \(day)" : "\(day)"
            case "b": out += String(months[month - 1].prefix(3))
            case "B": out += months[month - 1]
            case "a": out += String(weekdays[weekday - 1].prefix(3))
            case "A": out += weekdays[weekday - 1]
            case "H": out += two(hour)
            case "I": out += two(hour % 12 == 0 ? 12 : hour % 12)
            case "M": out += two(c.minute ?? 0)
            case "S": out += two(c.second ?? 0)
            case "p": out += hour < 12 ? "AM" : "PM"
            case "j": out += String(format: "%03d", dayOfYear)
            case "%": out += "%"
            default: out += "%\(code)"
            }
        }
        return out
    }
}

private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

/// `money`'s symbols; another currency is written after the amount ("9.90 XYZ").
private let moneySymbols = ["USD": "$", "CAD": "$", "AUD": "$", "NZD": "$", "SGD": "$", "INR": "₹", "EUR": "€", "GBP": "£", "JPY": "¥"]

/// `amount` to the cent with thousands grouped: 1234.5 is "1,234.50".
private func grouped(_ amount: Double) -> String {
    let cents = (amount * 100).rounded()
    let fixed = String(format: "%.2f", abs(cents) / 100)
    let parts = fixed.split(separator: ".")
    var whole = String(parts[0])
    var groups: [String] = []
    while whole.count > 3 {
        groups.insert(String(whole.suffix(3)), at: 0)
        whole = String(whole.dropLast(3))
    }
    groups.insert(whole, at: 0)
    return (cents < 0 ? "-" : "") + groups.joined(separator: ",") + "." + (parts.count > 1 ? String(parts[1]) : "00")
}

// MARK: Numbers that never trap

/// `number` as an Int, clamped to Int's range; nil when it is NaN.
private func clampedInt(_ number: Double) -> Int? {
    if number.isNaN { return nil }
    if number >= Double(Int.max) { return .max }
    if number <= Double(Int.min) { return .min }
    return Int(number)
}

/// A whole `number` (already rounded) as an integer when Int holds it, else as the number it is; nil (nothing) when it
/// isn't finite.
private func whole(_ number: Double) -> JSONValue {
    guard number.isFinite else { return .null }
    return Int(exactly: number).map { .int($0) } ?? .double(number)
}

/// `x` divided by `y` rounded down (Ruby's integer division); an overflow (`Int.min / -1`) is reported, not trapped.
private func floorDivide(_ x: Int, _ y: Int) -> (Int, Bool) {
    let (quotient, overflow) = x.dividedReportingOverflow(by: y)
    if overflow { return (0, true) }
    // no overflow: the product is no further from zero than x
    let rest = x - quotient * y
    return (rest != 0 && (rest < 0) != (y < 0)) ? (quotient - 1, false) : (quotient, false)
}

/// `x` modulo `y` with the sign of `y` (Ruby's); an overflow (`Int.min % -1`) is reported, not trapped.
private func floorModulo(_ x: Int, _ y: Int) -> (Int, Bool) {
    let (rest, overflow) = x.remainderReportingOverflow(dividingBy: y)
    if overflow { return (0, true) }
    // opposite signs: the sum is between them
    return (rest != 0 && (rest < 0) != (y < 0)) ? (rest + y, false) : (rest, false)
}
