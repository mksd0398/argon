import XCTest
@testable import ArgonStorefront

/// Argon's Liquid (Liquid.swift) against every shared case in Fixtures/liquid/cases.json, the lenient ones too: the same
/// cases liquidjs and Liquid.kt pass.
final class LiquidTests: XCTestCase {
    /// `over` merged into `base`, objects key by key, as the node test merges a case's context over the shared one.
    private func merge(_ base: [String: JSONValue], _ over: [String: JSONValue]?) -> [String: JSONValue] {
        guard let over = over else { return base }
        var out = base
        for (key, value) in over {
            if let map = value.object {
                out[key] = .object(merge(base[key]?.object ?? [:], map))
            } else {
                out[key] = value
            }
        }
        return out
    }

    func testEveryCase() throws {
        let root = try XCTUnwrap(JSONValue(json: contractFixture("liquid/cases.json"))?.object)
        let shared = try XCTUnwrap(root["context"]?.object)
        let cases = try XCTUnwrap(root["cases"]?.array)
        XCTAssertGreaterThanOrEqual(cases.count, 60)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        for item in cases {
            let name = item["name"]?.string ?? "?"
            let template = try XCTUnwrap(item["template"]?.string, name)
            let expected = try XCTUnwrap(item["expected"]?.string, name)
            let context = merge(shared, item["context"]?.object)
            XCTAssertEqual(Liquid.render(template, context, timeZone: utc), expected, name)
        }
    }

    func testTextWithoutLiquidIsAsItIs() {
        XCTAssertEqual(Liquid.render("50% off { not liquid }", [:]), "50% off { not liquid }")
        XCTAssertEqual(Liquid.render("", [:]), "")
    }

    func testNeverACrash() {
        let context: [String: JSONValue] = ["n": .int(3)]
        XCTAssertEqual(Liquid.render("a{% if n > 1 %}b", context), "ab", "an unclosed block: the text without the Liquid")
        XCTAssertEqual(Liquid.render("a{% endif %}b", context), "ab")
        XCTAssertEqual(Liquid.render("{{ n | divided_by: 0 }}|{{ n | modulo: 0 }}", context), "|")
        XCTAssertEqual(Liquid.render("{{ 'x }}", context), "")
        XCTAssertEqual(Liquid.render("{% for i in n %}{{ i }}{% else %}none{% endfor %}", context), "none", "not a list")
        XCTAssertEqual(Liquid.render("{{ n | date: '%Y' }}", context, timeZone: TimeZone(identifier: "UTC")!), "1970")
        XCTAssertEqual(Liquid.render("{{ 'soon' | date: '%Y' }}", context), "soon", "not a date: as it is")
    }

    func testNumbersNeverTrap() {
        let context: [String: JSONValue] = [
            "big": .int(Int.max - 1), "min": .int(Int.min), "items": .array([.int(1), .int(2)]),
            "huge": .double(1e300), "neg": .double(-1e30),
        ]
        let utc = TimeZone(identifier: "UTC")!
        func render(_ template: String) -> String { Liquid.render(template, context, timeZone: utc) }
        XCTAssertEqual(render(#"{{ "1e300" | ceil }}|{{ "1e300" | floor }}|{{ "1e300" | round }}"#), "1e+300|1e+300|1e+300")
        XCTAssertEqual(render("{% for i in items limit: huge %}{{ i }}{% endfor %}"), "12")
        XCTAssertEqual(render("{% for i in items offset: huge %}{{ i }}{% else %}none{% endfor %}"), "none")
        XCTAssertEqual(render("{{ big | modulo: 7 }} {{ big | modulo: -2 }} {{ min | modulo: -1 }}"), "\((Int.max - 1) % 7) 0 0")
        XCTAssertEqual(render("{{ min | divided_by: -1 }}"), "9.223372036854776e+18")
        XCTAssertEqual(render("{{ min | abs }}"), "9.223372036854776e+18")
        XCTAssertEqual(render("{{ big | plus: 10 }}"), "9.223372036854776e+18")
        XCTAssertEqual(render("{{ 'abc' | truncate: neg }}"), "...")
        XCTAssertEqual(render("{{ huge | date: '%Y' }}"), "1e+300", "not a date: as it is")
    }

    func testARunawayTemplateIsItsTextWithoutLiquid() {
        let start = Date()
        let doubling = "{% assign s = 'ab' %}" + String(repeating: "{% assign s = s | append: s %}", count: 40) + "[{{ s }}]"
        XCTAssertEqual(Liquid.render(doubling, [:]), "[]", "over the output cap")
        let many = String(repeating: "a,", count: 5000)
        let loops = "{% assign xs = '\(many)' | split: ',' %}{% for a in xs %}{% for b in xs %}{{ b }}{% endfor %}{% endfor %}done"
        XCTAssertEqual(Liquid.render(loops, [:]), "done", "over the work budget")
        let nested = String(repeating: "{% if true %}", count: 10_000) + "deep" + String(repeating: "{% endif %}", count: 10_000)
        XCTAssertEqual(Liquid.render(nested, [:]), "deep", "too deep")
        XCTAssertEqual(Liquid.render("{{ a" + String(repeating: "[a", count: 100) + String(repeating: "]", count: 100) + " }}", [:]), "")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testMoreThanTheCases() {
        let context: [String: JSONValue] = [
            "items": .array([.int(3), .int(1), .int(2)]),
            "map": .object(["size": .string("XL")]),
            "price": .string("-1234.567"),
            "shop": .object(["currency": .string("EUR")]),
        ]
        XCTAssertEqual(Liquid.render("{{ items[-1] }} {{ items.size }} {{ map.size }}", context), "2 3 XL")
        XCTAssertEqual(Liquid.render("{{ price | money }} {{ price | abs | money_without_currency }}", context), "€-1,234.57 1,234.57")
        XCTAssertEqual(Liquid.render("{{ -7 | divided_by: 2 }} {{ -7 | modulo: 3 }}", context), "-4 2")
        XCTAssertEqual(Liquid.render("{% if items contains 1 %}yes{% endif %}", context), "yes")
        XCTAssertEqual(Liquid.render("{% for i in items reversed limit: 2 %}{{ i }}{% endfor %}", context), "13")
        XCTAssertEqual(Liquid.render("{% assign x = items | size %}{% if x >= 3 and map %}{{ x | times: 2 }}{% endif %}", context), "6")
    }
}
