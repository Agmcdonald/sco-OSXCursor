# Metron Metadata Integration (September 13, 2026)

Adds [metron.cloud](https://metron.cloud) as a **second comic metadata
provider** alongside ComicVine. Metron supplies publisher, creators, summary,
story arcs, **characters**, **teams**, and the **in-store (shipping) date** —
the last three are new fields the ComicVine path never filled. Built this
session against the live API's documented shape; **not yet exercised against a
real account** — see the manual checklist at the bottom.

Book (EPUB) lookups are untouched: they still route to Open Library / Google
Books / Hardcover. This setting only decides where *comic* fetches go.

## How it works

1. **Sign-in** (Settings → Metron Metadata). A free metron.cloud account;
   HTTP Basic auth with username + password, stored in UserDefaults
   (`metronUsername` / `metronPassword`). No credentials → Metron fetching is
   disabled everywhere, and the fetch buttons say so.
2. **Provider picker** (Settings → Comic Metadata Source, a segmented
   ComicVine / Metron control backed by `comicMetadataProvider`). `ComicSource`
   defaults to **ComicVine** when unset, so existing installs behave exactly as
   before. Selecting Metron without a sign-in shows an inline warning.
   Everything comic-side reads this one setting: the Edit Metadata sheet,
   right-click "Fetch from …", the selection-bar batch fetch, Dashboard →
   Health "Fetch All from …", and the Organize tab. **Exception:** the Edit
   Metadata sheet also offers a secondary "Fetch from \<other\> instead"
   button whenever the *inactive* provider has credentials, so either source
   can be tried on a single book without changing the Settings picker.
   `runFetch(force:via:)` dispatches straight to `fetchComicVineMetadata` /
   `fetchMetronMetadata`; candidates stay provider-tagged, so a `needsChoice`
   picker still applies through the service that produced them.
3. **Fetch.** `LibraryViewModel.fetchComicMetadata(for:force:)` is the single
   dispatcher — it switches on `ComicSource.current` and calls either
   `fetchComicVineMetadata` or `fetchMetronMetadata`. The Metron flow:
   search `series/?name=<query>` → project each row to `MTSeriesRef` → score
   against the book's year/publisher with the **shared ComicVine scoring core**
   (`ComicVineMatcher.score`, so both providers rank identically) → if one row
   is clearly best (single result, or score ≥ 0.75 **and** ≥ 0.2 ahead of the
   runner-up) apply it; otherwise store the top 5 candidates and show the
   match picker.
4. **Apply.** `MetronFetcher.fill` writes series-level fields, then — when the
   issue number is known — calls `issue/?series_id=<id>&number=<n>` and
   `issue/<id>/` for credits, arcs, characters, teams, and dates. **1–3 API
   calls** per book (search + issue list + issue detail), plus one extra when
   the fallback lookup runs. `applySeries` / `applyIssue` are pure functions
   (no network, no persistence) so they're unit-tested directly.
5. **Never re-fetched automatically.** Same rule as ComicVine: once
   `metadataFetchedAt` is set the book is skipped unless you press
   "Re-fetch from Metron". A book with stored candidates returns `needsChoice`
   rather than burning another search call.
6. **Undo.** Every applied fetch first captures a `CVMetadataSnapshot` into
   `metadataBackup`, now including `characters`, `teams`, `storeDate`,
   `metronSeriesID`, and `metronIssueID` (all optional, so pre-v32 snapshots
   still decode). Revert restores the Metron values too. `metadataSource` is
   set to `"Metron"` on apply.
7. **Issue-lookup fallback.** If the number-filtered issue call returns empty,
   the flow lists the series' issues and matches the normalized number locally
   — mirroring the ComicVine path. An `AppLog.metadata` line records whether
   the issue matched and which creators filled.

## New fields & where they surface

- `characters: [String]`, `teams: [String]`, `storeDate: Date?`,
  `metronSeriesID: Int?`, `metronIssueID: Int?` on `Comic`
  (migration `v32_metron_metadata`).
- **Edit sheet** — read-only Characters and Teams sections (only shown when
  non-empty), each with a hint that you can search the library by that name.
- **Inspector** — an "In Stores" row when `storeDate` is set.
- **Search** — `comicMatchesSearch` matches characters and teams alongside
  tags and story arcs, so "Lois Lane" or "Justice League" finds books.

### Dates are UTC calendar days

Metron sends plain `yyyy-MM-dd` strings. `MetronDates.parse` reads them with a
**UTC** formatter, so a store date is stored as that calendar day at UTC
midnight. Display therefore also has to be UTC-pinned: `MetronDates.display`
uses a medium-style formatter with the user's locale but `TimeZone(UTC)`.
Formatting those dates with the local time zone slides them a day earlier for
anyone west of UTC — that's why the inspector calls `MetronDates.display`
rather than `.formatted()`.

## Rate limiting & the dashboard counter

- Metron: **20 requests/minute** and **5,000 requests/day** (more for donors).
  We self-throttle to **~1 request / 3.1s** (`MetronThrottle` actor) and count
  every call against a rolling 24-hour budget.
- `MetronQuota` (a `@MainActor ObservableObject`) keeps the call timestamps in
  UserDefaults (`metronCallTimestamps`), so the readout survives relaunches.
  A rolling window is conservative versus the server's fixed daily reset.
- Shown in **Settings** (calls / 5,000, progress bar, when budget returns) and
  on **Dashboard → Overview**. The dashboard card is **provider-aware and
  reactive**: it reads the setting through `@AppStorage`, so switching the
  provider in Settings flips the card live between "ComicVine API"
  (calls this hour / 200) and "Metron API" (calls in the last 24 hours /
  5,000) without a relaunch.
- **HTTP 429 handling.** The client throws `MTError.rateLimited(retryAfter:)`,
  parsed from the `Retry-After` header when present. That maps to the typed
  `ComicVineFetchOutcome.rateLimited`, and the UI shows
  "Rate limit reached — try again after <time>."
- **Batch fetch stops early on 429.** `fetchComicMetadataBatch` routes to the
  Metron loop when Metron is active; on a `rateLimited` outcome it logs
  `[Metron] Rate limited — stopping batch with N books unattempted`, **counts
  every unattempted book as `failed`** in the summary line, reports progress as
  complete, and returns. That keeps the queue from hammering a closed door; the
  cost is that the summary says "N failed" for books that were never tried.
  (The ComicVine batch has no early exit — it counts a 429 as one failure and
  keeps going.)
- **Link overrides pass rate-limiting through.** `applyMetronLink` inspects a
  thrown error and re-emits `.rateLimited(retryAfter:)` instead of flattening
  it into `.failed`, so the picker shows the "try again after …" message rather
  than a raw error string.

## Fill semantics

Deliberately conservative — a fetch should never destroy something you typed.

- **Series name is canonical.** A non-empty Metron series name always
  overwrites `series` (this is the one exception, same as ComicVine).
- **Scalars blank-fill only.** `publisher`, `year`, `title`, `summary`,
  `storeDate`, and the creator fields are written only when the existing value
  is nil/empty. Credits go through the shared
  `ComicVineMatcher.applyCredits`, with Metron's structured
  `{creator, role[]}` credits flattened to one `CVPersonCredit` per
  creator-role pair so the same role-name matcher handles both providers.
- **`storyArcs` / `characters` / `teams` replace but never wipe.** When Metron
  returns a non-empty list it becomes the value (Metron is authoritative for
  these); when it returns nothing, the existing list is left alone.
- **Titles.** `title` prefers the first non-empty per-issue story title
  (JSON `name`), falling back to the collection/TPB title (JSON `title`).
- **Covers are never downloaded.** `MTIssueDetail.image` is decoded but
  unused — out of scope by design, same as the ComicVine path.

## Candidate provider tagging

Stored candidates are shared between providers, so they carry their origin:
`CVCandidate.provider` is `"Metron"` for Metron series IDs and **nil or
`"ComicVine"`** for ComicVine volume IDs (nil = legacy rows written before this
change, which decode fine). `candidate.isMetron` is the test.

Everything that consumes a candidate **dispatches on the tag, not on the
current setting**:

- `applyMetadataCandidate(_:to:)` sends Metron-tagged candidates to
  `applyMetronSeries` and the rest to `applyComicVineCandidate`.
- `OrganizeViewModel.applyStagingCandidate(_:to:)` does the same for staged
  files.
- The match picker and the batch-review sheet label each row
  "Metron series #123" or "ComicVine volume #456".
- The picker's paste field (`applyProviderLink`) asks the *pending candidates*
  which provider they belong to, falling back to the active setting only when
  there are none.

So candidates stored under one provider still resolve correctly after you
switch the setting — a Metron candidate never gets looked up as a ComicVine
volume ID.

## Link / ID override (numeric IDs only)

`MTLinkParser.parse` accepts:

- a bare number → tried as a **series** ID first; if `series/<id>/` answers
  404 the same number is retried as an **issue** ID (`issue/<id>/` → parent
  series → `series/<id>/`), since users paste both kinds. Only when both come
  back 404 does the paste fail, with "No Metron series or issue found with ID
  \<n\>." Typed 429/401 outcomes still pass through untouched, so a
  rate-limited paste never gets downgraded to "not found";
- `…/series/<digits>` or `…/issue/<digits>` — the API-style URLs, e.g.
  `https://metron.cloud/api/series/2658/`. An issue reference costs one extra
  call (`issue/<id>/`) to resolve its parent series.

The regex is `(series|issue)/(\d+)(?=/|$|[?#])` — the lookahead **requires a
path/query/fragment boundary (or end of input) after the digits**. That is the
whole point: Metron's public site uses slug URLs, and some slugs start with
digits (`metron.cloud/series/2000-ad-1977/`, `metron.cloud/issue/52-2006-1/`).
Without the terminator those would parse as series 2000 / issue 52 and silently
match the wrong book. With it, **every slug URL is rejected** — including
digit-leading ones — and only numeric API-style links and bare IDs work.

A rejected paste returns a `failed` outcome with the explanatory text:
"Paste a numeric Metron ID or an api/series/\<id\> link — Metron's site URLs
(slugs) don't carry the ID."

## Key requirements honored (from API research)

- **HTTP Basic auth** built from the stored username/password
  (`Basic base64(user:pass)`) on every request.
- **Custom User-Agent** — `SuperComicOrganizer/1.0 (personal library app)`.
- **DRF pagination** (`{count, next, results}`) — the client reads page 1 only.
- **401/403 → a sign-in error** ("check username/password in Settings") rather
  than a generic HTTP failure; 429 → the typed rate-limited case.
- **Filter parameter names are exact.** Metron's `IssueFilter` declares
  `series_id = NumberFilter(field_name="series__id")`, and django-filter
  **silently ignores** params it does not know. Sending `series=<id>` therefore
  returned page 1 of *every* issue with that number across the whole database,
  and the fill applied a stranger's title/credits/summary even when the user
  had picked the right series. `MetronService.issueQuery(seriesID:issueNumber:)`
  is a pure static helper pinned by unit tests so the name can't drift again;
  issue list rows also decode their nested `series.name` as a second layer of
  defense.
- **Key-name quirks handled**: the series *list* row carries the display name
  under the JSON key `series`, while the series *detail* uses `name`; the issue
  detail's `title` is the collection/TPB title while `name` is an array of
  story titles. `MTSeriesRef` is the common projection both paths produce.

## Files

- `Services/Metadata/Metron.swift` — the whole integration: `ComicSource`
  setting, `MetronConfig`, `MetronQuota`, `MetronThrottle`, DTOs,
  `MetronDates`, `MetronService` client, `MTLinkParser`, `MetronMatcher`,
  `MetronFetcher`, and the `LibraryViewModel` fetch/dispatch extension.
  (One file, matching the app's service style and `ComicVine.swift`'s shape.)
- `Services/Metadata/ComicVine.swift` — `CVCandidate.provider`/`isMetron`,
  Metron fields on `CVMetadataSnapshot`, provider-aware picker copy and link
  routing, provider-aware batch summary text.
- `Models/Comic.swift` — `characters`, `teams`, `storeDate`,
  `metronSeriesID`, `metronIssueID` (+ encode/decode/init).
- `Services/Database/DatabaseManager.swift` — migration `v32_metron_metadata`.
- `ViewModels/OrganizeViewModel.swift` — `fetchMetronStaging`,
  `applyMetronCandidate`, `applyStagingCandidate`, provider-routed staging
  fetch and batch summary.
- `Views/Settings/SettingsView.swift` — Comic Metadata Source picker, Metron
  sign-in fields, daily quota readout.
- `Views/Dashboard/DashboardOverviewView.swift` — provider-aware quota card
  (reactive via `@AppStorage`).
- `Views/Dashboard/DashboardHealthView.swift`,
  `Views/Library/LibraryView.swift`, `Views/Library/ComicCellModifiers.swift`,
  `Views/Organize/OrganizeView.swift`,
  `Views/Organize/OrganizeInspectorView.swift` — provider-named buttons/help
  text, routed through the dispatcher.
- `Views/Library/ComicDetailView.swift` — provider-named fetch button,
  read-only Characters and Teams sections.
- `Views/Library/ComicInspectorView.swift` — "In Stores" row
  (`MetronDates.display`).
- `Views/Library/LibraryModels.swift` — search predicate matches characters
  and teams.
- `SCO-OSXCursorTests/MetronMatchTests.swift` — model/snapshot round-trips,
  DTO decoding, link-parser cases (including the digit-leading slug
  rejections), UTC date handling, scoring, and the pure fill functions.

## Manual test checklist (needs a real metron.cloud account)

1. Settings → Metron: enter username/password → "Sign-in saved".
2. Settings → Comic Metadata Source → Metron.
3. Edit a well-known issue (e.g. "Superman #6 2016") → button reads
   "Fetch from Metron" → fetch → publisher/creators/summary/characters/
   teams/store date fill; Settings + Dashboard counters increment.
4. Ambiguous series (e.g. "Superman", no year) → match picker lists
   Metron candidates → pick one → fields fill.
5. Re-open the book → "Re-fetch from Metron"; plain fetch skipped.
6. Batch: select several → Fetch Metadata → summary line; ambiguous books
   route to Review Matches; picker applies via Metron.
7. Organize tab: stage a comic file → Fetch from Metron fills staged fields.
8. Paste-link override: a numeric API link works; a slug URL shows the
   explanatory error.
9. Switch source back to ComicVine → force re-fetch the same book →
   metadataSource flips to ComicVine; Revert restores the Metron values
   (characters/teams/storeDate included).
10. Wrong password → fetch reports the sign-in error.
11. Fire >20 fetch calls rapidly (batch) → no 429 (3.1s spacing holds).

## Known follow-ups (not built)

- **Book transfers drop the new fields.** `TransferManifest` has no
  `characters`, `teams`, `storeDate`, `metronSeriesID`, or `metronIssueID`, so
  a `.scobook` round-trip loses them. (`storyArcs` and the ComicVine IDs do
  survive.) Needs a manifest format bump.
- **Organize 429 shows as a plain failure.** `StagingCVOutcome` has no
  `.rateLimited` case, so a rate-limited staging fetch falls into `.failed` —
  the message text is still correct (it comes from `MTError`), but the Organize
  UI can't offer the "try again after …" treatment the library path does.
- **Metron's fallback issue lookup reads only the first DRF page.** If a
  filtered `issue/?series_id=…&number=…` call comes back empty and the issue sits
  past page 1 of the series' issue list, the local number match won't find it.
- **The throttle actor is advisory under concurrency.** `MetronThrottle.wait()`
  serializes callers correctly today only because fetches are issued
  sequentially; truly parallel fetches could interleave between the `wait` and
  the request and briefly exceed 20/min.
- **Cross-provider force re-fetch leaves stale Metron-only fields.** Correcting a
  wrong Metron match by force re-fetching the same book through ComicVine
  rewrites the shared fields but never touches the Metron-only ones
  (`characters`, `teams`, `storeDate`), so those stay on the record from the bad
  match. Revert (metadata backup) or a corrected Metron fetch clears them.
