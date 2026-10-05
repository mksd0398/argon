package app.storefront.auth

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** PKCE (RFC 7636) for the public-client sign-in: S256 challenge, base64url without padding. */
object Pkce {
    private val random = SecureRandom()
    private val base64Url = Base64.getUrlEncoder().withoutPadding()

    /** 64 base64url characters (48 random bytes). Also used for `state` and `nonce`: any unguessable value will do. */
    fun verifier(): String = base64Url.encodeToString(ByteArray(48).also(random::nextBytes))

    fun challenge(verifier: String): String =
        base64Url.encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
}
