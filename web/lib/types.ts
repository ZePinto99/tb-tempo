export type LibraryState = "active" | "stopped" | "completed";
export type ShowStatus =
  | "Returning Series"
  | "Ended"
  | "Canceled"
  | "Planned"
  | "In Production"
  | "Pilot"
  | "Unknown";
export type AirDatePrecision = "dateOnly" | "dateTime" | "unknown";
export type WatchSource = "manual" | "tvTimeV2" | "tvTimeLegacy" | "backup";

export interface WatchEvent {
  stableKey: string;
  watchedAt: string;
  source: WatchSource;
  isEstimatedDate: boolean;
}

export interface Episode {
  id: string;
  seasonNumber: number;
  episodeNumber: number;
  title: string;
  overview: string;
  tmdbID?: number;
  tvdbID?: number;
  runtimeMinutes?: number;
  airDate?: string;
  airDatePrecision: AirDatePrecision;
  stillPath?: string;
  isSpecial: boolean;
  isCanceled: boolean;
  watchEvents: WatchEvent[];
}

export interface Show {
  id: string;
  title: string;
  overview: string;
  status: ShowStatus;
  libraryState: LibraryState;
  genres: string[];
  tmdbID?: number;
  tvdbID?: number;
  posterPath?: string;
  backdropPath?: string;
  defaultRuntimeMinutes?: number;
  followedAt?: string;
  lastActivityAt?: string;
  notificationsEnabled: boolean;
  episodes: Episode[];
}

export interface NotificationSettings {
  globalEnabled: boolean;
  hour: number;
  minute: number;
  horizonDays: number;
  rollingLimit: number;
}

export interface LibraryPayload {
  shows: Show[];
  notificationSettings: NotificationSettings;
}

export interface BackupManifest {
  format: "com.tbtempo.backup";
  schemaVersion: 1;
  createdAt: string;
  appVersion: string;
  contents: ["manifest.json", "data.json"] | string[];
}

export interface CatalogResult {
  id: number;
  title: string;
  overview: string;
  firstAirDate?: string;
  posterPath?: string;
}

export interface CatalogShow {
  tmdbID: number;
  tvdbID?: number;
  title: string;
  overview: string;
  status: ShowStatus;
  genres: string[];
  posterPath?: string;
  backdropPath?: string;
  defaultRuntimeMinutes?: number;
  episodes: Omit<Episode, "id" | "watchEvents">[];
}

export const EMPTY_LIBRARY: LibraryPayload = {
  shows: [],
  notificationSettings: {
    globalEnabled: false,
    hour: 9,
    minute: 0,
    horizonDays: 90,
    rollingLimit: 50,
  },
};
