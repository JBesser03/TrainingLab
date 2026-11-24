//
//  Theme.swift
//  Workout App (iOS)
//
//  The design system. Its colors and title font come from the style the user
//  picked in Settings → Appearance (`AppTheme`, Terrakotta by default): an accent,
//  card and text tones, and SF Pro Rounded, New York, SF Mono and so on for
//  titles and big numbers. Screens use these rather than colors, gradients
//  and materials of their own, so each style reads as one calm surface with
//  a single color that means "act here".
//

import SwiftUI
import UIKit

enum Theme {
    // Every color below resolves to the style in the view's environment
    // (`EnvironmentValues.appTheme`, set by `TabBarView`), so a new choice
    // shows at once without rebuilding anything.

    /// Text, icons, strokes and selection, lighter in dark mode so it reads
    /// on black.
    static let accent = Color(uiColor: AppTheme.themed(.accent))
    /// Primary buttons and filled highlights, with `onAccent` on top.
    static let accentFill = Color(uiColor: AppTheme.themed(.fill))
    static let onAccent = Color(uiColor: AppTheme.themed(.onFill))
    /// The accent and the fill as gradients — one color in a solid style
    /// (`Spec.gradientEnds`). Use `accentFillGradient` to fill a shape;
    /// `accentFill` only where a single color is needed, like a tint.
    static let accentGradient = gradient(.accent, .accentEnd)
    static let accentFillGradient = gradient(.fill, .fillEnd)
    /// Behind an accent icon: a badge that gives a card its bit of color.
    static let accentTint = accent.opacity(0.14)
    /// Cards, chips and rows on the page background, tinted by the style.
    static let surface = Color(uiColor: AppTheme.themed(.surface))
    /// A panel, chip or button inside a card: a step from the card color.
    /// Not the page color, which made white boxes on a light card and black
    /// holes in a dark one.
    static let inset = Color(uiColor: AppTheme.themed(.inset))
    /// Body text, and the quieter text beside it. Also what `Color.primary`
    /// and `Color.secondary` mean in this app (see `Workout_App.swift`).
    static let primaryText = Color(uiColor: AppTheme.themed(.primaryText))
    static let secondaryText = Color(uiColor: AppTheme.themed(.secondaryText))
    /// Status: done or a record, caution, an error or the heart rate. The
    /// same hues in every style, at a lightness that sits with it.
    static let success = Color(uiColor: AppTheme.themed(.success))
    static let warning = Color(uiColor: AppTheme.themed(.warning))
    static let danger = Color(uiColor: AppTheme.themed(.danger))
    /// The page itself: white, or black in dark mode.
    static let background = Color(uiColor: .systemBackground)
    /// The rare edge a control needs, like an unselected chip on a card.
    static let hairline = Color.primary.opacity(0.1)
    /// The line around a button or chip in an outlined style (Graphite).
    static let outline = Color.primary.opacity(0.22)

    /// A shade of the accent for a category or a list's rows (`AppTheme.tone`):
    /// variety without a second color. 0 is the accent.
    static func tone(_ index: Int) -> Color {
        Color(uiColor: UIColor { traits in traits.appTheme.tone(index, for: traits).uiColor })
    }

    private static func gradient(_ start: AppTheme.Role, _ end: AppTheme.Role) -> LinearGradient {
        LinearGradient(colors: [Color(uiColor: AppTheme.themed(start)), Color(uiColor: AppTheme.themed(end))],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The style's font for the navigation bar titles, which SwiftUI can't
    /// style: for bars created from now on, and for the ones on screen.
    @MainActor
    static func applyNavigationBarFonts(_ theme: AppTheme) {
        let large: [NSAttributedString.Key: Any] = [.font: theme.typography.uiTitle(size: 34, weight: .bold, textStyle: .largeTitle)]
        let inline: [NSAttributedString.Key: Any] = [.font: theme.typography.uiTitle(size: 17, weight: .semibold, textStyle: .headline)]
        UINavigationBar.appearance().largeTitleTextAttributes = large
        UINavigationBar.appearance().titleTextAttributes = inline
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                for bar in navigationBars(in: window) {
                    bar.largeTitleTextAttributes = large
                    bar.titleTextAttributes = inline
                }
            }
        }
    }

    @MainActor
    private static func navigationBars(in view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap(navigationBars(in:))
    }
}

/// The spacing scale: paddings and gaps come from these steps, so screens
/// share one rhythm.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// The type scale: four sizes carry the app — `title` (the style's font,
/// `displayFont`), `headline`, `body`/`subheadline` and `caption`. Nothing
/// smaller than `caption` for text people need to read.

extension View {
    /// The style's title font at a text style: page and section titles, card
    /// headings.
    func displayFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(DisplayFont(style: style, weight: weight))
    }

    /// The style's font for a big number — the workout timer, reps, a score —
    /// at a size the caller scales with `@ScaledMetric`.
    func displayNumberFont(size: CGFloat) -> some View {
        modifier(DisplayNumberFont(size: size))
    }

    /// A card: padding, then `cardBackground()`.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding).cardBackground()
    }

    /// The style's card behind the view: a filled panel with its corner
    /// radius — tighter for an `.inset` panel inside a card.
    func cardBackground(_ fill: ThemedFill = .surface) -> some View {
        modifier(ThemedBackground(fill: fill, isCard: true))
    }

    /// The same for a button or chip: the style's control radius — capsules
    /// in some styles, squares in others — and an outline in an outlined style.
    func controlBackground(_ fill: ThemedFill = .surface) -> some View {
        modifier(ThemedBackground(fill: fill, isCard: false))
    }

    /// Where a card's zoom into its detail screen starts, with the card's
    /// corners. The detail screen gets `.navigationTransition(.zoom(sourceID:in:))`
    /// with the same id and namespace.
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        modifier(ZoomSource(id: id, namespace: namespace))
    }

    /// Section title above a group of cards or a horizontal row.
    func sectionTitleStyle() -> some View {
        self.displayFont(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The style's soft, even tint behind a page of cards (the main tabs, a
    /// workout or plan, the lists). Not behind forms, which keep the grouped
    /// system look, or the workout itself.
    func pageTint(onPlanPage: Bool = false) -> some View {
        background { PageTintBackground(onPlanPage: onPlanPage) }
    }

    /// The tinted page behind a form or grouped list, in place of the grey
    /// system one. `StyledForm` and `StyledList` use it; a list built some
    /// other way also gives its rows `FormRowBackground()`.
    func styledFormBackground(onPlanPage: Bool = false) -> some View {
        scrollContentBackground(.hidden)
            .pageTint(onPlanPage: onPlanPage)
    }
}

/// A card's shape on its own, for a tile built as a `ZStack`: the style's
/// corners and fill.
struct ThemedPanel: View {
    var fill: ThemedFill = .surface

    var body: some View {
        Color.clear.cardBackground(fill)
    }
}

/// What a card or control is filled with.
enum ThemedFill {
    /// The style's surface color — the usual card, chip or secondary button.
    case surface
    /// A panel or chip inside a card (`Theme.inset`).
    case inset
    /// The accent: a primary button, a selected chip, a highlighted card.
    case accent
}

/// Shapes and fonts can't resolve from a trait the way colors do, so these
/// read the style from the environment.
private struct ThemedBackground: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let fill: ThemedFill
    let isCard: Bool

    func body(content: Content) -> some View {
        let geometry = theme.geometry
        let radius = !isCard ? geometry.controlRadius : fill == .inset ? geometry.insetRadius : geometry.cardRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // A ghost control: the page with a line around it.
        let outlined = !isCard && geometry.outlinedControls && fill != .accent
        let frosted = geometry.frostedCards && fill == .surface
        let style: AnyShapeStyle = switch fill {
        case .accent: AnyShapeStyle(Theme.accentFillGradient)
        case .inset: AnyShapeStyle(Theme.inset)
        case .surface: frosted ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(outlined ? Theme.background : Theme.surface)
        }
        content
            .background {
                if frosted && isCard {
                    shape.fill(style)
                        .shadow(color: (colorScheme == .dark ? Color.black : Color.gray).opacity(0.15), radius: 8, y: 4)
                } else {
                    shape.fill(style)
                }
            }
            .overlay {
                if outlined {
                    shape.strokeBorder(Theme.outline, lineWidth: 1)
                } else if isCard && geometry.frostedCards && fill == .surface {
                    shape.strokeBorder(Theme.accentGradient, lineWidth: 1)
                        .opacity(0.5)
                }
            }
    }
}

private struct ZoomSource<ID: Hashable>: ViewModifier {
    @Environment(\.appTheme) private var theme
    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content.matchedTransitionSource(id: id, in: namespace) { source in
            source.clipShape(RoundedRectangle(cornerRadius: theme.geometry.cardRadius, style: .continuous))
        }
    }
}

private struct DisplayFont: ViewModifier {
    @Environment(\.appTheme) private var theme
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(theme.typography.title(style, weight: weight))
    }
}

private struct DisplayNumberFont: ViewModifier {
    @Environment(\.appTheme) private var theme
    let size: CGFloat

    func body(content: Content) -> some View {
        content.font(theme.typography.number(size: size))
    }
}

// MARK: - Buttons

/// The one main action of a screen: full width, in the accent and the
/// style's control shape.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .displayFont(.headline, weight: .semibold)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .controlBackground(.accent)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Everything next to the main action: the surface color with primary text.
struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .displayFont(.headline, weight: .semibold)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .controlBackground()
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A card that's a link or a button: it sinks a little while pressed, so it
/// feels like something to touch.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

extension ButtonStyle where Self == SecondaryActionButtonStyle {
    static var secondaryAction: SecondaryActionButtonStyle { SecondaryActionButtonStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Chips

/// A small label or filter in the style's control shape: the surface color,
/// or the accent when selected.
struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected = false

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
        .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
        .controlBackground(isSelected ? .accent : .surface)
    }
}

// MARK: - Icon badge

/// An SF Symbol in the accent color on its tint — the touch of color on a
/// card or row.
struct IconBadge: View {
    let systemName: String
    var size: CGFloat = 44
    /// A shade of the accent (`Theme.tone`) to tell categories apart; nil is
    /// the accent.
    var tone: Int?

    @Environment(\.appTheme) private var theme

    private var color: AnyShapeStyle {
        tone.map { AnyShapeStyle(Theme.tone($0)) } ?? AnyShapeStyle(Theme.accentGradient)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                // A circle, or a square with the style's corners.
                let shape = RoundedRectangle(cornerRadius: min(theme.geometry.controlRadius, size / 2), style: .continuous)
                if theme.geometry.frostedCards {
                    // Frosted glass, with a blurred glow of the gradient.
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        Circle()
                            .fill(color)
                            .frame(width: size * 0.8, height: size * 0.8)
                            .blur(radius: size * 0.45)
                            .opacity(0.4)
                    }
                } else {
                    shape.fill(color).opacity(0.14)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Forms

/// A form in the style: its rows in the card color on the tinted page, so
/// settings and editors look like the rest of the app rather than stock iOS.
/// A row can still set its own `listRowBackground`.
struct StyledForm<Content: View>: View {
    var onPlanPage = false
    @ViewBuilder var content: Content

    var body: some View {
        // On a Group: on the form itself the row background reaches no row.
        Form { Group { content }.listRowBackground(FormRowBackground()) }
            .styledFormBackground(onPlanPage: onPlanPage)
    }
}

/// The same for a grouped list.
struct StyledList<Content: View>: View {
    var onPlanPage = false
    @ViewBuilder var content: Content

    var body: some View {
        List { Group { content }.listRowBackground(FormRowBackground()) }
            .styledFormBackground(onPlanPage: onPlanPage)
    }
}

/// Behind a row of a form: the style's card color, or frosted glass in a
/// frosted style, whose grey would barely show on its page.
struct FormRowBackground: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.geometry.frostedCards {
            Rectangle().fill(.regularMaterial)
        } else {
            Theme.surface
        }
    }
}

// MARK: - Page tint

/// The style's tint over the page (`AppTheme.pageTint`), from one color at
/// the top right to the other at the bottom left; see `pageTint(onPlanPage:)`.
/// Left out with Increase Contrast, for a plain page.
struct PageTintBackground: View {
    let onPlanPage: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.colorIntensity) private var intensity
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .standard {
            let tint = theme.pageTint(onPlanPages: onPlanPage, intensity: intensity)
            let dark = colorScheme == .dark
            let opacity = dark ? tint.darkOpacity : tint.lightOpacity
            LinearGradient(colors: [tint.top, tint.bottom].map { Color(uiColor: (dark ? $0.dark : $0.light).uiColor).opacity(opacity) },
                           startPoint: .topTrailing, endPoint: .bottomLeading)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Placeholders

/// A card's shape while its content loads: grey bars where the title, text
/// and button will be, gently pulsing.
struct SkeletonCard: View {
    var lines = 3
    var showsButton = true

    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            bar(width: 0.55, height: 22)
            ForEach(0..<lines, id: \.self) { index in
                bar(width: index == lines - 1 ? 0.7 : 1, height: 12)
            }
            if showsButton {
                RoundedRectangle(cornerRadius: theme.geometry.controlRadius, style: .continuous)
                    .fill(Theme.inset)
                    .frame(height: 50)
                    .padding(.top, Spacing.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
        .opacity(dimmed ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dimmed = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Theme.inset).frame(width: geometry.size.width * width)
        }
        .frame(height: height)
    }
}

// MARK: - Empty states

/// What a list shows with nothing in it: a large symbol in the style, one
/// line, and the one thing to do about it.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Spacing.l) {
            IconBadge(systemName: systemImage, size: 88)
            VStack(spacing: Spacing.s) {
                Text(title)
                    .displayFont(.title3)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            actions
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xl * 2)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, systemImage: String, message: String? = nil) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

// MARK: - Celebration

/// A short shower of confetti in shades of the accent, for a finished
/// workout. Nothing with Reduce Motion.
struct CelebrationBurst: View {
    private struct Piece {
        let x: Double, drift: Double, fall: Double, delay: Double, spin: Double, tone: Int, wide: Bool
    }

    @State private var start: Date?
    @State private var pieces: [Piece] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration: TimeInterval = 2.6

    var body: some View {
        ZStack {
            // Only while it falls: no timeline ticking otherwise.
            if let start {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSince(start)
                        let fade = max(0, min(1, (Self.duration - time) / 0.6))
                        for piece in pieces {
                            let t = time - piece.delay
                            guard t > 0 else { continue }
                            let x = size.width * piece.x + piece.drift * t + sin(t * 3 + piece.spin) * 10
                            let y = -12 + piece.fall * t + 140 * t * t
                            var layer = context
                            layer.opacity = fade
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: .degrees(piece.spin * t))
                            let rect = piece.wide ? CGRect(x: -5, y: -2, width: 10, height: 4) : CGRect(x: -3, y: -3, width: 6, height: 6)
                            layer.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.tone(piece.tone)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            pieces = (0..<80).map { _ in
                Piece(x: .random(in: 0.05...0.95), drift: .random(in: -40...40), fall: .random(in: 160...320),
                      delay: .random(in: 0...0.5), spin: .random(in: -400...400), tone: .random(in: 0...4), wide: .random())
            }
            start = .now
            try? await Task.sleep(for: .seconds(Self.duration))
            start = nil
        }
    }
}
