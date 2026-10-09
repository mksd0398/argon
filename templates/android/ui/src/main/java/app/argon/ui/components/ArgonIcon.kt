package app.argon.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.R

/**
 * The icons the library ships: Material Symbols Outlined (filled for the *Filled names, play and pause, as their SF
 * Symbols are on iOS), bundled as `res/drawable/argon_ic_<snake_name>.xml`. The comment is the Material Symbol each one is.
 */
enum class ArgonIconName(@DrawableRes val drawable: Int) {
    Home(R.drawable.argon_ic_home), // home
    Grid(R.drawable.argon_ic_grid), // grid_view
    Search(R.drawable.argon_ic_search), // search
    Bag(R.drawable.argon_ic_bag), // shopping_bag
    Heart(R.drawable.argon_ic_heart), // favorite
    HeartFilled(R.drawable.argon_ic_heart_filled), // favorite, filled
    Person(R.drawable.argon_ic_person), // person
    Menu(R.drawable.argon_ic_menu), // menu
    Close(R.drawable.argon_ic_close), // close
    Back(R.drawable.argon_ic_back), // arrow_back (mirrored in RTL)
    ChevronRight(R.drawable.argon_ic_chevron_right), // chevron_right
    ChevronDown(R.drawable.argon_ic_chevron_down), // keyboard_arrow_down
    ChevronUp(R.drawable.argon_ic_chevron_up), // keyboard_arrow_up
    Plus(R.drawable.argon_ic_plus), // add
    Minus(R.drawable.argon_ic_minus), // remove
    Filter(R.drawable.argon_ic_filter), // filter_list
    Sort(R.drawable.argon_ic_sort), // swap_vert
    Share(R.drawable.argon_ic_share), // share
    Star(R.drawable.argon_ic_star), // star
    StarFilled(R.drawable.argon_ic_star_filled), // star, filled
    Location(R.drawable.argon_ic_location), // location_on
    Phone(R.drawable.argon_ic_phone), // call
    Mail(R.drawable.argon_ic_mail), // mail
    Check(R.drawable.argon_ic_check), // check
    Info(R.drawable.argon_ic_info), // info
    Warning(R.drawable.argon_ic_warning), // warning
    Trash(R.drawable.argon_ic_trash), // delete
    Edit(R.drawable.argon_ic_edit), // edit
    Play(R.drawable.argon_ic_play), // play_arrow, filled
    Pause(R.drawable.argon_ic_pause), // pause, filled
    Truck(R.drawable.argon_ic_truck), // local_shipping
    Returns(R.drawable.argon_ic_returns), // undo
    Leaf(R.drawable.argon_ic_leaf), // eco
    Clock(R.drawable.argon_ic_clock), // schedule
    Gift(R.drawable.argon_ic_gift), // redeem
    Lock(R.drawable.argon_ic_lock), // lock
    Globe(R.drawable.argon_ic_globe), // globe
    Calendar(R.drawable.argon_ic_calendar), // calendar_today
    Tag(R.drawable.argon_ic_tag), // sell
    External(R.drawable.argon_ic_external), // open_in_new
    Eye(R.drawable.argon_ic_eye), // visibility
    EyeOff(R.drawable.argon_ic_eye_off), // visibility_off
}

/** [name] at [size], tinted [tint] (the current content colour by default). Decorative unless [contentDescription] is set. */
@Composable
fun ArgonIcon(
    name: ArgonIconName,
    modifier: Modifier = Modifier,
    size: Dp = 24.dp,
    tint: Color? = null,
    contentDescription: String? = null,
) = Icon(painterResource(name.drawable), contentDescription, modifier.size(size), tint ?: LocalContentColor.current)
