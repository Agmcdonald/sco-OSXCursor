# Metron Metadata Integration — Design

**Date:** 2026-09-12
**Status:** Approved for planning

Add [Metron](https://metron.cloud) (Metron Comic Book Database) as a second
metadata provider for comics, alongside ComicVine. The user picks one
preferred comic source in Settings; every existing fetch entry point routes
to it. A Metron fetch fills everything the ComicVine fetch fills today,
plus characters, teams, and store date. Cover-image download stays out of
scope (explicitly deferred, same as ComicVine).

## Why Metron

- Curated, community-run comic database with a clean REST API
  (`https://metron.cloud/api/`), free account.
- Issue records carry credits with roles, story arcs, characters, teams,
  cover date, store date, description — richer than ComicVine's issue
  payload, in a single detail call.
- Cross-reference IDs (`cv_id`, `gcd_id`) on series and issues leave the
  door open for future ComicVine ↔ Metron interop.

## API facts (from Mokkari, the reference Python client)

- **Base URL:** `https://metron.cloud/api/<resource>/`
- **Auth:** HTTP Basic (username + password of the user's free Metron
  account). Sent on every request.
- **Rate limits:** 20 requests/minute (burst) and 5,000 requests/day
  (sustained; higher for OpenCollective donors). HTTP 429 + `Retry-After`
  when exceeded. `X-RateLimit-Burst-*` / `X-RateLimit-Sustained-*`
  response headers report remaining budget.
- **Endpoints used:**
  - `series/?name=<q>` — series search. Result rows: `id`, `series`
    (display name), `year_began`, `year_end`, `volume`, `issue_count`,
    `publisher`, `series_type`, `cv_id`, `gcd_id`.
  - `issue/?series=<id>&number=<n>` — issue list filtered by series +
    number. Rows: `id`, `number`, `issue` (name), `cover_date`,
    `store_date`, `image`.
  - `issue/<id>/` — issue detail: `title` (collection title), `name`
    (story titles, list), `cover_date`, `store_date`, `desc`, `rating`,
    `credits` (list of `{creator, role: [{name}]}`), `arcs`,
    `characters`, `teams`, `publisher`, `series`, `cv_id`, `gcd_id`.
- **User-Agent:** send a custom agent
  (`SuperComicOrganizer/1.0 (personal library app)`), matching the
  ComicVine convention.
- Pagination is DRF-style (`count`, `next`, `results`); we only ever read
  the first page.

## Architecture: mirror file + routing switch

Approach chosen over a provider-protocol refactor: ComicVine's plumbing is
proven and stays untouched; Metron is additive, in the app's
one-file-per-service style.

New file `SCO-OSXCursor/Services/Metadata/Metron.swift` containing, in the
same order as `ComicVine.swift`:

1. `MetronConfig` — UserDefaults-backed `username` / `password`
   (`metronUsername`, `metronPassword`), `hasCredentials`, and a computed
   `Authorization: Basic …` header value.
2. `MetronQuota` — `@MainActor ObservableObject`, rolling **24-hour** call
   counter persisted to UserDefaults (`metronCallTimestamps`), daily limit
   constant 5,000. Same shape as `ComicVineQuota` (which is hourly).
3. `MetronThrottle` — actor, minimum 3.1s between requests (< 20/min).
4. DTOs — `MTSeriesResult`, `MTIssueResult`, `MTIssueDetail`,
   `MTCredit`, plus a generic `MTPage<T>` for the DRF envelope.
5. `MetronService` — URLSession client. Basic-auth header, custom
   User-Agent, throttle + quota recording before each call, HTTP 429 →
   friendly "rate limited, retry after …" error using `Retry-After`.
   Methods: `searchSeries(_:)`, `issues(seriesID:issueNumber:)`,
   `issuesForSeries(seriesID:)` (local-match fallback), `issueDetail(id:)`,
   `series(id:)`, `seriesID(forIssueID:)`.
6. `MetronFetcher.fill(_:from:)` — pure fill function, mirroring
   `ComicVineFetcher.fill`.
7. `MTLinkParser` — parses pasted metron.cloud series/issue URLs
   (`metron.cloud/series/<slug-or-id>/`, `/issue/<id>/`) and bare numeric
   IDs (treated as a series ID). Slug-only URLs without a numeric ID are
   rejected with a clear message.
8. `LibraryViewModel` extension — `fetchMetronMetadata(for:force:…)`,
   `applyMetronCandidate`, `applyMetronLink`, reusing the shared outcome
   enum (below).

### Scoring reuse

`ComicVineMatcher.score` needs only name, start year, publisher, and issue
count — all present on Metron series rows. Metron results are adapted into
that scoring path (rename the helper's inputs if needed rather than
duplicating the math). Confidence thresholds and candidate-count (top 5)
are identical.

### Shared candidate storage with a provider tag

`CVCandidate` gains `var provider: String?` — `nil` or `"ComicVine"` means
ComicVine (so every previously stored candidate JSON still decodes and
behaves identically), `"Metron"` means the candidate's `id` is a Metron
series ID. The match picker and batch review sheets apply a candidate via
the service named by its tag. The fetch outcome enum
(`ComicVineFetchOutcome`) is reused as-is for Metron fetches (rename not
required; it's internal).

## Data model & migration

Migration `v32_metron_metadata` adds to `comics`:

| Column | Type | Model property |
|---|---|---|
| `characters` | TEXT (JSON array) | `characters: [String]` |
| `teams` | TEXT (JSON array) | `teams: [String]` |
| `store_date` | DATETIME | `storeDate: Date?` |
| `metron_series_id` | INTEGER | `metronSeriesID: Int?` |
| `metron_issue_id` | INTEGER | `metronIssueID: Int?` |

- `characters` / `teams` default to `[]`, stored exactly like `story_arcs`.
- `CVMetadataSnapshot` (undo) gains all five as optionals so pre-v32
  snapshots still decode; `restore` writes them back.
- `metadataSource` value for Metron fetches: `"Metron"`.

## Fetch flow (identical shape to ComicVine)

1. Guard credentials; guard `metadataFetchedAt` unless forced; pending
   candidates → `.needsChoice`.
2. Search series by `comic.series ?? title ?? filename`.
3. Score, auto-apply when confident (same 0.75 / 0.2-gap rule), honoring
   the existing `autoApplyConfidentMatches` setting; otherwise store top 5
   tagged candidates.
4. Apply series: series name canonical; publisher/year fill blanks only;
   set `metronSeriesID`.
5. If issue number known: filtered issue lookup, fallback to listing the
   series' issues and matching the normalized number locally. From the
   issue detail: title (first story title, or collection title), summary
   (`desc`), cover-date year (blank-fill), `storeDate`, credits by role
   (writer, penciller/artist, cover, colorist, inker, editor — Metron
   roles are structured, matched case-insensitively), and
   **replace-but-never-wipe** semantics for `storyArcs`, `characters`,
   `teams` (Metron authoritative when non-empty, existing values kept when
   the response is empty).
6. Snapshot before apply (`metadataBackup`), set
   `metadataSource = "Metron"`, `metadataFetchedAt`, clear candidates.
7. Batch fetch and Organize staging reuse the same routine per book, same
   summary strings.

A book fetched from one provider may be force re-fetched from the other;
the snapshot/undo path is provider-agnostic. The other provider's IDs are
left in place (they're cross-references, not conflicts).

## Routing

New setting `comicMetadataProvider` (UserDefaults string: `"ComicVine"` |
`"Metron"`, default `"ComicVine"`). Read at every comic fetch entry point:

- ComicDetailView fetch button + link override + match picker
- Library context menu fetch, selection-bar batch fetch, batch review
- Organize staging fetch (single + checked batch)

Ebook routing (Open Library / Google Books / Hardcover) is untouched.
Buttons and messages name the active provider ("Fetch from Metron").
Missing credentials for the active provider → same disabled-button +
"add credentials in Settings" hint pattern as ComicVine today.

## Settings UI

- **"Comic Metadata Source" picker** (segmented, ComicVine | Metron) above
  the two provider sections, with one line explaining what it routes.
- **"Metron Metadata" section:** username field, password field
  (SecureField), sign-up link to `https://metron.cloud`, saved-state line,
  daily usage readout (`n / 5,000` + progress bar + reset note), and a
  "limited to 20 requests/minute" caption.
- ComicVine section unchanged.

Credentials live in UserDefaults via `@AppStorage`, consistent with the
ComicVine key and Hardcover token (accepted trade-off in this app).

## UI for new fields

- **ComicDetailView:** read-only "Characters" and "Teams" rows in the
  Story Arcs style (chips/text + caption noting the source), shown when
  non-empty.
- **Search:** characters and teams join tags + story arcs in the library
  search index (same mechanism `storyArcs` uses today).
- **ComicInspectorView:** store date line when present; provider name
  already displays via `metadataSource`.
- **Dashboard:** the existing API card shows the active provider's quota
  (ComicVine hourly, or Metron daily when Metron is selected).

## Error handling

- No credentials → `.noKey` outcome (same UX copy pattern).
- HTTP 401 → "Metron sign-in failed — check username/password in
  Settings."
- HTTP 429 → surfaced with retry-after time; batch fetch stops early and
  reports how many completed.
- Network/decoding errors → `.failed(message)`, logged to
  `AppLog.metadata` with a `[Metron]` prefix.

## Testing

New `SCO-OSXCursorTests/MetronMatchTests.swift`:

- DTO decoding from canned JSON fixtures (series page, issue list, issue
  detail with credits/arcs/characters/teams).
- `MTLinkParser` cases: series URL, issue URL, bare ID, garbage.
- `MetronFetcher.fill` behavior: blank-fill vs. canonical series,
  replace-never-wipe for arcs/characters/teams, store date set, snapshot
  round-trip with the new fields.
- Credit role mapping (writer/penciller/cover/colorist/inker/editor).

Manual live-API checklist (docs, mirroring the ComicVine one): credentials
save, single fetch, ambiguous fetch → picker, batch fetch, 429 behavior,
provider switch round-trip, undo.

## Out of scope

- Cover image download (`image` URL is decoded but unused) — explicit
  user decision.
- Chaining/fallback between providers.
- Locations (Metron doesn't expose them), variants, reprints, pricing.
- Keychain storage for credentials.
