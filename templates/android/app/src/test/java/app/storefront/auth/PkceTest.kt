package app.storefront.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PkceTest {
    @Test
    fun challengeMatchesRfc7636AppendixB() {
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", Pkce.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    }

    @Test
    fun verifierIs64Base64UrlCharsAndRandom() {
        val verifiers = List(100) { Pkce.verifier() }
        verifiers.forEach { assertTrue(it, Regex("^[A-Za-z0-9_-]{64}$").matches(it)) }
        assertEquals(100, verifiers.toSet().size)
    }
}
