# TV Time GDPR archive audit

Audit date: 2026-07-31. The raw archive was inspected in place and was not copied into this project.

## Inventory and identifier validation

The ZIP contains 59 CSV files. Sensitive and out-of-scope sources—including tokens, login records, device data, IP addresses, social content, ratings, reactions, comments, movies, and ad identifiers—are never opened by the app importer.

The newer `tracking-prod-records-v2.csv` has 6,232 rows:

- 6,120 episode watch records with 6,120 distinct `ep_id` values;
- 111 series-state records;
- one aggregate/statistics row.

Its meaningful `s_id` values overlap all 111 `tv_show_id` values in `user_tv_show_data.csv`. A privacy-preserving sample check against a public catalog resolved 9 of 12 series IDs to exact current titles; the other three were catalog/title variants. A second check sent 10 sampled episode IDs through TheTVDB's official episode dereferrer, and all 10 resolved successfully. These checks establish that `s_id`/`tv_show_id` and `ep_id` are TVDB identifiers. The importer still treats an ID as untrusted input until its series context is internally consistent.

## Relevant source schemas

| File | Rows | Relevant role |
| --- | ---: | --- |
| `tracking-prod-records-v2.csv` | 6,232 | Authoritative individual watches, series state, timestamps, runtimes, TVDB series/episode IDs, season/episode coordinates, follow/archive state, aggregates |
| `tracking-prod-records.csv` | 882 | Older mixed tracking generation; retained on the allowlist for future diagnostics, not preferred over v2 |
| `user_tv_show_data.csv` | 111 | Legacy series ID/title/follow and watched-total cross-check |
| `followed_tv_show.csv` | 81 | Legacy follow/archive state |
| `followed_tv_show_source.csv` | 29 | Legacy follow provenance |
| `seen_episode_source.csv` | 282 | Legacy watch provenance and coordinates |
| `show_seen_episode_latest.csv` | 79 | Latest episode pointer per legacy show |
| `seen_episode_latest.csv` | 9 | Additional legacy latest pointers |
| `user_statistics.csv` | 1 | Old aggregate counters |
| `stats-prod-cache.csv` | 6 | Mixed cached aggregate/statistical payloads |

The app currently imports v2 rows and uses the aggregate sources for comparison. Other allowlisted sources are available for future migrations but cannot override a v2 individual record.

## Observed inconsistencies

- The export spans at least two generations of the TV Time tracking system.
- `user_statistics.csv` reports only 5 watched episodes and `time_spent = 108152`, while the v2 export contains 6,120 individual episode rows.
- The v2 aggregate `total_series_runtime = 11278560` behaves as seconds, or 187,976 minutes. Its unit differs from per-episode `runtime`, which behaves as minutes.
- Only 3,040 of 6,120 v2 watch rows include a runtime. A per-series median is therefore retained as a fallback; missing values remain visible in reconciliation.
- There are 19 extra rows across series/season/episode coordinate collisions where multiple TVDB episode IDs occupy the same coordinate. These are not silently merged. They become unresolved records for manual matching.
- `created_at` has far fewer distinct values than watch rows because bulk watches share timestamps. A timestamp alone is not a safe identity key; the unique v2 `key` is used.
- Legacy followed datasets contain fewer shows than the v2/user-show datasets and can disagree on active/archive state.
- Specials are present and must remain outside normal-season completion.

## Deterministic rules

1. Accept unique v2 individual records before aggregates or legacy pointers.
2. Deduplicate on the source namespace plus v2 record key.
3. Keep both series TVDB ID and episode TVDB ID.
4. Inside a verified series, use a unique season/episode coordinate as the secondary episode match.
5. Use normalized title only as validation; do not attach conflicting IDs based on title.
6. Keep original parseable watch timestamps. If no date is recoverable, report the record unresolved.
7. Preserve row runtime; otherwise use the series median default; otherwise count zero minutes and report unknown runtime.
8. Store coordinate collisions as unresolved and require an explicit episode choice later.
9. Save the full import in one context transaction/save and retain an archive SHA-256 receipt.
10. Compare calculated episode/time totals with exported aggregates without changing the accepted individual history.
