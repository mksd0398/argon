import XCTest
@testable import ArgonStorefront

final class PkceTests: XCTestCase {
    func testChallengeMatchesRfc7636AppendixB() {
        XCTAssertEqual(Pkce.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierIs64Base64UrlCharsAndRandom() {
        let verifiers = (0..<100).map { _ in Pkce.verifier() }
        for verifier in verifiers {
            XCTAssertNotNil(verifier.range(of: "^[A-Za-z0-9_-]{64}$", options: .regularExpression), verifier)
        }
        XCTAssertEqual(Set(verifiers).count, 100)
    }
}
