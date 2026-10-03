import JSZip from "jszip";
import {
  type BackupManifest,
  type Episode,
  type LibraryPayload,
  type Show,
  type WatchEvent,
} from "./types";

const FORMAT = "com.tbtempo.backup";
const SCHEMA_VERSION = 1;
const MANIFEST_LIMIT = 1_000_000;
const DATA_LIMIT = 100_000_000;

function assertString(value: unknown, label: string): asserts value is string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Invalid backup: ${label} is missing.`);
  }
}

export function assertLibraryPayload(value: unknown): asserts value is LibraryPayload {
  if (!value || typeof value !== "object") throw new Error("Invalid backup data.");
  const payload = value as Partial<LibraryPayload>;
  if (!Array.isArray(payload.shows) || !payload.notificationSettings) {
    throw new Error("Invalid backup data.");
  }

  const showIDs = new Set<string>();
  const episodeIDs = new Set<string>();
  const eventKeys = new Set<string>();
  for (const show of payload.shows as Show[]) {
    assertString(show.id, "show ID");
    assertString(show.title, "show title");
    if (showIDs.has(show.id)) throw new Error("Invalid backup: duplicate show ID.");
    showIDs.add(show.id);
    if (!Array.isArray(show.episodes)) throw new Error("Invalid backup: episodes are missing.");
    for (const episode of show.episodes) {
      assertString(episode.id, "episode ID");
      if (episodeIDs.has(episode.id)) throw new Error("Invalid backup: duplicate episode ID.");
      episodeIDs.add(episode.id);
      if (!Array.isArray(episode.watchEvents)) throw new Error("Invalid backup: watch events are missing.");
      for (const event of episode.watchEvents) {
        assertString(event.stableKey, "watch-event key");
        if (eventKeys.has(event.stableKey)) throw new Error("Invalid backup: duplicate watch-event key.");
        eventKeys.add(event.stableKey);
      }
    }
  }
}

export async function readBackup(file: File): Promise<LibraryPayload> {
  const zip = await JSZip.loadAsync(await file.arrayBuffer());
  const manifestEntry = zip.file("manifest.json");
  const dataEntry = zip.file("data.json");
  if (!manifestEntry || !dataEntry) throw new Error("This is not a valid TB Tempo backup.");

  const [manifestText, dataText] = await Promise.all([
    manifestEntry.async("string"),
    dataEntry.async("string"),
  ]);
  if (manifestText.length > MANIFEST_LIMIT || dataText.length > DATA_LIMIT) {
    throw new Error("The backup is larger than the supported limit.");
  }

  const manifest = JSON.parse(manifestText) as BackupManifest;
  if (manifest.format !== FORMAT) throw new Error("This is not a TB Tempo backup.");
  if (manifest.schemaVersion !== SCHEMA_VERSION) {
    throw new Error(`Backup schema ${manifest.schemaVersion} is not supported.`);
  }
  if (!manifest.contents?.includes("manifest.json") || !manifest.contents.includes("data.json")) {
    throw new Error("The backup manifest is incomplete.");
  }

  const payload: unknown = JSON.parse(dataText);
  assertLibraryPayload(payload);
  return payload;
}

function mergeEvents(current: WatchEvent[], incoming: WatchEvent[], globalKeys: Set<string>): WatchEvent[] {
  const result = [...current];
  for (const event of incoming) {
    if (!globalKeys.has(event.stableKey)) {
      result.push({ ...event, source: "backup" });
      globalKeys.add(event.stableKey);
    }
  }
  return result;
}

function mergeEpisodes(current: Episode[], incoming: Episode[], globalKeys: Set<string>): Episode[] {
  const byID = new Map(current.map((episode) => [episode.id, episode]));
  for (const episode of incoming) {
    const existing = byID.get(episode.id);
    byID.set(
      episode.id,
      existing
        ? { ...existing, ...episode, watchEvents: mergeEvents(existing.watchEvents, episode.watchEvents, globalKeys) }
        : { ...episode, watchEvents: mergeEvents([], episode.watchEvents, globalKeys) },
    );
  }
  return [...byID.values()];
}

export function mergeLibraries(current: LibraryPayload, incoming: LibraryPayload): LibraryPayload {
  const globalKeys = new Set(
    current.shows.flatMap((show) => show.episodes.flatMap((episode) => episode.watchEvents.map((event) => event.stableKey))),
  );
  const byID = new Map(current.shows.map((show) => [show.id, show]));
  for (const show of incoming.shows) {
    const existing = byID.get(show.id);
    byID.set(
      show.id,
      existing
        ? { ...existing, ...show, episodes: mergeEpisodes(existing.episodes, show.episodes, globalKeys) }
        : { ...show, episodes: mergeEpisodes([], show.episodes, globalKeys) },
    );
  }
  return {
    shows: [...byID.values()],
    notificationSettings: incoming.notificationSettings,
  };
}

function isoSeconds(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) return value;
  return parsed.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function portablePayload(payload: LibraryPayload): LibraryPayload {
  return {
    ...payload,
    shows: payload.shows.map((show) => ({
      ...show,
      followedAt: isoSeconds(show.followedAt),
      lastActivityAt: isoSeconds(show.lastActivityAt),
      episodes: show.episodes.map((episode) => ({
        ...episode,
        airDate: isoSeconds(episode.airDate),
        watchEvents: episode.watchEvents.map((event) => ({
          ...event,
          watchedAt: isoSeconds(event.watchedAt) ?? event.watchedAt,
        })),
      })),
    })),
  };
}

function download(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export async function exportBackup(payload: LibraryPayload): Promise<void> {
  const createdAt = isoSeconds(new Date().toISOString())!;
  const manifest: BackupManifest = {
    format: FORMAT,
    schemaVersion: SCHEMA_VERSION,
    createdAt,
    appVersion: "web-0.1.0",
    contents: ["manifest.json", "data.json"],
  };
  const zip = new JSZip();
  zip.file("manifest.json", JSON.stringify(manifest, null, 2));
  zip.file("data.json", JSON.stringify(portablePayload(payload), null, 2));
  const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE" });
  download(blob, `TBTempo-${createdAt.slice(0, 10)}.tbtempo`);
}

function csvCell(value: string): string {
  return /[",\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
}

export function exportViewingHistory(payload: LibraryPayload): void {
  const rows = ["series,season,episode,episode_title,watched_at,runtime_minutes,source"];
  for (const show of [...payload.shows].sort((a, b) => a.title.localeCompare(b.title))) {
    for (const episode of [...show.episodes].sort(
      (a, b) => a.seasonNumber - b.seasonNumber || a.episodeNumber - b.episodeNumber,
    )) {
      for (const event of [...episode.watchEvents].sort((a, b) => a.watchedAt.localeCompare(b.watchedAt))) {
        rows.push(
          [
            show.title,
            String(episode.seasonNumber),
            String(episode.episodeNumber),
            episode.title,
            event.watchedAt,
            String(episode.runtimeMinutes ?? show.defaultRuntimeMinutes ?? ""),
            event.source,
          ]
            .map(csvCell)
            .join(","),
        );
      }
    }
  }
  download(new Blob([rows.join("\n")], { type: "text/csv;charset=utf-8" }), "TBTempo-viewing-history.csv");
}
