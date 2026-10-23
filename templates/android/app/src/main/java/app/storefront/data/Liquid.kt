package app.storefront.data

import java.math.BigDecimal
import java.math.RoundingMode
import java.net.URLEncoder
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Argon's own Liquid: the subset of the screens v2 spec, the same on iOS (`Liquid.swift`), checked by the shared cases
 * in contract/fixtures/liquid/cases.json. Values are Kotlin's: null (nil), Boolean, Long, Double (a literal with a
 * decimal point), String, List and Map (`Map<String, Any?>`). It never throws: an unknown filter makes its output empty,
 * an unknown tag renders nothing, and a syntax error renders the text without any of its Liquid.
 */
object Liquid {
    /**
     * [template] rendered with [context]. `date` formats in [zone]; `money` uses the currency at `shop.currency`. Text
     * without `{{` or `{%` comes back as it is, without being parsed.
     */
    fun render(template: String, context: Map<String, Any?>, zone: ZoneId = ZoneId.systemDefault()): String {
        if (!hasLiquid(template)) return template
        return try {
            val nodes = LiquidParser(tokenize(template)).parse()
            buildString { LiquidRenderer(context, zone).render(nodes, this) }
        } catch (e: Exception) {
            // a syntax error, the work budget or the output cap ([LiquidRenderer]), or a value no filter can take (NaN, an
            // infinite amount, a date out of range): the text without its Liquid, never a crash; reported, with the
            // template's start, so a store's broken Liquid shows up in App health
            CrashReports.record(e, "liquid: ${template.take(120)}")
            withoutLiquid(template)
        } catch (e: StackOverflowError) {
            CrashReports.record(e, "liquid: ${template.take(120)}")
            withoutLiquid(template)
        }
    }

    /** Whether [text] has any Liquid to evaluate. */
    fun hasLiquid(text: String): Boolean = "{{" in text || "{%" in text

    /** A JSON value as a Liquid value (a metafield's parsed value, a section's settings, the test cases' context). */
    fun value(json: JsonElement): Any? = when (json) {
        JsonNull -> null
        is JsonPrimitive -> if (json.isString) json.content else json.booleanOrNull ?: json.longOrNull ?: json.doubleOrNull
        is JsonArray -> json.map(::value)
        is JsonObject -> json.mapValues { value(it.value) }
    }

    private val COMPLETE_TAG = Regex("""\{\{.*?\}\}|\{%.*?%\}""", RegexOption.DOT_MATCHES_ALL)

    /** [template] with every Liquid tag taken out, and an unterminated one cut to the end: what a syntax error renders. */
    internal fun withoutLiquid(template: String): String {
        val text = template.replace(COMPLETE_TAG, "")
        val open = listOf(text.indexOf("{{"), text.indexOf("{%")).filter { it >= 0 }.minOrNull()
        return if (open == null) text else text.substring(0, open)
    }
}

internal class LiquidSyntaxError(message: String) : Exception(message)

private class UnknownFilter : Exception()

// ─── Tokens ───────────────────────────────────────────────────────────────

private sealed interface LiquidToken {
    class Text(var text: String) : LiquidToken
    class Output(val markup: String) : LiquidToken
    class Tag(val name: String, val markup: String) : LiquidToken
}

private val RAW_END = Regex("""\{%-?\s*endraw\s*-?%\}""")
private val COMMENT_END = Regex("""\{%-?\s*endcomment\s*-?%\}""")

/** The template as text, outputs and tags, with whitespace control (`{{-`, `-%}`) already applied to the text. */
private fun tokenize(template: String): List<LiquidToken> {
    val tokens = mutableListOf<LiquidToken>()
    var trimNext = false
    var i = 0
    fun text(value: String) {
        val trimmed = if (trimNext) value.trimStart() else value
        trimNext = false
        if (trimmed.isNotEmpty()) tokens += LiquidToken.Text(trimmed)
    }
    fun trimPrevious() {
        val last = tokens.lastOrNull() as? LiquidToken.Text ?: return
        last.text = last.text.trimEnd()
        if (last.text.isEmpty()) tokens.removeAt(tokens.lastIndex)
    }
    while (i < template.length) {
        val output = template.indexOf("{{", i)
        val tag = template.indexOf("{%", i)
        val start = listOf(output, tag).filter { it >= 0 }.minOrNull()
        if (start == null) {
            text(template.substring(i))
            break
        }
        text(template.substring(i, start))
        val isOutput = start == output
        val close = template.indexOf(if (isOutput) "}}" else "%}", start + 2)
        if (close < 0) throw LiquidSyntaxError("unterminated tag")
        var markup = template.substring(start + 2, close)
        if (markup.startsWith("-")) {
            markup = markup.substring(1)
            trimPrevious()
        }
        val trimAfter = markup.endsWith("-")
        if (trimAfter) markup = markup.dropLast(1)
        markup = markup.trim()
        i = close + 2
        trimNext = trimAfter
        if (isOutput) {
            tokens += LiquidToken.Output(markup)
            continue
        }
        val name = markup.substringBefore(' ').substringBefore('\n').trim()
        val rest = markup.substring(name.length).trim()
        when (name) {
            // raw: the text up to endraw, as it is; comment: nothing up to endcomment
            "raw", "comment" -> {
                val end = (if (name == "raw") RAW_END else COMMENT_END).find(template, i) ?: throw LiquidSyntaxError("no end$name")
                if (name == "raw") text(template.substring(i, end.range.first)) else trimNext = false
                trimNext = end.value.endsWith("-%}")
                i = end.range.last + 1
            }
            else -> tokens += LiquidToken.Tag(name, rest)
        }
    }
    return tokens
}

// ─── Expressions ──────────────────────────────────────────────────────────

private sealed interface LiquidLexeme {
    data class Str(val value: String) : LiquidLexeme
    data class Num(val value: Any) : LiquidLexeme
    data class Ident(val name: String) : LiquidLexeme
    data class Sym(val symbol: String) : LiquidLexeme
}

private val LEXEME = Regex(
    """\s*(?:'([^']*)'|"([^"]*)"|(-?\d+\.\d+)|(-?\d+)|([A-Za-z_][A-Za-z0-9_-]*\??)|(==|!=|<>|<=|>=|[<>.\[\]|:,()]))""",
    RegexOption.DOT_MATCHES_ALL,
)

private fun lex(markup: String): List<LiquidLexeme> {
    val out = mutableListOf<LiquidLexeme>()
    var i = 0
    while (i < markup.length) {
        if (markup[i].isWhitespace()) {
            i++
            continue
        }
        val match = LEXEME.matchAt(markup, i) ?: throw LiquidSyntaxError("unexpected '${markup[i]}'")
        val g = match.groupValues
        out += when {
            match.groups[1] != null -> LiquidLexeme.Str(g[1])
            match.groups[2] != null -> LiquidLexeme.Str(g[2])
            match.groups[3] != null -> LiquidLexeme.Num(g[3].toDouble())
            match.groups[4] != null -> LiquidLexeme.Num(g[4].toLongOrNull() ?: g[4].toDouble())
            match.groups[5] != null -> LiquidLexeme.Ident(g[5])
            else -> LiquidLexeme.Sym(g[6])
        }
        i = match.range.last + 1
    }
    return out
}

private sealed interface LiquidExpr {
    data class Literal(val value: Any?) : LiquidExpr
    data class Variable(val name: String, val path: List<LiquidExpr>) : LiquidExpr
}

/** Liquid's `empty`: equal to an empty text, list or map. */
private object LiquidEmpty

private class LiquidFilter(val name: String, val args: List<LiquidExpr>)

private class LiquidFiltered(val expr: LiquidExpr, val filters: List<LiquidFilter>)

/** One comparison of a condition; [op] null: [left] alone, by its truthiness. */
private class LiquidComparison(val left: LiquidExpr, val op: String?, val right: LiquidExpr?)

/** Comparisons joined by `and` / `or` ([joins] between them), evaluated right to left as Liquid does. */
private class LiquidCondition(val parts: List<LiquidComparison>, val joins: List<String>)

private class LiquidLexer(private val items: List<LiquidLexeme>) {
    var at = 0
    val done: Boolean get() = at >= items.size
    fun peek(): LiquidLexeme? = items.getOrNull(at)
    fun next(): LiquidLexeme = items.getOrNull(at++) ?: throw LiquidSyntaxError("unexpected end")
    fun isSym(symbol: String) = (peek() as? LiquidLexeme.Sym)?.symbol == symbol
    fun isIdent(name: String) = (peek() as? LiquidLexeme.Ident)?.name == name
    fun expect(symbol: String) {
        if (!isSym(symbol)) throw LiquidSyntaxError("expected $symbol")
        at++
    }
    fun end() {
        if (!done) throw LiquidSyntaxError("unexpected ${peek()}")
    }

    fun expr(): LiquidExpr = when (val lexeme = next()) {
        is LiquidLexeme.Str -> LiquidExpr.Literal(lexeme.value)
        is LiquidLexeme.Num -> LiquidExpr.Literal(lexeme.value)
        is LiquidLexeme.Ident -> when (lexeme.name) {
            "true" -> LiquidExpr.Literal(true)
            "false" -> LiquidExpr.Literal(false)
            "nil", "null" -> LiquidExpr.Literal(null)
            "empty", "blank" -> LiquidExpr.Literal(LiquidEmpty)
            else -> {
                val path = mutableListOf<LiquidExpr>()
                while (true) {
                    if (isSym(".")) {
                        at++
                        val key = next() as? LiquidLexeme.Ident ?: throw LiquidSyntaxError("expected a name")
                        path += LiquidExpr.Literal(key.name)
                    } else if (isSym("[")) {
                        at++
                        path += expr()
                        expect("]")
                    } else {
                        break
                    }
                }
                LiquidExpr.Variable(lexeme.name, path)
            }
        }
        is LiquidLexeme.Sym -> throw LiquidSyntaxError("unexpected ${lexeme.symbol}")
    }

    fun filtered(): LiquidFiltered {
        val expr = expr()
        val filters = mutableListOf<LiquidFilter>()
        while (isSym("|")) {
            at++
            val name = next() as? LiquidLexeme.Ident ?: throw LiquidSyntaxError("expected a filter")
            val args = mutableListOf<LiquidExpr>()
            if (isSym(":")) {
                at++
                do {
                    if (args.isNotEmpty() || isSym(",")) expect(",")
                    // a named argument (`key: value`) is read for its value
                    if (peek() is LiquidLexeme.Ident && (items.getOrNull(at + 1) as? LiquidLexeme.Sym)?.symbol == ":") at += 2
                    args += expr()
                } while (isSym(","))
            }
            filters += LiquidFilter(name.name, args)
        }
        return LiquidFiltered(expr, filters)
    }

    fun condition(): LiquidCondition {
        val parts = mutableListOf<LiquidComparison>()
        val joins = mutableListOf<String>()
        while (true) {
            val left = expr()
            val op = when (val lexeme = peek()) {
                is LiquidLexeme.Sym -> lexeme.symbol.takeIf { it in setOf("==", "!=", "<>", "<", ">", "<=", ">=") }
                is LiquidLexeme.Ident -> lexeme.name.takeIf { it == "contains" }
                else -> null
            }
            if (op != null) at++
            parts += LiquidComparison(left, op, if (op != null) expr() else null)
            if (isIdent("and") || isIdent("or")) joins += (next() as LiquidLexeme.Ident).name else break
        }
        end()
        return LiquidCondition(parts, joins)
    }
}

private fun filteredOf(markup: String) = LiquidLexer(lex(markup)).let { lexer -> lexer.filtered().also { lexer.end() } }

// ─── Nodes ────────────────────────────────────────────────────────────────

private sealed interface LiquidNode {
    class Text(val text: String) : LiquidNode
    class Output(val value: LiquidFiltered) : LiquidNode
    class If(val branches: List<Pair<LiquidCondition, List<LiquidNode>>>, val otherwise: List<LiquidNode>?, val unless: Boolean) : LiquidNode
    class For(
        val variable: String,
        val collection: LiquidExpr,
        val limit: LiquidExpr?,
        val offset: LiquidExpr?,
        val reversed: Boolean,
        val body: List<LiquidNode>,
        val otherwise: List<LiquidNode>?,
    ) : LiquidNode
    class Assign(val name: String, val value: LiquidFiltered) : LiquidNode
    class Capture(val name: String, val body: List<LiquidNode>) : LiquidNode
}

private val CLOSING = setOf("elsif", "else", "endif", "endunless", "endfor", "endcapture")

private class LiquidParser(private val tokens: List<LiquidToken>) {
    private var at = 0

    fun parse(): List<LiquidNode> {
        val (nodes, end) = block(emptySet())
        if (end != null) throw LiquidSyntaxError("unexpected ${end.name}")
        return nodes
    }

    /** Nodes up to one of the tags [ends] (returned with them); null at the template's end, which only the top may reach. */
    private fun block(ends: Set<String>): Pair<List<LiquidNode>, LiquidToken.Tag?> {
        val nodes = mutableListOf<LiquidNode>()
        while (at < tokens.size) {
            when (val token = tokens[at++]) {
                is LiquidToken.Text -> nodes += LiquidNode.Text(token.text)
                is LiquidToken.Output -> nodes += LiquidNode.Output(filteredOf(token.markup))
                is LiquidToken.Tag -> when {
                    token.name in ends -> return nodes to token
                    token.name in CLOSING -> throw LiquidSyntaxError("unexpected ${token.name}")
                    token.name == "if" || token.name == "unless" -> nodes += conditional(token)
                    token.name == "for" -> nodes += loop(token)
                    token.name == "assign" -> {
                        val name = token.markup.substringBefore('=').trim()
                        if (!name.matches(Regex("[A-Za-z_][A-Za-z0-9_-]*")) || '=' !in token.markup) throw LiquidSyntaxError("bad assign")
                        nodes += LiquidNode.Assign(name, filteredOf(token.markup.substringAfter('=')))
                    }
                    token.name == "capture" -> {
                        val name = token.markup.trim().trim('\'', '"')
                        val (body, _) = closed(setOf("endcapture"))
                        nodes += LiquidNode.Capture(name, body)
                    }
                    // any other tag (render, section, form, paginate, ...) renders nothing
                    else -> Unit
                }
            }
        }
        if (ends.isNotEmpty()) throw LiquidSyntaxError("missing ${ends.last()}")
        return nodes to null
    }

    private fun closed(ends: Set<String>): Pair<List<LiquidNode>, LiquidToken.Tag> {
        val (nodes, end) = block(ends)
        return nodes to (end ?: throw LiquidSyntaxError("missing ${ends.last()}"))
    }

    private fun conditional(open: LiquidToken.Tag): LiquidNode {
        val unless = open.name == "unless"
        val endName = if (unless) "endunless" else "endif"
        val branches = mutableListOf<Pair<LiquidCondition, List<LiquidNode>>>()
        var condition = LiquidLexer(lex(open.markup)).condition()
        while (true) {
            val (body, end) = closed(setOf("elsif", "else", endName))
            branches += condition to body
            when (end.name) {
                "elsif" -> condition = LiquidLexer(lex(end.markup)).condition()
                "else" -> return LiquidNode.If(branches, closed(setOf(endName)).first, unless)
                else -> return LiquidNode.If(branches, null, unless)
            }
        }
    }

    private fun loop(open: LiquidToken.Tag): LiquidNode {
        val lexer = LiquidLexer(lex(open.markup))
        val variable = (lexer.next() as? LiquidLexeme.Ident)?.name ?: throw LiquidSyntaxError("for needs a name")
        if ((lexer.next() as? LiquidLexeme.Ident)?.name != "in") throw LiquidSyntaxError("for needs in")
        val collection = lexer.expr()
        var limit: LiquidExpr? = null
        var offset: LiquidExpr? = null
        var reversed = false
        while (!lexer.done) {
            when ((lexer.next() as? LiquidLexeme.Ident)?.name) {
                "reversed" -> reversed = true
                "limit" -> {
                    lexer.expect(":")
                    limit = lexer.expr()
                }
                "offset" -> {
                    lexer.expect(":")
                    offset = lexer.expr()
                }
                else -> throw LiquidSyntaxError("bad for")
            }
            if (lexer.isSym(",")) lexer.next()
        }
        val (body, end) = closed(setOf("else", "endfor"))
        val otherwise = if (end.name == "else") closed(setOf("endfor")).first else null
        return LiquidNode.For(variable, collection, limit, offset, reversed, body, otherwise)
    }
}

// ─── Rendering ────────────────────────────────────────────────────────────

private class LiquidRenderer(private val context: Map<String, Any?>, private val zone: ZoneId) {
    // what one render may do: a template that loops or grows past this (a merchant's mistake) renders as text without Liquid
    private var steps = 0

    private fun step() {
        if (++steps > MAX_STEPS) throw LiquidSyntaxError("over the work budget")
    }

    private fun capped(value: Any?): Any? {
        if (value is String && value.length > MAX_OUTPUT) throw LiquidSyntaxError("over the output cap")
        return value
    }

    // assigns, captures and loop variables: they shadow the context
    private val locals = mutableMapOf<String, Any?>()

    fun render(nodes: List<LiquidNode>, out: StringBuilder) {
        for (node in nodes) {
            step()
            if (out.length > MAX_OUTPUT) throw LiquidSyntaxError("over the output cap")
            renderNode(node, out)
        }
    }

    private fun renderNode(node: LiquidNode, out: StringBuilder) {
        when (node) {
            is LiquidNode.Text -> out.append(node.text)
            is LiquidNode.Output -> out.append(text(try {
                evaluate(node.value)
            } catch (e: UnknownFilter) {
                null
            }))
            is LiquidNode.If -> {
                // unless: its own condition reads the other way round; its elsif branches don't
                val branch = node.branches.withIndex().firstOrNull { (i, branch) -> test(branch.first) != (node.unless && i == 0) }
                if (branch != null) render(branch.value.second, out) else node.otherwise?.let { render(it, out) }
            }
            is LiquidNode.For -> loop(node, out)
            is LiquidNode.Assign -> locals[node.name] = try {
                evaluate(node.value)
            } catch (e: UnknownFilter) {
                null
            }
            is LiquidNode.Capture -> locals[node.name] = buildString { render(node.body, this) }
        }
    }

    private fun loop(node: LiquidNode.For, out: StringBuilder) {
        val all = when (val value = evaluate(node.collection)) {
            is List<*> -> value
            is Map<*, *> -> value.entries.map { listOf(it.key, it.value) }
            null, LiquidEmpty -> emptyList()
            else -> listOf(value)
        }
        val offset = node.offset?.let { number(evaluate(it)).toInt() } ?: 0
        val limit = node.limit?.let { number(evaluate(it)).toInt() }
        val sliced = all.drop(offset.coerceAtLeast(0)).let { if (limit != null) it.take(limit.coerceAtLeast(0)) else it }
        val items = if (node.reversed) sliced.reversed() else sliced
        if (items.isEmpty()) {
            node.otherwise?.let { render(it, out) }
            return
        }
        val saved = locals.containsKey(node.variable) to locals[node.variable]
        val savedLoop = locals["forloop"]
        for ((i, item) in items.withIndex()) {
            step()
            locals[node.variable] = item
            locals["forloop"] = mapOf(
                "index" to (i + 1).toLong(), "index0" to i.toLong(), "rindex" to (items.size - i).toLong(), "rindex0" to (items.size - i - 1).toLong(),
                "first" to (i == 0), "last" to (i == items.lastIndex), "length" to items.size.toLong(),
            )
            render(node.body, out)
        }
        if (saved.first) locals[node.variable] = saved.second else locals.remove(node.variable)
        locals["forloop"] = savedLoop
    }

    private fun test(condition: LiquidCondition): Boolean {
        var result = compare(condition.parts.last())
        for (i in condition.joins.indices.reversed()) {
            val left = compare(condition.parts[i])
            result = if (condition.joins[i] == "and") left && result else left || result
        }
        return result
    }

    private fun compare(c: LiquidComparison): Boolean {
        val left = evaluate(c.left)
        if (c.op == null) return truthy(left)
        val right = evaluate(c.right!!)
        return when (c.op) {
            "==" -> same(left, right)
            "!=", "<>" -> !same(left, right)
            "contains" -> when (left) {
                is String -> right != null && text(right) in left
                is List<*> -> left.any { same(it, right) }
                else -> false
            }
            else -> {
                val order = order(left, right) ?: return false
                when (c.op) {
                    "<" -> order < 0
                    ">" -> order > 0
                    "<=" -> order <= 0
                    else -> order >= 0
                }
            }
        }
    }

    private fun evaluate(value: LiquidFiltered): Any? =
        value.filters.fold(evaluate(value.expr)) { input, filter -> capped(applyFilter(filter.name, input, filter.args.map(::evaluate))) }

    private fun evaluate(expr: LiquidExpr): Any? = when (expr) {
        is LiquidExpr.Literal -> expr.value
        is LiquidExpr.Variable -> expr.path.fold(if (locals.containsKey(expr.name)) locals[expr.name] else context[expr.name]) { node, key ->
            lookup(node, evaluate(key))
        }
    }

    private fun lookup(node: Any?, key: Any?): Any? = when (node) {
        is Map<*, *> -> when {
            node.containsKey(key) -> node[key]
            key == "size" -> node.size.toLong()
            else -> null
        }
        is List<*> -> when (key) {
            is Number -> key.toInt().let { i -> node.getOrNull(if (i < 0) node.size + i else i) }
            "size" -> node.size.toLong()
            "first" -> node.firstOrNull()
            "last" -> node.lastOrNull()
            else -> null
        }
        is String -> if (key == "size") node.length.toLong() else null
        else -> null
    }

    private fun applyFilter(name: String, input: Any?, args: List<Any?>): Any? {
        fun arg(i: Int) = args.getOrNull(i)
        fun s(i: Int) = text(arg(i))
        val str = text(input)
        return when (name) {
            "append" -> str + s(0)
            "prepend" -> s(0) + str
            "upcase" -> str.uppercase()
            "downcase" -> str.lowercase()
            "capitalize" -> str.lowercase().replaceFirstChar { it.uppercase() }
            "strip" -> str.trim()
            "lstrip" -> str.trimStart()
            "rstrip" -> str.trimEnd()
            "strip_html" -> str.replace(SCRIPTS, "").replace(TAGS, "")
            "escape" -> str.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
            "truncate" -> {
                val length = if (args.isEmpty()) 50 else number(arg(0)).toInt()
                val ellipsis = if (args.size > 1) s(1) else "..."
                if (str.length <= length) str else str.take((length - ellipsis.length).coerceAtLeast(0)) + ellipsis
            }
            "truncatewords" -> {
                val count = if (args.isEmpty()) 15 else number(arg(0)).toInt().coerceAtLeast(1)
                val ellipsis = if (args.size > 1) s(1) else "..."
                val words = str.split(WHITESPACE).filter { it.isNotEmpty() }
                if (words.size <= count) str else words.take(count).joinToString(" ") + ellipsis
            }
            "replace" -> str.replace(s(0), s(1))
            "replace_first" -> str.replaceFirst(s(0), s(1))
            "remove" -> str.replace(s(0), "")
            "remove_first" -> str.replaceFirst(s(0), "")
            "split" -> if (s(0).isEmpty()) str.map { it.toString() } else str.split(s(0)).dropLastWhile { it.isEmpty() }
            "join" -> if (input is List<*>) input.joinToString(if (args.isEmpty()) " " else s(0)) { text(it) } else str
            "first" -> if (input is List<*>) input.firstOrNull() else str.take(1).ifEmpty { null }
            "last" -> if (input is List<*>) input.lastOrNull() else str.takeLast(1).ifEmpty { null }
            "size" -> when (input) {
                is List<*> -> input.size.toLong()
                is Map<*, *> -> input.size.toLong()
                null -> 0L
                else -> str.length.toLong()
            }
            "default" -> if (input == null || input == false || input == "" || (input as? Collection<*>)?.isEmpty() == true || (input as? Map<*, *>)?.isEmpty() == true) arg(0) else input
            "plus" -> math(input, arg(0), Long::plus, Double::plus)
            "minus" -> math(input, arg(0), Long::minus, Double::minus)
            "times" -> math(input, arg(0), Long::times, Double::times)
            "divided_by" -> {
                val divisor = numeric(arg(0))
                if (divisor.toDouble() == 0.0) null else math(input, divisor, { a, b -> Math.floorDiv(a, b) }, Double::div)
            }
            "modulo" -> {
                val divisor = numeric(arg(0))
                if (divisor.toDouble() == 0.0) null else math(input, divisor, { a, b -> Math.floorMod(a, b) }, { a, b -> a - b * floor(a / b) })
            }
            "round" -> {
                val places = if (args.isEmpty()) 0 else number(arg(0)).toInt()
                val value = number(input)
                if (places <= 0) value.roundToLong() else (value * 10.0.pow(places)).roundToLong() / 10.0.pow(places)
            }
            "ceil" -> ceil(number(input)).toLong()
            "floor" -> floor(number(input)).toLong()
            "abs" -> when (val n = numeric(input)) {
                is Long -> abs(n)
                else -> abs(n.toDouble())
            }
            "date" -> date(input, s(0))
            "money" -> money(input, currency = true)
            "money_without_currency" -> money(input, currency = false)
            "handleize", "handle" -> str.lowercase().replace(NOT_HANDLE, "-").trim('-')
            "url_encode" -> URLEncoder.encode(str, "UTF-8")
            "newline_to_br" -> str.replace("\n", "<br />\n")
            "pluralize" -> if (number(input) == 1.0) s(0) else s(1)
            else -> throw UnknownFilter()
        }
    }

    private fun math(a: Any?, b: Any?, whole: (Long, Long) -> Long, real: (Double, Double) -> Double): Any {
        val x = numeric(a)
        val y = numeric(b)
        return if (x is Long && y is Long) whole(x, y) else real(x.toDouble(), y.toDouble())
    }

    private fun date(input: Any?, format: String): Any? {
        val time: ZonedDateTime = when (input) {
            "now", "today" -> ZonedDateTime.now(zone)
            is Number -> Instant.ofEpochSecond(input.toLong()).atZone(zone)
            is String -> parseTime(input.trim(), zone) ?: return input
            else -> return input
        }
        if (format.isEmpty()) return input
        return strftime(time, format)
    }

    private fun money(input: Any?, currency: Boolean): String {
        val amount = when (input) {
            is Number -> BigDecimal(input.toString())
            else -> text(input).trim().toBigDecimalOrNull() ?: BigDecimal.ZERO
        }
        val grouped = DecimalFormat("#,##0.00", DecimalFormatSymbols(Locale.US)).apply { roundingMode = RoundingMode.HALF_UP }.format(amount)
        if (!currency) return grouped
        val code = text(lookup(context["shop"], "currency")).trim().uppercase()
        return MONEY_SYMBOLS[code]?.let { it + grouped } ?: "$grouped $code".trim()
    }
}

/** The work one render may do: tags, outputs and loop iterations. */
private const val MAX_STEPS = 100_000

/** The longest output, or text value, one render may make (256 KB). */
private const val MAX_OUTPUT = 256 * 1024

private val SCRIPTS = Regex("""<(script|style)\b[^>]*>.*?</\1\s*>|<!--.*?-->""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
private val TAGS = Regex("<[^>]*>")
private val WHITESPACE = Regex("\\s+")
private val NOT_HANDLE = Regex("[^a-z0-9]+")

/** The currencies `money` writes with a symbol (the same table as iOS and test/liquid.test.js); others get their code after. */
internal val MONEY_SYMBOLS = mapOf("USD" to "$", "CAD" to "$", "AUD" to "$", "NZD" to "$", "SGD" to "$", "INR" to "₹", "EUR" to "€", "GBP" to "£", "JPY" to "¥")

private fun truthy(value: Any?) = value != null && value != false

/** Liquid's `==`: numbers by value, `empty` against an empty text, list or map, anything else as equal values. */
private fun same(a: Any?, b: Any?): Boolean = when {
    a === LiquidEmpty -> isEmpty(b)
    b === LiquidEmpty -> isEmpty(a)
    a is Number && b is Number -> a.toDouble() == b.toDouble()
    else -> a == b
}

private fun isEmpty(value: Any?) = value == "" || (value as? Collection<*>)?.isEmpty() == true || (value as? Map<*, *>)?.isEmpty() == true

private fun order(a: Any?, b: Any?): Int? = when {
    a is Number && b is Number -> a.toDouble().compareTo(b.toDouble())
    a is String && b is String -> a.compareTo(b)
    else -> null
}

/** A value as a number for math: Long when it is a whole one, Double when not; text is read, anything else is 0. */
private fun numeric(value: Any?): Number = when (value) {
    is Long -> value
    is Int -> value.toLong()
    is Double -> value
    is Number -> value.toDouble()
    is String -> value.trim().let { it.toLongOrNull() ?: it.toDoubleOrNull() ?: 0L }
    else -> 0L
}

private fun number(value: Any?): Double = numeric(value).toDouble()

/** A value as output text: nil is empty, a whole double has no decimals (as liquidjs prints it), a list is joined. */
private fun text(value: Any?): String = when (value) {
    null, LiquidEmpty -> ""
    is Double -> if (value.isFinite() && value == floor(value) && abs(value) < 1e15) value.toLong().toString() else value.toString()
    is List<*> -> value.joinToString("") { text(it) }
    is Map<*, *> -> ""
    else -> value.toString()
}

private fun parseTime(value: String, zone: ZoneId): ZonedDateTime? =
    runCatching { Instant.parse(value).atZone(zone) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(value).atZoneSameInstant(zone) }.getOrNull()
        ?: runCatching { LocalDate.parse(value).atStartOfDay(zone) }.getOrNull()

private val MONTHS = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
private val DAYS = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

/** [time] by the strftime subset `%Y %m %d %e %b %B %a %A %H %M %S %I %p %y %j %%`, in English; other directives stay as written. */
private fun strftime(time: ZonedDateTime, format: String): String = buildString {
    var i = 0
    fun two(n: Int) = n.toString().padStart(2, '0')
    while (i < format.length) {
        val c = format[i]
        if (c != '%' || i == format.lastIndex) {
            append(c)
            i++
            continue
        }
        val hour12 = (time.hour % 12).let { if (it == 0) 12 else it }
        when (val d = format[i + 1]) {
            'Y' -> append(time.year)
            'm' -> append(two(time.monthValue))
            'd' -> append(two(time.dayOfMonth))
            'e' -> append(time.dayOfMonth.toString().padStart(2, ' '))
            'b' -> append(MONTHS[time.monthValue - 1].take(3))
            'B' -> append(MONTHS[time.monthValue - 1])
            'a' -> append(DAYS[time.dayOfWeek.value - 1].take(3))
            'A' -> append(DAYS[time.dayOfWeek.value - 1])
            'H' -> append(two(time.hour))
            'M' -> append(two(time.minute))
            'S' -> append(two(time.second))
            'I' -> append(two(hour12))
            'p' -> append(if (time.hour < 12) "AM" else "PM")
            'y' -> append(two(time.year % 100))
            'j' -> append(time.dayOfYear.toString().padStart(3, '0'))
            '%' -> append('%')
            else -> append('%').append(d)
        }
        i += 2
    }
}
