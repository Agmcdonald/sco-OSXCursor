# Research: Amazon as an ebook/comic metadata source (June 2026)

Backlog item from June 12: "tap into Amazon's API for books to pull ebook
and comic information." Short answer: **not viable for this app** — Amazon
gates catalog access behind an active affiliate-sales requirement. Better
options below.

## Amazon: state of play

- **PA-API 5.0 (the old product API) is dead.** Deprecated April 30, 2026,
  endpoint retired May 15, 2026; it stopped accepting new customers before
  that. ([docs](https://webservices.amazon.com/paapi5/documentation/),
  [auth-layer writeup](https://dev.to/th3nate/amazon-pa-api-v5-is-shutting-down-april-30-2026-here-is-what-changes-at-the-auth-layer-22ek))
- **Its replacement is the Creators API** — REST access to the Amazon
  catalog (search, ASIN lookup, pricing, images, reviews).
  ([overview](https://affiliate-program.amazon.com/creatorsapi),
  [docs](https://affiliate-program.amazon.com/creatorsapi/docs/))
- **Eligibility is the blocker**: requires an approved Amazon Associates
  (affiliate) account that has generated **10+ qualified sales in the past
  30 days — continuously**. Drop below the threshold and API access is
  suspended until sales recover.
  ([requirements](https://www.keywordrush.com/blog/amazon-creator-api-what-changed-and-how-to-switch/),
  [10-sales rule](https://www.keywordrush.com/blog/amazon-pa-api-associatenoteligible-error-is-there-a-new-10-sales-rule/))
- A personal library app drives no affiliate sales, so access would never
  activate (or would immediately suspend). There is **no public Kindle
  metadata API** outside this program, and scraping Amazon pages violates
  their conditions of use.

**Verdict: drop Amazon as a metadata source.** Revisit only if the app ever
has an affiliate storefront angle, which is a product direction question,
not a technical one.

## Alternatives that fit (no affiliate requirements)

| Source | Coverage | Cost / limits | Fit |
|---|---|---|---|
| **Google Books API** | Huge ebook/print catalog; ISBN, title/author search; covers, descriptions, page counts, categories | Free; ~1,000 req/day without billing, no user auth for public data | Best general ebook/novel source — strong for the EPUB side |
| **Open Library (Internet Archive)** | Large book catalog; ISBN/title lookup; covers API | Free, open data, no key | Good fallback + bulk-friendly; data quality varies |
| **ComicVine API** | The comics database: series, issues, volumes, publishers, creators, covers | Free key; non-commercial terms; ~200 req/resource/hr | Best comics source — maps directly onto the existing publisher/series/issue model and Stage 3 knowledge base |
| **ISBNdb** | Commercial ISBN database | Paid (~$15+/mo) | Only if Google/OpenLibrary coverage proves insufficient |

(Goodreads retired its public API in 2020 — not an option.)

## Recommended direction

Two-tier metadata fetch matching the app's two content types:

1. **Comics (.cbz/.cbr/PDF)** → ComicVine: search `series + issue + year`
   from the existing parser output; high-confidence matches feed the same
   fields ComicInfo.xml does today, and results can seed
   `series_knowledge` (Stage 3) so each lookup improves offline matching.
2. **eBooks (.epub)** → Google Books primary (ISBN from EPUB OPF metadata
   when present, else title/author), Open Library fallback.

Both are simple REST + JSON with API-key auth (ComicVine) or none
(Open Library), so they slot into a small `MetadataFetchService` with
per-source rate limiting. No accounts, no sales thresholds, no scraping.
