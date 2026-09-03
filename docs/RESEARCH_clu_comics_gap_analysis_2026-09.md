# CLU Coverage Report — feature gap analysis vs. Comic Library Utilities

**Compared:** SCO-OSXCursor @ `7d8db91` against [allaboutduncan/clu-comics](https://github.com/allaboutduncan/clu-comics) v6.3 (docs at clucomics.org)
**Date:** September 2026
**Interactive version:** https://claude.ai/code/artifact/33f064f0-9ab8-44fd-ba42-03ba38930827

## The framing

CLU is a Docker web app that **edits the files on disk**. We are a native Mac/iPad app that
**reads them beautifully**. That single difference explains nearly every gap below.

| | Us | CLU |
| --- | --- | --- |
| Formats read | CBZ, CBR, PDF, **EPUB** | CBZ, CBR, PDF |
| Files written | **none** | conversion, repack, page edits, rename, ComicInfo.xml |
| Metadata providers | 4 (ComicVine, Open Library, Google Books, Hardcover) | 8 (+ Metron, GCD, AniList, MangaDex, MangaUpdates, Bedetheque) |

---

## The keystone: we read ComicInfo.xml, we never write it

`CBZReader.extractComicInfo()` parses embedded metadata on import — then everything the user
fixes afterward lives only in our GRDB catalog. Rename the file outside the app, move to
another machine, open the same comic in Komga/Panels/Chunky: all that work is invisible.

CLU writes `ComicInfo.xml` back into the CBZ, which is why its metadata survives everything.
Writing metadata back is the prerequisite for a real bulk-tagging flow, for Source Wall-style
review, and for being a good citizen in someone's existing library.

---

## 1. File operations we cannot do at all (7 gaps)

CLU's core, our emptiest column. We already own the archive-writing primitives in
`BookPackageExporter` — they're just never pointed at the user's library.

- **Convert CBR → CBZ** (none). Per-file, per-folder, whole-library. CLU uses `unar`, which
  handles RARs pure-library implementations choke on. *Payoff for us: CBR is second-class in
  our reader; converting on import makes every such file permanently faster.*
- **Convert PDF → CBZ** (none). JPEG or WebP output. *We already distinguish comic PDFs from
  book PDFs via `pdfReadsAsBook`, which is a better conversion prompt than CLU can offer.*
- **CBZ page editor** (none). Rename, drag-reorder, add, delete pages. *`ThumbnailGridView` is
  already a page grid — grow it rather than build a new surface.*
- **Crop cover / remove first page / add blank** (none). *"Add blank page" directly fixes spread
  alignment in `SpreadReaderView`, a bug users can currently only live with.*
- **Split multi-issue / combine files** (none). *Our `BookFormat` enum already knows which files
  are collected volumes, i.e. split candidates.*
- **Bulk rename + clean files on disk** (partial). CLU: regex volume/issue extraction,
  zero-padding control, "remove text from all filenames", exclude terms, `__MACOSX` and `._`
  junk removal, page renumbering inside the archive. *We have `namingPattern` /
  `FolderStructure` / `ReorganizeViewModel`, which only rename on move — no in-place clean, no
  zero-padding control, no exclude terms.*
- **Trash + restore manifest** (none). *Ship this **before** any of the six above. Our
  Maintenance backup covers the catalog, not the files.*

## 2. Collection intelligence (4 gaps)

Our Dashboard answers "what's wrong with what I have." CLU also answers "what don't I have yet."

- **Missing-issue detection** (none) — *best win-to-effort ratio on this list.*
  `DashboardInsightsView` already computes Collection Completeness over series with 5+ issues;
  surfacing *which* issues are absent is mostly presentation.
- **Real reading lists** (none). Named, ordered, multiple. `.cbl` import (the ComicRack
  reading-order format the community publishes crossover orders in), story-arc import from
  Metron/ComicVine, mapped against what you own. *We have one boolean, `isOnReadingList`, plus a
  `storyArcs` array — an unordered pile, not a reading order.*
- **Pull list / weekly releases / wanted** (adapt). Take the tracking, leave the automation —
  it's genuinely useful and App Store-safe as long as it isn't wired to a downloader.
- **Series identity + automap** (partial). CLU matches folders to canonical series records and
  reads Mylar-compatible `series.json` sidecars. *`SeriesKnowledge` gets us close; what's missing
  is a canonical series record with a total issue count — which is also what unblocks
  missing-issue detection.*

## 3. Metadata depth (5 gaps)

Good spread for *books*; one provider deep and rate-limited for *comics*.

- **Metron** (none) — *highest-value single provider we could add.* CLU's primary source, better
  structured than ComicVine for series/arcs/weekly releases, with spelled-out editorial roles.
  Our `ComicVineQuota` UI exists only because ComicVine caps us at 200 calls/hour.
- **Manga + European providers** (none). AniList, MangaDex, MangaUpdates, Bedetheque, GCD.
  *ComicVine is poor on manga, and manga is a large share of digital collections — those
  libraries currently get almost nothing from our fetch.*
- **Local offline metadata database** (none). CLU runs ComicVine and GCD from local SQLite.
  *This deletes a whole class of our UX problem: the quota meter, the throttling, and the
  auto-apply-confident-matches compromise all exist to ration a remote API.*
- **Source Wall — bulk metadata review** (none). Spreadsheet-style staged edits with a visible
  diff before commit. *`BulkEditSheet` is find-and-replace; this is diff review. The Organize
  staging table is the natural place to grow it.*
- **Batch history + bulk revert** (partial). *We have per-book `metadataBackup` — one book, one
  undo. Fetch 200 books, get one bad run, and there's no single action to undo it.* CLU also
  does creator-credit backfill for records published before their credits land.

## 4. Stats, automation, plumbing (6 gaps)

- **Reading timeline** (none). `lastReadDate` is on every `Comic` — the data exists, unrendered.
- **"Wrapped" year in review** (none). *Most marketable feature on CLU's list, near-free to
  compute from data we already store, and a native app renders/shares images far better than a
  container does.*
- **Deeper insights** (partial). Top writers/artists/characters, reading by year, disk usage.
  *Free win: we store `writer`, `artist`, `colorist`, `inker`, `coverArtist`, `editor` and
  `fileSize` already. "Your top 10 writers" is a group-by we aren't running.*
- **Watch folder** (none). *Fits us well — `autoSortIntoLibrary` and the security-scoped home
  library bookmark already exist. Scope it Mac-first; genuinely harder on iPad.*
- **Log viewer + debug export** (partial). *"Reproduce it with Console.app open" is not a
  reasonable ask of a TestFlight user. A Maintenance "Export Diagnostics" button pays for itself
  on the first bug report.*
- **OPDS / companion API / Komga sync** (optional). Low priority, but note the direction: people
  run CLU *alongside* Komga. Reading an existing comic server's library rather than replacing it
  would serve users we currently can't reach at all.

---

## Where we're already ahead

Worth stating plainly, because it decides what we should *not* copy. CLU is a maintenance layer
that grew a reader; we're a reader that grew a maintenance layer.

- **The reader, decisively** — page curl, spreads, vertical scroll, native UIKit slide pager,
  zoomable canvas, tap zones, next-issue preview, per-book transition/zoom memory. CLU's reader
  is page-by-page navigation that remembers your place.
- **EPUB with real typography** — font, line spacing, margins, per-book theme/size, chapter-level
  restore. CLU doesn't read EPUB at all.
- **Zero setup** — no Docker, volume mapping, `PUID`/`PGID`/`UMASK`, or reverse proxy.
- **Learning from corrections** — `OrganizationLearner` + knowledge base with confidence scoring.
  CLU's automap matches a remote catalog but doesn't learn the user's own patterns.
- **Device-to-device transfer** — `.scobook` packages, streamed and SHA-256 verified. CLU assumes
  a server.
- **Library health score** — one diagnosis covering duplicates, missing metadata, missing covers.
- **Publisher branding** — banners, logo library, per-publisher color.

## Deliberately not copying

- **Downloads (GetComics / Usenet / DC++ / MEGA / browser extension)** — App Review will reject
  it and it's real legal exposure for a paid app. Self-hosted GPL software carries risk we can't.
  Take the *pull list*, leave the pipes.
- **Multi-user accounts, roles, per-folder permissions** — solving a problem we don't have.
  iCloud sync across one person's devices is our version of this.
- **AI recommendations** — needs a fourth user-supplied API key on a settings screen that already
  asks for three. Revisit only if it can run with zero configuration.
- **Scheduled server jobs / `/health` / in-app restart** — container concerns. Background refresh
  on launch and incremental rescan, yes; a scheduler UI, no.

---

## Suggested build order

A genuine dependency sequence, not a ranking.

| # | Item | Depends on |
| --- | --- | --- |
| 1 | Trash + restore for file operations | — (blocks 2, 4, 9, 10) |
| 2 | Write `ComicInfo.xml` back into CBZ | 1 (blocks 5, 7) |
| 3 | Missing-issue detection | — (feeds 6) |
| 4 | CBR → CBZ conversion, on import and in bulk | 1 |
| 5 | Metron as a second comics provider | 2 (feeds 3, 6) |
| 6 | Reading lists + pull list | 3, 5 |
| 7 | Batch metadata history with bulk revert | 2 |
| 8 | Timeline, deeper insights, Wrapped | — |
| 9 | Page editor grown out of `ThumbnailGridView` | 1, 4 |
| 10 | Watch folder (Mac-first) + diagnostics export | 1, 4 |

**Rationale for the top three:** #1 because everything after it writes to user files and
"don't lose or corrupt user files" stops being a slogan the moment we do. #2 because it's the
keystone — portable metadata is what makes all the tagging work worth doing. #3 because the
data is nearly in hand and it answers the question collectors actually care about.
