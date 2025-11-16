//
//  InReaderSettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import SwiftUI

@MainActor
struct InReaderSettingsView: View {
    @Binding var comic: Comic
    @Binding var isPresented: Bool
    @ObservedObject private var settings = ReaderSettings.shared
    let onComicUpdated: (Comic) -> Void  // Callback to save changes
    
    @State private var selectedTransition: PageTransition?
    @State private var useDefault: Bool = true
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Current setting info
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Current Transition")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                        
                        HStack(spacing: Spacing.md) {
                            Image(systemName: effectiveTransition.icon)
                                .font(.system(size: 24))
                                .foregroundColor(AccentColors.primary)
                                .frame(width: 40, height: 40)
                                .background(AccentColors.primary.opacity(0.15))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(effectiveTransition.rawValue)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                
                                Text(useDefault ? "Using app default" : "Custom for this book")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                } header: {
                    Text("Active Transition")
                }
                
                Section {
                    // Use default toggle
                    Toggle("Use App Default", isOn: $useDefault)
                        .tint(AccentColors.primary)
                        .onChange(of: useDefault) { _, newValue in
                            if newValue {
                                selectedTransition = nil
                            } else {
                                selectedTransition = settings.effectiveTransition(for: comic)
                            }
                        }
                    
                    if !useDefault {
                        // Transition picker
                        Picker("Page Transition", selection: Binding(
                            get: { selectedTransition ?? settings.pageTransition },
                            set: { selectedTransition = $0 }
                        )) {
                            ForEach(
                                PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform },
                                id: \.self
                            ) { transition in
                                Label(transition.rawValue, systemImage: transition.icon)
                                    .tag(transition)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                } header: {
                    Text("Transition Settings")
                } footer: {
                    Text("Custom transitions only apply to this book. Other books will use the app default.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
                
                Section {
                    HStack(spacing: Spacing.lg) {
                        ForEach(
                            PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform }.prefix(4),
                            id: \.self
                        ) { transition in
                            TransitionPreviewCard(transition: transition)
                        }
                    }
                } header: {
                    Text("Preview")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Reader Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Load current settings
            if let preferredString = comic.preferredTransition,
               let preferred = PageTransition(rawValue: preferredString) {
                useDefault = false
                selectedTransition = preferred
            } else {
                useDefault = true
                selectedTransition = nil
            }
        }
    }
    
    private var effectiveTransition: PageTransition {
        if useDefault {
            return settings.pageTransition
        } else {
            return selectedTransition ?? settings.pageTransition
        }
    }
    
    private func saveChanges() {
        var updatedComic = comic
        if useDefault {
            updatedComic.preferredTransition = nil
        } else {
            updatedComic.preferredTransition = selectedTransition?.rawValue
        }
        updatedComic.dateModified = Date()
        
        comic = updatedComic
        onComicUpdated(updatedComic)
    }
}

// MARK: - Transition Preview Card
struct TransitionPreviewCard: View {
    let transition: PageTransition
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: transition.icon)
                .font(.system(size: 20))
                .foregroundColor(AccentColors.primary)
                .frame(width: 60, height: 60)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(BorderColors.subtle, lineWidth: 1)
                )
            
            Text(transition.rawValue)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

