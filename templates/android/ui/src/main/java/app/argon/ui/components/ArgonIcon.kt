package app.argon.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.R

/**
 * The icons the library ships: Material Symbols Outlined (filled for the *Filled names, play and pause, as their SF
 * Symbols are on iOS), bundled as `res/drawable/argon_ic_<snake_name>.xml`, and each filled (`_fill`) for the theme's
 * filled icons ([ArgonIconStyle]). The comment is the Material Symbol each one is.
 */
enum class ArgonIconName(@DrawableRes val drawable: Int, @DrawableRes val filled: Int = drawable) {
    Home(R.drawable.argon_ic_home, R.drawable.argon_ic_home_fill), // home
    Grid(R.drawable.argon_ic_grid, R.drawable.argon_ic_grid_fill), // grid_view
    Search(R.drawable.argon_ic_search, R.drawable.argon_ic_search_fill), // search
    Bag(R.drawable.argon_ic_bag, R.drawable.argon_ic_bag_fill), // shopping_bag
    Heart(R.drawable.argon_ic_heart, R.drawable.argon_ic_heart_fill), // favorite
    HeartFilled(R.drawable.argon_ic_heart_filled), // favorite, filled
    Person(R.drawable.argon_ic_person, R.drawable.argon_ic_person_fill), // person
    Menu(R.drawable.argon_ic_menu, R.drawable.argon_ic_menu_fill), // menu
    Close(R.drawable.argon_ic_close, R.drawable.argon_ic_close_fill), // close
    Back(R.drawable.argon_ic_back, R.drawable.argon_ic_back_fill), // arrow_back (mirrored in RTL)
    ChevronRight(R.drawable.argon_ic_chevron_right, R.drawable.argon_ic_chevron_right_fill), // chevron_right
    ChevronDown(R.drawable.argon_ic_chevron_down, R.drawable.argon_ic_chevron_down_fill), // keyboard_arrow_down
    ChevronUp(R.drawable.argon_ic_chevron_up, R.drawable.argon_ic_chevron_up_fill), // keyboard_arrow_up
    Plus(R.drawable.argon_ic_plus, R.drawable.argon_ic_plus_fill), // add
    Minus(R.drawable.argon_ic_minus, R.drawable.argon_ic_minus_fill), // remove
    Filter(R.drawable.argon_ic_filter, R.drawable.argon_ic_filter_fill), // filter_list
    Sort(R.drawable.argon_ic_sort, R.drawable.argon_ic_sort_fill), // swap_vert
    Share(R.drawable.argon_ic_share, R.drawable.argon_ic_share_fill), // share
    Star(R.drawable.argon_ic_star, R.drawable.argon_ic_star_fill), // star
    StarFilled(R.drawable.argon_ic_star_filled), // star, filled
    Location(R.drawable.argon_ic_location, R.drawable.argon_ic_location_fill), // location_on
    Phone(R.drawable.argon_ic_phone, R.drawable.argon_ic_phone_fill), // call
    Mail(R.drawable.argon_ic_mail, R.drawable.argon_ic_mail_fill), // mail
    Check(R.drawable.argon_ic_check, R.drawable.argon_ic_check_fill), // check
    Info(R.drawable.argon_ic_info, R.drawable.argon_ic_info_fill), // info
    Warning(R.drawable.argon_ic_warning, R.drawable.argon_ic_warning_fill), // warning
    Trash(R.drawable.argon_ic_trash, R.drawable.argon_ic_trash_fill), // delete
    Edit(R.drawable.argon_ic_edit, R.drawable.argon_ic_edit_fill), // edit
    Play(R.drawable.argon_ic_play), // play_arrow, filled
    Pause(R.drawable.argon_ic_pause), // pause, filled
    Truck(R.drawable.argon_ic_truck, R.drawable.argon_ic_truck_fill), // local_shipping
    Returns(R.drawable.argon_ic_returns, R.drawable.argon_ic_returns_fill), // undo
    Leaf(R.drawable.argon_ic_leaf, R.drawable.argon_ic_leaf_fill), // eco
    Clock(R.drawable.argon_ic_clock, R.drawable.argon_ic_clock_fill), // schedule
    Gift(R.drawable.argon_ic_gift, R.drawable.argon_ic_gift_fill), // redeem
    Lock(R.drawable.argon_ic_lock, R.drawable.argon_ic_lock_fill), // lock
    Globe(R.drawable.argon_ic_globe, R.drawable.argon_ic_globe_fill), // globe
    Calendar(R.drawable.argon_ic_calendar, R.drawable.argon_ic_calendar_fill), // calendar_today
    Tag(R.drawable.argon_ic_tag, R.drawable.argon_ic_tag_fill), // sell
    External(R.drawable.argon_ic_external, R.drawable.argon_ic_external_fill), // open_in_new
    Eye(R.drawable.argon_ic_eye, R.drawable.argon_ic_eye_fill), // visibility
    EyeOff(R.drawable.argon_ic_eye_off, R.drawable.argon_ic_eye_off_fill), // visibility_off
}

/** [name] at [size], tinted [tint] (the current content colour by default). Decorative unless [contentDescription] is set. */
@Composable
fun ArgonIcon(
    name: ArgonIconName,
    modifier: Modifier = Modifier,
    size: Dp = 24.dp,
    tint: Color? = null,
    contentDescription: String? = null,
) = Icon(
    painterResource(if (LocalArgonIconStyle.current == ArgonIconStyle.Filled) name.filled else name.drawable),
    contentDescription,
    modifier.size(size),
    tint ?: LocalContentColor.current,
)

/** The theme's icon style (contract/theme.js ICON_STYLES): every [ArgonIcon] outlined, or filled. */
enum class ArgonIconStyle { Outline, Filled }

/** The icon style [ArgonIcon]s are drawn in; set by ArgonTheme. */
val LocalArgonIconStyle = staticCompositionLocalOf { ArgonIconStyle.Outline }
