//
//  OrganizeView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct OrganizeView: View {
    @ObservedObject var viewModel: OrganizeViewModel

    var body: some View {
        HSplitView {
            // Left: File List (Staging Area)
            VStack(spacing: 0) {
                // Header / Toolbar
                HStack {
                    Text("File Processor")
                        .font(.title3)

                    Spacer()

                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.canCreateDirectories = false
                        let types = [
                            UTType(filenameExtension: "cbz"), UTType(filenameExtension: "cbr"),
                            .pdf,
                        ].compactMap { $0 }
                        panel.allowedContentTypes = types

                        panel.begin { response in
                            if response == .OK {
                                Task {
                                    await viewModel.addFiles(panel.urls)
                                }
                            }
                        }
                    }) {
                        Label("Add Files...", systemImage: "plus")
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        // Scan folder logic (future)
                    }) {
                        Label("Scan Folder...", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }
                .padding()
                #if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor))
                #endif

                Divider()

                // List
                List(viewModel.stagedComics, selection: $viewModel.selectedComicID) { comic in
                    HStack(spacing: 8) {
                        // Checkbox
                        Image(
                            systemName: viewModel.checkedComicIDs.contains(comic.id)
                                ? "checkmark.square.fill" : "square"
                        )
                        .foregroundColor(
                            viewModel.checkedComicIDs.contains(comic.id) ? .accentColor : .secondary
                        )
                        .onTapGesture {
                            viewModel.toggleCheck(for: comic.id)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(comic.proposedFileName)
                                .font(.body)
                                .foregroundColor(.primary)

                            HStack {
                                Text(comic.originalFileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                if comic.status == .ready {
                                    Text("Ready")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                } else {
                                    Text("Pending")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(comic.id)
                }
                .listStyle(.sidebar)

                // Batch Action Bar
                if !viewModel.stagedComics.isEmpty {
                    Divider()
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                await viewModel.confirmAllReady()
                            }
                        }) {
                            Label("Apply All Ready", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.stagedComics.filter { $0.status == .ready }.isEmpty)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }

                // Empty State / Drop Zone
                if viewModel.stagedComics.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Drag and drop comic files here")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Background?
                }
            }
            .frame(minWidth: 300)
            // .onDrop(...) // TODO

            // Right: Inspector / Editor
            if let selected = viewModel.selectedComic {
                OrganizeInspectorView(comic: selected, viewModel: viewModel)
                    .id(selected.id)  // Force rebuild on selection change
                    .frame(minWidth: 300)
            } else {
                VStack {
                    Text("Select a file to review details")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(macOS)
                    .background(Color(NSColor.textBackgroundColor))
                #endif
            }
        }
    }
}
