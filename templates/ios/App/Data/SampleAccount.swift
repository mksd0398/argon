import Foundation
import Observation

/// The demo store's sample account. mock.shop has no customer accounts, so the CLI bundles the Customer Account
/// operations' sample answers (`<Operation>.sample.json`, for mock.shop only) and the signed-out Account screen offers
/// to preview with them. While the preview is on (`AppGraph.sampleAccount`), `AppGraph.customerAccount` answers every
/// operation from those files, mutations too: nothing is saved.
enum SampleAccount {
    /// Whether the bundle has the sample files.
    static let available = url("Customer") != nil

    /// The response body of `operation`: its sample file as the `data`.
    static func response(_ operation: String) throws -> Data {
        guard let url = url(operation) else { throw NotFound(what: "Sample \(operation)") }
        return Data("{\"data\":".utf8) + (try Data(contentsOf: url)) + Data("}".utf8)
    }

    /// The demo store's sample reviews (a Judge.me widget's HTML), when the bundle has them.
    static let reviewsURL: URL? = Bundle.main.url(forResource: "JudgeMeWidget.sample", withExtension: "html")
        ?? Bundle.main.url(forResource: "JudgeMeWidget.sample", withExtension: "html", subdirectory: "sample")

    private static func url(_ operation: String) -> URL? {
        // a synchronized folder may copy sample/ flat into the bundle
        Bundle.main.url(forResource: "\(operation).sample", withExtension: "json")
            ?? Bundle.main.url(forResource: "\(operation).sample", withExtension: "json", subdirectory: "sample")
    }
}

/// Whether the sample account is on show, so views observe it.
@MainActor
@Observable
final class SampleAccountState {
    var active = false
}
