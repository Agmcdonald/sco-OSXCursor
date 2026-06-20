# ComicVine Metadata Integration (June 12, 2026)

Pulls publisher, creators, summary, and cover dates for comics from the
[ComicVine API](https://comicvine.gamespot.com/api/). Built this session;
**not yet device-tested** — needs a build + an API key to exercise.

## How it works

1. **API key** (Settings → ComicVine Metadata). Free, from a ComicVine/Fandom
   account at comicvine.gamespot.com/api. Stored in UserDefaults
   (`comicVineAPIKey`). No key → fetching is disabled everywhere.
2. **Fetch** from a book's Edit Metadata sheet → "Fetch from ComicVine".
   Flow: search volumes by series name → score candidates against the book's
   year/publisher → if one is clearly best, apply it; otherwise store the top
   5 candidates and show the **match picker** so you choose.
3. **Apply**: series/publisher/year fill from the volume; if the issue number
   is known, two more calls fetch the issue (title, summary, cover date) and
   its creators (writer/penciller/inker/colorist/cover/editor). Existing
   non-empty fields are never overwritten — ComicVine only fills blanks
   (series name is the one canonical exception).
4. **Never re-fetched automatically.** Once `metadataFetchedAt` is set, the
   book is skipped unless you explicitly "Re-fetch" — required by ComicVine's
   caching terms and protects the hourly budget. Ambiguous candidates are
   stored on the record, so resolving later costs no extra search call.
5. **Disambiguation.** `ComicVineMatchPicker` lists candidates (name • year •
   publisher • issue count). Pick one, or "None of These" to clear them.

## Rate limiting & the dashboard counter

- ComicVine: **200 requests/resource/hour** + velocity detection (HTTP 403 on
  bursts). We self-throttle to **~1 request/second** (`CVThrottle` actor) and
  count every call against a single 200/hr budget (conservative).
- `ComicVineQuota` (a `@MainActor ObservableObject`) keeps a rolling-hour list
  of call timestamps in UserDefaults, so the count survives relaunches.
- Shown on **Dashboard → Overview** ("ComicVine API" card) and in **Settings**:
  calls-this-hour / 200, a progress bar, and when budget starts replenishing
  (oldest in-window call + 1h).

## Key requirements honored (from API research)

- **Custom User-Agent** — ComicVine 403s default/empty agents. We send
  `SuperComicOrganizer/1.0 (personal library app)`.
- **`format=json` + `field_list`** on every request to shrink payloads.
- **`status_code == 1` checked** in the JSON body even on HTTP 200.
- **Search capped at limit=10**; we request 10 and rank locally.
- **Credits only on the single `/issue/4000-<id>/` endpoint** — the flow does
  the two-step fan-out (issues list → issue detail).
- **Non-commercial + attribution.** Personal-use app is fine; if ComicVine
  data is ever shown verbatim in a shipping UI, add a "Data from ComicVine"
  link back. (Currently it just fills editable metadata fields.)

## Files

- `Services/Metadata/ComicVine.swift` — config, quota tracker, throttle, DTOs,
  API client, the `LibraryViewModel` fetch extension, matcher/scoring, and the
  match picker sheet. (One file, matching the app's service style.)
- `Models/Comic.swift` — added `comicVineVolumeID`, `comicVineIssueID`,
  `metadataFetchedAt`, `metadataCandidates` (+ encode/decode/init).
- `Services/Database/DatabaseManager.swift` — migration `v16_comicvine_metadata`.
- `Views/Library/ComicDetailView.swift` — fetch button + match-picker sheet.
- `Views/Settings/SettingsView.swift` — API key field + quota readout.
- `Views/Dashboard/DashboardOverviewView.swift` — quota card.

## Test checklist (morning, needs a real key)

1. Settings → paste a ComicVine key → "Key saved".
2. Edit a well-known issue (e.g. "Batman #608 2002") → Fetch → confirm
   publisher/creators/summary fill, dashboard counter increments.
3. Edit an ambiguous book (common series name, no year) → Fetch → match
   picker appears → pick one → fields fill.
4. Re-open the same book → button reads "Re-fetch"; plain fetch is skipped
   (`alreadyFetched`) until you press Re-fetch.
5. With no key set → button disabled, helper text points to Settings.
6. Dashboard → ComicVine card shows count + reset time; Settings mirrors it.
7. Fire several fetches → confirm ~1s spacing (no 403s), counter climbs.

## June 20 fixes & additions

- **Edit-sheet draft refresh (critical bug).** The Edit sheet binds to
  `@State draft*` vars captured when it opened. A fetch updated the stored
  comic but not the drafts, so fetched data was invisible — and pressing Save
  wrote the stale drafts back, **erasing** what ComicVine had just saved.
  `resyncDrafts()` now reloads the drafts from the updated comic after a
  fetch and after a match-pick, so results show and survive Save. This was
  the main reason "blanks weren't filling."
- **No-sheet fetch.** Right-click a comic → "Fetch from ComicVine" fills and
  saves directly (no Edit sheet). Ambiguous → match picker opens. A bottom
  status pill reports the result.
- **Batch fetch.** Select multiple → "Fetch Metadata" in the selection bar.
  Runs them in sequence (throttled), skips already-fetched, and reports a
  summary ("4 updated, 2 need a match choice, 1 no match"). Ambiguous books
  keep their candidates for later resolution via Edit → Choose Match.
- **Issue-lookup fallback.** If the filtered `issues?filter=...,issue_number:N`
  call returns empty (ComicVine sometimes stores the number oddly), we list
  the volume's issues and match the normalized number locally. Plus a log
  line (`AppLog.metadata`) showing whether the issue matched and which
  creators filled — check Console if a book still comes back sparse.

## Known follow-ups (not built yet)

- Cover image download from `image.super_url`/`original_url` (DTOs don't yet
  request `image`; would set `coverImageData`).
- Smarter issue matching (cover-date year tie-breaks among same-number issues).
- Google Books / Open Library for the eBook side.
