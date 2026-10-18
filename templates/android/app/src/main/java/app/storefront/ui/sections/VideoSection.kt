package app.storefront.ui.sections

import android.net.Uri
import android.widget.VideoView
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.storefront.data.SectionContent
import app.storefront.ui.StoreImage

/**
 * A video section: the platform's [VideoView] (an mp4 or HLS url), in a box of the section's aspect, its poster over it
 * until it plays. Muted (the volume set to 0 once prepared) and looping by its settings; a tap plays or pauses it.
 */
@Composable
internal fun VideoSection(content: SectionContent.Video) {
    val url = content.url ?: return
    var playing by remember { mutableStateOf(false) }
    var started by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<VideoView?>(null) }
    Box(
        Modifier.fillMaxWidth().aspectRatio(content.ratio).clickable(onClickLabel = if (playing) "Pause" else "Play", role = Role.Button) {
            val player = view ?: return@clickable
            if (player.isPlaying) player.pause() else player.start()
            playing = player.isPlaying
            started = started || playing
        },
        Alignment.Center,
    ) {
        AndroidView(
            factory = { context ->
                VideoView(context).apply {
                    setOnPreparedListener { player ->
                        player.isLooping = content.loop
                        if (content.muted) player.setVolume(0f, 0f)
                        if (content.autoplay) {
                            start()
                            playing = true
                            started = true
                        }
                    }
                    setOnCompletionListener { playing = false }
                    // a video that can't be played keeps its poster; returning true stops the system's error dialog
                    setOnErrorListener { _, _, _ -> playing = false; true }
                    setVideoURI(Uri.parse(url))
                    view = this
                }
            },
            modifier = Modifier.matchParentSize(),
            onRelease = { it.stopPlayback() },
        )
        if (!started) {
            content.poster?.let { StoreImage(it, null, Modifier.matchParentSize()) }
            ArgonIcon(ArgonIconName.Play, size = 40.dp, tint = ArgonTheme.colors.paper)
        }
    }
}
