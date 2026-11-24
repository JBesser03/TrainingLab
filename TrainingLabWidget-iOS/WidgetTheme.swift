//
//  WidgetTheme.swift
//  TrainingLabWidget-iOS
//
//  The app's look for every widget in this extension: the accent, colors,
//  fonts and corners of the style the user picked in Settings → Appearance
//  (`AppTheme`, read from the App Group). The widget has its own asset
//  catalog and cannot see the app's colors, so `Color("accentColor")` would
//  silently render black.
//

import SwiftUI

/// The app's `Theme.accent`, lighter in dark mode so it reads on black.
var accent: Color { AppTheme.current.color(.accent) }

/// The accent as it looks in dark mode. For the Live Activity, whose card is
/// dark in both appearances.
var accentOnDark: Color { AppTheme.current.darkAccent }

/// A color of the user's style at their color intensity (Settings →
/// Appearance), in this extension's light or dark mode.
func themed(_ role: AppTheme.Role) -> Color { AppTheme.current.color(role, intensity: .current) }

/// The style's font for titles and numbers.
var typography: AppTheme.Typography { AppTheme.current.typography }

/// The style's corners for buttons and chips.
var controlRadius: CGFloat { AppTheme.current.geometry.controlRadius }

/// The Live Activity's card: the style's card color as it is in dark mode.
var activityBackground: Color { AppTheme.current.darkColor(.surface, intensity: .current) }

/// Behind a widget: the app's page — white or black with the style's tint.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = AppTheme.current.pageTint(intensity: .current)
        let dark = colorScheme == .dark
        let opacity = dark ? tint.darkOpacity : tint.lightOpacity
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(colors: [tint.top, tint.bottom].map { Color(uiColor: (dark ? $0.dark : $0.light).uiColor).opacity(opacity) },
                           startPoint: .topTrailing, endPoint: .bottomLeading)
        }
    }
}
