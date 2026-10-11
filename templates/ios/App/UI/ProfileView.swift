import ArgonUI
import SwiftUI

/// The customer's name, email and phone (route `profile`).
/// Placeholder: the account pages replace this body.
@MainActor
struct ProfileView: View {
    var body: some View {
        Text("Profile").argonTopBar(title: "Profile")
    }
}
