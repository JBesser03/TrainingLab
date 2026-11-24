//
//  ExerciseSymbol.swift
//  Workout App (iOS)
//
//  An exercise's `symbol` names either one of the app's own figure assets or,
//  for movements that have none (swimming, rowing, curls…), an SF Symbol such
//  as "figure.pool.swim". This resolves which one it is, so call sites stop
//  assuming every symbol is an asset name.
//

import SwiftUI
import UIKit

enum ExerciseSymbol: Equatable {
    case asset(String)
    case system(String)

    /// Assets whose SVG holds an SF Symbol typed as SF Pro *text*. The asset
    /// catalog can't render SVG text and draws a "?" box instead, so names
    /// still stored on older or custom exercises resolve to the symbol the
    /// asset was meant to show.
    static let textGlyphAssets: [String: String] = [
        "deadlift": "figure.strengthtraining.traditional",
        "sprintSymbol": "figure.run",
    ]

    /// Nil for an empty name, the legacy "not Found" placeholder, or a name
    /// that is neither an asset nor an SF Symbol.
    init?(name: String) {
        guard !name.isEmpty, name != "not Found", name != "Not found" else { return nil }
        if let system = Self.textGlyphAssets[name] {
            self = .system(system)
        } else if UIImage(named: name) != nil {
            self = .asset(name)
        } else if UIImage(systemName: name) != nil {
            self = .system(name)
        } else {
            return nil
        }
    }

    /// The asset name, when the symbol is one of the app's own images. Those
    /// carry their own colors (with a dark-mode variant).
    var assetName: String? {
        if case .asset(let name) = self { return name }
        return nil
    }

    /// The SF Symbol name, when the symbol is a system image. Those take the
    /// caller's foreground style, like the muscle-group fallback does.
    var systemName: String? {
        if case .system(let name) = self { return name }
        return nil
    }
}

/// An exercise symbol scaled to fit its frame: the asset in its own colors, or
/// the SF Symbol in the primary color. Any other name is drawn as an asset, as
/// before — that keeps the "not Found" placeholder image showing.
struct ExerciseSymbolImage: View {
    let name: String

    var body: some View {
        if let system = ExerciseSymbol(name: name)?.systemName {
            Image(systemName: system)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        } else {
            Image(name)
                .resizable()
                .scaledToFit()
        }
    }
}

#if DEBUG
/// Every catalog exercise with its resolved symbol — one place to review the
/// whole library's artwork in light and dark mode.
private struct ExerciseSymbolCatalogPreview: View {
    var body: some View {
        List(GymExerciseCatalog.all, id: \.id) { def in
            HStack(spacing: 14) {
                let symbol = ExerciseSymbol(name: def.symbol)
                Group {
                    if let asset = symbol?.assetName {
                        Image(asset).resizable().scaledToFit()
                    } else if let system = symbol?.systemName {
                        Image(systemName: system).resizable().scaledToFit()
                            .foregroundStyle(Theme.accent)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading) {
                    Text(def.name)
                    Text(def.symbol).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("Light") { ExerciseSymbolCatalogPreview() }
#Preview("Dark") { ExerciseSymbolCatalogPreview().preferredColorScheme(.dark) }
#endif
