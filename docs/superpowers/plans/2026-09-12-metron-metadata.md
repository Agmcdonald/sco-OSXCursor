# Metron Metadata Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add metron.cloud as a user-selectable second metadata provider for comics, filling everything ComicVine fills plus characters, teams, and store date.

**Architecture:** New `Services/Metadata/Metron.swift` mirrors the shape of `ComicVine.swift` (config → quota → throttle → DTOs → client → fetcher → view-model extension). A `comicMetadataProvider` setting routes every existing comic-fetch entry point through a new dispatcher, `LibraryViewModel.fetchComicMetadata`. Candidates stored on records gain a `provider` tag so the existing pickers apply through the right service.

**Tech Stack:** Swift / SwiftUI (macOS + iOS targets in one file set), GRDB 7 for persistence, Swift Testing (`import Testing`) for unit tests, URLSession for HTTP. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-12-metron-metadata-design.md`

## Global Constraints

- Metron API: base `https://metron.cloud/api/`, HTTP Basic auth, ≤20 requests/minute (self-throttle 3.1s), 5,000/day budget, custom User-Agent `SuperComicOrganizer/1.0 (personal library app)`.
- Metadata fill rules: series name canonical (always overwritten); every other scalar fills blanks only; `storyArcs`/`characters`/`teams` replace-but-never-wipe.
- `metadataSource` string for Metron fetches is exactly `"Metron"`; provider setting values are exactly `"ComicVine"` and `"Metron"`; default provider is ComicVine.
- Cover images: decode the `image` URL field but never download it (explicit user decision).
- Legacy compatibility: candidate JSON without a `provider` field and snapshots without the new fields must decode and behave as ComicVine data.
- All logging via `AppLog.metadata` with a `[Metron]` prefix.
- Build: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`.
- Tests: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`.
- The Xcode project uses synchronized file groups — new `.swift` files under `SCO-OSXCursor/` and `SCO-OSXCursorTests/` are picked up automatically; do NOT edit `project.pbxproj`.
- Commits: one per task, message ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Comic model fields, snapshot fields, and DB migration v32

**Files:**
- Modify: `SCO-OSXCursor/Models/Comic.swift` (property block ~line 96, init params ~line 161, init body ~line 216, `Columns` ~line 777, `encode(to:)` ~line 835, row init ~line 873/924)
- Modify: `SCO-OSXCursor/Services/Metadata/ComicVine.swift` (`CVMetadataSnapshot`, ~line 190)
- Modify: `SCO-OSXCursor/Services/Database/DatabaseManager.swift` (after `v31_folder_position`, ~line 703)
- Test: `SCO-OSXCursorTests/MetronMatchTests.swift` (create)

**Interfaces:**
- Consumes: existing `Comic`, `CVMetadataSnapshot`.
- Produces: `Comic.characters: [String]`, `Comic.teams: [String]`, `Comic.storeDate: Date?`, `Comic.metronSeriesID: Int?`, `Comic.metronIssueID: Int?` (all with matching init params, columns `characters`, `teams`, `store_date`, `metron_series_id`, `metron_issue_id`); `CVMetadataSnapshot` capturing/restoring all five.

- [ ] **Step 1: Write the failing test**

Create `SCO-OSXCursorTests/MetronMatchTests.swift`:

```swift
//
//  MetronMatchTests.swift
//  SCO-OSXCursorTests
//
//  Tests for the Metron metadata integration: model fields, snapshot
//  round-trip, DTO decoding, link parsing, and fill behavior.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Model & snapshot

@Suite struct MetronModelTests {

    @Test func snapshotRoundTripsMetronFields() throws {
        var comic = Comic(
            filePath: URL(fileURLWithPath: "/tmp/a.cbz"),
            fileName: "a.cbz",
            series: "Alpha",
            year: 2020
        )
        comic.characters = ["Superman", "Lois Lane"]
        comic.teams = ["Justice League"]
        comic.storeDate = Date(timeIntervalSince1970: 1_700_000_000)
        comic.metronSeriesID = 42
        comic.metronIssueID = 99

        let snapshot = CVMetadataSnapshot(of: comic)
        var restored = Comic(
            filePath: URL(fileURLWithPath: "/tmp/a.cbz"),
            fileName: "a.cbz"
        )
        // Simulate a fetch having overwritten everything, then undo.
        restored.characters = ["Wrong"]
        restored.teams = ["Wrong"]
        restored.storeDate = Date()
        restored.metronSeriesID = 1
        restored.metronIssueID = 2
        snapshot.restore(onto: &restored)

        #expect(restored.characters == ["Superman", "Lois Lane"])
        #expect(restored.teams == ["Justice League"])
        #expect(restored.storeDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(restored.metronSeriesID == 42)
        #expect(restored.metronIssueID == 99)
    }

    @Test func legacySnapshotJSONStillDecodes() throws {
        // A pre-v32 snapshot has none of the Metron fields.
        let legacy = #"{"title":"Old","storyArcs":["Arc"]}"#
        let snapshot = CVMetadataSnapshot.decode(legacy)
        #expect(snapshot != nil)
        #expect(snapshot?.title == "Old")
        #expect(snapshot?.characters == nil)
        #expect(snapshot?.teams == nil)
        #expect(snapshot?.storeDate == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/MetronModelTests -quiet`
Expected: BUILD FAILURE — `Comic` has no member `characters` etc.

- [ ] **Step 3: Add the model fields**

In `SCO-OSXCursor/Models/Comic.swift`, directly under the `storyArcs` property (line ~96):

```swift
    /// Characters appearing in this issue (from Metron). Searchable
    /// alongside tags and story arcs. Empty for never-fetched books.
    var characters: [String]
    /// Teams appearing in this issue (from Metron). Searchable.
    var teams: [String]
    /// In-store (shipping) date from Metron, when known.
    var storeDate: Date?
```

Under the ComicVine ID properties (line ~84):

```swift
    // MARK: - Metron Metadata
    var metronSeriesID: Int?          // Matched Metron series id
    var metronIssueID: Int?           // Matched Metron issue id (if resolved)
```

Init parameter list — add after `storyArcs: [String] = [],`:

```swift
        characters: [String] = [],
        teams: [String] = [],
        storeDate: Date? = nil,
        metronSeriesID: Int? = nil,
        metronIssueID: Int? = nil,
```

Init body — add after `self.storyArcs = storyArcs`:

```swift
        self.characters = characters
        self.teams = teams
        self.storeDate = storeDate
        self.metronSeriesID = metronSeriesID
        self.metronIssueID = metronIssueID
```

`Columns` enum — add after `static let storyArcs`:

```swift
        static let characters = Column("characters")
        static let teams = Column("teams")
        static let storeDate = Column("store_date")
        static let metronSeriesID = Column("metron_series_id")
        static let metronIssueID = Column("metron_issue_id")
```

`encode(to:)` — add after the `storyArcs` line:

```swift
        container[Columns.characters] = try? JSONEncoder().encode(characters)  // JSON array
        container[Columns.teams] = try? JSONEncoder().encode(teams)  // JSON array
        container[Columns.storeDate] = storeDate
        container[Columns.metronSeriesID] = metronSeriesID
        container[Columns.metronIssueID] = metronIssueID
```

Row init — after the `decodedStoryArcs` block add:

```swift
        // Decode characters / teams from JSON
        var decodedCharacters: [String] = []
        if let charData: Data = row["characters"] {
            decodedCharacters = (try? JSONDecoder().decode([String].self, from: charData)) ?? []
        }
        var decodedTeams: [String] = []
        if let teamData: Data = row["teams"] {
            decodedTeams = (try? JSONDecoder().decode([String].self, from: teamData)) ?? []
        }
```

and in the `self.init(...)` call, after `storyArcs: decodedStoryArcs,`:

```swift
            characters: decodedCharacters,
            teams: decodedTeams,
            storeDate: row["store_date"],
            metronSeriesID: row["metron_series_id"],
            metronIssueID: row["metron_issue_id"],
```

- [ ] **Step 4: Extend the undo snapshot**

In `SCO-OSXCursor/Services/Metadata/ComicVine.swift`, `CVMetadataSnapshot`: add stored properties (all optional so pre-v32 snapshots decode):

```swift
    var characters: [String]?  // Optional so pre-v32 snapshots still decode (Metron)
    var teams: [String]?       // Optional so pre-v32 snapshots still decode (Metron)
    var storeDate: Date?
    var metronSeriesID: Int?
    var metronIssueID: Int?
```

In `init(of:)` add:

```swift
        characters = comic.characters
        teams = comic.teams
        storeDate = comic.storeDate
        metronSeriesID = comic.metronSeriesID
        metronIssueID = comic.metronIssueID
```

In `restore(onto:)` add (arrays default to `[]` like `storyArcs`):

```swift
        comic.characters = characters ?? []
        comic.teams = teams ?? []
        comic.storeDate = storeDate
        comic.metronSeriesID = metronSeriesID
        comic.metronIssueID = metronIssueID
```

- [ ] **Step 5: Register migration v32**

In `SCO-OSXCursor/Services/Database/DatabaseManager.swift`, after the `v31_folder_position` migration block, following the house pattern exactly:

```swift
        migrator.registerMigration("v32_metron_metadata") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v32_metron_metadata")
            if try db.tableExists("comics") {
                let columns: [(String, Database.ColumnType)] = [
                    ("characters", .text),          // JSON [String] (Metron)
                    ("teams", .text),               // JSON [String] (Metron)
                    ("store_date", .datetime),      // Metron store date
                    ("metron_series_id", .integer),
                    ("metron_issue_id", .integer),
                ]
                for (name, type) in columns {
                    do {
                        try db.alter(table: "comics") { t in
                            t.add(column: name, type)
                        }
                        AppLog.database.info("[DatabaseManager] ✅ Added \(name) column")
                    } catch {
                        AppLog.database.error("[DatabaseManager] ℹ️ \(name) column may already exist: \(error.localizedDescription)")
                    }
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v32_metron_metadata complete")
        }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS (new suite + all existing suites, proving no regressions in encode/decode).

- [ ] **Step 7: Commit**

```bash
git add SCO-OSXCursor/Models/Comic.swift SCO-OSXCursor/Services/Metadata/ComicVine.swift SCO-OSXCursor/Services/Database/DatabaseManager.swift SCO-OSXCursorTests/MetronMatchTests.swift
git commit -m "feat(metron): comic model fields + migration v32 for Metron metadata

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Provider tag on stored candidates

**Files:**
- Modify: `SCO-OSXCursor/Services/Metadata/ComicVine.swift` (`CVCandidate`, ~line 170)
- Test: `SCO-OSXCursorTests/MetronMatchTests.swift` (append)

**Interfaces:**
- Consumes: `CVCandidate` (Codable, stored as JSON on `Comic.metadataCandidates`).
- Produces: `CVCandidate.provider: String?` — `nil` or `"ComicVine"` ⇒ ComicVine volume ID; `"Metron"` ⇒ Metron series ID. `CVCandidate.isMetron: Bool`. New memberwise usage: existing 4 construction sites keep compiling because `provider` gets a default.

- [ ] **Step 1: Write the failing test** (append to `MetronMatchTests.swift`)

```swift
// MARK: - Candidate provider tag

@Suite struct CandidateProviderTests {

    @Test func legacyCandidateJSONDecodesAsComicVine() {
        let legacy = #"[{"id":123,"name":"Iron Man","startYear":1968,"publisher":"Marvel","issueCount":332}]"#
        let list = CVCandidate.decodeList(legacy)
        #expect(list.count == 1)
        #expect(list[0].provider == nil)
        #expect(list[0].isMetron == false)
    }

    @Test func metronCandidateRoundTrips() {
        let candidate = CVCandidate(
            id: 42, name: "Superman", startYear: 2016,
            publisher: "DC Comics", issueCount: 45, provider: "Metron"
        )
        let json = CVCandidate.encodeList([candidate])
        let decoded = CVCandidate.decodeList(json)
        #expect(decoded.first?.isMetron == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/CandidateProviderTests -quiet`
Expected: BUILD FAILURE — `CVCandidate` has no member `provider`.

- [ ] **Step 3: Implement**

In `CVCandidate` add after `let issueCount: Int?`:

```swift
    /// Which provider these candidate IDs belong to. Nil (legacy) or
    /// "ComicVine" = ComicVine volume IDs; "Metron" = Metron series IDs.
    var provider: String? = nil

    var isMetron: Bool { provider == "Metron" }
```

(`var provider: String? = nil` keeps the synthesized memberwise init callable WITHOUT the new argument, so every existing `CVCandidate(...)` construction site — `fetchComicVineMetadata`, the Organize staging fetch — compiles unchanged as ComicVine-tagged, and synthesized Codable still decodes legacy JSON missing the key. Only the Metron paths added in Task 5 pass `provider: "Metron"` explicitly.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/Services/Metadata/ComicVine.swift SCO-OSXCursorTests/MetronMatchTests.swift
git commit -m "feat(metron): provider tag on stored match candidates

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Metron service core — config, quota, throttle, DTOs, client, link parser

**Files:**
- Create: `SCO-OSXCursor/Services/Metadata/Metron.swift`
- Test: `SCO-OSXCursorTests/MetronMatchTests.swift` (append)

**Interfaces:**
- Consumes: `AppLog.metadata`.
- Produces (used by Tasks 4–8):
  - `enum ComicSource: String { case comicVine = "ComicVine"; case metron = "Metron" }` with `static let defaultsKey = "comicMetadataProvider"`, `static var current: ComicSource`, `var displayName: String`.
  - `enum MetronConfig { usernameDefaultsKey = "metronUsername"; passwordDefaultsKey = "metronPassword"; static var hasCredentials: Bool; static var authorizationValue: String }`
  - `final class MetronQuota: ObservableObject` — `static let shared`, `static let dailyLimit = 5000`, `func recordCall()`, `var callsInLastDay: Int`, `var nextReset: Date?`.
  - `actor MetronThrottle { static let shared; func wait() async }`
  - DTOs: `MTPage<T>`, `MTGenericItem {id, name}`, `MTSeriesResult` (list row), `MTSeriesDetail`, `MTSeriesRef {id, name, yearBegan, publisher, issueCount}` (+ `.init(listRow:)`, `.init(detail:)`), `MTIssueResult`, `MTCredit {creator, roles}`, `MTIssueDetail`, `MTIssueSeriesRef`.
  - `final class MetronService` — `static let shared`; `enum MTError: LocalizedError { noCredentials, badURL, unauthorized, rateLimited(retryAfter: Date?), http(Int), badResponse }`; `func searchSeries(_ name: String) async throws -> [MTSeriesResult]`; `func issues(seriesID: Int, issueNumber: String?) async throws -> [MTIssueResult]`; `func issuesForSeries(seriesID: Int) async throws -> [MTIssueResult]`; `func issueDetail(id: Int) async throws -> MTIssueDetail`; `func seriesDetail(id: Int) async throws -> MTSeriesDetail`; `func seriesID(forIssueID: Int) async throws -> Int?`.
  - `enum MTReference: Equatable { case series(Int), issue(Int) }`; `enum MTLinkParser { static func parse(_ raw: String) -> MTReference? }`.
  - `enum MetronDates { static func parse(_ s: String?) -> Date?; static func year(from s: String?) -> Int? }`.

- [ ] **Step 1: Write the failing tests** (append to `MetronMatchTests.swift`)

```swift
// MARK: - Metron DTO decoding

@Suite struct MetronDTOTests {

    @Test func decodesSeriesListPage() throws {
        let json = """
        {"count":2,"next":null,"previous":null,"results":[
          {"id":2658,"series":"Superman (2016)","year_began":2016,"year_end":2018,
           "volume":4,"issue_count":52,
           "publisher":{"id":2,"name":"DC Comics"},
           "series_type":{"id":10,"name":"Ongoing Series"},
           "cv_id":91699,"gcd_id":null,"modified":"2024-01-01T00:00:00Z"}
          ,
          {"id":100,"series":"Superman (1987)","year_began":1987,"year_end":2006,
           "volume":2,"issue_count":228,
           "publisher":{"id":2,"name":"DC Comics"},
           "series_type":{"id":10,"name":"Ongoing Series"},
           "cv_id":null,"gcd_id":null,"modified":"2024-01-01T00:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(MTPage<MTSeriesResult>.self, from: json)
        #expect(page.results.count == 2)
        let ref = MTSeriesRef(listRow: page.results[0])
        #expect(ref.id == 2658)
        #expect(ref.name == "Superman (2016)")
        #expect(ref.yearBegan == 2016)
        #expect(ref.publisher == "DC Comics")
        #expect(ref.issueCount == 52)
    }

    @Test func decodesIssueListRow() throws {
        let json = """
        {"count":1,"next":null,"previous":null,"results":[
          {"id":38181,"series":{"name":"Superman","volume":4,"year_began":2016},
           "number":"6","issue":"Superman (2016) #6",
           "cover_date":"2016-11-01","store_date":"2016-09-07",
           "image":"https://static.metron.cloud/media/issue/2018/x.jpg",
           "cover_hash":"abc","modified":"2024-01-01T00:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(MTPage<MTIssueResult>.self, from: json)
        #expect(page.results.first?.id == 38181)
        #expect(page.results.first?.number == "6")
        #expect(page.results.first?.coverDate == "2016-11-01")
        #expect(page.results.first?.storeDate == "2016-09-07")
    }

    @Test func decodesIssueDetail() throws {
        let json = """
        {"id":38181,"publisher":{"id":2,"name":"DC Comics"},
         "series":{"id":2658,"name":"Superman","sort_name":"Superman","volume":4,
                   "year_began":2016,"series_type":{"id":10,"name":"Ongoing Series"},"genres":[]},
         "number":"6","alt_number":"","title":"","name":["Son of Superman, Part Six"],
         "cover_date":"2016-11-01","store_date":"2016-09-07",
         "price":"2.99","rating":{"id":1,"name":"Everyone"},"sku":"","isbn":"","upc":"","page":32,
         "desc":"Superman and son face the Eradicator.",
         "image":"https://static.metron.cloud/media/issue/2018/x.jpg","cover_hash":"abc",
         "arcs":[{"id":93,"name":"Son of Superman","modified":"2024-01-01T00:00:00Z"}],
         "credits":[
           {"id":573,"creator":"Peter J. Tomasi","role":[{"id":30,"name":"Writer"}]},
           {"id":574,"creator":"Patrick Gleason","role":[{"id":1,"name":"Penciller"},{"id":6,"name":"Cover"}]},
           {"id":575,"creator":"Mick Gray","role":[{"id":2,"name":"Inker"}]}
         ],
         "characters":[{"id":1,"name":"Superman","modified":"2024-01-01T00:00:00Z"},
                       {"id":2,"name":"Jonathan Kent","modified":"2024-01-01T00:00:00Z"}],
         "teams":[{"id":5,"name":"Eradicators","modified":"2024-01-01T00:00:00Z"}],
         "universes":[],"reprints":[],"variants":[],
         "cv_id":519906,"gcd_id":null,"resource_url":"https://metron.cloud/issue/superman-2016-6/",
         "modified":"2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(MTIssueDetail.self, from: json)
        #expect(detail.storyTitles == ["Son of Superman, Part Six"])
        #expect(detail.desc == "Superman and son face the Eradicator.")
        #expect(detail.arcs?.map(\.name) == ["Son of Superman"])
        #expect(detail.characters?.map(\.name) == ["Superman", "Jonathan Kent"])
        #expect(detail.teams?.map(\.name) == ["Eradicators"])
        #expect(detail.credits?.count == 3)
        #expect(detail.credits?[1].roles.map(\.name) == ["Penciller", "Cover"])
        #expect(detail.storeDate == "2016-09-07")
    }
}

// MARK: - Metron link parsing

@Suite struct MetronLinkParserTests {

    @Test func parsesAPIStyleSeriesURL() {
        #expect(MTLinkParser.parse("https://metron.cloud/api/series/2658/") == .series(2658))
    }

    @Test func parsesNumericIssueURL() {
        #expect(MTLinkParser.parse("https://metron.cloud/issue/38181/") == .issue(38181))
    }

    @Test func bareNumberIsSeries() {
        #expect(MTLinkParser.parse(" 2658 ") == .series(2658))
    }

    @Test func slugURLRejected() {
        #expect(MTLinkParser.parse("https://metron.cloud/issue/superman-2016-6/") == nil)
    }

    @Test func garbageRejected() {
        #expect(MTLinkParser.parse("not a link") == nil)
        #expect(MTLinkParser.parse("") == nil)
    }
}

// MARK: - Metron dates

@Suite struct MetronDateTests {

    @Test func parsesISODateAndYear() {
        #expect(MetronDates.year(from: "2016-11-01") == 2016)
        #expect(MetronDates.parse("2016-09-07") != nil)
        #expect(MetronDates.parse(nil) == nil)
        #expect(MetronDates.year(from: "bad") == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/MetronDTOTests -quiet`
Expected: BUILD FAILURE — `MTPage` undefined.

- [ ] **Step 3: Create `SCO-OSXCursor/Services/Metadata/Metron.swift`**

```swift
//
//  Metron.swift
//  SCO-OSXCursor
//
//  Metron (metron.cloud) metadata integration: provider setting, config,
//  daily quota tracker, throttle, DTOs, API client, link parser, and the
//  fetch fill logic. Mirrors the structure of ComicVine.swift.
//
//  API notes (metron.cloud/api):
//  - Auth: HTTP Basic with the user's free Metron account credentials.
//  - Limits: 20 requests/minute + 5,000 requests/day — we self-throttle
//    to ~1 request / 3.1s and track a rolling daily budget.
//  - DRF-style pagination ({count, next, results}); we read page 1 only.
//  - Cover image URLs are decoded but never downloaded (out of scope).
//

import Foundation
import Combine
import SwiftUI
import os

// MARK: - Provider setting

/// Which provider comic (non-ebook) fetches use. Ebook routing is separate.
enum ComicSource: String, CaseIterable, Identifiable {
    case comicVine = "ComicVine"
    case metron = "Metron"

    static let defaultsKey = "comicMetadataProvider"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// The user's chosen source; ComicVine when unset (pre-Metron behavior).
    static var current: ComicSource {
        ComicSource(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .comicVine
    }
}

// MARK: - Configuration

enum MetronConfig {
    static let usernameDefaultsKey = "metronUsername"
    static let passwordDefaultsKey = "metronPassword"

    static var username: String {
        (UserDefaults.standard.string(forKey: usernameDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var password: String {
        (UserDefaults.standard.string(forKey: passwordDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasCredentials: Bool { !username.isEmpty && !password.isEmpty }

    /// "Basic <base64(user:pass)>" for the Authorization header.
    static var authorizationValue: String {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}

// MARK: - Daily Quota Tracker

/// Rolling-24h call counter, persisted so the readout survives relaunches.
/// Metron allows 5,000 requests/day (more for donors); a rolling window is
/// conservative vs. the server's fixed daily reset.
@MainActor
final class MetronQuota: ObservableObject {
    static let shared = MetronQuota()
    static let dailyLimit = 5000

    @Published private(set) var callTimestamps: [Date] = []

    private let defaultsKey = "metronCallTimestamps"
    private static let day: TimeInterval = 24 * 3600

    private init() {
        if let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Double] {
            callTimestamps = stored.map { Date(timeIntervalSince1970: $0) }
        }
        prune()
    }

    func recordCall() {
        prune()
        callTimestamps.append(Date())
        save()
    }

    /// Calls made in the trailing 24 hours.
    var callsInLastDay: Int {
        callTimestamps.filter { $0 > Date().addingTimeInterval(-Self.day) }.count
    }

    /// When the OLDEST call in the window ages out — when budget returns.
    var nextReset: Date? {
        callTimestamps
            .filter { $0 > Date().addingTimeInterval(-Self.day) }
            .min()?
            .addingTimeInterval(Self.day)
    }

    private func prune() {
        // Keep a little history beyond the day for clock skew, cap size.
        callTimestamps = callTimestamps.suffix(6000).filter {
            $0 > Date().addingTimeInterval(-2 * Self.day)
        }
    }

    private func save() {
        UserDefaults.standard.set(callTimestamps.map { $0.timeIntervalSince1970 }, forKey: defaultsKey)
    }
}

// MARK: - Request throttle

/// Metron allows 20 requests/minute — 3.1s spacing keeps us safely under.
actor MetronThrottle {
    static let shared = MetronThrottle()
    private let minInterval: TimeInterval = 3.1
    private var lastRequest: Date = .distantPast

    func wait() async {
        let now = Date()
        let earliest = lastRequest.addingTimeInterval(minInterval)
        if earliest > now {
            let delay = earliest.timeIntervalSince(now)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequest = Date()
    }
}

// MARK: - DTOs

/// DRF page envelope. We only ever read the first page.
struct MTPage<T: Decodable>: Decodable {
    let count: Int
    let results: [T]
}

struct MTGenericItem: Decodable {
    let id: Int
    let name: String
}

/// Series LIST row (`series/?name=…`). The display name arrives in the
/// JSON key "series" (detail responses use "name" — see MTSeriesDetail).
struct MTSeriesResult: Decodable {
    let id: Int
    let series: String?
    let yearBegan: Int?
    let yearEnd: Int?
    let volume: Int?
    let issueCount: Int?
    let publisher: MTGenericItem?

    enum CodingKeys: String, CodingKey {
        case id, series, volume, publisher
        case yearBegan = "year_began"
        case yearEnd = "year_end"
        case issueCount = "issue_count"
    }
}

/// Series DETAIL (`series/<id>/`).
struct MTSeriesDetail: Decodable {
    let id: Int
    let name: String?
    let yearBegan: Int?
    let volume: Int?
    let issueCount: Int?
    let publisher: MTGenericItem?

    enum CodingKeys: String, CodingKey {
        case id, name, volume, publisher
        case yearBegan = "year_began"
        case issueCount = "issue_count"
    }
}

/// Common projection of a Metron series used by scoring, candidates, and
/// the fill path, regardless of whether it came from a list or detail call.
struct MTSeriesRef {
    let id: Int
    let name: String?
    let yearBegan: Int?
    let publisher: String?
    let issueCount: Int?

    init(listRow: MTSeriesResult) {
        id = listRow.id
        name = listRow.series
        yearBegan = listRow.yearBegan
        publisher = listRow.publisher?.name
        issueCount = listRow.issueCount
    }

    init(detail: MTSeriesDetail) {
        id = detail.id
        name = detail.name
        yearBegan = detail.yearBegan
        publisher = detail.publisher?.name
        issueCount = detail.issueCount
    }

    init(id: Int, name: String?, yearBegan: Int?, publisher: String?, issueCount: Int?) {
        self.id = id
        self.name = name
        self.yearBegan = yearBegan
        self.publisher = publisher
        self.issueCount = issueCount
    }
}

/// Issue LIST row (`issue/?series=<id>&number=<n>`).
struct MTIssueResult: Decodable {
    let id: Int
    let number: String?
    let issueName: String?      // "Superman (2016) #6"
    let coverDate: String?      // "2016-11-01"
    let storeDate: String?

    enum CodingKeys: String, CodingKey {
        case id, number
        case issueName = "issue"
        case coverDate = "cover_date"
        case storeDate = "store_date"
    }
}

struct MTCredit: Decodable {
    let creator: String?
    let roles: [MTGenericItem]

    enum CodingKeys: String, CodingKey {
        case creator
        case roles = "role"
    }
}

/// Issue DETAIL (`issue/<id>/`). `image` is decoded for future use but
/// never downloaded (covers are out of scope by design).
struct MTIssueDetail: Decodable {
    let id: Int
    let number: String?
    let collectionTitle: String?   // JSON "title" — TPB/collection title
    let storyTitles: [String]?     // JSON "name" — per-issue story titles
    let coverDate: String?
    let storeDate: String?
    let desc: String?
    let image: String?
    let credits: [MTCredit]?
    let arcs: [MTGenericItem]?
    let characters: [MTGenericItem]?
    let teams: [MTGenericItem]?

    enum CodingKeys: String, CodingKey {
        case id, number, desc, image, credits, arcs, characters, teams
        case collectionTitle = "title"
        case storyTitles = "name"
        case coverDate = "cover_date"
        case storeDate = "store_date"
    }
}

/// Minimal projection to resolve an issue's parent series ID.
struct MTIssueSeriesRef: Decodable {
    struct SeriesRef: Decodable { let id: Int }
    let series: SeriesRef?
}

// MARK: - Date helpers

enum MetronDates {
    /// Metron dates are plain "yyyy-MM-dd" strings.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s)
    }

    static func year(from s: String?) -> Int? {
        guard let s, s.count >= 4, let year = Int(s.prefix(4)) else { return nil }
        return year
    }
}

// MARK: - API Client

final class MetronService {
    static let shared = MetronService()

    private let baseURL = "https://metron.cloud/api"
    private let userAgent = "SuperComicOrganizer/1.0 (personal library app)"

    enum MTError: LocalizedError {
        case noCredentials
        case badURL
        case unauthorized
        case rateLimited(retryAfter: Date?)
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No Metron username/password configured."
            case .badURL:
                return "Could not build the request URL."
            case .unauthorized:
                return "Metron sign-in failed — check username/password in Settings."
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    let time = retryAfter.formatted(date: .omitted, time: .shortened)
                    return "Metron rate limit reached. Try again after \(time)."
                }
                return "Metron rate limit reached. Try again shortly."
            case .http(let code):
                return "Metron returned HTTP \(code)."
            case .badResponse:
                return "Metron returned an unexpected response."
            }
        }
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        guard MetronConfig.hasCredentials else { throw MTError.noCredentials }

        var components = URLComponents(string: "\(baseURL)/\(path)")
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw MTError.badURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(MetronConfig.authorizationValue, forHTTPHeaderField: "Authorization")

        await MetronThrottle.shared.wait()
        await MainActor.run { MetronQuota.shared.recordCall() }
        AppLog.metadata.info("[Metron] → \(path)")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401, 403: throw MTError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)
                    .map { Date().addingTimeInterval($0) }
                throw MTError.rateLimited(retryAfter: retryAfter)
            default: throw MTError.http(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLog.metadata.error("[Metron] Decode failed for \(path): \(error.localizedDescription)")
            throw MTError.badResponse
        }
    }

    /// Search series by name. 1 API call.
    func searchSeries(_ name: String) async throws -> [MTSeriesResult] {
        let page: MTPage<MTSeriesResult> = try await request(
            path: "series/",
            query: [URLQueryItem(name: "name", value: name)]
        )
        return page.results
    }

    /// Issues of a series, optionally filtered to one issue number. 1 call.
    func issues(seriesID: Int, issueNumber: String?) async throws -> [MTIssueResult] {
        var query = [URLQueryItem(name: "series", value: String(seriesID))]
        if let issueNumber, !issueNumber.isEmpty {
            query.append(URLQueryItem(name: "number", value: issueNumber))
        }
        let page: MTPage<MTIssueResult> = try await request(path: "issue/", query: query)
        return page.results
    }

    /// First page of a series' issues (for local number matching when the
    /// filtered lookup comes back empty). 1 API call.
    func issuesForSeries(seriesID: Int) async throws -> [MTIssueResult] {
        try await issues(seriesID: seriesID, issueNumber: nil)
    }

    /// Full issue details (credits, arcs, characters, teams). 1 API call.
    func issueDetail(id: Int) async throws -> MTIssueDetail {
        try await request(path: "issue/\(id)/")
    }

    /// One series by ID (pasted-link override). 1 API call.
    func seriesDetail(id: Int) async throws -> MTSeriesDetail {
        try await request(path: "series/\(id)/")
    }

    /// Resolve an issue ID to its parent series ID. 1 API call.
    func seriesID(forIssueID id: Int) async throws -> Int? {
        let ref: MTIssueSeriesRef = try await request(path: "issue/\(id)/")
        return ref.series?.id
    }
}

// MARK: - Link / ID parsing

/// A reference parsed from a pasted metron.cloud link or ID.
enum MTReference: Equatable {
    case series(Int)
    case issue(Int)
}

/// Extracts a Metron series/issue reference from a pasted URL or number.
/// Metron's public site uses slug URLs (no numeric ID), so only API-style
/// numeric URLs and bare IDs are accepted; slugs are rejected so the UI
/// can explain what to paste instead.
enum MTLinkParser {
    static func parse(_ raw: String) -> MTReference? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // "series/<digits>" or "issue/<digits>" anywhere in the string.
        if let range = trimmed.range(of: #"(series|issue)/(\d+)"#, options: .regularExpression) {
            let token = trimmed[range]
            let parts = token.split(separator: "/")
            if parts.count == 2, let id = Int(parts[1]) {
                return parts[0] == "series" ? .series(id) : .issue(id)
            }
        }

        // Bare numeric input → assume a series ID.
        if let id = Int(trimmed) { return .series(id) }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS (DTO, link parser, and date suites green).

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/Services/Metadata/Metron.swift SCO-OSXCursorTests/MetronMatchTests.swift
git commit -m "feat(metron): service core — config, quota, throttle, DTOs, client, link parser

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Generic scoring overload + pure Metron fill functions

**Files:**
- Modify: `SCO-OSXCursor/Services/Metadata/ComicVine.swift` (`ComicVineMatcher.score`, ~line 1090)
- Modify: `SCO-OSXCursor/Services/Metadata/Metron.swift` (append fetcher section)
- Test: `SCO-OSXCursorTests/MetronMatchTests.swift` (append)

**Interfaces:**
- Consumes: `ComicVineMatcher.nameSimilarity`, `.yearScore`, `.normalizedIssueNumber`, `.stripHTML`, `.applyCredits`, `CVPersonCredit`; Task 3 DTOs.
- Produces:
  - `ComicVineMatcher.score(name:startYear:publisher:issueCount:against:query:) -> Double` (existing `score(_:against:query:)` delegates to it — same math, refactor not re-derivation).
  - `enum MetronMatcher { static func score(_ ref: MTSeriesRef, against: Comic, query: String) -> Double }`
  - `enum MetronFetcher`:
    - `static func applySeries(_ ref: MTSeriesRef, to comic: Comic) -> Comic` (pure)
    - `static func applyIssue(list: MTIssueResult, detail: MTIssueDetail?, to comic: Comic) -> Comic` (pure)
    - `static func fill(_ comic: Comic, from ref: MTSeriesRef) async -> Comic` (orchestrator: network + the two pure functions; sets `metadataFetchedAt`, clears `metadataCandidates`)

- [ ] **Step 1: Write the failing tests** (append to `MetronMatchTests.swift`)

```swift
// MARK: - Metron scoring & fill

@Suite struct MetronFillTests {

    private func makeComic(
        series: String? = "Superman", issue: String? = "6",
        year: Int? = 2016, publisher: String? = nil
    ) -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/s.cbz"),
            fileName: "s.cbz",
            publisher: publisher,
            series: series,
            issueNumber: issue,
            year: year
        )
    }

    @Test func scoringPrefersMatchingYear() {
        let comic = makeComic(year: 2016)
        let new = MTSeriesRef(id: 1, name: "Superman", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let old = MTSeriesRef(id: 2, name: "Superman", yearBegan: 1987, publisher: "DC Comics", issueCount: 228)
        let q = "Superman"
        #expect(MetronMatcher.score(new, against: comic, query: q)
                > MetronMatcher.score(old, against: comic, query: q))
    }

    @Test func applySeriesFillsBlanksAndCanonicalName() {
        var comic = makeComic(series: "superman", publisher: nil)
        comic.year = nil
        let ref = MTSeriesRef(id: 2658, name: "Superman (2016)", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let filled = MetronFetcher.applySeries(ref, to: comic)
        #expect(filled.series == "Superman (2016)")   // canonical
        #expect(filled.publisher == "DC Comics")      // blank-filled
        #expect(filled.year == 2016)                  // blank-filled
        #expect(filled.metronSeriesID == 2658)
    }

    @Test func applySeriesNeverClobbersExistingPublisherOrYear() {
        let comic = makeComic(year: 1999, publisher: "My Publisher")
        let ref = MTSeriesRef(id: 1, name: "Superman", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let filled = MetronFetcher.applySeries(ref, to: comic)
        #expect(filled.publisher == "My Publisher")
        #expect(filled.year == 1999)
    }

    @Test func applyIssueFillsEverything() {
        let comic = makeComic()
        let list = MTIssueResult(
            id: 38181, number: "6", issueName: "Superman (2016) #6",
            coverDate: "2016-11-01", storeDate: "2016-09-07"
        )
        let detail = MTIssueDetail(
            id: 38181, number: "6", collectionTitle: "",
            storyTitles: ["Son of Superman, Part Six"],
            coverDate: "2016-11-01", storeDate: "2016-09-07",
            desc: "Superman and son face the Eradicator.",
            image: nil,
            credits: [
                MTCredit(creator: "Peter J. Tomasi", roles: [MTGenericItem(id: 30, name: "Writer")]),
                MTCredit(creator: "Patrick Gleason", roles: [
                    MTGenericItem(id: 1, name: "Penciller"), MTGenericItem(id: 6, name: "Cover"),
                ]),
                MTCredit(creator: "Mick Gray", roles: [MTGenericItem(id: 2, name: "Inker")]),
            ],
            arcs: [MTGenericItem(id: 93, name: "Son of Superman")],
            characters: [MTGenericItem(id: 1, name: "Superman"), MTGenericItem(id: 2, name: "Jonathan Kent")],
            teams: [MTGenericItem(id: 5, name: "Eradicators")]
        )
        let filled = MetronFetcher.applyIssue(list: list, detail: detail, to: comic)
        #expect(filled.metronIssueID == 38181)
        #expect(filled.title == "Son of Superman, Part Six")
        #expect(filled.summary == "Superman and son face the Eradicator.")
        #expect(filled.writer == "Peter J. Tomasi")
        #expect(filled.artist == "Patrick Gleason")
        #expect(filled.coverArtist == "Patrick Gleason")
        #expect(filled.inker == "Mick Gray")
        #expect(filled.storyArcs == ["Son of Superman"])
        #expect(filled.characters == ["Superman", "Jonathan Kent"])
        #expect(filled.teams == ["Eradicators"])
        #expect(filled.storeDate == MetronDates.parse("2016-09-07"))
    }

    @Test func applyIssueNeverWipesArcsCharactersTeamsWithEmpty() {
        var comic = makeComic()
        comic.storyArcs = ["Existing Arc"]
        comic.characters = ["Existing Character"]
        comic.teams = ["Existing Team"]
        let list = MTIssueResult(id: 1, number: "6", issueName: nil, coverDate: nil, storeDate: nil)
        let detail = MTIssueDetail(
            id: 1, number: "6", collectionTitle: nil, storyTitles: nil,
            coverDate: nil, storeDate: nil, desc: nil, image: nil,
            credits: nil, arcs: [], characters: [], teams: []
        )
        let filled = MetronFetcher.applyIssue(list: list, detail: detail, to: comic)
        #expect(filled.storyArcs == ["Existing Arc"])
        #expect(filled.characters == ["Existing Character"])
        #expect(filled.teams == ["Existing Team"])
    }
}
```

Note: this requires `MTIssueResult`, `MTIssueDetail`, `MTCredit`, `MTGenericItem` to have memberwise inits available — they are structs with `let` fields and a custom `CodingKeys` only, so the synthesized memberwise init exists inside the module and is visible to `@testable import`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/MetronFillTests -quiet`
Expected: BUILD FAILURE — `MetronMatcher` / `MetronFetcher` undefined.

- [ ] **Step 3: Refactor scoring into a generic overload**

In `ComicVineMatcher` (ComicVine.swift), replace the body of `score(_ volume:against:query:)` with a delegation and add the generic form:

```swift
    static func score(_ volume: CVVolumeResult, against comic: Comic, query: String) -> Double {
        score(
            name: volume.name,
            startYear: volume.startYear.flatMap { Int($0) },
            publisher: volume.publisher?.name,
            against: comic,
            query: query
        )
    }

    /// Provider-agnostic scoring core: same math, callable with plain
    /// values so Metron results score identically to ComicVine ones.
    static func score(
        name: String?, startYear: Int?, publisher: String?,
        against comic: Comic, query: String
    ) -> Double {
        var score = nameSimilarity(name ?? "", query)

        score += yearScore(comicYear: comic.year, volumeYear: startYear)

        if let comicPublisher = comic.publisher?.lowercased(),
           let volumePublisher = publisher?.lowercased(),
           !comicPublisher.isEmpty {
            if comicPublisher == volumePublisher { score += 0.15 }
            else if volumePublisher.contains(comicPublisher) || comicPublisher.contains(volumePublisher) {
                score += 0.08
            }
        }

        return score
    }
```

(The publisher/name/year logic moves verbatim; the old body is deleted, not duplicated.)

- [ ] **Step 4: Append matcher + fetcher to Metron.swift**

```swift
// MARK: - Matching

enum MetronMatcher {
    /// Same scoring math as ComicVine — one shared core.
    static func score(_ ref: MTSeriesRef, against comic: Comic, query: String) -> Double {
        ComicVineMatcher.score(
            name: ref.name, startYear: ref.yearBegan, publisher: ref.publisher,
            against: comic, query: query
        )
    }
}

// MARK: - Shared fetch core

/// Fills a `Comic` from Metron data. The two `apply*` functions are pure
/// (no persistence, no network) so they're unit-testable; `fill`
/// orchestrates the network calls, mirroring `ComicVineFetcher.fill`.
enum MetronFetcher {

    /// Series-level fields: series name canonical; publisher/year fill
    /// blanks only; records the Metron series ID.
    static func applySeries(_ ref: MTSeriesRef, to comic: Comic) -> Comic {
        var updated = comic
        if let name = ref.name, !name.isEmpty { updated.series = name }
        if updated.publisher == nil || updated.publisher?.isEmpty == true {
            updated.publisher = ref.publisher
        }
        if updated.year == nil {
            updated.year = ref.yearBegan
        }
        updated.metronSeriesID = ref.id
        return updated
    }

    /// Issue-level fields from a list row + optional detail. Blank-fill
    /// scalars; replace-but-never-wipe arcs/characters/teams.
    static func applyIssue(list: MTIssueResult, detail: MTIssueDetail?, to comic: Comic) -> Comic {
        var updated = comic
        updated.metronIssueID = list.id

        if updated.year == nil {
            updated.year = MetronDates.year(from: list.coverDate ?? detail?.coverDate)
        }
        if updated.storeDate == nil {
            updated.storeDate = MetronDates.parse(list.storeDate ?? detail?.storeDate)
        }

        guard let detail else { return updated }

        if updated.title == nil || updated.title?.isEmpty == true {
            let storyTitle = detail.storyTitles?.first(where: { !$0.isEmpty })
            let collection = (detail.collectionTitle?.isEmpty == false) ? detail.collectionTitle : nil
            updated.title = storyTitle ?? collection
        }
        if updated.summary == nil || updated.summary?.isEmpty == true {
            updated.summary = ComicVineMatcher.stripHTML(detail.desc)
        }

        // Credits: adapt Metron's structured roles to the shared role-name
        // matcher (one CVPersonCredit per creator-role pair).
        if let credits = detail.credits {
            let flat = credits.flatMap { credit in
                credit.roles.map { CVPersonCredit(name: credit.creator, role: $0.name) }
            }
            ComicVineMatcher.applyCredits(flat, to: &updated)
        }

        // Metron authoritative when non-empty; never wipe with empty.
        let arcNames = (detail.arcs ?? []).map(\.name).filter { !$0.isEmpty }
        if !arcNames.isEmpty { updated.storyArcs = arcNames }
        let characterNames = (detail.characters ?? []).map(\.name).filter { !$0.isEmpty }
        if !characterNames.isEmpty { updated.characters = characterNames }
        let teamNames = (detail.teams ?? []).map(\.name).filter { !$0.isEmpty }
        if !teamNames.isEmpty { updated.teams = teamNames }

        return updated
    }

    /// Full fill: series fields, then (when the issue number is known)
    /// issue list + detail. 1–3 API calls. Marks the comic fetched.
    static func fill(_ comic: Comic, from ref: MTSeriesRef) async -> Comic {
        var updated = applySeries(ref, to: comic)

        if let issueNumber = ComicVineMatcher.normalizedIssueNumber(comic.issueNumber) {
            do {
                var issues = try await MetronService.shared.issues(
                    seriesID: ref.id, issueNumber: issueNumber
                )
                // Fallback: list the series' issues and match the
                // normalized number locally (mirrors the ComicVine path).
                if issues.isEmpty {
                    let all = try await MetronService.shared.issuesForSeries(seriesID: ref.id)
                    if let match = all.first(where: {
                        ComicVineMatcher.normalizedIssueNumber($0.number) == issueNumber
                    }) {
                        issues = [match]
                    }
                }
                if let issue = issues.first {
                    let detail = try? await MetronService.shared.issueDetail(id: issue.id)
                    updated = applyIssue(list: issue, detail: detail, to: updated)
                    AppLog.metadata.info("[Metron] Issue #\(issueNumber) matched (id \(issue.id)) for series \(ref.id) — writer:\(updated.writer ?? "–") artist:\(updated.artist ?? "–")")
                } else {
                    AppLog.metadata.info("[Metron] No issue #\(issueNumber) found in series \(ref.id)")
                }
            } catch {
                // Series data still worth keeping; log and continue.
                AppLog.metadata.error("[Metron] Issue lookup failed: \(error.localizedDescription)")
            }
        }

        updated.metadataFetchedAt = Date()
        updated.metadataCandidates = nil
        return updated
    }
}
```

Check `ComicVineMatcher.applyCredits` role matching covers Metron's role names: it matches lowercased contains on "writer", "penciler"/"artist", "cover", "colorist", "inker", "editor". Metron spells it "Penciller" (double L) — the existing `names(for: "penciler")` check will MISS it. Update `applyCredits` in ComicVine.swift:

```swift
        if comic.artist?.isEmpty != false {
            comic.artist = names(for: "penciller") ?? names(for: "penciler") ?? names(for: "artist")
        }
```

(ComicVine uses "penciler", Metron "penciller"; `contains("penciler")` does not match "penciller" — the substring is "pencille" ≠ "penciler" — so both spellings are checked.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS, including the existing `ComicVineMatchTests` (scoring refactor must not change results).

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Services/Metadata/ComicVine.swift SCO-OSXCursor/Services/Metadata/Metron.swift SCO-OSXCursorTests/MetronMatchTests.swift
git commit -m "feat(metron): shared scoring core + pure Metron fill functions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: LibraryViewModel Metron fetch flow, dispatcher, and candidate routing

**Files:**
- Modify: `SCO-OSXCursor/Services/Metadata/Metron.swift` (append view-model extension)
- Modify: `SCO-OSXCursor/Services/Metadata/ComicVine.swift` (`ComicVineFetchOutcome`, batch loop)

**Interfaces:**
- Consumes: Tasks 1–4; existing `fetchComicVineMetadata`, `applyComicVineCandidate`, `updateComic`, `BatchResult`, `autoApplyConfidentMatches` default.
- Produces (call sites in Tasks 6–8 use exactly these):
  - `ComicVineFetchOutcome` gains case `.rateLimited(retryAfter: Date?)`.
  - `LibraryViewModel.fetchMetronMetadata(for: Comic, force: Bool, autoApplyConfident: Bool = true) async -> ComicVineFetchOutcome`
  - `LibraryViewModel.fetchComicMetadata(for: Comic, force: Bool, autoApplyConfident: Bool = true) async -> ComicVineFetchOutcome` — routes by `ComicSource.current`.
  - `LibraryViewModel.fetchComicMetadataBatch(for: [Comic], onProgress:) async -> BatchResult` — routes by setting; stops early on `.rateLimited`.
  - `LibraryViewModel.applyMetadataCandidate(_ c: CVCandidate, to: Comic) async -> ComicVineFetchOutcome` — dispatches on `c.isMetron`.
  - `LibraryViewModel.applyMetronLink(_ raw: String, to: Comic) async -> ComicVineFetchOutcome`
  - `LibraryViewModel.applyProviderLink(_ raw: String, to: Comic) async -> ComicVineFetchOutcome` — routes by candidate context (see below).

- [ ] **Step 1: Add the `.rateLimited` outcome**

In ComicVine.swift change:

```swift
enum ComicVineFetchOutcome {
    case updated
    case needsChoice
    case alreadyFetched
    case noKey
    case noMatches
    case rateLimited(retryAfter: Date?)
    case failed(String)
}
```

Fix every non-exhaustive switch the compiler now flags (ComicDetailView `runFetch`, LibraryView `fetchMetadataSingle`, batch loop, OrganizeInspectorView). For ComicVine paths the case is unreachable; handle it like `.failed`:
- ComicDetailView: `case .rateLimited: fetchMessage = outcome.rateLimitMessage` — add a small helper below.
- Batch loop (`fetchComicVineMetadataBatch`): `case .rateLimited: result.failed += 1`.

Add convenience on the enum:

```swift
extension ComicVineFetchOutcome {
    /// User-facing text for the rate-limited case.
    var rateLimitMessage: String {
        if case .rateLimited(let retryAfter) = self, let retryAfter {
            let time = retryAfter.formatted(date: .omitted, time: .shortened)
            return "Rate limit reached — try again after \(time)."
        }
        return "Rate limit reached — try again shortly."
    }
}
```

- [ ] **Step 2: Append the view-model extension to Metron.swift**

```swift
// MARK: - Fetch Flow

extension LibraryViewModel {

    /// Route a comic fetch to the user's chosen provider.
    @MainActor
    func fetchComicMetadata(
        for comic: Comic, force: Bool, autoApplyConfident: Bool = true
    ) async -> ComicVineFetchOutcome {
        switch ComicSource.current {
        case .comicVine:
            return await fetchComicVineMetadata(
                for: comic, force: force, autoApplyConfident: autoApplyConfident)
        case .metron:
            return await fetchMetronMetadata(
                for: comic, force: force, autoApplyConfident: autoApplyConfident)
        }
    }

    /// Fetch Metron metadata for one book. Mirrors fetchComicVineMetadata:
    /// never re-fetches unless forced, stores top-5 candidates (tagged
    /// "Metron") when ambiguous, honors autoApplyConfident.
    @MainActor
    func fetchMetronMetadata(
        for comic: Comic, force: Bool, autoApplyConfident: Bool = true
    ) async -> ComicVineFetchOutcome {
        guard MetronConfig.hasCredentials else { return .noKey }
        if !force, comic.metadataFetchedAt != nil { return .alreadyFetched }
        if !force, comic.metadataCandidates != nil { return .needsChoice }

        let query = comic.series
            ?? comic.title
            ?? (comic.fileName as NSString).deletingPathExtension

        do {
            let rows = try await MetronService.shared.searchSeries(query)
            guard !rows.isEmpty else { return .noMatches }

            let refs = rows.map(MTSeriesRef.init(listRow:))
            let scored = refs
                .map { (ref: $0, score: MetronMatcher.score($0, against: comic, query: query)) }
                .sorted { $0.score > $1.score }

            let best = scored[0]
            let second = scored.count > 1 ? scored[1].score : 0
            let confident = scored.count == 1 || (best.score >= 0.75 && best.score - second >= 0.2)

            if confident && autoApplyConfident {
                return await applyMetronSeries(best.ref, to: comic)
            }

            let candidates = scored.prefix(5).map { item in
                CVCandidate(
                    id: item.ref.id,
                    name: item.ref.name ?? "Unknown",
                    startYear: item.ref.yearBegan,
                    publisher: item.ref.publisher,
                    issueCount: item.ref.issueCount,
                    provider: "Metron"
                )
            }
            var updated = comic
            updated.metadataCandidates = CVCandidate.encodeList(Array(candidates))
            updated.dateModified = Date()
            updateComic(updated)
            return .needsChoice
        } catch let error as MetronService.MTError {
            if case .rateLimited(let retryAfter) = error {
                return .rateLimited(retryAfter: retryAfter)
            }
            AppLog.metadata.error("[Metron] Fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription ?? "Metron request failed.")
        } catch {
            AppLog.metadata.error("[Metron] Fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Provider-routed batch fetch. Stops early when Metron rate-limits.
    @MainActor
    func fetchComicMetadataBatch(
        for comics: [Comic],
        onProgress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async -> BatchResult {
        guard ComicSource.current == .metron else {
            return await fetchComicVineMetadataBatch(for: comics, onProgress: onProgress)
        }

        var result = BatchResult()
        guard MetronConfig.hasCredentials else {
            result.noKey = true
            return result
        }
        let autoApply = UserDefaults.standard.object(forKey: "autoApplyConfidentMatches") as? Bool ?? true
        let total = comics.count
        for (index, comic) in comics.enumerated() {
            let latest = self.comics.first(where: { $0.id == comic.id }) ?? comic
            let outcome = await fetchMetronMetadata(
                for: latest, force: false, autoApplyConfident: autoApply
            )
            switch outcome {
            case .updated: result.updated += 1
            case .needsChoice:
                result.needChoice += 1
                result.pendingReviewIDs.append(latest.id)
            case .alreadyFetched: result.skipped += 1
            case .noMatches: result.noMatch += 1
            case .failed: result.failed += 1
            case .noKey: result.noKey = true
            case .rateLimited:
                // Budget gone — stop burning the queue; the rest stay unfetched.
                result.failed += comics.count - index
                onProgress(total, total)
                return result
            }
            onProgress(index + 1, total)
        }
        return result
    }

    /// Apply a stored candidate through the provider that produced it.
    @MainActor
    func applyMetadataCandidate(_ candidate: CVCandidate, to comic: Comic) async -> ComicVineFetchOutcome {
        if candidate.isMetron {
            let ref = MTSeriesRef(
                id: candidate.id, name: candidate.name,
                yearBegan: candidate.startYear, publisher: candidate.publisher,
                issueCount: candidate.issueCount
            )
            return await applyMetronSeries(ref, to: comic)
        }
        return await applyComicVineCandidate(candidate, to: comic)
    }

    /// Apply a pasted metron.cloud link/ID (match-picker override).
    @MainActor
    func applyMetronLink(_ raw: String, to comic: Comic) async -> ComicVineFetchOutcome {
        guard MetronConfig.hasCredentials else { return .noKey }
        guard let ref = MTLinkParser.parse(raw) else {
            return .failed("Paste a numeric Metron ID or an api/series/<id> link — Metron's site URLs (slugs) don't carry the ID.")
        }
        do {
            let seriesID: Int
            switch ref {
            case .series(let id):
                seriesID = id
            case .issue(let id):
                guard let resolved = try await MetronService.shared.seriesID(forIssueID: id) else {
                    return .failed("Couldn't find the series for that issue.")
                }
                seriesID = resolved
            }
            let detail = try await MetronService.shared.seriesDetail(id: seriesID)
            return await applyMetronSeries(MTSeriesRef(detail: detail), to: comic)
        } catch {
            AppLog.metadata.error("[Metron] Link match failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Link override routed by the active provider (used by pickers when
    /// the pending candidates are provider-tagged; falls back to setting).
    @MainActor
    func applyProviderLink(_ raw: String, to comic: Comic) async -> ComicVineFetchOutcome {
        let pending = CVCandidate.decodeList(comic.metadataCandidates)
        let useMetron = pending.first?.isMetron ?? (ComicSource.current == .metron)
        return useMetron
            ? await applyMetronLink(raw, to: comic)
            : await applyComicVineLink(raw, to: comic)
    }

    @MainActor
    private func applyMetronSeries(_ ref: MTSeriesRef, to comic: Comic) async -> ComicVineFetchOutcome {
        let current = comics.first(where: { $0.id == comic.id }) ?? comic
        let snapshot = CVMetadataSnapshot(of: current)
        var updated = await MetronFetcher.fill(current, from: ref)
        updated.metadataBackup = snapshot.encoded()
        updated.metadataSource = "Metron"
        updated.dateModified = Date()
        updateComic(updated)
        return .updated
    }
}
```

Note on `error.localizedDescription ?? …`: `MTError.errorDescription` is `String?`; use `error.errorDescription ?? "Metron request failed."` — adjust to compile cleanly.

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: SUCCESS after fixing all switches the new `.rateLimited` case flags. Fix each flagged switch with the pattern from Step 1 (message via `outcome.rateLimitMessage`, or count as failed in batch loops).

- [ ] **Step 4: Run full tests**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A SCO-OSXCursor SCO-OSXCursorTests
git commit -m "feat(metron): fetch flow, provider dispatcher, candidate + link routing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Route the UI call sites through the dispatcher

**Files:**
- Modify: `SCO-OSXCursor/Views/Library/LibraryView.swift` (`fetchMetadataSingle` ~line 1405, batch path ~line 1482)
- Modify: `SCO-OSXCursor/Views/Library/ComicDetailView.swift` (`comicVineSection` ~line 415, `runFetch` ~line 483)
- Modify: `SCO-OSXCursor/Views/Organize/OrganizeInspectorView.swift` (fetch ~line 392)
- Modify: `SCO-OSXCursor/ViewModels/OrganizeViewModel.swift` (`fetchComicVine(for:)` ~line 705)
- Modify: `SCO-OSXCursor/Services/Metadata/ComicVine.swift` (`ComicVineMatchPicker.apply` + `applyLink`, `ComicVineBatchReviewView.apply`)
- Modify: `SCO-OSXCursor/Views/Organize/OrganizeInspectorView.swift` (staging match picker apply, ~line 379)

**Interfaces:**
- Consumes: `fetchComicMetadata`, `fetchComicMetadataBatch`, `applyMetadataCandidate`, `applyProviderLink`, `ComicSource.current`, `MetronConfig.hasCredentials`.
- Produces: no new API; behavior change only. A helper used by several views:

In Metron.swift (bottom, UI helpers section):

```swift
// MARK: - Provider UI helpers

extension ComicSource {
    /// True when the active provider has usable credentials.
    var hasCredentials: Bool {
        switch self {
        case .comicVine: return ComicVineConfig.hasKey
        case .metron: return MetronConfig.hasCredentials
        }
    }

    /// "Add a ComicVine API key…" / "Add your Metron username…" hint.
    var credentialsHint: String {
        switch self {
        case .comicVine:
            return "Add a ComicVine API key in Settings first."
        case .metron:
            return "Add your Metron username and password in Settings first."
        }
    }
}
```

- [ ] **Step 1: LibraryView**

In `fetchMetadataSingle` (non-ebook branch) replace both `viewModel.fetchComicVineMetadata(for:force:)` calls with `viewModel.fetchComicMetadata(for:force:)`, and make messages provider-aware:

```swift
        let source = ComicSource.current
        ...
        case .noKey:
            flashComicVineStatus(source.credentialsHint)
        case .noMatches:
            flashComicVineStatus("\(comic.displayTitle): no \(source.displayName) match found.")
        case .rateLimited:
            flashComicVineStatus(outcome.rateLimitMessage)
```

In the selection batch path (~line 1491) replace `viewModel.fetchComicVineMetadataBatch(for: issues)` with `viewModel.fetchComicMetadataBatch(for: issues)`.

- [ ] **Step 2: ComicDetailView**

`comicVineSection` becomes provider-aware (rename not required; keep the property name to minimize churn):

- Header text: `Text("\(ComicSource.current.displayName) Metadata")`
- No-credentials hint: `if !ComicSource.current.hasCredentials { Text(ComicSource.current.credentialsHint) … }`
- Button label: `Text(liveComic.metadataFetchedAt != nil ? "Re-fetch from \(ComicSource.current.displayName)" : "Fetch from \(ComicSource.current.displayName)")`
- Button disabled/background: use `ComicSource.current.hasCredentials` instead of `ComicVineConfig.hasKey`.
- `runFetch`: `viewModel` call → `libraryViewModel.fetchComicMetadata(for: liveComic, force: force)`; messages: "Metadata updated from \(ComicSource.current.displayName). Review and Save to keep.", `.noKey` → `ComicSource.current.credentialsHint`, `.noMatches` → "No \(ComicSource.current.displayName) matches found for this book.", `.rateLimited` → `outcome.rateLimitMessage`.
- The help text at ~line 249/267 mentioning ComicVine: change "ComicVine" to `ComicSource.current.displayName` where it describes comic routing.

- [ ] **Step 3: Match pickers apply through the dispatcher**

- `ComicVineMatchPicker.apply(_:)`: `viewModel.applyComicVineCandidate` → `viewModel.applyMetadataCandidate`.
- `ComicVineMatchPicker.applyLink()`: `viewModel.applyComicVineLink` → `viewModel.applyProviderLink`; `.noKey` message → `ComicSource.current.credentialsHint`. Link-section placeholder text: when the pending candidates are Metron (`candidates.first?.isMetron == true`), show `TextField("Metron series ID or metron.cloud/api/series/<id>/", …)` and caption "None match? Paste a Metron ID"; otherwise the existing ComicVine placeholder.
- `ComicVineBatchReviewView.apply(_:)`: same dispatcher swap.
- Candidate subtitle fallbacks ("ComicVine volume #…") → `"\(candidate.isMetron ? "Metron series" : "ComicVine volume") #\(candidate.id)"` (both pickers + Organize staging picker).

- [ ] **Step 4: Organize staging**

`OrganizeViewModel.fetchComicVine(for:)` (staging proxy path): route by provider. Where it currently calls `ComicVineService.shared.searchVolumes` + `ComicVineMatcher.score` + `ComicVineFetcher.fill`, wrap:

```swift
        if ComicSource.current == .metron {
            return await fetchMetronStaging(for: id)
        }
```

and add `fetchMetronStaging(for:)` in OrganizeViewModel — same structure as the existing method but using `MetronService.shared.searchSeries`, `MTSeriesRef`, `MetronMatcher.score`, `MetronFetcher.fill`, `MetronConfig.hasCredentials` for the `.noKey` guard, and candidates tagged `provider: "Metron"`. The staging picker's apply (OrganizeInspectorView ~line 379) switches `viewModel.applyComicVineCandidate` → the staging equivalent routed by `candidate.isMetron` (add `applyMetronCandidate(_:toStaged:)` beside the existing ComicVine one, both ending in the same staged-comic update path the CV version uses today — copy its post-fill bookkeeping verbatim).

OrganizeInspectorView labels (~line 317, 324, 361, 577) and OrganizeView guide/help strings (~line 234, 381): replace literal "ComicVine" with `ComicSource.current.displayName` for comic-format items (leave the ebook wording untouched).

- [ ] **Step 5: Build + full tests**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet && xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: SUCCESS / PASS.

- [ ] **Step 6: Commit**

```bash
git add -A SCO-OSXCursor
git commit -m "feat(metron): route all comic fetch entry points through the provider dispatcher

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Settings UI — provider picker + Metron section

**Files:**
- Modify: `SCO-OSXCursor/Views/Settings/SettingsView.swift` (section list ~line 191, provider settings ~line 421)

**Interfaces:**
- Consumes: `ComicSource`, `MetronConfig`, `MetronQuota`.
- Produces: none (leaf UI).

- [ ] **Step 1: Add state**

Next to the existing `@AppStorage` lines (~line 423):

```swift
    @AppStorage(ComicSource.defaultsKey) private var comicMetadataProvider: String = ComicSource.comicVine.rawValue
    @AppStorage(MetronConfig.usernameDefaultsKey) private var metronUsername: String = ""
    @AppStorage(MetronConfig.passwordDefaultsKey) private var metronPassword: String = ""
    @ObservedObject private var metronQuota = MetronQuota.shared
```

- [ ] **Step 2: Add the sections**

In the section list, ABOVE the ComicVine section insert:

```swift
                // Comic metadata source (routes every comic fetch)
                settingsSection(title: "Comic Metadata Source", icon: "arrow.triangle.branch") {
                    comicSourceSettings
                }
```

and BELOW the ComicVine section:

```swift
                // Metron Metadata Section
                settingsSection(title: "Metron Metadata", icon: "books.vertical") {
                    metronSettings
                }
```

- [ ] **Step 3: Implement the two views** (near `comicVineSettings`)

```swift
    // MARK: - Comic Source Settings

    private var comicSourceSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Which database comic fetches use — everywhere: the edit sheet, right-click fetch, batch fetch, and the Organize tab. Book (EPUB) lookups are separate and unaffected.")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Comic metadata source", selection: $comicMetadataProvider) {
                ForEach(ComicSource.allCases) { source in
                    Text(source.displayName).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if ComicSource(rawValue: comicMetadataProvider) == .metron && !MetronConfig.hasCredentials {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text("Metron is selected but has no sign-in below — fetching is disabled until you add one.")
                        .font(Typography.caption)
                }
                .foregroundColor(AccentColors.warning)
            }
        }
    }

    // MARK: - Metron Settings

    private var metronSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pull publisher, creators, summary, story arcs, characters, and teams from the Metron Comic Book Database. Free account; community-run.")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            Link(destination: URL(string: "https://metron.cloud")!) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text("Create a free Metron account")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(AccentColors.primary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Username")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                TextField("Your metron.cloud username", text: $metronUsername)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .padding(Spacing.md)
                    .background(BackgroundColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BorderColors.subtle, lineWidth: 1)
                    )
                    #if os(iOS)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif

                Text("Password")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                SecureField("Your metron.cloud password", text: $metronPassword)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .padding(Spacing.md)
                    .background(BackgroundColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BorderColors.subtle, lineWidth: 1)
                    )

                HStack(spacing: Spacing.xs) {
                    Image(systemName: MetronConfig.hasCredentials ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text(MetronConfig.hasCredentials ? "Sign-in saved" : "No sign-in — Metron fetching is disabled")
                        .font(Typography.caption)
                }
                .foregroundColor(MetronConfig.hasCredentials ? AccentColors.success : TextColors.tertiary)
            }

            Divider()
                .background(BorderColors.subtle)
                .padding(.vertical, Spacing.xs)

            // Daily usage
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("API Calls (Last 24h)")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Spacer()
                    Text("\(metronQuota.callsInLastDay) / \(MetronQuota.dailyLimit)")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                }
                ProgressView(
                    value: Double(min(metronQuota.callsInLastDay, MetronQuota.dailyLimit)),
                    total: Double(MetronQuota.dailyLimit)
                )
                .tint(metronQuota.callsInLastDay >= MetronQuota.dailyLimit ? AccentColors.error : AccentColors.primary)

                if let reset = metronQuota.nextReset {
                    Text("Budget starts returning \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
                Text("Limited to 20 requests/minute and 5,000 calls/day per Metron's terms.")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }
        }
    }
```

If `AccentColors.warning` doesn't exist in DesignSystem.swift, use `AccentColors.error` (check `grep -n "warning" SCO-OSXCursor/Utilities/DesignSystem.swift` first).

- [ ] **Step 4: Build, run visually if possible**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: SUCCESS.

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/Views/Settings/SettingsView.swift
git commit -m "feat(metron): settings — comic source picker + Metron sign-in and daily quota

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: New-field UI — characters/teams sections, search, inspector store date, dashboard card

**Files:**
- Modify: `SCO-OSXCursor/Views/Library/ComicDetailView.swift` (after Story Arcs section, ~line 855)
- Modify: `SCO-OSXCursor/Views/Library/LibraryModels.swift` (search filter, ~line 173)
- Modify: `SCO-OSXCursor/Views/Library/ComicInspectorView.swift` (info rows)
- Modify: `SCO-OSXCursor/Views/Dashboard/DashboardOverviewView.swift` (quota card, ~line 110/294)
- Test: `SCO-OSXCursorTests/MetronMatchTests.swift` (append)

**Interfaces:**
- Consumes: `Comic.characters/teams/storeDate`, `MetronQuota`, `ComicSource.current`.
- Produces: none (leaf UI) except the search predicate change.

- [ ] **Step 1: Write the failing search test** (append to MetronMatchTests.swift)

The filter closure lives inside LibraryModels; test via the same route existing code exposes. Check with `grep -n "func filtered\|struct LibraryFilter" SCO-OSXCursor/Views/Library/LibraryModels.swift` — the search block at line ~160 is inside a filtering function. If it is a testable pure function (e.g. `LibraryFilterState.apply(to:)` or similar), write:

```swift
// MARK: - Search over characters/teams

@Suite struct MetronSearchTests {
    @Test func searchMatchesCharactersAndTeams() {
        var comic = Comic(filePath: URL(fileURLWithPath: "/tmp/x.cbz"), fileName: "x.cbz", series: "X")
        comic.characters = ["Booster Gold"]
        comic.teams = ["Birds of Prey"]
        // Use the same predicate the library search uses.
        #expect(comicMatchesSearch(comic, "booster"))
        #expect(comicMatchesSearch(comic, "birds of prey"))
        #expect(!comicMatchesSearch(comic, "zatanna"))
    }
}
```

To make this testable, extract the existing search predicate into a free function in LibraryModels.swift as part of this task:

```swift
/// One place for the library search predicate, so tests cover it.
func comicMatchesSearch(_ comic: Comic, _ searchText: String) -> Bool {
    comic.displayTitle.localizedCaseInsensitiveContains(searchText)
        || comic.fileName.localizedCaseInsensitiveContains(searchText)
        || comic.title?.localizedCaseInsensitiveContains(searchText) == true
        || comic.publisher?.localizedCaseInsensitiveContains(searchText) == true
        || comic.series?.localizedCaseInsensitiveContains(searchText) == true
        || comic.writer?.localizedCaseInsensitiveContains(searchText) == true
        || comic.artist?.localizedCaseInsensitiveContains(searchText) == true
        || comic.coverArtist?.localizedCaseInsensitiveContains(searchText) == true
        || comic.summary?.localizedCaseInsensitiveContains(searchText) == true
        || comic.issueNumber?.localizedCaseInsensitiveContains(searchText) == true
        || comic.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        || comic.storyArcs.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        || comic.characters.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        || comic.teams.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
}
```

and replace the inline block at ~line 160 with `result = result.filter { comicMatchesSearch($0, searchText) }`.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/MetronSearchTests -quiet`
Expected: BUILD FAILURE — `comicMatchesSearch` undefined.

- [ ] **Step 3: Implement search extraction (above), then the UI pieces**

**ComicDetailView** — after the Story Arcs section block add two sibling sections (same pattern; only shown when non-empty):

```swift
            // Characters Section (read-only, from Metron)
            if !editedComic.characters.isEmpty {
                metadataSection(title: "Characters", icon: "person.2") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(editedComic.characters, id: \.self) { name in
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "person")
                                    .font(.system(size: 11))
                                    .foregroundColor(AccentColors.primary)
                                Text(name)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                            }
                        }
                        Text("From Metron — search your library by character name to find related books.")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }
            }

            // Teams Section (read-only, from Metron)
            if !editedComic.teams.isEmpty {
                metadataSection(title: "Teams", icon: "person.3") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(editedComic.teams, id: \.self) { name in
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "person.3.sequence")
                                    .font(.system(size: 11))
                                    .foregroundColor(AccentColors.primary)
                                Text(name)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                            }
                        }
                        Text("From Metron — search your library by team name to find related books.")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }
            }
```

**ComicInspectorView** — locate the info rows (`grep -n "infoRow\|Fetched" SCO-OSXCursor/Views/Library/ComicInspectorView.swift`) and add, in the metadata block, following the established row helper:

```swift
        if let storeDate = comic.storeDate {
            // In-store (shipping) date from Metron
            infoRow(label: "In Stores", value: storeDate.formatted(date: .abbreviated, time: .omitted))
        }
```

(Adopt the file's actual row helper name/signature — read the surrounding rows first and match exactly.)

**DashboardOverviewView** — make the quota card provider-aware. Add `@ObservedObject private var metronQuota = MetronQuota.shared` beside the ComicVine one; in `comicVineQuotaCard` switch title and content:

```swift
    private var comicVineQuotaCard: some View {
        let source = ComicSource.current
        return dashboardCard(                     // keep the file's existing card wrapper call
            title: source == .metron ? "Metron API" : "ComicVine API",
            ...
        ) {
            if source == .metron { metronQuotaContent } else { comicVineQuotaContent }
        }
    }

    private var metronQuotaContent: some View {
        // Same layout as comicVineQuotaContent with:
        //   metronQuota.callsInLastDay / MetronQuota.dailyLimit,
        //   "/ 5000 calls (24h)" caption, and metronQuota.nextReset.
    }
```

Copy `comicVineQuotaContent`'s body for `metronQuotaContent`, substituting the quota object, limit constant, and reset text — read the existing content view (~line 294) and mirror it exactly rather than inventing a new layout. Keep the existing card wrapper API (read ~line 110 for its real signature; the sketch above is directional, the wrapper call must match the file).

- [ ] **Step 4: Run tests + build**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A SCO-OSXCursor SCO-OSXCursorTests
git commit -m "feat(metron): characters/teams UI, searchable, store date row, provider-aware dashboard card

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Integration doc + manual live-API checklist

**Files:**
- Create: `docs/METRON_INTEGRATION.md`

**Interfaces:** none — documentation.

- [ ] **Step 1: Write the doc**

Create `docs/METRON_INTEGRATION.md` describing (mirroring `docs/COMICVINE_INTEGRATION.md`'s structure): how it works (sign-in → provider picker → fetch flow), rate limiting (20/min throttle at 3.1s, 5,000/day rolling quota, 429 → stop batch early), fill semantics (canonical series, blank-fill, replace-never-wipe for arcs/characters/teams), candidate provider tagging, link override (numeric IDs only — site slugs rejected), files touched, and this manual test checklist:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/METRON_INTEGRATION.md
git commit -m "docs(metron): integration notes + manual live-API checklist

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet` — SUCCESS
- [ ] `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet` — all suites PASS
- [ ] `git log --oneline` shows one commit per task
- [ ] Spec cross-check: every section of `docs/superpowers/specs/2026-09-12-metron-metadata-design.md` maps to a task (settings→7, quota/throttle→3, model/migration→1, fetch flow→4+5, routing→6, new-field UI→8, error handling→3+5, testing→1–4+8, docs→9)
