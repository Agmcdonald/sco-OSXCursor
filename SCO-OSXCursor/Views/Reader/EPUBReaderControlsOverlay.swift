//
//  EPUBReaderControlsOverlay.swift
//  SCO-OSXCursor
//
//  HUD overlay for the EPUB reader: title, chapter progress, font size controls,
//  previous/next chapter navigation, and close button.
//

import SwiftUI

struct EPUBReaderControlsOverlay: View {
    let comic: Comic
    @Binding var currentChapter: Int
    let totalChapters: Int
    @Binding var fontSize: Int
    let chapters: [EPUBChapter]
    @Binding var showTableOfContents: Bool
    /// Currently active theme — drives the cycle button's icon.
    let theme: EPUBTheme
    var onClose: () -> Void
    var onShowSettings: () -> Void
    /// One-click theme cycle: Dark → Light → Sepia → Dark.
    var onCycleTheme: () -> Void
    var onPreviousChapter: () -> Void
    var onNextChapter: () -> Void
    var onUserInteraction: () -> Void

    // Font size constraints
    private let minFont = 12
    private let maxFont = 28

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ──────────────────────────────────────────────────────
            topBar
                .padding(.top, safeTopPadding)

            Spacer()

            // ── Bottom bar ───────────────────────────────────────────────────
            bottomBar
                .padding(.bottom, safeBottomPadding)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    // macOS NOTE: the window's titlebar container swallows clicks across the
    // entire top band even when the toolbar is hidden, so on macOS the top
    // bar carries NO interactive controls — Close/Settings/ToC live in the
    // bottom bar instead (which reliably receives clicks). Esc still closes.

    private var topBar: some View {
        HStack(spacing: 12) {
            #if !os(macOS)
            // Close button
            closeButton
            #endif

            Spacer()

            // Title + chapter
            VStack(spacing: 2) {
                Text(comic.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Chapter \(currentChapter + 1) of \(totalChapters)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            #if !os(macOS)
            themeButton
            settingsButton
            tocButton
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Shared Buttons

    private var closeButton: some View {
        Button(action: {
            onUserInteraction()
            onClose()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close reader")
    }

    private var themeButton: some View {
        Button(action: {
            onUserInteraction()
            onCycleTheme()
        }) {
            Image(systemName: theme.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .background(AnyShapeStyle(.ultraThinMaterial))
        .clipShape(Circle())
        .buttonStyle(.plain)
        .help("Theme: \(theme.displayName) — click to switch")
    }

    private var settingsButton: some View {
        Button(action: {
            onUserInteraction()
            onShowSettings()
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .background(AnyShapeStyle(.ultraThinMaterial))
        .clipShape(Circle())
        .buttonStyle(.plain)
        .help("Reader Settings (theme, font)")
    }

    private var tocButton: some View {
        Button(action: {
            onUserInteraction()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showTableOfContents.toggle()
            }
        }) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .background(showTableOfContents ? AnyShapeStyle(Color(hex: "#9B8FE8").opacity(0.3)) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(Circle())
        .buttonStyle(.plain)
        .help("Table of Contents")
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Progress scrubber
            progressScrubber

            HStack(spacing: 0) {
                #if os(macOS)
                // Close — lives down here on macOS because the window's
                // titlebar swallows clicks in the top band (see topBar note)
                closeButton
                    .padding(.horizontal, 10)

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.15))
                #endif

                // Previous chapter
                Button(action: {
                    onUserInteraction()
                    onPreviousChapter()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Previous")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(currentChapter > 0 ? .white : .white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(currentChapter <= 0)
                .help("Previous chapter")

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.15))

                // Font size controls
                fontSizeControls
                    .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.15))

                // Next chapter
                Button(action: {
                    onUserInteraction()
                    onNextChapter()
                }) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(currentChapter < totalChapters - 1 ? .white : .white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(currentChapter >= totalChapters - 1)
                .help("Next chapter")

                #if os(macOS)
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.15))

                // Theme cycle + Settings + ToC — relocated from the top
                themeButton
                    .padding(.leading, 10)
                settingsButton
                    .padding(.leading, 10)
                tocButton
                    .padding(.horizontal, 10)
                #endif
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Progress Scrubber

    private var progressScrubber: some View {
        HStack(spacing: 12) {
            Text("1")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))

            // Chapter progress dots
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#9B8FE8"))
                        .frame(
                            width: totalChapters > 1
                                ? geo.size.width * CGFloat(currentChapter) / CGFloat(totalChapters - 1)
                                : geo.size.width,
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.2), value: currentChapter)
                }
                // Tap to jump
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard totalChapters > 1 else { return }
                            let fraction = value.location.x / geo.size.width
                            let chapter = Int(fraction * Double(totalChapters - 1) + 0.5)
                            let clamped = max(0, min(totalChapters - 1, chapter))
                            if clamped != currentChapter {
                                currentChapter = clamped
                                onUserInteraction()
                            }
                        }
                )
            }
            .frame(height: 20)

            Text("\(totalChapters)")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Font Size Controls

    private var fontSizeControls: some View {
        HStack(spacing: 10) {
            Button(action: {
                onUserInteraction()
                if fontSize > minFont { fontSize -= 1 }
            }) {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 14))
                    .foregroundColor(fontSize > minFont ? .white : .white.opacity(0.25))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(fontSize <= minFont)
            .help("Decrease font size")

            Text("\(fontSize)pt")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 36)

            Button(action: {
                onUserInteraction()
                if fontSize < maxFont { fontSize += 1 }
            }) {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 14))
                    .foregroundColor(fontSize < maxFont ? .white : .white.opacity(0.25))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(fontSize >= maxFont)
            .help("Increase font size")
        }
        .padding(.vertical, 6)
    }

    // MARK: - Safe area helpers

    private var safeTopPadding: CGFloat {
        #if os(macOS)
        // The window's invisible title-bar drag region swallows clicks in
        // the top ~28pt (and the traffic lights sit top-left). Push the
        // bar's content below it so Close/Settings/ToC are actually
        // clickable and the X doesn't collide with close/minimize/zoom.
        // The gradient background still extends to the window edge.
        return 38
        #else
        return 0  // SwiftUI safe area handles this
        #endif
    }

    private var safeBottomPadding: CGFloat {
        #if os(macOS)
        return 0
        #else
        return 0
        #endif
    }
}
