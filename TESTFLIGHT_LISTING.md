# Super Comic Organizer — TestFlight Copy

Fields map to App Store Connect → TestFlight → Test Information.

---

## Beta App Description
*(4,000 char limit — this is ~1,100. Shown to testers before they install.)*

Super Comic Organizer turns a folder of cryptic filenames into a real comic library.

Drop in CBZ, CBR, PDF, or EPUB files and the app reads each filename to pull out series, issue number, year, and volume — with a confidence rating on every match, so you can see what it's sure about and what it guessed. Corrections you make feed a knowledge base built from your own library, so it gets sharper the more you use it. Connect ComicVine for publisher info, creator credits, summaries, and cover dates.

Browse in a grid, a list, or a publisher-and-series shelf that reads like a real longbox. Sort into folders, search, and filter by series, publisher, or reading status.

Then read. The reader does single-page, spread, and continuous scroll, pinch and double-tap zoom, adjustable tap zones, and right-to-left manga mode. EPUBs get dark, light, and sepia themes plus a table of contents. Zoom level, position, and progress are remembered per book.

Reading on your Mac but heading out with your iPad? Send books straight from your Mac library to your iPad.

Everything stays on your device. There's no account, and your library isn't uploaded anywhere.

This is a beta. Some parts are newer than others and I'd rather hear about a rough edge than have you work around it — the in-app feedback and a screenshot go a long way.

---

## What to Test
*(4,000 char limit. Rewrite this per build — it's the highest-value field in TestFlight.)*

**New in this build**

- Brand-new app icon, including a dark-appearance variant. On iOS, set your Home Screen to Dark (long-press the Home Screen → Edit → Customize → Dark) and confirm the icon switches to the dark-bordered version and looks right against a dark wallpaper.
- The iOS Home Screen name is now "SCOrganizer". It was showing as "SuperComicOr…" because iOS strips spaces from icon labels too long to fit. macOS still shows the full "Super Comic Organizer" in the menu bar and Dock. Worth a look on both — tell me if the short name reads badly to you.

**Where I most want eyes**

- **ComicVine matching.** The newest and least battle-tested area. Point it at a large library, at series with ambiguous names, and at anything obscure or non-English. I want to know about wrong matches, matches it refuses to make, and anything that feels slow or gets rate-limited.
- **Import and parsing accuracy.** Throw your genuinely messy filenames at it — scanlation group tags, bracket soup, volume-vs-issue ambiguity, non-English titles. If it parses something wrong, the original filename is the single most useful thing you can send me.
- **Mac ↔ iPad transfer.** Send books both ways, including large files, and try backgrounding the app mid-transfer.
- **The reader across formats.** Every mode (single, spread, continuous) against CBZ, CBR, PDF, and EPUB. Especially: does your position survive closing and reopening a book? Right-to-left manga mode and the tap zones deserve a hard look.
- **iPad orientation and layout.** Rotate in every view. Split View and Slide Over too, if you use them.

**Known, no need to report**

- ComicVine is labelled Beta on purpose.
- Reading progress does not sync between your Mac and iPad yet. Transfer moves the book, not your place in it.
- This build ships several sample comics inside the app, which is why the download is large. That's leftover test content, not a feature — it's coming out.

**Reporting**

Screenshot then shake (iOS), or use TestFlight's Send Beta Feedback. For a bad parse or a bad ComicVine match, include the exact filename. For a crash, what you were doing right before beats an exact reproduction.

---

## Beta App Review Information
*(Only needed for external testing groups. Internal testers skip review.)*

- **Sign-in required:** No. The app has no accounts and no login.
- **Contact:** andrewmnj@gmail.com
- **Notes for the reviewer:**
  Super Comic Organizer is a local library manager and reader for comic files the
  user already owns. It ships no comic content of its own and has no store,
  catalog, or download feature — files are added by the user via drag-and-drop or
  the file picker. The sample files included in this build are public-domain
  golden-age comics used for testing.

  ComicVine integration is read-only metadata lookup (publisher, credits,
  summaries, cover dates) against the public ComicVine API. No user data is sent.
  All library data and reading progress stay in local storage on device.

---

## Test Information (one-time setup)

- **Feedback email:** andrewmnj@gmail.com
- **Marketing URL:** *(optional — leave blank if there's no site yet)*
- **Privacy Policy URL:** *(required for external testing)*

## Suggested tester groups

- **Internal** — you and any team Apple IDs. No review, builds go live in minutes.
- **Power collectors** — large libraries, thousands of files. The people who will break ComicVine matching and the importer.
- **Manga readers** — right-to-left mode, EPUB themes, non-English filename parsing.
- **Mac + iPad owners** — the only group that can exercise the transfer feature.
