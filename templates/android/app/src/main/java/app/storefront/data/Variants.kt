package app.storefront.data

object Variants {
    /** The variant whose options are exactly [selection] (option name to value), or null when none exists. */
    fun match(variants: List<Variant>, selection: Map<String, String>): Variant? =
        variants.firstOrNull { it.options == selection }
}
