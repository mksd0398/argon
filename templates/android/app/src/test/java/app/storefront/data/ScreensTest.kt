package app.storefront.data

import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The sample templates of contract/fixtures/screens, decoded as the app reads them. */
class ScreensTest {
    private fun template(name: String) = ScreenTemplate.decode(ScreensTest::class.java.getResource("/fixtures/screens/$name.json")!!.readText())!!

    private val home = template("home")
    private val product = template("product")
    private val about = template("about")

    private fun ScreenTemplate.section(id: String) = sections.single { it.id == id }

    @Test
    fun hiddenOtherPlatformAndUnknownSectionsAreLeftOut() {
        assertEquals(listOf("hero", "slides", "cats", "new", "picks", "story", "atelier", "film", "sale", "gap", "bad"), home.sections.map { it.id })
        assertEquals(listOf("shop.custom.promo"), home.metafields)
        assertEquals(listOf(MetafieldIdentifier("custom", "promo")), home.metafields("shop"))
        assertTrue(home.metafields("product").isEmpty())
    }

    @Test
    fun androidOnlySectionStaysAndIosOnlyIsDropped() {
        val json = """{"sections":[{"id":"a","type":"spacer","platforms":["ios"]},{"id":"b","type":"spacer","platforms":["android"]},{"id":"c","type":"spacer"}]}"""
        assertEquals(listOf("b", "c"), ScreenTemplate.decode(json)!!.sections.map { it.id })
    }

    @Test
    fun notJsonOrNoSectionsIsNoTemplate() {
        assertNull(ScreenTemplate.decode("not json"))
        assertNull(ScreenTemplate.decode(null))
        assertNull(ScreenTemplate.decode("""{"version":2}"""))
        assertNull(ScreenTemplate.decode("[]"))
    }

    @Test
    fun sectionsWithoutIdOrTypeAreSkippedAndIdsAreUnique() {
        val json = """{"sections":[{"type":"spacer"},{"id":"x"},{"id":3,"type":"spacer"},"text",{"id":"y","type":"spacer"},{"id":"y","type":"banner"}]}"""
        assertEquals(listOf("y" to "spacer"), ScreenTemplate.decode(json)!!.sections.map { it.id to it.type })
    }

    @Test
    fun settingsAreReadByType() {
        val banner = home.section("hero").content as SectionContent.Banner
        assertEquals("Winter is here", banner.slide.heading)
        assertEquals("{{ shop.metafields.custom.promo | default: 'New season' }}", banner.slide.text)
        assertEquals("/collections/men", banner.slide.link)
        assertEquals(1024, banner.slide.image?.width)
        assertEquals("Winter", banner.slide.image?.alt)
        assertEquals("hero" to "large", banner.style to banner.height)
        assertEquals("#FFFFFF", banner.textColor)
        assertEquals("winter_hero", home.section("hero").trackName)
        assertEquals("a section without track goes by its type", "slideshow", home.section("slides").trackName)

        val slides = home.section("slides").content as SectionContent.Slideshow
        assertEquals(6, slides.interval)
        assertEquals("medium", slides.height)
        assertEquals(listOf("s1", "s2"), slides.slides.map { it.id })
        assertNull(slides.slides[1].image)
        assertEquals("/pages/about", slides.slides[1].link)

        val rail = home.section("new").content as SectionContent.Products
        assertEquals("gid://shopify/Collection/429493780502", rail.collection)
        assertTrue(rail.products.isEmpty())
        assertEquals(4, rail.limit)

        val video = home.section("film").content as SectionContent.Video
        assertEquals(16f / 9f, video.ratio, 0.001f)
        assertTrue(video.muted && video.loop && video.autoplay)

        val countdown = home.section("sale").content as SectionContent.Countdown
        assertEquals(Instant.parse("2030-01-01T00:00:00Z"), countdown.endsAt)

        assertEquals(SectionContent.Spacer(32, true), home.section("gap").content)
        assertEquals("center", (home.section("story").content as SectionContent.RichText).alignment)
        assertEquals("end", (home.section("atelier").content as SectionContent.ImageWithText).imagePosition)
    }

    @Test
    fun badValuesFallBackToTheirDefaults() {
        assertEquals(SectionContent.Products(null, null, emptyList(), "carousel", 8, true), home.section("bad").content)
        val json = """{"sections":[{"id":"s","type":"slideshow","settings":{"interval":99,"autoplay":"yes","height":"giant"}},
            |{"id":"b","type":"banner","settings":{"text_color":"red","image":{"url":"http://x"},"style":5}},
            |{"id":"g","type":"spacer","settings":{"height":1}}]}""".trimMargin()
        val sections = ScreenTemplate.decode(json)!!.sections
        val slides = sections[0].content as SectionContent.Slideshow
        assertEquals("a number is clamped", 15, slides.interval)
        assertTrue(slides.autoplay)
        assertEquals("large", slides.height)
        val banner = sections[1].content as SectionContent.Banner
        assertEquals("#FFFFFF", banner.textColor)
        assertNull("not https", banner.slide.image)
        assertEquals("hero", banner.style)
        assertEquals(4, (sections[2].content as SectionContent.Spacer).height)
    }

    @Test
    fun mainPlacement() {
        val placement = product.placement("product")
        assertEquals(listOf("promo"), placement.above.map { it.id })
        assertEquals("main", placement.main?.id)
        assertEquals(listOf("fabric"), placement.below.map { it.id })
        // collection and search have nothing below their grid
        val collection = product.placement("collection")
        assertEquals(listOf("promo", "fabric"), collection.above.map { it.id })
        assertTrue(collection.below.isEmpty())
        // no main: everything above, as if it were at the end
        assertEquals(home.sections, home.placement("cart").above)
        assertTrue(home.placement("cart").below.isEmpty())
        // a custom page has no main of its own
        assertEquals(listOf("promo", "fabric"), product.placement("about").above.map { it.id })
    }

    @Test
    fun productBlockOrderAndHidden() {
        assertEquals(
            "the listed ones in order, reviews hidden, the unknown one ignored, the missing ones after",
            listOf("gallery", "title", "price", "options", "purchase", "details", "bundle", "rails"),
            productBlocks(product.placement("product").main),
        )
        assertEquals(PRODUCT_BLOCKS, productBlocks(null))
        val main = ScreenTemplate.decode("""{"sections":[{"id":"main","type":"main","settings":{"blocks":[{"type":"rails"},{"type":"gallery","hidden":true},{"type":"rails"}]}}]}""")!!.sections[0]
        assertEquals(listOf("rails", "title", "price", "options", "purchase", "bundle", "details", "reviews"), productBlocks(main))
    }

    @Test
    fun collectionFiltersOverride() {
        val main = ScreenTemplate.decode("""{"sections":[{"id":"main","type":"main","settings":{"filters":"bottom"}}]}""")!!.sections[0]
        assertEquals(CollectionTemplate.Bottom, collectionFilters(main))
        assertNull(collectionFilters(null))
        assertNull(collectionFilters(main.copy(settings = SectionSettings())))
    }

    @Test
    fun customNodesDecode() {
        val intro = about.section("intro").content as SectionContent.Custom
        assertTrue(intro.isNative)
        assertEquals(
            listOf(
                CustomNode.Heading(2, "Hello {{ customer.first_name | default: 'there' }}"),
                CustomNode.Paragraph(listOf(TextRun("Made in "), TextRun("Italy", bold = true, link = "/pages/about"))),
                CustomNode.Bullets(true, listOf(listOf(TextRun("One")), listOf(TextRun("Two", italic = true)))),
                CustomNode.Image("https://cdn.shopify.com/s/files/1/about.jpg", "Workshop", null),
                CustomNode.Button("Shop now", "/collections/all"),
                CustomNode.Divider,
                CustomNode.Product("gid://shopify/Product/7982904639510"),
                CustomNode.Collection("gid://shopify/Collection/429493780502", 4),
            ),
            intro.nodes,
        )
        val table = about.section("table").content as SectionContent.Custom
        assertFalse(table.isNative)
        assertEquals(0, table.height)
        assertFalse("native without nodes is drawn as web", (about.section("lost").content as SectionContent.Custom).isNative)
    }

    @Test
    fun oneSectionNodesQueryLoadsEveryGid() {
        assertEquals(listOf("gid://shopify/Collection/429493780502", "gid://shopify/Product/7982904639510"), sectionNodeIds(home.sections))
        assertEquals(listOf("gid://shopify/Product/7982904639510", "gid://shopify/Collection/429493780502"), sectionNodeIds(about.sections))
    }

    @Test
    fun metafieldContext() {
        val metafields = listOf(
            Metafield("custom", "fabric", "single_line_text_field", "Recycled nylon"),
            Metafield("custom", "sizes", "list.single_line_text_field", """["S","M"]"""),
            Metafield("custom", "count", "number_integer", "3"),
            Metafield("custom", "spec", "json", """{"a":true}"""),
            Metafield("custom", "number_text", "single_line_text_field", "42"),
            Metafield("other", "broken", "json", "{nope"),
        )
        assertEquals(
            mapOf(
                "custom" to mapOf("fabric" to "Recycled nylon", "sizes" to listOf("S", "M"), "count" to 3L, "spec" to mapOf("a" to true), "number_text" to "42"),
                "other" to mapOf("broken" to "{nope"),
            ),
            ScreenContext.metafields(metafields),
        )
    }

    @Test
    fun sectionTextIsEvaluatedWithTheScreensObjects() {
        val shop = ScreenContext.shop(Shop("gid://shopify/Shop/1", "Summit", paymentSettings = Shop.PaymentSettings("USD", "US")), listOf(Metafield("custom", "promo", null, "Free shipping")))
        val context = ScreenContext.forSection(mapOf("shop" to shop, "cart" to ScreenContext.cart(null)), home.section("hero"))
        val banner = home.section("hero").content as SectionContent.Banner
        assertEquals("Free shipping", Liquid.render(banner.slide.text!!, context, ZoneOffset.UTC))
        assertEquals("hero 0 $0.00", Liquid.render("{{ section.id }} {{ cart.item_count }} {{ cart.total_price | money }}", context, ZoneOffset.UTC))
        assertEquals("New season", Liquid.render(banner.slide.text!!, ScreenContext.forSection(emptyMap(), home.section("hero")), ZoneOffset.UTC))
        val promo = product.section("promo").content as SectionContent.RichText
        val p = Product("gid://shopify/Product/1", "shell", "Shell", availableForSale = true)
        assertEquals("<p>In stock: ships today</p>", Liquid.render(promo.text!!, mapOf("product" to ScreenContext.product(p, emptyList())), ZoneOffset.UTC))
    }

    @Test
    fun promotionParams() {
        val promotion = Promotion("hero", "winter_hero", "home:0")
        assertEquals(
            mapOf("promotion_id" to "hero", "promotion_name" to "winter_hero", "creative_slot" to "home:0"),
            AnalyticsEvent.ViewPromotion(promotion).params,
        )
        assertEquals("view_promotion", AnalyticsEvent.ViewPromotion(promotion).name)
        val select = AnalyticsEvent.SelectPromotion(promotion.copy(creative = "s2", slot = "home:1"))
        assertEquals("select_promotion", select.name)
        assertEquals("s2", select.params["creative_name"])
        assertEquals("home:1", select.params["creative_slot"])
        assertEquals(MetaEvent("select_promotion", null, select.params), metaEvent(select))
        assertEquals("select_promotion" to select.params, moEngageEvent(select))
    }

    @Test
    fun theScreensOwnLook() {
        val look = ScreenTemplate.decode("""{"screen":{"top_bar":"transparent","top_bar_tint":"dark","background":"#f7f3ee"},"sections":[]}""")!!.screen
        assertEquals(ScreenLook("transparent", darkTint = true, background = "#F7F3EE"), look)
        assertEquals("missing: home goes by transparentOnHome", ScreenLook(), ScreenTemplate.decode("""{"sections":[]}""")!!.screen)
        val bad = ScreenTemplate.decode("""{"screen":{"top_bar":"glass","top_bar_tint":7,"background":"beige"},"sections":[]}""")!!.screen
        assertEquals(ScreenLook(), bad)
        assertEquals(ScreenLook(), ScreenTemplate.decode("""{"screen":"transparent","sections":[]}""")!!.screen)
        assertEquals("solid", ScreenTemplate.decode("""{"screen":{"top_bar":"solid"},"sections":[]}""")!!.screen.topBar)
    }

    @Test
    fun everySectionsBackgroundAndPadding() {
        val json = """{"sections":[
            {"id":"a","type":"spacer","settings":{"background":"#1f6feb","padding":"large"}},
            {"id":"b","type":"spacer","settings":{"padding":"small"}},
            {"id":"c","type":"spacer","settings":{"padding":"medium","background":"blue"}},
            {"id":"d","type":"spacer","settings":{"padding":"huge"}}
        ]}"""
        val sections = ScreenTemplate.decode(json)!!.sections
        assertEquals(listOf("#1F6FEB", null, null, null), sections.map { it.background })
        assertEquals(listOf(40, 12, 24, 0), sections.map { it.padding })
    }

    @Test
    fun theDetailingSectionTypes() {
        val json = """{"sections":[
            {"id":"m","type":"marquee","settings":{"text":"Free shipping {{ shop.name }}","link":"/collections/all","speed":"fast"}},
            {"id":"m2","type":"marquee","settings":{"speed":"warp","text_color":"red"}},
            {"id":"f","type":"faq","settings":{"heading":"FAQ"},"blocks":[
                {"id":"q1","type":"question","settings":{"question":"Returns?","answer":"<p>30 days</p>"}},
                {"id":"q2","type":"question","settings":{"answer":"no question"}},
                {"id":"x","type":"slide","settings":{"question":"wrong block"}}]},
            {"id":"ft","type":"features","settings":{"layout":"grid"},"blocks":[
                {"id":"a","type":"feature","settings":{"icon":"truck","heading":"Fast"}},
                {"id":"b","type":"feature","settings":{"icon":"rocket","text":"Unknown icon"}}]},
            {"id":"g","type":"image_grid","settings":{"columns":"3","aspect":"portrait"},"blocks":[
                {"id":"t1","type":"tile","settings":{"image":{"url":"https://cdn.shopify.com/a.jpg"},"heading":"Men","link":"/collections/men"}},
                {"id":"t2","type":"tile","settings":{"heading":"No image"}}]},
            {"id":"g2","type":"image_grid","settings":{"columns":"4","aspect":"wide"}}
        ]}"""
        val t = ScreenTemplate.decode(json)!!
        assertEquals("the new types are kept", listOf("m", "m2", "f", "ft", "g", "g2"), t.sections.map { it.id })

        val marquee = t.section("m").content as SectionContent.Marquee
        assertEquals(SectionContent.Marquee("Free shipping {{ shop.name }}", "/collections/all", 90, "#FFFFFF"), marquee)
        val plain = t.section("m2").content as SectionContent.Marquee
        assertEquals(60 to "#FFFFFF", plain.speed to plain.textColor)

        val faq = t.section("f").content as SectionContent.Faq
        assertEquals("FAQ", faq.heading)
        assertEquals("a question without its question is skipped", listOf("q1" to "Returns?"), faq.questions.map { it.block.id to it.question })
        assertEquals("<p>30 days</p>", faq.questions.single().answer)

        val features = t.section("ft").content as SectionContent.Features
        assertEquals("grid", features.layout)
        assertEquals(listOf("truck", "check"), features.features.map { it.icon })
        assertEquals("Fast", features.features[0].heading)

        val grid = t.section("g").content as SectionContent.ImageGrid
        assertEquals(3, grid.columns)
        assertEquals(4f / 5f, grid.ratio, 0.001f)
        assertEquals("a tile without an image is skipped", listOf("t1"), grid.tiles.map { it.block.id })
        assertEquals("/collections/men", grid.tiles.single().link)
        val defaults = t.section("g2").content as SectionContent.ImageGrid
        assertEquals(2 to 1f, defaults.columns to defaults.ratio)
        assertTrue(defaults.tiles.isEmpty())
    }
}
