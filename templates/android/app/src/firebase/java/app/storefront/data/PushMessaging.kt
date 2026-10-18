package app.storefront.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import app.storefront.AppGraph
import app.storefront.MainActivity
import app.storefront.R
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Request

// Push through Firebase Cloud Messaging: compiled in with Firebase (`app/google-services.json`), used only with `PUSH`
// (the manifest enables PushService and FCM's auto-init with it).

/** Subscribes this install to an FCM topic, or unsubscribes it; the SDK's Task, awaited by hand. */
fun pushTopic(): (suspend (String, Boolean) -> Unit)? = { name, subscribe ->
    val messaging = FirebaseMessaging.getInstance()
    val task = if (subscribe) messaging.subscribeToTopic(name) else messaging.unsubscribeFromTopic(name)
    suspendCancellableCoroutine { continuation ->
        task.addOnCompleteListener {
            if (it.isSuccessful) continuation.resume(Unit) else continuation.resumeWithException(it.exception ?: IOException("FCM topic $name"))
        }
    }
}

private const val CHANNEL = "push"

/**
 * A message that arrives while the app is in the foreground: FCM leaves showing it to the app, so it is shown here, with
 * its image when it has one, and a tap opens the app with its `link` (as FCM's own notification does in the background).
 */
class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"]
        val body = message.notification?.body ?: message.data["body"]
        if (title == null && body == null) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Offers and news", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        PushStore.link(message.data)?.let { open.putExtra("link", it) }
        val tap = PendingIntent.getActivity(this, message.messageId.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.launcher_logo)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(tap)
        // onMessageReceived runs off the main thread: the picture can be fetched here
        (message.notification?.imageUrl?.toString() ?: message.data["image"])?.let { url ->
            runCatching {
                AppGraph.http.newCall(Request.Builder().url(url).build()).execute().use { BitmapFactory.decodeStream(it.body.byteStream()) }
            }.getOrNull()?.let { picture -> notification.setLargeIcon(picture).setStyle(NotificationCompat.BigPictureStyle().bigPicture(picture)) }
        }
        // without the permission (Android 13+) the system drops it
        runCatching { manager.notify(message.messageId.hashCode(), notification.build()) }
    }
}
