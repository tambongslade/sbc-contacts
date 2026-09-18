import SwiftUI

/// The SBC brand lockup. Use `markOnly` where only the people-in-circle glyph fits.
struct SBCLogo: View {
    var height: CGFloat = 72
    var markOnly = false

    var body: some View {
        Image(markOnly ? "mark" : "logo")
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
            .frame(height: height)
            // The lockup carries the product name; screen readers get it once here.
            .accessibilityLabel("SBC")
    }
}
