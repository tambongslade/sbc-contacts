import SwiftUI
import UIKit

/// Montserrat (SBC's product font) on the Material 3 type scale the Flutter
/// app used, scaled with Dynamic Type.
///
/// The bundled font is variable, so weights are set on its `wght` axis — a
/// plain `Font.custom(...).weight(...)` does not reliably select an instance.
enum SBCTextStyle {
    case headlineMedium, headlineSmall
    case titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall
    case labelLarge, labelMedium, labelSmall

    var size: CGFloat {
        switch self {
        case .headlineMedium: 28
        case .headlineSmall: 24
        case .titleLarge: 22
        case .titleMedium: 16
        case .titleSmall: 14
        case .bodyLarge: 16
        case .bodyMedium: 14
        case .bodySmall: 12
        case .labelLarge: 14
        case .labelMedium: 12
        case .labelSmall: 11
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .titleMedium, .titleSmall, .labelLarge, .labelMedium, .labelSmall: .medium
        default: .regular
        }
    }

    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .headlineMedium, .headlineSmall: .title2
        case .titleLarge: .title3
        case .titleMedium, .bodyLarge: .body
        case .titleSmall, .bodyMedium, .labelLarge: .subheadline
        case .bodySmall, .labelMedium: .footnote
        case .labelSmall: .caption1
        }
    }
}

enum SBCFont {
    static let family = "Montserrat"

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular, textStyle: UIFont.TextStyle? = nil) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [wghtAxis: axisValue(weight)],
        ])
        let base = UIFont(descriptor: descriptor, size: size)
        let font = base.familyName == family ? base : .systemFont(ofSize: size, weight: uiWeight(weight))
        guard let textStyle else { return font }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    /// `'wght'` as a four-char code.
    private static let wghtAxis = 0x7767_6874

    private static func axisValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

/// Montserrat for the text UIKit draws itself — navigation titles, bar
/// buttons, tab labels, segmented controls and the search field.
///
/// Only the legacy per-proxy text attributes are set, never a
/// `UINavigationBarAppearance` / `UITabBarAppearance` object: assigning those
/// replaces the system background and switches off Liquid Glass on iOS 26.
enum FontAppearance {
    @MainActor
    static func configure() {
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: SBCFont.uiFont(size: 17, weight: .bold, textStyle: .headline)]
        nav.largeTitleTextAttributes = [.font: SBCFont.uiFont(size: 34, weight: .heavy, textStyle: .largeTitle)]

        let barButton = UIBarButtonItem.appearance()
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            barButton.setTitleTextAttributes([.font: SBCFont.uiFont(size: 17, weight: .semibold, textStyle: .body)], for: state)
        }

        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes([.font: SBCFont.uiFont(size: 10, weight: .semibold)], for: .normal)
        tabItem.setTitleTextAttributes([.font: SBCFont.uiFont(size: 10, weight: .bold)], for: .selected)

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: SBCFont.uiFont(size: 13, weight: .medium, textStyle: .footnote)], for: .normal)
        segmented.setTitleTextAttributes([.font: SBCFont.uiFont(size: 13, weight: .bold, textStyle: .footnote)], for: .selected)

        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font =
            SBCFont.uiFont(size: 17, weight: .medium, textStyle: .body)
    }
}

extension Font {
    /// Montserrat on Apple's text-style scale: `.montserrat(.headline)` is the
    /// Montserrat counterpart of `.headline`, same size and Dynamic Type
    /// scaling. Weights go through the variable font's axis, so pass them here
    /// rather than chaining `.weight()` / `.bold()`.
    static func montserrat(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let (size, defaultWeight, uiStyle): (CGFloat, Font.Weight, UIFont.TextStyle) = switch style {
        case .largeTitle: (34, .bold, .largeTitle)
        case .title: (28, .bold, .title1)
        case .title2: (22, .bold, .title2)
        case .title3: (20, .semibold, .title3)
        case .headline: (17, .bold, .headline)
        case .callout: (16, .medium, .callout)
        case .subheadline: (15, .medium, .subheadline)
        case .footnote: (13, .medium, .footnote)
        case .caption: (12, .medium, .caption1)
        case .caption2: (11, .medium, .caption2)
        default: (17, .medium, .body)
        }
        return Font(SBCFont.uiFont(size: size, weight: weight ?? defaultWeight, textStyle: uiStyle))
    }

    /// `Font.sbc(.titleLarge, weight: .heavy)` ≈ Flutter's
    /// `textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)`.
    static func sbc(_ style: SBCTextStyle, weight: Font.Weight? = nil) -> Font {
        Font(SBCFont.uiFont(size: style.size, weight: weight ?? style.defaultWeight, textStyle: style.uiTextStyle))
    }
}
