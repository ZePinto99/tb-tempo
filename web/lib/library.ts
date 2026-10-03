import type { Episode, LibraryPayload, LibraryState, Show } from "./types";

export function regularEpisodes(show: Show): Episode[] {
  return show.episodes.filter((episode) => !episode.isSpecial);
}

export function watchedCount(show: Show): number {
  return regularEpisodes(show).filter((episode) => episode.watchEvents.length > 0).length;
}

export function libraryStateAfterProgress(show: Show, episodes: Episode[] = show.episodes): LibraryState {
  const regular = episodes.filter((episode) => !episode.isSpecial);
  const seriesIsFinished = show.status === "Ended" || show.status === "Canceled";
  const watchedEveryRegularEpisode =
    regular.length > 0 && regular.every((episode) => episode.watchEvents.length > 0);
  return seriesIsFinished && watchedEveryRegularEpisode ? "completed" : show.libraryState;
}

export function applyAutomaticCompletions(payload: LibraryPayload): LibraryPayload {
  let changed = false;
  const shows = payload.shows.map((show) => {
    const libraryState = libraryStateAfterProgress(show);
    if (libraryState === show.libraryState) return show;
    changed = true;
    return { ...show, libraryState };
  });
  return changed ? { ...payload, shows } : payload;
}

export function nextUp(show: Show): Episode | undefined {
  return regularEpisodes(show)
    .filter((episode) => episode.watchEvents.length === 0)
    .sort((a, b) => a.seasonNumber - b.seasonNumber || a.episodeNumber - b.episodeNumber)[0];
}

export function coordinate(episode: Episode): string {
  return `S${String(episode.seasonNumber).padStart(2, "0")}E${String(episode.episodeNumber).padStart(2, "0")}`;
}

export function imageURL(path: string | undefined, width = 500): string | undefined {
  return path ? `https://image.tmdb.org/t/p/w${width}${path}` : undefined;
}

export function totals(payload: LibraryPayload) {
  const pairs = payload.shows.flatMap((show) =>
    show.episodes.flatMap((episode) => episode.watchEvents.map((event) => ({ show, episode, event }))),
  );
  return {
    uniqueEpisodes: new Set(pairs.map(({ episode }) => episode.id)).size,
    watchEvents: pairs.length,
    minutes: pairs.reduce(
      (sum, { show, episode }) => sum + (episode.runtimeMinutes ?? show.defaultRuntimeMinutes ?? 0),
      0,
    ),
    unknownRuntime: pairs.filter(({ show, episode }) => episode.runtimeMinutes == null && show.defaultRuntimeMinutes == null)
      .length,
  };
}

export function duration(minutes: number): string {
  const days = Math.floor(minutes / 1_440);
  const hours = Math.floor((minutes % 1_440) / 60);
  const remainder = minutes % 60;
  return [days ? `${days}d` : "", hours ? `${hours}h` : "", `${remainder}m`].filter(Boolean).join(" ");
}

export function statsByShow(payload: LibraryPayload) {
  return payload.shows
    .map((show) => {
      const events = show.episodes.flatMap((episode) =>
        episode.watchEvents.map(() => episode.runtimeMinutes ?? show.defaultRuntimeMinutes ?? 0),
      );
      return { id: show.id, title: show.title, events: events.length, minutes: events.reduce((a, b) => a + b, 0) };
    })
    .filter((row) => row.events > 0)
    .sort((a, b) => b.minutes - a.minutes);
}
