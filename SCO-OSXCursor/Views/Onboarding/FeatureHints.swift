//
//  FeatureHints.swift
//  SCO-OSXCursor
//
//  One-time contextual hints ("coach marks") that introduce each area of
//  the app the first time the user encounters it. A hint appears as a
//  dismissible card overlaid on the view; once dismissed it never shows
//  again (persisted in UserDefaults). All hints can be re-armed from
//  Settings → Appearance → Show Feature Hints Again.
//

import SwiftUI

// MARK: - Hint Persistence

enum FeatureHintStore {
    private static let keyPrefix = "featureHint.dismissed."

    static func isDismissed(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: keyPrefix + id)
    }

    static func dismiss(_ id: String) {
        UserDefaults.standard.set(true, forKey: keyPrefix + id)
    }

    /// Re-arms every hint so each shows again on next encounter.
    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Hint Card

struct FeatureHintCard: View {
    let icon: String
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(AccentColors.primary)
                .frame(width: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text(message)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AccentColors.primary)
                .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 440)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AccentColors.primary.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }
}

// MARK: - View Modifier

private struct FeatureHintModifier: ViewModifier {
    let id: String
    let icon: String
    let title: String
    let message: String
    let alignment: Alignment

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if isVisible {
                    FeatureHintCard(icon: icon, title: title, message: message) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isVisible = false
                        }
                        FeatureHintStore.dismiss(id)
                    }
                    .padding(Spacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onAppear {
                guard !FeatureHintStore.isDismissed(id) else { return }
                // Small delay so the hint fades in after the view settles,
                // rather than popping in with it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard !FeatureHintStore.isDismissed(id) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    /// Overlays a one-time dismissible hint card the first time this view
    /// appears. `id` is the persistence key — reuse the same id to share
    /// a single hint across multiple entry points.
    func featureHint(
        id: String,
        icon: String,
        title: String,
        message: String,
        alignment: Alignment = .bottom
    ) -> some View {
        modifier(FeatureHintModifier(
            id: id, icon: icon, title: title, message: message, alignment: alignment
        ))
    }
}
