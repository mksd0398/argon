package app.storefront.auth

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Seals the customer's tokens with an AES-256-GCM key that never leaves the Android Keystore. A sealed value is
 * `base64(iv):base64(ciphertext)`. [decrypt] throws when the key is gone or the value was tampered with; AuthStore then
 * treats the session as signed out.
 */
object TokenCrypto {
    private const val ALIAS = "argon_tokens"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private val base64 = Base64.getEncoder()

    fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) } // the Keystore picks the IV
        return base64.encodeToString(cipher.iv) + ":" + base64.encodeToString(cipher.doFinal(plain.toByteArray()))
    }

    fun decrypt(sealed: String): String {
        val (iv, data) = sealed.split(':').map(Base64.getDecoder()::decode)
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
        return String(cipher.doFinal(data))
    }

    // Synchronized: two first calls at once must not each generate a key (the second would replace the first).
    @Synchronized
    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(spec) }.generateKey()
    }
}
