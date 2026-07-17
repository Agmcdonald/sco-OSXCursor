# Webcomics in Super Comic Organizer — Exploratory Research

*July 2026. Exploratory only — no implementation decisions made.*

## TL;DR

Webcomics are messy because there is no standard unit: some are numbered strips (xkcd), some are date-keyed (Penny Arcade, SMBC historically), some are chapter/page (Paranatural), some are episode-based infinite scroll (Webtoon/Tapas). SCO is well positioned on the **reading** side (vertical-scroll webtoon reader already exists) but has three real gaps: it can't import loose image folders, its filename parser assumes `Series #123 (Year)` conventions, and it has no concept of date- or episode-ordered series. The safest, highest-value path is: **import what users have already saved** (folders of images → bundled CBZ with generated ComicInfo.xml), add a `webcomic` book format with date/episode-aware parsing and sorting, and treat any built-in downloading as a later, carefully-scoped phase (legal risk varies enormously by site).

---

## 1. The webcomic landscape — sorting/naming taxonomy

The example sites break down into four ordering models:

| Model | Unit | Ordering key | Examples |
|---|---|---|---|
| **Numbered strip** | single image | sequential integer | xkcd (`xkcd.com/614`), JL8 (`limbero.org/jl8/270_8` — strip 270, `_8` is a language/mirror variant) |
| **Date-keyed strip** | single image (sometimes multi-panel) | publish date | Penny Arcade (`/comic/2026/07/13/slug`), SMBC (slug URLs, date-ordered archive), PhD Comics (numeric id + date) |
| **Chapter/page** | page within a chapter | chapter → page | Paranatural (`/comic/chapter-1`), most long-form story comics on ComicFury/Hiveworks/WordPress-ComicPress |
| **Episode scroll** | tall vertical episode (many stitched images) | episode number within a series | Webtoon (`title_no` + `episode_no`), Tapas, WebComics app |

Cross-cutting realities:

- **Hosting is fragmented.** Big platforms (Webtoon, Tapas) vs. collectives (Hiveworks — Pixie Trix, Penny Arcade self-hosted) vs. indie WordPress/ComicPress sites (SMBC, Paranatural) vs. hand-rolled HTML (xkcd). No shared archive format.
- **One strip ≠ one image.** SMBC has the hidden "votey" bonus panel; xkcd has alt-text that is part of the joke; Webtoon episodes are 20–60 sliced JPEGs meant to be read as one continuous strip.
- **Series metadata lives nowhere.** Unlike print comics (ComicVine), there's no canonical metadata DB for webcomics. The closest things are tracker sites' crowd-sourced indexes: [Piperka](https://piperka.net/) (~5,000+ comics, archive-page index) and [Comic Rocket](https://www.comic-rocket.com/help/) (crowd-sourced reading-position tracker). Neither exposes a supported public API, but both prove the "index + bookmark" model works.

## 2. Getting the images — what exists today

**Users' own saved files (most realistic source).** People who archive webcomics typically have: a folder of sequentially numbered images (`0001.png … 2900.png`), date-named images (`2019-03-14.png`), per-chapter subfolders, or CBZs produced by the tools below. This is content SCO can legitimately organize — it's already on disk.

**Site APIs/feeds (rare but real):**
- xkcd has a genuine JSON API: [`xkcd.com/info.0.json`](https://xkcd.com/json.html) and `/{num}/info.0.json` — number, title, image URL, alt text, publish date. No auth. This is the exception, not the rule.
- **RSS/Atom is the closest thing to a universal webcomic API.** Nearly every indie/WordPress comic (SMBC, Penny Arcade, xkcd, PhD, most Hiveworks sites) publishes a feed with the latest strips. Good for "new strip" notification; useless for back-catalog.
- Webtoon/Tapas have no public APIs; their apps use private, authenticated endpoints.

**Existing scraper/archiver tools (mature ecosystem, all Python CLIs):**
- [dosage](https://github.com/webcomics/dosage) — strip downloader/archiver, ~2,000 comics in its module database, per-site scraping rules maintained by the community. Designed for "keep a local mirror, catch up since last run."
- [webcomix](https://github.com/J-CPelletier/webcomix) — generic next-button crawler; you give it a start URL + XPath for image and next link; can emit **CBZ directly**. Works on static sites only (no JS).
- [gallery-dl](https://gallery-dl.com/gallery-dl-supported-sites-list/) — supports Webtoon episode/series downloads among hundreds of sites; plus one-off tools like [Tapas-Comic-Downloader](https://github.com/TilCreator/Tapas-Comic-Downloader).

The takeaway from these tools: **per-site adapters are unavoidable** for scraping (every site differs), the community already maintains that logic, and the sensible interchange format they converge on is **CBZ**.

**Legal reality check.** This is the constraint that shapes the feature:
- Platform ToS matter. [Webtoon's terms](https://www.webtoons.com/en/terms) grant personal viewing only and explicitly prohibit reproducing, copying, or downloading content beyond what the app offers, plus an anti-circumvention clause. Building a Webtoon ripper into a Mac App Store app is a non-starter (both legally and for App Review).
- Indie sites are a spectrum: xkcd is CC BY-NC 2.5 (archiving fine); many indie comics tolerate personal archiving; some creators explicitly object because ad views are their income.
- **Organizing files the user already has carries essentially no risk. Downloading on the user's behalf carries site-by-site risk.** Any fetch feature should be opt-in, personal-use, rate-limited, and scoped to sites that permit it (or to RSS, which is published for exactly this kind of consumption).

## 3. Where SCO stands today (codebase findings)

What already fits:
- `VerticalScrollReaderView` + `ReadingStyle.verticalScroll` is a working webtoon reader, and `PageImageCache` already special-cases very tall strip images. Reading style resolves per-book → per-folder → global, so a webcomic folder can force vertical scroll.
- CBZ is a first-class citizen (`CBZReader`), and ComicInfo.xml is already parsed on import (`MetadataParser.parseComicInfo`) and prioritized over filename parsing.
- Folders are virtual (junction table), carry a `readingStyle`, and never move files — a natural home for a webcomic series.
- `BookFormat` (issue/oneShot/volume/ebook) is a raw-string enum on an existing column; adding `.webcomic` is a small migration.

The gaps:
1. **Import allow-list is `cbz/cbr/pdf/epub` only** (`OrganizeViewModel.addFiles`, mirrored in `LibraryViewModel`). A folder of loose PNGs — the most common webcomic archive shape — is silently skipped.
2. **Filename parser is print-comic shaped** (`MetadataParser.parseFromFilename`): `#123`, `V2`, `(1999)`, release-group noise stripping. Webcomic names (`2019-03-14.png`, `ch03_p045.png`, `Episode 112 - The Return.jpg`, `0614.png`) will parse to low confidence with empty issue numbers.
3. **No date- or episode-native ordering.** `issueNumber` is a string sorted with natural compare (fine for episode numbers), but there's no publish-date sort within a series, no chapter entity, and no ordered reading list.
4. **No content networking at all.** Existing networking is metadata-only (ComicVine/OpenLibrary/GoogleBooks/Hardcover), API-key gated and quota-tracked. A downloader would be greenfield and needs entitlement/sandbox/App Review thought.
5. **Progress is integer pages.** Fine if strips become CBZ pages; continuous-scroll archives might eventually want fractional progress (EPUB already has locators as a pattern to copy).

## 4. Integration options

**Option A — "Organize what you saved" (low risk, high value).**
Import loose image folders as webcomics. Flow: user drops a folder → SCO detects it's an image sequence (no cbz/cbr/pdf inside, many jpg/png/webp/gif) → offers "Import as webcomic" → sorts images naturally, optionally splits by subfolder into chapters → **bundles each unit into a CBZ with a generated ComicInfo.xml** (Series, Number, Web, Format=Webcomic) → normal library pipeline takes over. Everything downstream (reader, folders, relocation) already works on CBZ. This also matches what dosage/webcomix/gallery-dl users already have on disk.

- Design choice inside A: bundle-to-CBZ vs. a new "folder-of-images reader" (`ComicReaderProtocol` conformer). CBZ bundling is less code, keeps one canonical file per book, and survives the existing move/rename logic; a folder reader avoids duplicating the user's files. CBZ bundling looks like the better default, with "leave originals in place" as an option.
- Granularity choice: one CBZ per chapter (Paranatural-style) vs. one CBZ per year (daily strips like xkcd/SMBC — a 2,900-page CBZ is unwieldy) vs. one per episode (Webtoon rips). Probably user-picked at import with a smart default based on folder structure and image count.

**Option B — Webcomic-aware metadata & sorting (pairs with A).**
Add `BookFormat.webcomic`; extend the parser with webcomic patterns (ISO dates, `chNN`/`pNN`, `Episode NNN`, bare zero-padded sequences); add a publish-date-ish sort key (a `sortDate` or reuse of year+new month/day fields) so date-keyed strips order correctly; let `SeriesKnowledge` learn "this series is a webcomic, vertical scroll, episode-ordered." ComicInfo.xml can't carry a day-of-month (only Year/Month — a [known limitation](https://anansi-project.github.io/docs/comicinfo/documentation) of the Anansi-governed spec), so full dates would live in SCO's own DB or in the `Notes`/`Web` fields. For comparison, Komga and Kavita both handle webtoons purely as a *reading mode* (auto-detected by page aspect ratio) and punt on webcomic-specific metadata — SCO doing episode/date-aware organization would be a real differentiator.

**Option C — RSS "new strip" tracking (medium risk, nice-to-have).**
Subscribe to a comic's RSS feed; when a new strip appears, either notify/link out (zero legal risk — this is the Piperka/Comic Rocket model) or fetch the image into the series' CBZ (small risk, but RSS is published for consumption; keep it opt-in and rate-limited). Gives SCO an "ongoing series" concept print comics don't need: update cadence, unread-new-strip badges.

**Option D — Built-in site scrapers (high risk, defer).**
Per-site adapters (xkcd JSON API is the only clean one) or embedding/community-syncing dosage-style rules. High maintenance (sites break constantly), ToS exposure (Webtoon/Tapas categorically off-limits), App Review risk. If ever done: a narrow allow-list of permissive sites (xkcd first — clean API, CC-licensed), or simply document/integrate with external tools ("point dosage at a folder, SCO watches it").

## 5. Suggested phasing

1. **Phase 1 (A + B):** image-folder import → CBZ bundling with generated ComicInfo.xml, `webcomic` book format, webcomic filename patterns, episode/date sorting, per-series vertical-scroll default. No networking. Ships value to anyone with an existing archive.
2. **Phase 2 (C-lite):** RSS subscription per series with notify/link-out; optional image fetch behind a preference.
3. **Phase 3 (C-full / D-narrow):** auto-append new strips to the series CBZ; xkcd API adapter as the proof case. Reassess App Review/legal posture then.

Open questions worth deciding before Phase 1: CBZ bundling vs. folder reader; chapter/year/episode granularity defaults; whether `webcomic` is a `BookFormat` case or an orthogonal flag (a Webtoon rip is arguably both a webcomic *and* volume-like); whether Series should become a first-class entity (webcomics push in that direction: status, cadence, source URL, reading style all belong on the series, not the file).

## Sources

- [xkcd JSON interface](https://xkcd.com/json.html)
- [dosage — comic strip downloader](https://github.com/webcomics/dosage) / [dosage.rocks](https://dosage.rocks/)
- [webcomix — webcomic downloader with CBZ output](https://github.com/J-CPelletier/webcomix)
- [gallery-dl supported sites](https://gallery-dl.com/gallery-dl-supported-sites-list/) / [Tapas-Comic-Downloader](https://github.com/TilCreator/Tapas-Comic-Downloader)
- [Piperka — webcomic tracking](https://piperka.net/about.html) / [Comic Rocket help](https://www.comic-rocket.com/help/)
- [WEBTOON Terms of Use](https://www.webtoons.com/en/terms)
- [ComicInfo.xml documentation — The Anansi Project](https://anansi-project.github.io/docs/comicinfo/documentation)
- [Kavita comic/manga reader (webtoon mode)](https://wiki.kavitareader.com/guides/readers/comic-manga/) / [Komga](https://komga.org/)
- [Is web scraping legal? — Decodo](https://decodo.com/blog/is-web-scraping-legal)
