import type { CatalogResult, CatalogShow, ShowStatus } from "./types";

const API_ROOT = "https://api.themoviedb.org/3";

function token(): string {
  const value = process.env.TMDB_READ_ACCESS_TOKEN?.trim();
  if (!value || value === "paste_your_personal_read_access_token_here") {
    throw new Error("TMDB is not configured. Add TMDB_READ_ACCESS_TOKEN to web/.env.local.");
  }
  return value;
}

async function request<T>(path: string, search: Record<string, string> = {}): Promise<T> {
  const url = new URL(`${API_ROOT}${path}`);
  Object.entries(search).forEach(([key, value]) => url.searchParams.set(key, value));
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token()}`, Accept: "application/json" },
    next: { revalidate: 3_600 },
  });
  if (!response.ok) {
    const detail = (await response.json().catch(() => null)) as { status_message?: string } | null;
    throw new Error(detail?.status_message ?? `TMDB returned ${response.status}.`);
  }
  return response.json() as Promise<T>;
}

function optional<T>(value: T | null | undefined): T | undefined {
  return value ?? undefined;
}

function airDate(value: string | null | undefined): string | undefined {
  return value ? `${value}T12:00:00Z` : undefined;
}

function showStatus(value: string): ShowStatus {
  const supported: ShowStatus[] = [
    "Returning Series",
    "Ended",
    "Canceled",
    "Planned",
    "In Production",
    "Pilot",
    "Unknown",
  ];
  return supported.includes(value as ShowStatus) ? (value as ShowStatus) : "Unknown";
}

interface SearchResponse {
  results: Array<{
    id: number;
    name: string;
    overview: string;
    first_air_date?: string;
    poster_path?: string | null;
  }>;
}

interface ShowResponse {
  id: number;
  name: string;
  overview: string;
  status: string;
  genres: Array<{ name: string }>;
  poster_path?: string | null;
  backdrop_path?: string | null;
  episode_run_time: number[];
  seasons: Array<{ season_number: number }>;
  external_ids?: { tvdb_id?: number | null };
}

interface SeasonResponse {
  episodes: Array<{
    id: number;
    name: string;
    overview: string;
    season_number: number;
    episode_number: number;
    runtime?: number | null;
    air_date?: string | null;
    still_path?: string | null;
  }>;
}

export async function searchCatalog(query: string, language: string): Promise<CatalogResult[]> {
  const data = await request<SearchResponse>("/search/tv", {
    query,
    include_adult: "false",
    language,
  });
  return data.results.map((item) => ({
    id: item.id,
    title: item.name,
    overview: item.overview,
    firstAirDate: optional(item.first_air_date),
    posterPath: optional(item.poster_path),
  }));
}

export async function catalogShow(id: number, language: string): Promise<CatalogShow> {
  const detail = await request<ShowResponse>(`/tv/${id}`, {
    append_to_response: "external_ids",
    language,
  });
  const seasons = await Promise.all(
    detail.seasons
      .filter((season) => season.season_number >= 0)
      .map((season) => request<SeasonResponse>(`/tv/${id}/season/${season.season_number}`, { language })),
  );
  return {
    tmdbID: detail.id,
    tvdbID: optional(detail.external_ids?.tvdb_id),
    title: detail.name,
    overview: detail.overview,
    status: showStatus(detail.status),
    genres: detail.genres.map((genre) => genre.name),
    posterPath: optional(detail.poster_path),
    backdropPath: optional(detail.backdrop_path),
    defaultRuntimeMinutes: optional(detail.episode_run_time[0]),
    episodes: seasons.flatMap((season) =>
      season.episodes.map((episode) => ({
        seasonNumber: episode.season_number,
        episodeNumber: episode.episode_number,
        title: episode.name,
        overview: episode.overview,
        tmdbID: episode.id,
        runtimeMinutes: optional(episode.runtime),
        airDate: airDate(episode.air_date),
        airDatePrecision: episode.air_date ? ("dateOnly" as const) : ("unknown" as const),
        stillPath: optional(episode.still_path),
        isSpecial: episode.season_number === 0,
        isCanceled: false,
      })),
    ),
  };
}
