# Research: AniList as a manga metadata source (September 2026)

Manga and manhwa are the one category the current metadata stack handles
badly. ComicVine is a Western-comics database — its Japanese coverage is
thin and inconsistently titled. Open Library / Google Books / Hardcover
index the *print editions* (Viz, Yen Press, Kodansha USA), so they find
"Chainsaw Man, Vol. 5" but know nothing about the series itself.

**Verdict: AniList is a good fit and cheap to add.** Free, no API key, no
account, ~500k anime + manga entries curated by a moderation team. It slots
in as a fourth source alongside the book providers, routed by content type
rather than file format. Two caveats worth deciding on before writing code:
the **commercial-revenue clause** and the **absent publisher field** — both
detailed below.

Source: [AniList/docs](https://github.com/AniList/docs) (the repo behind
<https://docs.anilist.co>), read at commit HEAD, September 2026.

---

## API basics

| | |
|---|---|
| Protocol | GraphQL — **`POST` only**, to `https://graphql.anilist.co` |
| Payload | JSON `{ "query": "...", "variables": { ... } }` |
| Auth | **None required for public media data.** OAuth2 is only for user lists and mutations |
| Key | None. Nothing to put in Settings, unlike ComicVine/Hardcover |
| Cost | Free (see Terms below) |
| Explorer | [Apollo Studio sandbox](https://studio.apollographql.com/sandbox/explorer?endpoint=https%3A%2F%2Fgraphql.anilist.co) — the old GraphiQL editor and `anilist.github.io/ApiV2-GraphQL-Docs` are both deprecated |

The docs are explicit that no auth is needed to "get anime and manga data"
or "search characters" — exactly our use case. That makes AniList the only
provider we'd ship where the user has zero setup to do, which is a real UX
win over the ComicVine key and Hardcover token.

### Rate limiting

> "The API is currently in a degraded state and is limited to **30 requests
> per minute**. This is a temporary measure until the API is fully restored."

Nominal limit is 90/min; the degraded 30/min notice has been in the docs
long enough to be treated as the real number. On top of that there is an
unspecified **burst limiter**. Responses carry `X-RateLimit-Limit` and
`X-RateLimit-Remaining`; a 429 adds `Retry-After` (seconds) and
`X-RateLimit-Reset` (Unix timestamp), plus a GraphQL error with
`"status": 429`.

Design implication: a `~2.0s` minimum spacing actor, same shape as
`HCThrottle` / `CVThrottle`, keeps us under 30/min with headroom and also
satisfies the burst limiter. Read `Retry-After` on 429 and back off for
real rather than retrying blind. **AniList also manually IP-bans abusive
callers** — one request per second sustained is not a limit to design up
to.

### Error handling gotchas

Three behaviours that differ from the REST providers we already have:

1. **HTTP 200 can still be an error.** GraphQL puts failures in the
   response's `errors` array with `data: null`. Every response has to be
   checked for `errors` regardless of status code.
2. **404 for a wrong-type ID.** IDs are not unique across `ANIME` and
   `MANGA`; requesting a manga ID while filtering `type: ANIME` returns
   404, not an empty result.
3. **403 when the API is disabled.** AniList temporarily suspends the API
   during severe outages, returning 403 with an explanatory GraphQL
   message. This needs to surface as a "try later" state, not a "no match"
   — the same distinction `OpenLibraryFetchOutcome` already draws between
   deferral and no-match.

### Pagination

Top-level queries (`Media`, `Character`, `Staff`) return a single object.
For lists, wrap in `Page` and lowercase the field (`Page { media(...) }`).
A `Page` may contain **only one data field** plus `pageInfo`. Note:

> "`PageInfo` Degradation — the `total` and `lastPage` fields are not
> currently accurate. You should only rely on `hasNextPage`."

For our use (one page of ~10 search candidates) this is a non-issue.

---

## Terms of Use — two things to decide

Full text: <https://docs.anilist.co/guide/terms-of-use>

**1. Commercial revenue threshold.** Free for non-commercial use, and free
for commercial apps earning **under $150/month in revenue**. Above that a
commercial licence must be negotiated by emailing `contact@anilist.co`.
Super Comic Organizer / Rapture Press is heading for the App Store, so this
is a live question rather than a hypothetical. It is a low bar to clear by
email, but it should be cleared *before* the app is monetised, not after.

**2. The competing-services clause.** Use of the API "within competing,
non-complementary services of the same nature is prohibited… includes, but
is not limited to, anime and manga **list or tracker services**." SCO is a
local file organizer and reader, not a catalogue or social tracker — but it
*does* keep reading lists and per-book progress. My read is that we're
complementary (we organize files the user already owns; we don't replace
AniList's tracking or social layer, and we don't republish their catalogue).
Worth a sentence in the same email as the commercial ask so it's on record.

Also relevant, and easy to comply with:

- **No hoarding / mass collection.** Our existing pattern — fetch once per
  book on demand, cache the result on the `Comic` record, never auto-refetch
  unless the user forces it — is exactly right here. Do **not** add any bulk
  pre-seeding of `series_knowledge` from AniList.
- **Never use the API as data storage or backup.**
- **Naming:** only applies if "AniList" appears in the app's name. Using it
  as an attributed source in the metadata credit line is fine.

### Adult content — App Store risk

The docs call this out directly: entries may contain adult content, and app
stores prohibit it. AniList exposes `isAdult` on `Media` and an `isAdult`
filter argument, so **always query with `isAdult: false`** and additionally
drop any result whose `isAdult` is true. Two known sharp edges:

- Ecchi is **not** classified adult by AniList, and has caused App Store
  problems for other clients.
- Tags carry their own `isAdult` and `isMediaSpoiler` flags — filter both
  before mapping tags into `Comic.tags`, or a spoiler ends up on a cover
  badge.

The docs explicitly disclaim the accuracy of their own filtering and
recommend client-side checks on top. Given the app already has
`ContentRating`, an AniList `isAdult` hit is a reason to skip the match
entirely rather than import and rate it.

---

## Field mapping: `Media` → `Comic`

The `Media` type covers both anime and manga; `type: MANGA` plus
`format_in: [MANGA, ONE_SHOT, NOVEL]` scopes it to what we care about.

| AniList field | → `Comic` | Notes |
|---|---|---|
| `title { english romaji native }` | `series`, `title` | Prefer `english`, fall back to `romaji`. `native` is useful for matching files named in Japanese |
| `synonyms` | (matching only) | Alternative titles — significantly improves fuzzy matching on scanlation filenames |
| `description(asHtml: false)` | `summary` | Markdown-ish with `<br>` tags; run through `ComicVineMatcher.stripHTML` |
| `startDate { year month day }` | `year` | `FuzzyDate` — any component may be null |
| `volumes` | — | **Series total**, not this file's volume. Useful for "Vol. 5 of 12" display, not for `Comic.volume` |
| `chapters` | — | Series total chapter count |
| `staff { edges { role node { name { full native } } } }` | `writer`, `artist` | `role` is a free-text string; manga entries commonly use `"Story & Art"`, `"Story"`, `"Art"`, `"Original Creator"`. Map `Story` → writer, `Art` → artist, `Story & Art` → both |
| `genres` + `tags { name rank isAdult isMediaSpoiler }` | `tags` | Genres are a small controlled vocabulary; tags are ranked 0–100 — take `rank >= 60`, non-adult, non-spoiler |
| `coverImage { extraLarge large }` | `coverImageData` | Only as a fallback — the app already extracts covers from the file itself, which is better |
| `format` | `bookFormat` | `ONE_SHOT` → `.oneShot`; `MANGA` → `.volume`; `NOVEL` (light novel) → `.ebook` |
| `countryOfOrigin` | reader default | ISO 3166-1 alpha-2. **`JP` → `mangaRTL`, `KR`/`CN` → vertical scroll.** Free win: the reading direction can be set correctly on import instead of the user discovering it backwards |
| `status` | — | `FINISHED` / `RELEASING` / `HIATUS` / `CANCELLED` — could drive a "series ongoing" badge |
| `id`, `siteUrl` | new `aniListMediaID` | Same role `comicVineVolumeID` plays: stable handle for re-fetch and for a "View on AniList" link |
| `isAdult` | reject match | See above |
| `idMal` | — | MyAnimeList cross-reference, if a second source is ever wanted |

### The gap: there is no publisher field

`Media` has **no publisher**. `studios` is anime-only (animation studios).
This matters because SCO files books into folders *by publisher* and shows
publisher branding — an AniList-only match leaves `publisher` empty and the
book lands in "Unknown Publisher" with a `needsPublisher` badge.

Options, roughly in order of preference:

1. **Chain the sources.** AniList for series identity, credits, summary,
   tags and reading direction; keep Google Books / Open Library for the
   English publisher (Viz Media, Yen Press, Seven Seas, Kodansha USA) when
   an ISBN is present. The existing `fetchBookSources` fill-only-when-missing
   merge already composes cleanly this way — AniList would just be another
   `consider(...)` contributor plus a publisher pass.
2. **Infer from `externalLinks`** (`site`, `type: INFO`, `language`) — often
   carries official publisher pages. Fuzzy and unreliable; not worth it as a
   primary path.
3. **Leave `publisher` empty** and let the existing `needsPublisher` badge
   invite the user to fill it. Acceptable, but worse than (1).

---

## Query shapes we'd actually use

Search by title (the main path — one request per book):

```graphql
query ($search: String!) {
  Page(perPage: 10) {
    media(search: $search, type: MANGA, isAdult: false, sort: [SEARCH_MATCH]) {
      id
      siteUrl
      title { english romaji native }
      synonyms
      format
      status
      description(asHtml: false)
      startDate { year month day }
      volumes
      chapters
      countryOfOrigin
      isAdult
      genres
      tags { name rank isAdult isMediaSpoiler }
      coverImage { extraLarge large }
      staff(perPage: 10) {
        edges { role node { name { full native } } }
      }
    }
  }
}
```

Re-fetch a known match by stored ID (`Media(id:)` returns a single object,
no `Page` wrapper — 404 if the ID doesn't exist as a manga):

```graphql
query ($id: Int!) {
  Media(id: $id, type: MANGA) { ...sameSelection }
}
```

`sort: [SEARCH_MATCH]` ranks by search relevance; `POPULARITY_DESC` is the
usual tiebreaker when a title is ambiguous. Note the docs' own warning:
titles are not unique, so "get manga by name" doesn't exist — search and
score, exactly as `ComicVineMatcher` already does for volumes.

---

## Integration plan

Everything below mirrors patterns already in the codebase; nothing here
needs new architecture.

1. **`SCO-OSXCursor/Services/Metadata/AniList.swift`** — new file, modelled
   on `Hardcover.swift` (the existing GraphQL client) rather than
   `ComicVine.swift`:
   - `ALThrottle` actor, 2.0s minimum spacing.
   - `AniListService.shared` with `search(title:)` and `media(id:)`.
   - `ALMediaDoc` DTO for the selection above, decoded with `Decodable`
     (AniList returns clean typed JSON — no Typesense-style raw blob to walk
     like Hardcover's `search.results`).
   - `ALError` mirroring `HCError`, with cases for `apiDisabled` (403),
     `rateLimited(retryAfter:)` (429 + `Retry-After`), and `graphQL([String])`
     for the 200-with-errors case.
   - No config enum — there's no key to store.

2. **`Comic.swift` + a GRDB migration** — add `aniListMediaID: Int?`
   alongside `comicVineVolumeID`, and extend the `metadataSource` values
   with `"AniList"`. `ComicInspectorView`'s source line and
   `TransferManifest` need the new field carried through.

3. **Routing.** Today `OrganizeViewModel.fetchMetadata(for:)` splits on
   `bookFormat == .ebook` → book sources, else ComicVine. AniList needs a
   *content*-based signal, not a format one, because manga arrives as both
   CBZ and EPUB. Cheapest reliable signal, in order:
   - an existing `manga`/`manhwa`/`manhua` tag or the RTL reading style
     already set on the book;
   - the library folder / publisher (Viz, Yen Press, Kodansha, Seven Seas…);
   - a filename hint (`vol.`/`v01` with no issue number, Japanese
     characters in the name).

   Simplest first cut that avoids guessing wrong: **try AniList in parallel
   with the existing sources and let the match score decide.** It costs one
   extra request per fetch and needs no classifier. A user-facing "this is
   manga" toggle on the book (or a per-folder default) is the honest
   long-term answer.

4. **Scoring.** Reuse `ComicVineMatcher.nameSimilarity`, scored against
   `title.english`, `title.romaji`, `title.native` **and every entry in
   `synonyms`**, taking the best. Synonyms are where AniList beats the book
   providers on scanlation-style filenames.

5. **Caching / undo.** Reuse the existing contract exactly:
   `metadataFetchedAt` gates auto-refetch, `metadataBackup` enables revert,
   `metadataCandidates` stores an ambiguous result set for the picker sheet
   at zero extra API cost. This also happens to be what AniList's no-hoarding
   rule wants.

6. **Attribution.** Credit AniList in the inspector's source line and link
   `siteUrl` from the detail view, as ComicVine already is.

Rough size: the service file is ~200 lines (Hardcover is 191 and does more
JSON spelunking); routing and mapping are another ~150 across
`OrganizeViewModel` and the library fetch path; plus the migration.

## Open questions

- **Commercial licence** — email `contact@anilist.co` before the app earns
  above $150/month. Include the complementary-use argument in the same note.
- **Manga detection** — auto-classify, or ship a user-set flag? Parallel
  querying sidesteps the decision for v1 at the cost of one request.
- **Publisher** — accept the chained-source approach (AniList + Google Books
  for the English edition), or accept empty publishers on manga?
- **Light novels** — `format: NOVEL` under `type: MANGA` means AniList also
  covers light novels, which currently go to the book providers. Worth
  comparing coverage before deciding whether AniList should win those too.
