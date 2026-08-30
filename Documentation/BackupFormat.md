# `.tbtempo` backup format, schema 1

A `.tbtempo` file is a standard, unencrypted ZIP package. Paths are fixed and UTF-8 encoded:

```text
manifest.json
data.json
```

Regenerable artwork bytes are not included.

## `manifest.json`

```json
{
  "appVersion": "1.0",
  "contents": ["manifest.json", "data.json"],
  "createdAt": "2026-07-31T12:00:00Z",
  "format": "com.tbtempo.backup",
  "schemaVersion": 1
}
```

An importer must reject another `format`, an unsupported schema version, a missing fixed entry, a manifest larger than 1 MB, or data larger than 100 MB before decoding.

## `data.json`

The payload contains:

- `shows[]`: stable UUID, title/synopsis/status/library state, genres, TMDB and TVDB series IDs, image paths, default runtime, follow/activity dates, and per-series notification preference;
- `episodes[]`: stable UUID, coordinates, metadata, TMDB and TVDB episode IDs, runtime, air date/precision, special/canceled state, and still path;
- `watchEvents[]`: stable key, original date, source, and whether the date was estimated;
- `notificationSettings`: enabled state, local hour/minute, 90-day horizon, and rolling limit.

Dates use ISO 8601. JSON keys are sorted in exports for readable diffs.

## Merge and replace

- Merge upserts stable show/episode UUIDs and inserts only missing watch-event keys. Repeating a merge is idempotent.
- Replace deletes the current library/import diagnostics, constructs the backup graph, and saves. A decode/validation failure happens before mutation; a save failure rolls the model context back.

Future schema changes should add a decoder/migrator from each supported earlier version before raising `schemaVersion`. Unknown newer versions must never be partially imported.
