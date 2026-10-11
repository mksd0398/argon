package app.storefront.ui.product

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonBottomSheet
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonProgressBar
import app.argon.ui.components.ArgonRating
import app.argon.ui.components.ArgonSheetDetent
import app.argon.ui.components.ArgonSpinner
import app.argon.ui.components.ArgonTextArea
import app.storefront.AppGraph
import app.storefront.data.JudgeMe
import app.storefront.data.Review
import app.storefront.data.ReviewPage
import app.storefront.data.ReviewSummary
import app.storefront.ui.LabelTag
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage
import app.storefront.ui.displayDate
import java.util.Locale
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Block 11 of the product page: the product's Judge.me reviews (summary, list, "Load more") and the sheet to write one.

/**
 * The stars beside the product's title: the reviews' own [summary] once it has loaded with reviews, else the product's
 * rating metafields ([rating], [ratingCount]). Null for a product nobody has reviewed.
 */
internal fun shownRating(summary: ReviewSummary?, rating: Double?, ratingCount: Int?): Pair<Double, Int?>? = when {
    summary != null && summary.count > 0 -> summary.average to summary.count
    rating != null && ratingCount != 0 -> rating to ratingCount
    else -> null
}

/** "1 star", "4 stars". */
internal fun starsLabel(stars: Int): String = if (stars == 1) "1 star" else "$stars stars"

/** "1 review", "128 reviews". */
internal fun reviewCountLabel(count: Int): String = if (count == 1) "1 review" else "$count reviews"

/** "4.6": the average with one decimal. */
internal fun averageLabel(average: Double): String = String.format(Locale.US, "%.1f", average)

/** How much of the bar for [stars] is filled: the share of all the reviews that gave them, 0 to 1. */
internal fun histogramShare(summary: ReviewSummary, stars: Int): Float =
    if (summary.count <= 0) 0f else ((summary.histogram[stars] ?: 0).toFloat() / summary.count).coerceIn(0f, 1f)

/** What the shopper has put in the write-a-review sheet; [rating] 0 is none chosen yet. */
internal data class ReviewForm(val rating: Int = 0, val title: String = "", val body: String = "", val name: String = "", val email: String = "")

/** What is wrong with a [ReviewForm], by field (null: nothing). */
internal data class ReviewFormErrors(val rating: String? = null, val body: String? = null, val name: String? = null, val email: String? = null) {
    /** Nothing is wrong: the review can be sent. */
    val isEmpty: Boolean get() = this == ReviewFormErrors()
}

// something@something.something, without spaces: enough to catch a slip, Judge.me checks the rest
private val EMAIL = Regex("""[^@\s]+@[^@\s]+\.[^@\s.]+""")

/** A review needs a rating, a body, a name and a plausible email; the title is optional. */
internal fun validate(form: ReviewForm) = ReviewFormErrors(
    rating = "Choose a rating".takeIf { form.rating !in 1..5 },
    body = "Write your review".takeIf { form.body.isBlank() },
    name = "Enter your name".takeIf { form.name.isBlank() },
    email = "Enter a valid email address".takeIf { !EMAIL.matches(form.email.trim()) },
)

internal const val REVIEW_SENT = "Thanks. Your review appears once it's approved."
internal const val REVIEW_NOT_SENT = "Your review couldn't be sent. Try again."

/**
 * A product's reviews as far as they are loaded. [load] fetches a page (from 1), [send] a new review. Loading never
 * throws: a failure sets [failed] (the block shows "Reviews couldn't load" with Retry) and the next [loadMore] asks for
 * the same page again.
 */
@Stable
internal class ReviewsState(private val load: suspend (page: Int) -> ReviewPage, private val send: suspend (ReviewForm) -> Unit) {
    constructor(judgeMe: JudgeMe, productId: String) : this(
        load = { page -> judgeMe.reviews(productId, page) },
        send = { form -> judgeMe.submit(productId, form.name.trim(), form.email.trim(), form.rating, form.title.trim(), form.body.trim()) },
    )

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests
    private val log = Logger.getLogger("ProductReviews")
    private var page = 0

    var summary by mutableStateOf<ReviewSummary?>(null)
        private set
    var items by mutableStateOf(emptyList<Review>())
        private set
    var hasMore by mutableStateOf(false)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var failed by mutableStateOf(false)
        private set

    /** The first page has arrived (there may be no reviews at all). */
    var isLoaded by mutableStateOf(false)
        private set

    /** The first page, once. */
    suspend fun loadFirst() {
        if (!isLoaded) loadMore()
    }

    /** The next page, added under the ones already here ("Load more", and "Retry" after a failure). */
    suspend fun loadMore() {
        if (isLoading) return
        isLoading = true
        failed = false
        try {
            val next = load(page + 1)
            page += 1
            next.summary?.let { summary = it }
            // a review that slid onto the next page while a new one came in is not shown twice
            items = (items + next.reviews).distinctBy { it.id }
            hasMore = next.hasNextPage
            isLoaded = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("reviews not loaded: ${e.message}")
            failed = true
        } finally {
            isLoading = false
        }
    }

    /** Sends [form] (already valid) to the store; throws when it can't be sent. */
    suspend fun submit(form: ReviewForm) = send(form)
}

/**
 * The reviews block: the summary (average, stars, count, a bar per star), "Write a review" ([onWrite]), the reviews
 * loaded so far, then "Load more" ([onLoadMore]) while there are more. A load that failed shows a quiet line with Retry
 * (also [onLoadMore]); it never takes the page down.
 * ponytail: the loaded reviews are all in this one list item (five a page, a few pages at most in practice). Upgrade:
 * one lazy item per review, for stores whose shoppers page through hundreds.
 */
@Composable
internal fun ProductReviews(reviews: ReviewsState, modifier: Modifier = Modifier, onWrite: () -> Unit, onLoadMore: () -> Unit) {
    val spacing = ArgonTheme.spacing
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.l),
    ) {
        SectionHeader("Reviews")
        val summary = reviews.summary
        if (summary != null && summary.count > 0) {
            SummaryView(summary)
        } else if (reviews.isLoaded) {
            Text("No reviews yet", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
        }
        ArgonButton("Write a review", style = ArgonButtonStyle.Secondary, fullWidth = true, action = onWrite)
        for (review in reviews.items) {
            ArgonDivider()
            ReviewView(review)
        }
        when {
            reviews.failed -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Reviews couldn't load", Modifier.weight(1f), style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
                ArgonButton("Retry", style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, action = onLoadMore)
            }
            reviews.isLoading -> Box(Modifier.fillMaxWidth(), Alignment.Center) { ArgonSpinner(ArgonSize.S) }
            reviews.hasMore -> ArgonButton("Load more", style = ArgonButtonStyle.Tertiary, fullWidth = true, action = onLoadMore)
        }
    }
}

/** The average with its stars and "128 reviews", beside one bar per star from 5 down to 1. */
@Composable
private fun SummaryView(summary: ReviewSummary) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(spacing.xl), verticalAlignment = Alignment.CenterVertically) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
            Text(averageLabel(summary.average), style = type.display, color = colors.ink)
            ArgonRating(summary.average, size = ArgonSize.M)
            Text(reviewCountLabel(summary.count), style = type.caption, color = colors.muted)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            for (stars in 5 downTo 1) {
                val count = summary.histogram[stars] ?: 0
                Row(
                    // read as one line: "5 stars, 96 reviews"
                    Modifier.clearAndSetSemantics { contentDescription = "${starsLabel(stars)}, ${reviewCountLabel(count)}" },
                    horizontalArrangement = Arrangement.spacedBy(spacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("$stars", Modifier.widthIn(min = 12.dp), style = type.caption, color = colors.muted, textAlign = TextAlign.Center)
                    ArgonProgressBar(histogramShare(summary, stars), Modifier.weight(1f))
                    Text("$count", Modifier.widthIn(min = 28.dp), style = type.caption, color = colors.muted, textAlign = TextAlign.End)
                }
            }
        }
    }
}

/** One review: its stars and "Verified", title, body, the shopper's photos, who wrote it and when, and the store's reply. */
@Composable
private fun ReviewView(review: Review) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
        Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.CenterVertically) {
            ArgonRating(review.rating.toDouble())
            if (review.verified) LabelTag("Verified")
        }
        review.title?.let { Text(it, Modifier.semantics { heading() }, style = type.headline, color = colors.ink) }
        if (review.body.isNotBlank()) Text(review.body, style = type.body, color = colors.ink)
        if (review.pictures.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                for (url in review.pictures) StoreImage(url, "Review photo", Modifier.size(72.dp).clip(ArgonTheme.radius.s))
            }
        }
        val byline = listOfNotNull(review.author.takeIf { it.isNotBlank() }, review.date?.let(::displayDate)).joinToString(" · ")
        if (byline.isNotEmpty()) Text(byline, style = type.caption, color = colors.muted)
        review.reply?.let { reply ->
            Column(
                Modifier.fillMaxWidth().background(colors.surface, ArgonTheme.radius.m).padding(spacing.m),
                verticalArrangement = Arrangement.spacedBy(spacing.xs),
            ) {
                Text("Reply from the store", style = type.caption, color = colors.muted)
                Text(reply, style = type.body, color = colors.ink)
            }
        }
    }
}

/**
 * The write-a-review sheet: a star picker, title, review, name and email, then "Submit review". What is missing shows
 * under its field from the first try to send ([validate]). Sent: the sheet closes and the app says [REVIEW_SENT]; not
 * sent: [REVIEW_NOT_SENT] shows above the button and the form stays as it is. [submit] sends a valid form.
 */
@Composable
internal fun ReviewSheet(isPresented: Boolean, onDismiss: () -> Unit, submit: suspend (ReviewForm) -> Unit) {
    val scope = rememberCoroutineScope()
    var form by remember { mutableStateOf(ReviewForm()) }
    var tried by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var notSent by remember { mutableStateOf(false) }
    val errors = if (tried) validate(form) else ReviewFormErrors()
    val spacing = ArgonTheme.spacing
    ArgonBottomSheet(isPresented, onDismiss, detents = setOf(ArgonSheetDetent.Large)) {
        Column(
            // above the keyboard, and scrolling: every field can be reached while typing
            Modifier.imePadding().verticalScroll(rememberScrollState()).padding(start = spacing.l, end = spacing.l, bottom = spacing.xl),
            verticalArrangement = Arrangement.spacedBy(spacing.m),
        ) {
            Text("Write a review", Modifier.semantics { heading() }, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
            StarPicker(form.rating) { form = form.copy(rating = it) }
            errors.rating?.let { Text(it, style = ArgonTheme.type.caption, color = ArgonTheme.colors.sale) }
            ArgonInput("Title", form.title, { form = form.copy(title = it) })
            ArgonTextArea("Review", form.body, { form = form.copy(body = it) }, error = errors.body)
            ArgonInput("Name", form.name, { form = form.copy(name = it) }, error = errors.name)
            ArgonInput("Email", form.email, { form = form.copy(email = it) }, keyboard = ArgonKeyboard.Email, error = errors.email)
            if (notSent) Text(REVIEW_NOT_SENT, style = ArgonTheme.type.label, color = ArgonTheme.colors.sale)
            ArgonButton("Submit review", isLoading = sending, fullWidth = true) {
                tried = true
                if (!validate(form).isEmpty) return@ArgonButton
                sending = true
                notSent = false
                scope.launch {
                    try {
                        submit(form)
                        form = ReviewForm()
                        tried = false
                        onDismiss()
                        AppGraph.toast.show(REVIEW_SENT)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        notSent = true
                    } finally {
                        sending = false
                    }
                }
            }
        }
    }
}

/** Five stars to tap: the ones up to [rating] are filled. */
@Composable
private fun StarPicker(rating: Int, onRate: (Int) -> Unit) = Row(Modifier.selectableGroup()) {
    for (stars in 1..5) {
        Box(
            Modifier.size(44.dp)
                .selectable(selected = stars == rating, role = Role.RadioButton) { onRate(stars) }
                .semantics { contentDescription = starsLabel(stars) },
            contentAlignment = Alignment.Center,
        ) {
            ArgonIcon(if (stars <= rating) ArgonIconName.StarFilled else ArgonIconName.Star, size = 32.dp, tint = ArgonTheme.colors.ink)
        }
    }
}
