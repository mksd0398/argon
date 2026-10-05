enum Variants {
    /// The variant whose options are exactly `selection` (option name to value), or nil when none exists.
    static func match(_ variants: [Variant], selection: [String: String]) -> Variant? {
        variants.first { $0.options == selection }
    }
}
