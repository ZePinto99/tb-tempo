import JSZip from "jszip";
import { describe, expect, it } from "vitest";
import { mergeLibraries, readBackup } from "./backup";
import { EMPTY_LIBRARY, type LibraryPayload, type Show } from "./types";

function show(eventKey = "event:one"): Show {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    title: "Example Show",
    overview: "A fixture.",
    status: "Returning Series",
    libraryState: "active",
    genres: ["Drama"],
    tmdbID: 42,
    followedAt: "2026-10-02T12:00:00Z",
    notificationsEnabled: true,
    episodes: [
      {
        id: "22222222-2222-4222-8222-222222222222",
        seasonNumber: 1,
        episodeNumber: 1,
        title: "Pilot",
        overview: "The beginning.",
        runtimeMinutes: 45,
        airDatePrecision: "dateOnly",
        isSpecial: false,
        isCanceled: false,
        watchEvents: [
          {
            stableKey: eventKey,
            watchedAt: "2026-10-02T20:00:00Z",
            source: "manual",
            isEstimatedDate: false,
          },
        ],
      },
    ],
  };
}

function payload(item = show()): LibraryPayload {
  return { ...structuredClone(EMPTY_LIBRARY), shows: [item] };
}

async function backupFile(
  data: LibraryPayload,
  name = "fixture.tbtempo",
  type = "application/zip",
): Promise<File> {
  const zip = new JSZip();
  zip.file(
    "manifest.json",
    JSON.stringify({
      format: "com.tbtempo.backup",
      schemaVersion: 1,
      createdAt: "2026-10-02T20:00:00Z",
      appVersion: "test",
      contents: ["manifest.json", "data.json"],
    }),
  );
  zip.file("data.json", JSON.stringify(data));
  const bytes = await zip.generateAsync({ type: "arraybuffer" });
  return new File([bytes], name, { type });
}

describe("TB Tempo backup compatibility", () => {
  it("reads a schema 1 .tbtempo package", async () => {
    const restored = await readBackup(await backupFile(payload()));
    expect(restored.shows[0].episodes[0].watchEvents[0].stableKey).toBe("event:one");
  });

  it("validates backup contents even when iPhone labels the file as a ZIP", async () => {
    const restored = await readBackup(await backupFile(payload(), "fixture.zip", "application/octet-stream"));
    expect(restored.shows).toHaveLength(1);
  });

  it("merges idempotently by stable event key", () => {
    const current = payload();
    const incomingShow = show("event:two");
    incomingShow.title = "Updated title";
    const once = mergeLibraries(current, payload(incomingShow));
    const twice = mergeLibraries(once, payload(incomingShow));
    expect(twice.shows[0].title).toBe("Updated title");
    expect(twice.shows[0].episodes[0].watchEvents).toHaveLength(2);
    expect(twice.shows[0].episodes[0].watchEvents[1].source).toBe("backup");
  });

  it("rejects duplicate event keys before import", async () => {
    const invalid = payload();
    invalid.shows[0].episodes.push({
      ...structuredClone(invalid.shows[0].episodes[0]),
      id: "33333333-3333-4333-8333-333333333333",
    });
    await expect(readBackup(await backupFile(invalid))).rejects.toThrow("duplicate watch-event key");
  });
});
