# TB Tempo

TB Tempo is a native, local-first iPhone series tracker. It uses SwiftUI, SwiftData, local notifications, and TMDB catalog metadata. There are no accounts, analytics, ads, CloudKit, or custom backend.

The project targets iOS 26.0 and builds with the closest installed SDK, Xcode 26.2 / iOS 26.2. The workspace was also tested on the installed iOS 26.4 simulator runtime.

## First run on an iPhone

1. Open `TBTempo.xcodeproj` in Xcode 26.2 or newer.
2. Select the **TBTempo** target, open **Signing & Capabilities**, and choose your personal development team.
3. If Xcode reports that `com.josepinto.TBTempo` is unavailable, change the bundle identifier to a unique value you control.
4. Connect and trust the iPhone, choose it as the run destination, and press Run.
5. If Xcode asks to install or update device support for iOS 26.5.2, allow it. The deployment target is 26.0, so the app itself is compatible with that device OS.

A free Apple developer account may require reinstalling/re-signing periodically. This project does not require App Store Connect or TestFlight.

The app launches into the normal Today tab. Import is optional and is never forced at launch.

## TMDB configuration

Create a personal, non-commercial TMDB API Read Access Token in your TMDB account:

1. Copy `Config/TMDBConfig.example.xcconfig` to `Config/TMDBConfig.xcconfig`.
2. Replace the example value with the API Read Access Token (the long bearer token, not the shorter v3 API key).
3. Build again.

`TMDBConfig.xcconfig` is excluded by `.gitignore`. The token is injected into the built app's Info.plist because this is a personal direct-installed client. Do not commit or share a build containing your token.

TB Tempo uses the TMDB API but is not endorsed or certified by TMDB. The attribution also appears in Settings → About & Attribution.

## Main features

- Today poster feed with Next Up, recent watches, active shows, immediate watched/unwatched controls, and six-second Undo.
- Upcoming list/calendar presentations for active followed shows, grouped into Today, Tomorrow, Next 7 Days, Next 30 Days, and Later, using local calendar-day calculations.
- Show library with active/stopped/completed states, search, filtering, sorting, season progress, whole-season actions, and mark-through actions.
- Statistics for unique watched episodes, watch events, viewing time, series, season, month, and year.
- Morning local notifications with global/per-show switches and a rolling 50-item schedule inside the 90-day horizon.
- Optional TV Time ZIP migration with preview, deterministic reconciliation, atomic confirmation, idempotent event keys, and manually resolvable ambiguous records.
- Versioned `.tbtempo` backup export/import with merge or replace, plus viewing-history CSV export.
- Offline access to the local library, progress, metadata snapshots, and cached poster/backdrop data.

## TV Time migration

Open Settings → Import TV Time History and choose the original GDPR ZIP using the document picker. The importer reads only the allowlist documented in [the archive audit](Documentation/TVTimeArchiveAudit.md). It does not extract arbitrary paths or copy the raw archive into the app.

The preview shows series, accepted individual watches, stopped shows, duplicates, unresolved coordinate collisions, runtime gaps, and aggregate comparisons. Nothing is written until **Confirm Atomic Import** is tapped.

Reconciliation precedence is:

1. individual `tracking-prod-records-v2.csv` watch rows;
2. stable TVDB series/episode IDs and the v2 row key;
3. season/episode coordinates when unique inside a verified series;
4. normalized title only to validate a catalog match, never as an automatic ambiguous attachment.

An archive SHA-256 receipt and stable watch keys make repeat imports idempotent. Ambiguous records appear in Settings → Unresolved Matches. Refresh the affected series metadata and choose the exact episode there to attach its preserved watch date.

Imported placeholders remain useful offline immediately. With a TMDB token configured, **Refresh All Metadata** resolves TVDB series IDs through TMDB's external-ID endpoint and fills posters, episode metadata, future air dates, and runtimes. Automatic matches require a unique external-ID result and verify the returned TVDB ID; unresolved entries can be matched manually from the placeholder’s menu.

Legacy TV Time timestamps in `yyyy-MM-dd HH:mm:ss` format are interpreted as UTC. If an earlier attempt created a receipt but imported zero watches, selecting the same ZIP again repairs that failed attempt in place.

## Statistics semantics

- “Episodes watched” is the number of unique episodes with at least one watch event.
- Viewing time sums the episode runtime once per watch event, so rewatches contribute again.
- An episode runtime wins over the show's default runtime. Import derives a default from the median reliable runtime available for that series.
- A watch with neither runtime contributes zero minutes and is reported as unknown.
- Imported aggregate values remain in the import receipt for comparison; they do not override individual records.
- Legacy TV Time counters can disagree because they cover different generations of tracking data, infer missing runtime, or count content outside this app's series-only scope.

## Backups

Settings → Export TB Tempo Backup creates an unencrypted `.tbtempo` ZIP. It contains private viewing history in readable JSON, so store it carefully. Artwork caches are intentionally omitted.

Import previews counts and validates the manifest/schema before writing:

- **Merge** keeps local data and inserts missing stable records.
- **Replace** removes the current local library and restores the backup in one save operation.

See [the backup format](Documentation/BackupFormat.md) for the portable schema. Viewing History CSV is intended for inspection and analysis, not full-fidelity restore.

## Architecture

- `Models/`: SwiftData library, episodes, watch events, import receipts, and unresolved records.
- `Services/CatalogProviding.swift`: provider protocol; TMDB stays behind this boundary.
- `Services/TMDBCatalogProvider.swift`: bearer-authenticated metadata, external-ID lookup, episode seasons, and artwork.
- `Services/ProgressController.swift`: immediate progress mutations and full event-snapshot Undo.
- `Services/MetadataRefreshCoordinator.swift`: cache-aware refresh, local artwork caching, and notification rescheduling.
- `Migration/`: allowlisted ZIP access, RFC-style CSV parsing, preview, reconciliation, and commit.
- `Backup/`: documented versioned JSON/ZIP backup and CSV export.
- `Views/`: five-tab SwiftUI interface with Dynamic Type, semantic labels, dark mode, and reduced-motion-aware transitions.

All visible SwiftUI string literals are localization-ready. English is the development language; a Portuguese strings catalog can be added later without changing the data model.

## Build and test

```sh
xcodebuild \
  -project TBTempo.xcodeproj \
  -scheme TBTempo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Coverage includes CSV parsing, migration ambiguity/deduplication/idempotency, progress and Undo, specials-aware completion, rewatches and runtime statistics, local-day countdowns, rolling notification planning, backup round-trip, and the empty-library primary-tab UI flow. Fixtures are synthetic and contain no exported user data.

## Privacy and limitations

- The raw GDPR ZIP, personal identifiers, tokens, access/authentication files, and device/IP data are not part of this repository.
- Network access goes only to TMDB metadata/artwork endpoints after the user configures a token.
- Local notifications depend on metadata available the last time the app refreshed. iOS background work is best-effort, so opening the app periodically is necessary for schedule changes.
- TMDB provides date-only TV air dates in this implementation. Those are scheduled at the chosen local morning time (09:00 by default). Time-specific broadcaster premieres are not inferred.
- The app records delay/cancellation when catalog metadata removes a date or a local episode is marked canceled; it does not attempt to infer unannounced schedule changes.
- Live TMDB calls and signing to the physical iPhone require the user's credential/team and were not performed during automated verification.
- Movie tracking and all social/rating/emotion/badge/profile features are intentionally out of scope.
