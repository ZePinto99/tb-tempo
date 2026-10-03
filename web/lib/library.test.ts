import { describe, expect, it } from "vitest";
import { applyAutomaticCompletions, libraryStateAfterProgress } from "./library";
import { EMPTY_LIBRARY } from "./types";
import type { Episode, Show } from "./types";

function episode(id: string, options: { watched?: boolean; special?: boolean } = {}): Episode {
  return {
    id,
    seasonNumber: options.special ? 0 : 1,
    episodeNumber: Number(id),
    title: `Episode ${id}`,
    overview: "",
    airDatePrecision: "unknown",
    isSpecial: options.special ?? false,
    isCanceled: false,
    watchEvents: options.watched
      ? [{ stableKey: `watch:${id}`, watchedAt: "2026-10-03T00:00:00Z", source: "manual", isEstimatedDate: false }]
      : [],
  };
}

function show(episodes: Episode[], libraryState: Show["libraryState"] = "active"): Show {
  return {
    id: "show:one",
    title: "Example Show",
    overview: "",
    status: "Ended",
    libraryState,
    genres: [],
    notificationsEnabled: true,
    episodes,
  };
}

describe("automatic show completion", () => {
  it("completes a show when every regular episode is watched", () => {
    const item = show([episode("1", { watched: true }), episode("2", { watched: true })]);
    expect(libraryStateAfterProgress(item)).toBe("completed");
  });

  it("ignores unwatched specials when deciding completion", () => {
    const item = show([
      episode("1", { watched: true }),
      episode("2", { watched: true }),
      episode("3", { special: true }),
    ]);
    expect(libraryStateAfterProgress(item)).toBe("completed");
  });

  it("does not complete a show with an unwatched regular episode", () => {
    const item = show([episode("1", { watched: true }), episode("2")]);
    expect(libraryStateAfterProgress(item)).toBe("active");
  });

  it("does not complete a show that only has specials", () => {
    const item = show([episode("1", { watched: true, special: true })]);
    expect(libraryStateAfterProgress(item)).toBe("active");
  });

  it("keeps a returning series active when it is caught up", () => {
    const item = show([episode("1", { watched: true })]);
    item.status = "Returning Series";
    expect(libraryStateAfterProgress(item)).toBe("active");
  });

  it("preserves an existing completed state when progress is cleared", () => {
    const item = show([episode("1")], "completed");
    expect(libraryStateAfterProgress(item)).toBe("completed");
  });

  it("repairs finished, fully watched shows when a library is loaded", () => {
    const ended = show([episode("1", { watched: true }), episode("2", { special: true })]);
    const returning = show([episode("3", { watched: true })]);
    returning.id = "show:two";
    returning.status = "Returning Series";

    const result = applyAutomaticCompletions({ ...structuredClone(EMPTY_LIBRARY), shows: [ended, returning] });

    expect(result.shows.map((item) => item.libraryState)).toEqual(["completed", "active"]);
  });
});
