//
//  AppTheme.swift
//  TrainingLab
//
//  The styles a user can choose in Settings → Appearance. Each is a whole
//  look, not just a color: an accent, the card and text tones that go with
//  it, a font for titles and numbers, and a shape language — soft or sharp
//  corners, capsule or square buttons, filled or outlined controls. Each is
//  defined in one place, its `Spec` (under "Styles" at the end).
//
//  The accent and the buttons are picked by hand. The cards and text around
//  them are derived from the style's hue in OKLCH, at the same lightness in
//  every style, so they're equally readable and Subtle simply takes most of
//  the color out. Only the neutral style, Graphite, gives exact greys.
//
//  A curated set rather than free choices: every color is checked as text
//  and icons on white, black, the style's own cards and the panels inside
//  them, and with its button text, in light and dark mode (WCAG AA, at least
//  4.5:1; AAA, 7:1, with Increase Contrast — see `AppThemeTests`). None uses
//  plain red, which iOS reserves for destructive actions.
//
//  Stored in the App Group, so the widget and the Live Activity follow the
//  choice. Compiled into both the app and the widget extension.
//

import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case earth, ocean, indigo, pink, clay, graphite

    /// The colors a style gives the app.
    enum Role: Sendable {
        /// Text, icons, strokes and selection.
        case accent
        /// The other end of the accent in a style with a gradient; the
        /// accent itself in a solid one.
        case accentEnd
        /// Primary buttons and filled highlights.
        case fill
        /// The other end of `fill`, the same way.
        case fillEnd
        /// Text and icons on `fill`.
        case onFill
        /// Cards, chips and rows.
        case surface
        /// Panels and chips inside a card: a step darker than the card in
        /// light mode, lighter in dark mode.
        case inset
        case primaryText
        case secondaryText
        /// Done, a record, a goal met.
        case success
        /// Caution: low recovery, a missing setting.
        case warning
        /// Errors, and the heart rate.
        case danger
    }

    static let storageKey = "appTheme"

    /// Shared with the widget extension. UserDefaults is thread-safe; the SDK
    /// just doesn't mark it `Sendable`.
    nonisolated(unsafe) static let store = UserDefaults(suiteName: WeeklyGoalsSnapshot.appGroup)

    /// The default style: Terrakotta, the App Store's and the primary app icon's.
    static let defaultStyle = AppTheme.clay

    /// The user's choice as stored. A style since removed (Plum, Classic)
    /// falls back to the default.
    static var current: AppTheme {
        store?.string(forKey: storageKey).flatMap(AppTheme.init(rawValue:)) ?? defaultStyle
    }

    var id: String { rawValue }

    /// Everything that makes the style.
    var spec: Spec {
        switch self {
        case .earth:    Spec.earth
        case .ocean:    Spec.ocean
        case .indigo:   Spec.indigo
        case .pink:     Spec.pink
        case .clay:     Spec.clay
        case .graphite: Spec.graphite
        }
    }

    var name: String { spec.name }
    /// What the style feels like, under its name in the picker.
    var character: String { spec.character }
    var typography: Typography { spec.typography }
    var geometry: Geometry { spec.geometry }

    /// Whether Subtle and Vivid differ: only a style whose cards and text are
    /// tinted has color there to take out.
    var followsColorIntensity: Bool {
        guard case .tinted = spec.neutrals else { return false }
        return true
    }

    // MARK: Spec

    /// A style: its names, fonts, shapes and colors.
    struct Spec: Sendable {
        let name: String
        let character: String
        let typography: Typography
        let geometry: Geometry
        let accent: Pair
        let fill: Pair
        let onFill: Pair
        /// Where the accent and the fill run to in a style with a gradient
        /// Nil for the solid styles.
        var gradientEnds: (accent: Pair, fill: Pair)?
        let neutrals: Neutrals
        let tint: Tint
    }

    /// The cards and text around the accent.
    enum Neutrals: Sendable {
        /// Derived from `hue` (OKLCH degrees) at the lightness steps every
        /// style shares (`Lightness`), with `chroma` of it: how colored the
        /// cards and text are. Secondary text gets twice as much, so it reads
        /// as tinted too; Subtle keeps a quarter.
        case tinted(hue: Double, chroma: Double)
        /// Exact greys, for the neutral styles. Subtle leaves them alone.
        case fixed(surface: Pair, inset: Pair, primaryText: Pair, secondaryText: Pair)
    }

    /// The soft color over a page (`pageTint()`), from the top right to the
    /// bottom left.
    struct Tint: Sendable {
        enum Colors: Sendable {
            /// From `hue` to `hue + shift` on the color wheel, at the tint's
            /// lightness steps, with `chroma`.
            case wheel(hue: Double, shift: Double, chroma: Double)
            case fixed(top: Pair, bottom: Pair)
        }

        let colors: Colors
        /// Plan pages, where a style gives them colors of their own.
        var onPlanPages: Colors?
        /// Low: enough to color the page, not so much that text on it drops
        /// under 4.5:1 or the cards, tinted the same hue, sink into it
        /// (`AppThemeTests`). Half in Subtle.
        var opacity = (light: 0.10, dark: 0.10)
    }

    /// The OKLCH lightness of the derived colors, the same in every style.
    /// Cards are a little darker in light mode than the neutral styles' so
    /// they still stand out on the page tint.
    private enum Lightness {
        static let surface = (light: 0.935, dark: 0.225)
        static let inset = (light: 0.905, dark: 0.27)
        static let primaryText = (light: 0.22, dark: 0.95)
        static let secondaryText = (light: 0.47, dark: 0.72)
        static let tint = (top: 0.60, bottom: 0.74)
    }

    // MARK: Typography

    /// The font of titles and big numbers. Body text stays SF Pro in every
    /// style, so lists and forms read the same.
    struct Typography: Sendable {
        let design: Font.Design
        let width: Font.Width
        let titleWeight: Font.Weight
        let numberWeight: Font.Weight

        func title(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
            .system(style, design: design, weight: weight ?? titleWeight).width(width)
        }

        func number(size: CGFloat) -> Font {
            .system(size: size, weight: numberWeight, design: design).width(width).monospacedDigit()
        }

        /// The same for UIKit (the navigation bar titles), scaled with Dynamic Type.
        func uiTitle(size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
            let uiWidth: UIFont.Width = width == .condensed ? .condensed : width == .expanded ? .expanded : .standard
            var font = UIFont.systemFont(ofSize: size, weight: weight, width: uiWidth)
            let uiDesign: UIFontDescriptor.SystemDesign? = switch design {
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
            default: nil
            }
            if let uiDesign, let descriptor = font.fontDescriptor.withDesign(uiDesign) {
                font = UIFont(descriptor: descriptor, size: size)
            }
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
    }

    // MARK: Shape

    /// Corners and card style.
    struct Geometry: Sendable {
        /// Corner radius of cards.
        let cardRadius: CGFloat
        /// Corner radius of buttons, chips and icon badges; a large value
        /// makes capsules and circles.
        let controlRadius: CGFloat
        /// Secondary buttons and unselected chips drawn as outlines on the
        /// page (ghost buttons) instead of filled.
        let outlinedControls: Bool
        /// The app's original look: frosted-glass cards, chips and icon
        /// badges, cards edged with a faint line in the accent gradient and
        /// lifted by a soft shadow. The page tint shows through them.
        var frostedCards = false

        /// A panel inside a card: the card's corners, tightened to sit
        /// inside it.
        var insetRadius: CGFloat { cardRadius * 0.6 }
    }

    // MARK: Colors

    /// A color of *this* style, following light and dark mode, the color
    /// intensity and Increase Contrast. For the widget and the picker; the
    /// app's views use `themed(_:)`, which follows the user's choice.
    func color(_ role: Role) -> Color {
        Color(uiColor: UIColor { self.rgb(role, for: $0).uiColor })
    }

    /// A color of whichever style the view it's drawn in carries (its
    /// `appTheme` trait, set from `EnvironmentValues.appTheme`). Changing the
    /// style re-resolves it in place — nothing is rebuilt.
    static func themed(_ role: Role) -> UIColor {
        UIColor { traits in traits.appTheme.rgb(role, for: traits).uiColor }
    }

    /// The accent as it looks in dark mode, for surfaces that are dark in
    /// both appearances (the Live Activity card).
    var darkAccent: Color { Color(uiColor: spec.accent.dark.uiColor) }

    /// A color of this style at a given intensity — for the widget, which
    /// has no app to set the trait.
    func color(_ role: Role, intensity: ColorIntensity) -> Color {
        Color(uiColor: UIColor { traits in
            self.rgb(role, for: traits.modifyingTraits { $0.colorIntensity = intensity }).uiColor
        })
    }

    /// The same as it looks in dark mode, for the Live Activity's card.
    func darkColor(_ role: Role, intensity: ColorIntensity) -> Color {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.colorIntensity = intensity
        }
        return Color(uiColor: rgb(role, for: traits).uiColor)
    }

    /// The same for the Apple Watch, which is always dark: red, green and blue,
    /// 0…1, as `WatchConnectivityManager.sendWorkoutLibrary` sends it.
    var watchComponents: [Double] {
        let color = spec.accent.dark
        return [color.red, color.green, color.blue]
    }

    func rgb(_ role: Role, for traits: UITraitCollection) -> RGB {
        let dark = traits.userInterfaceStyle == .dark
        let subtle = traits.colorIntensity == .subtle
        func plain(_ pair: Pair) -> RGB { dark ? pair.dark : pair.light }
        let base: RGB = switch role {
        case .accent:        plain(spec.accent)
        case .accentEnd:     plain(spec.gradientEnds?.accent ?? spec.accent)
        case .fill:          plain(spec.fill)
        case .fillEnd:       plain(spec.gradientEnds?.fill ?? spec.fill)
        case .onFill:        plain(spec.onFill)
        case .surface, .inset, .primaryText, .secondaryText: neutral(role, dark: dark, subtle: subtle)
        case .success, .warning, .danger: status(role, dark: dark)
        }
        guard traits.accessibilityContrast == .high else { return base }
        // Increase Contrast: further from the page, and from the text on a fill.
        switch role {
        case .accent, .accentEnd, .success, .warning, .danger:
            return dark ? base.mixed(with: .white, by: 0.35) : base.mixed(with: .black, by: 0.3)
        case .fill, .fillEnd:
            let text = plain(spec.onFill)
            return text.luminance > base.luminance ? base.mixed(with: .black, by: 0.3) : base.mixed(with: .white, by: 0.35)
        case .secondaryText:
            return base.mixed(with: neutral(.primaryText, dark: dark, subtle: subtle), by: 0.4)
        case .onFill, .surface, .inset, .primaryText:
            return base
        }
    }

    /// Green, amber and red at one lightness in every style, readable as text
    /// on the page, the cards and the panels in them — so they don't shout
    /// next to a quiet style.
    private func status(_ role: Role, dark: Bool) -> RGB {
        let hue: Double = switch role {
        case .success: 150
        case .warning: 70
        default:       27
        }
        return OKLCH(l: dark ? 0.78 : 0.47, c: 0.14, h: hue).rgb
    }

    /// A shade of the accent, for telling categories apart without a second
    /// color: its hue turned a little and its lightness nudged, so every shade
    /// still reads as the style's. A neutral accent (Graphite) only gets
    /// lighter and darker. Index 0 is the accent itself.
    func tone(_ index: Int, for traits: UITraitCollection) -> RGB {
        let steps: [(hue: Double, lightness: Double)] = [(0, 0), (22, 0.05), (-22, -0.04), (10, -0.08), (-10, 0.08)]
        let step = steps[abs(index) % steps.count]
        var shade = OKLCH(rgb(.accent, for: traits))
        shade.h += step.hue
        // Toward the page's opposite in dark mode, as in light.
        shade.l += traits.userInterfaceStyle == .dark ? -step.lightness / 2 : step.lightness
        return shade.rgb
    }

    /// Cards and text: derived from the style's hue, or its exact greys.
    private func neutral(_ role: Role, dark: Bool, subtle: Bool) -> RGB {
        func step(_ lightness: (light: Double, dark: Double)) -> Double { dark ? lightness.dark : lightness.light }
        switch spec.neutrals {
        case let .tinted(hue, chroma):
            let amount = subtle ? chroma / 4 : chroma
            return switch role {
            case .inset:         OKLCH(l: step(Lightness.inset), c: amount, h: hue).rgb
            case .primaryText:   OKLCH(l: step(Lightness.primaryText), c: amount, h: hue).rgb
            case .secondaryText: OKLCH(l: step(Lightness.secondaryText), c: amount * 2, h: hue).rgb
            default:             OKLCH(l: step(Lightness.surface), c: amount, h: hue).rgb
            }
        case let .fixed(surface, inset, primaryText, secondaryText):
            let pair = switch role {
            case .inset:         inset
            case .primaryText:   primaryText
            case .secondaryText: secondaryText
            default:             surface
            }
            return dark ? pair.dark : pair.light
        }
    }

    /// A light and a dark mode color.
    struct Pair: Sendable {
        let light: RGB, dark: RGB
        init(_ light: RGB, _ dark: RGB) { (self.light, self.dark) = (light, dark) }
    }

    // MARK: Page tint

    /// The page tint's two colors and strength, resolved.
    struct PageTint: Sendable {
        let top: Pair
        let bottom: Pair
        let lightOpacity: Double
        let darkOpacity: Double
    }

    func pageTint(onPlanPages: Bool = false, intensity: ColorIntensity) -> PageTint {
        let tint = spec.tint
        let colors = onPlanPages ? tint.onPlanPages ?? tint.colors : tint.colors
        let (top, bottom): (Pair, Pair)
        switch colors {
        case let .wheel(hue, shift, chroma):
            // The same in light and dark mode.
            let start = OKLCH(l: Lightness.tint.top, c: chroma, h: hue).rgb
            let end = OKLCH(l: Lightness.tint.bottom, c: chroma, h: hue + shift).rgb
            (top, bottom) = (Pair(start, start), Pair(end, end))
        case let .fixed(fixedTop, fixedBottom):
            (top, bottom) = (fixedTop, fixedBottom)
        }
        let scale = intensity == .subtle && followsColorIntensity ? 0.5 : 1
        return PageTint(top: top, bottom: bottom, lightOpacity: tint.opacity.light * scale, darkOpacity: tint.opacity.dark * scale)
    }
}

// MARK: - Styles

extension AppTheme.Spec {
    typealias Pair = AppTheme.Pair
    typealias Typography = AppTheme.Typography
    typealias Geometry = AppTheme.Geometry
    typealias Tint = AppTheme.Tint

    /// Soft neutrals like a wedding palette: blush-nude buttons with dark
    /// text — white can't be read on them — taupe links, ivory linen cards.
    /// Rounded. The default.
    static let earth = Self(
        name: NSLocalizedString("Earth", comment: "Style name: nude, linen and taupe"),
        character: NSLocalizedString("Cozy", comment: "Style: its soft font and warm earth tones"),
        typography: Typography(design: .rounded, width: .standard, titleWeight: .bold, numberWeight: .bold),
        geometry: Geometry(cardRadius: 22, controlRadius: 100, outlinedControls: false),
        accent: Pair(0x755D54, 0xDEC9BC), fill: Pair(0xDBC1B4, 0xDBC1B4), onFill: Pair(0x2B2321, 0x2B2321),
        neutrals: .tinted(hue: 60, chroma: 0.018),
        // Blush to champagne.
        tint: Tint(colors: .wheel(hue: 35, shift: 30, chroma: 0.05)))

    /// Clear sky blue, SF Pro.
    static let ocean = Self(
        name: NSLocalizedString("Ocean", comment: "Style name"),
        character: NSLocalizedString("Clean", comment: "Style: its font, SF Pro"),
        typography: Typography(design: .default, width: .standard, titleWeight: .bold, numberWeight: .bold),
        geometry: Geometry(cardRadius: 14, controlRadius: 12, outlinedControls: false),
        accent: Pair(0x1A5BC4, 0x6FA8F5), fill: Pair(0x1A5BC4, 0x2563D0), onFill: Pair(0xFFFFFF, 0xFFFFFF),
        neutrals: .tinted(hue: 255, chroma: 0.022),
        tint: Tint(colors: .wheel(hue: 258, shift: -40, chroma: 0.16)))

    /// Saturated violet; tall, tight and heavy, blocky like a scoreboard.
    static let indigo = Self(
        name: NSLocalizedString("Indigo", comment: "Style name"),
        character: NSLocalizedString("Athletic", comment: "Style: its font, SF Pro Condensed"),
        typography: Typography(design: .default, width: .condensed, titleWeight: .heavy, numberWeight: .heavy),
        geometry: Geometry(cardRadius: 10, controlRadius: 8, outlinedControls: false),
        accent: Pair(0x4038C9, 0xA9A5FF), fill: Pair(0x4038C9, 0x5148E0), onFill: Pair(0xFFFFFF, 0xFFFFFF),
        neutrals: .tinted(hue: 285, chroma: 0.040),
        tint: Tint(colors: .wheel(hue: 279, shift: -16, chroma: 0.20)))

    /// Hot pink buttons with dark text — white can't be read on this pink.
    /// Loud and bubbly.
    static let pink = Self(
        name: NSLocalizedString("Pink", comment: "Style name"),
        character: NSLocalizedString("Rounded", comment: "Style: its font, SF Pro Rounded"),
        typography: Typography(design: .rounded, width: .standard, titleWeight: .heavy, numberWeight: .black),
        geometry: Geometry(cardRadius: 28, controlRadius: 100, outlinedControls: false),
        accent: Pair(0xB8125A, 0xFF8AB8), fill: Pair(0xFF4F8B, 0xFF4F8B), onFill: Pair(0x2B0716, 0x2B0716),
        neutrals: .tinted(hue: 352, chroma: 0.036),
        tint: Tint(colors: .wheel(hue: 4, shift: 43, chroma: 0.20)))

    /// Terracotta on warm peach, in New York serif: the editorial one.
    static let clay = Self(
        name: NSLocalizedString("Clay", comment: "Style name"),
        character: NSLocalizedString("Serif", comment: "Style: its font, New York"),
        typography: Typography(design: .serif, width: .standard, titleWeight: .bold, numberWeight: .semibold),
        geometry: Geometry(cardRadius: 16, controlRadius: 100, outlinedControls: false),
        accent: Pair(0x973D1B, 0xEC9068), fill: Pair(0x973D1B, 0xA3461F), onFill: Pair(0xFFFFFF, 0xFFFFFF),
        neutrals: .tinted(hue: 55, chroma: 0.028),
        // Terracotta to amber.
        tint: Tint(colors: .wheel(hue: 38, shift: 34, chroma: 0.14)))

    /// Black, white and neutral grey in SF Mono, with sharp corners and
    /// outlined buttons. Near-black, and near-white in dark mode, so its
    /// button text flips. The cards are quiet grey: outlined cards
    /// everywhere made too many boxes.
    static let graphite = Self(
        name: NSLocalizedString("Graphite", comment: "Style name"),
        character: NSLocalizedString("Mono", comment: "Style: its font, SF Mono"),
        typography: Typography(design: .monospaced, width: .standard, titleWeight: .semibold, numberWeight: .bold),
        geometry: Geometry(cardRadius: 4, controlRadius: 4, outlinedControls: true),
        accent: Pair(0x0B0C0E, 0xF5F6F7), fill: Pair(0x0B0C0E, 0xF5F6F7), onFill: Pair(0xFFFFFF, 0x0B0C0E),
        neutrals: .fixed(surface: Pair(0xF2F3F4, 0x151618), inset: Pair(0xE8E9EA, 0x1F2023),
                         primaryText: Pair(0x0B0C0E, 0xF5F6F7), secondaryText: Pair(0x5A5E64, 0x9CA1A8)),
        // Grey: a little depth, no color.
        tint: Tint(colors: .fixed(top: Pair(0x7D848D, 0xC4C8CE), bottom: Pair(0xA9AEB5, 0x8A9099)),
                   opacity: (light: 0.05, dark: 0.06)))
}

// MARK: - Color intensity

/// How much of the app a style colors (Settings → Appearance). Subtle, the
/// default: the accent, font and shapes, on near-neutral cards and text and
/// a fainter page tint. Vivid: the cards, text and page in the style's hue
/// too. The neutral style, Graphite, looks the same in both
/// (`AppTheme.followsColorIntensity`).
enum ColorIntensity: String, CaseIterable, Identifiable, Sendable {
    case subtle, vivid

    static let storageKey = "appThemeIntensity"

    static var current: ColorIntensity {
        AppTheme.store?.string(forKey: storageKey).flatMap(ColorIntensity.init(rawValue:)) ?? .subtle
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .subtle: NSLocalizedString("Subtle", comment: "Settings: style color intensity, mostly neutral")
        case .vivid:  NSLocalizedString("Vivid", comment: "Settings: style color intensity, everything in the style's color")
        }
    }
}

// MARK: - RGB

/// A 0xRRGGBB color, with the arithmetic the contrast variants need.
struct RGB: ExpressibleByIntegerLiteral, Equatable, Sendable {
    let red: Double, green: Double, blue: Double

    static let white: RGB = 0xFFFFFF
    static let black: RGB = 0x000000

    init(red: Double, green: Double, blue: Double) {
        (self.red, self.green, self.blue) = (red, green, blue)
    }

    init(integerLiteral hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    func mixed(with other: RGB, by amount: Double) -> RGB {
        RGB(red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, 1…21.
    func contrast(with other: RGB) -> Double {
        let (high, low) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (high + 0.05) / (low + 0.05)
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
}

// MARK: - OKLCH

/// A color as lightness (0…1), chroma (0 is grey) and hue (degrees) in
/// OKLCH, where equal steps look equal: two colors at the same `l` look
/// equally light, whatever their hue. Björn Ottosson's Oklab, in polar form.
struct OKLCH: Equatable, Sendable {
    var l: Double, c: Double, h: Double

    init(l: Double, c: Double, h: Double) {
        (self.l, self.c, self.h) = (l, c, h)
    }

    init(_ rgb: RGB) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(rgb.red), linear(rgb.green), linear(rgb.blue))
        let lms = (cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b),
                   cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b),
                   cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b))
        let lab = (0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2,
                   1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2,
                   0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2)
        let hue = atan2(lab.2, lab.1) * 180 / .pi
        self.init(l: lab.0, c: (lab.1 * lab.1 + lab.2 * lab.2).squareRoot(), h: hue < 0 ? hue + 360 : hue)
    }

    /// In sRGB. A color too vivid for the screen keeps its lightness and hue
    /// and loses chroma until it fits.
    var rgb: RGB {
        if let rgb = linearRGB(chroma: c) { return rgb }
        var (low, high) = (0.0, c)
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if linearRGB(chroma: mid) != nil { low = mid } else { high = mid }
        }
        return linearRGB(chroma: low) ?? RGB(red: l, green: l, blue: l)
    }

    /// Nil when outside sRGB.
    private func linearRGB(chroma: Double) -> RGB? {
        let radians = h * .pi / 180
        let (a, b) = (chroma * cos(radians), chroma * sin(radians))
        let lms = (pow(l + 0.3963377774 * a + 0.2158037573 * b, 3),
                   pow(l - 0.1055613458 * a - 0.0638541728 * b, 3),
                   pow(l - 0.0894841775 * a - 1.2914855480 * b, 3))
        let linear = [4.0767416621 * lms.0 - 3.3077115913 * lms.1 + 0.2309699292 * lms.2,
                      -1.2684380046 * lms.0 + 2.6097574011 * lms.1 - 0.3413193965 * lms.2,
                      -0.0041960863 * lms.0 - 0.7034186147 * lms.1 + 1.7076147010 * lms.2]
        guard linear.allSatisfy({ (-0.0001...1.0001).contains($0) }) else { return nil }
        let srgb = linear.map { value -> Double in
            let c = min(max(value, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return RGB(red: srgb[0], green: srgb[1], blue: srgb[2])
    }
}

// MARK: - Trait and environment

/// The style as a UIKit trait. Dynamic colors read it when they resolve, so
/// a view tree shows the style its environment carries.
struct AppThemeTrait: UITraitDefinition {
    static let defaultValue = AppTheme.defaultStyle
    static let affectsColorAppearance = true
    static let identifier = "Besser.TrainingLab.appTheme"
    static let name = "App theme"
}

extension UITraitCollection {
    var appTheme: AppTheme { self[AppThemeTrait.self] }
}

extension UIMutableTraits {
    var appTheme: AppTheme {
        get { self[AppThemeTrait.self] }
        set { self[AppThemeTrait.self] = newValue }
    }
}

/// Bridged to the trait, so `.environment(\.appTheme, …)` reaches the colors
/// SwiftUI resolves from UIKit. The fonts read it directly (`displayFont`).
struct AppThemeKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = AppTheme.defaultStyle

    static func read(from traitCollection: UITraitCollection) -> AppTheme {
        traitCollection.appTheme
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: AppTheme) {
        mutableTraits.appTheme = value
    }
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// The color intensity as a trait, beside the style's, so it changes the
/// colors in place too.
struct ColorIntensityTrait: UITraitDefinition {
    static let defaultValue = ColorIntensity.subtle
    static let affectsColorAppearance = true
    static let identifier = "Besser.TrainingLab.colorIntensity"
    static let name = "Color intensity"
}

extension UITraitCollection {
    var colorIntensity: ColorIntensity { self[ColorIntensityTrait.self] }
}

extension UIMutableTraits {
    var colorIntensity: ColorIntensity {
        get { self[ColorIntensityTrait.self] }
        set { self[ColorIntensityTrait.self] = newValue }
    }
}

struct ColorIntensityKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = ColorIntensity.subtle

    static func read(from traitCollection: UITraitCollection) -> ColorIntensity {
        traitCollection.colorIntensity
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: ColorIntensity) {
        mutableTraits.colorIntensity = value
    }
}

extension EnvironmentValues {
    var colorIntensity: ColorIntensity {
        get { self[ColorIntensityKey.self] }
        set { self[ColorIntensityKey.self] = newValue }
    }
}
