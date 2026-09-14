# Super Comic Organizer

A native Swift/SwiftUI comic collection organizer and reader for macOS and iPadOS/iOS. Imports CBZ, CBR, PDF, and EPUB files, automatically organizes them by parsing filenames and fetching metadata, and reads them with per-book position and zoom memory. Local-first: no account, no upload.

## Features

### 🗂️ Intelligent File Processing

- **Smart Filename Parsing**: Automatically extracts series name, issue number, year, and volume from comic filenames
- **Knowledge Base Matching**: Uses a preseeded database of comic series to intelligently match and fill missing metadata
- **Confidence Scoring**: Rates matches as High/Medium/Low confidence to help identify uncertain results
- **Batch Processing**: Process multiple files simultaneously with progress tracking
- **Organize Tab (Mac)**: Stage files before import — review detections, fetch metadata, group into folders, then apply

### 🌐 Online Metadata

- **Two comic sources**: ComicVine (free API key) or Metron (free metron.cloud account) — pick your preferred source in Settings, and fetch from the other any time from the edit sheet
- **Rich fills**: Publisher, creators, summary, cover dates, story arcs — and from Metron, characters, teams, and in-store dates
- **Book sources for EPUBs**: Open Library, Google Books, and Hardcover, with ISBN-exact matching
- **Match picker & link override**: Confirm ambiguous matches, review batch results one at a time, or paste a database link/ID directly
- **Safe by design**: First fetch only fills blanks; Re-fetch deliberately replaces wrong data; every fetch is undoable with Revert
- **Rate-limit aware**: Built-in throttles and live quota readouts for both sources

### 📚 Library Management

- **Organized Collection**: Browse comics in grid, list, or publisher views with adjustable cover zoom (up to ~4 covers across on desktop)
- **Advanced Search & Filtering**: Search across titles, series, creators, tags, story arcs, characters, and teams; stack filters freely
- **Folders**: Your own collections, with per-folder reading style overrides — purely organizational, files never move
- **Fast selection**: Swipe to select, long-click to enter selection mode (Mac), Escape to clear, shift-click ranges
- **Bulk actions**: Fetch or re-fetch metadata, edit fields, mark read/unread, add to folders, send to device
- **Trash & Restore**: Every delete is recoverable — removed books (and deleted files) sit in a Trash in the Maintenance tab with a 7/30/90-day or never auto-purge, restorable with their metadata, reading progress, and folders intact
- **Metadata Editing**: Correct and update comic information with intelligent suggestions and autocomplete

### 📖 Reader

- **Every format**: CBZ/CBR page reader with pinch zoom and smooth page slides, PDF (comic or book mode), EPUB with themes and font sizing
- **Reading styles**: Western, manga (right-to-left), and vertical scroll, with per-book overrides
- **Progress memory**: Every book reopens exactly where you left it, including zoom and EPUB position

### 📲 Transfer

- **Send to Device**: Package a book with its metadata and reading progress into a `.scobook` and AirDrop it from Mac to iPad/iPhone

### 📊 Analytics & Insights

- **Collection Statistics**: Publisher breakdowns, decade analysis, and completion metrics
- **Library Health**: Monitor collection quality and fill metadata gaps in one click
- **API Usage**: Live quota card for the active metadata source

## Documentation

- In-app User Manual (Help) covers every feature and menu
- `docs/METRON_INTEGRATION.md` and `docs/COMICVINE_INTEGRATION.md` document the metadata integrations
