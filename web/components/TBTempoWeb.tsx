"use client";

import Image from "next/image";
import { useEffect, useMemo, useRef, useState } from "react";
import { exportBackup, exportViewingHistory, mergeLibraries, readBackup } from "@/lib/backup";
import {
  coordinate,
  duration,
  imageURL,
  nextUp,
  regularEpisodes,
  statsByShow,
  totals,
  watchedCount,
} from "@/lib/library";
import { loadLibrary, saveLibrary } from "@/lib/storage";
import {
  EMPTY_LIBRARY,
  type CatalogResult,
  type CatalogShow,
  type Episode,
  type LibraryPayload,
  type LibraryState,
  type Show,
} from "@/lib/types";

type Tab = "today" | "upcoming" | "shows" | "statistics" | "settings";
type ImportMode = "merge" | "replace";

const NAVIGATION: Array<{ id: Tab; label: string; symbol: string }> = [
  { id: "today", label: "Today", symbol: "✦" },
  { id: "upcoming", label: "Upcoming", symbol: "◷" },
  { id: "shows", label: "Shows", symbol: "▤" },
  { id: "statistics", label: "Statistics", symbol: "▥" },
  { id: "settings", label: "Settings", symbol: "⚙" },
];

function cloneEmpty(): LibraryPayload {
  return structuredClone(EMPTY_LIBRARY);
}

function sortEpisodes(episodes: Episode[]): Episode[] {
  return [...episodes].sort(
    (a, b) => a.seasonNumber - b.seasonNumber || a.episodeNumber - b.episodeNumber,
  );
}

function formatDate(value: string | undefined, options?: Intl.DateTimeFormatOptions): string {
  if (!value) return "Date not confirmed";
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "Date not confirmed";
  return new Intl.DateTimeFormat(undefined, options ?? { month: "short", day: "numeric" }).format(date);
}

function dayStart(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function relativeRelease(value: string | undefined): string {
  if (!value) return "Date not confirmed";
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "Date not confirmed";
  const days = Math.round((dayStart(date).valueOf() - dayStart(new Date()).valueOf()) / 86_400_000);
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days > 1) return `In ${days} days`;
  if (days === -1) return "Yesterday";
  return "Released";
}

function pageDescription(tab: Tab): string {
  switch (tab) {
    case "today":
      return "Pick up exactly where you left off.";
    case "upcoming":
      return "Your followed series, in release order.";
    case "shows":
      return "Everything you follow, all in one place.";
    case "statistics":
      return "Your viewing rhythm, without the noise.";
    case "settings":
      return "Your data stays yours.";
  }
}

function Poster({ show, priority = false }: { show: Show; priority?: boolean }) {
  const source = imageURL(show.posterPath);
  return (
    <div className="poster">
      {source ? (
        <Image src={source} alt={`${show.title} poster`} fill sizes="(max-width: 720px) 42vw, 190px" priority={priority} />
      ) : (
        <div className="posterFallback" aria-hidden="true">
          <span>TB</span>
          <small>{show.title}</small>
        </div>
      )}
      <div className="posterShade" />
    </div>
  );
}

function ProgressBar({ show }: { show: Show }) {
  const total = regularEpisodes(show).length;
  const watched = watchedCount(show);
  const percent = total ? Math.round((watched / total) * 100) : 0;
  return (
    <div className="progressBlock" aria-label={`${watched} of ${total} episodes watched`}>
      <div className="progressTrack">
        <span style={{ width: `${percent}%` }} />
      </div>
      <small>
        {watched}/{total} · {percent}%
      </small>
    </div>
  );
}

function EmptyState({ onAdd, onImport }: { onAdd: () => void; onImport: () => void }) {
  return (
    <section className="emptyState panel">
      <div className="emptyOrb" aria-hidden="true">
        <span>▶</span>
      </div>
      <p className="eyebrow">Your library is quiet</p>
      <h2>Your next episode starts here.</h2>
      <p>Follow a series from TMDB, or bring over the library you already built in the iPhone app.</p>
      <div className="buttonRow centered">
        <button className="button primary" onClick={onAdd}>Find a series</button>
        <button className="button secondary" onClick={onImport}>Import backup</button>
      </div>
    </section>
  );
}

function EpisodeRow({
  show,
  episode,
  onToggle,
  onOpen,
  date,
}: {
  show: Show;
  episode: Episode;
  onToggle: () => void;
  onOpen: () => void;
  date?: boolean;
}) {
  const watched = episode.watchEvents.length > 0;
  return (
    <article className={`episodeRow ${watched ? "watched" : ""}`}>
      <button className="episodeMain" onClick={onOpen} aria-label={`Open ${show.title}`}>
        <div className="episodeArtwork">
          {imageURL(episode.stillPath, 500) ? (
            <Image
              src={imageURL(episode.stillPath, 500)!}
              alt=""
              fill
              sizes="112px"
            />
          ) : (
            <span aria-hidden="true">▶</span>
          )}
        </div>
        <div className="episodeCopy">
          <span className="episodeMeta">
            {show.title} · {coordinate(episode)}
          </span>
          <strong>{episode.title || "Untitled episode"}</strong>
          <small>{date ? `${relativeRelease(episode.airDate)} · ${formatDate(episode.airDate)}` : "Next in your queue"}</small>
        </div>
      </button>
      <button
        className={`watchButton ${watched ? "isWatched" : ""}`}
        onClick={onToggle}
        aria-label={watched ? `Mark ${episode.title} unwatched` : `Mark ${episode.title} watched`}
        title={watched ? "Mark unwatched" : "Mark watched"}
      >
        {watched ? "✓" : "○"}
      </button>
    </article>
  );
}

function TodayPage({
  library,
  onAdd,
  onImport,
  onOpenShow,
  onToggle,
}: {
  library: LibraryPayload;
  onAdd: () => void;
  onImport: () => void;
  onOpenShow: (id: string) => void;
  onToggle: (showID: string, episodeID: string) => void;
}) {
  if (library.shows.length === 0) return <EmptyState onAdd={onAdd} onImport={onImport} />;

  const active = library.shows.filter((show) => show.libraryState === "active");
  const queue = active
    .map((show) => ({ show, episode: nextUp(show) }))
    .filter((item): item is { show: Show; episode: Episode } => Boolean(item.episode))
    .sort((a, b) => (b.show.lastActivityAt ?? "").localeCompare(a.show.lastActivityAt ?? ""));
  const recent = library.shows
    .flatMap((show) =>
      show.episodes.flatMap((episode) =>
        episode.watchEvents.map((event) => ({ show, episode, watchedAt: event.watchedAt })),
      ),
    )
    .sort((a, b) => b.watchedAt.localeCompare(a.watchedAt))
    .slice(0, 5);

  return (
    <div className="pageStack">
      {queue.length > 0 && (
        <section>
          <div className="sectionHeading">
            <div><p className="eyebrow">Keep your rhythm</p><h2>Next up</h2></div>
            <span>{queue.length} waiting</span>
          </div>
          <div className="episodeList panel">
            {queue.slice(0, 8).map(({ show, episode }) => (
              <EpisodeRow
                key={episode.id}
                show={show}
                episode={episode}
                onOpen={() => onOpenShow(show.id)}
                onToggle={() => onToggle(show.id, episode.id)}
              />
            ))}
          </div>
        </section>
      )}

      {active.length > 0 && (
        <section>
          <div className="sectionHeading">
            <div><p className="eyebrow">Your current rotation</p><h2>Active series</h2></div>
          </div>
          <div className="posterRail">
            {active.map((show, index) => (
              <button className="showTile" key={show.id} onClick={() => onOpenShow(show.id)}>
                <Poster show={show} priority={index < 3} />
                <strong>{show.title}</strong>
                <ProgressBar show={show} />
              </button>
            ))}
          </div>
        </section>
      )}

      {recent.length > 0 && (
        <section>
          <div className="sectionHeading"><div><p className="eyebrow">A little rewind</p><h2>Recently watched</h2></div></div>
          <div className="episodeList panel compact">
            {recent.map(({ show, episode, watchedAt }) => (
              <EpisodeRow
                key={`${episode.id}-${watchedAt}`}
                show={show}
                episode={episode}
                onOpen={() => onOpenShow(show.id)}
                onToggle={() => onToggle(show.id, episode.id)}
              />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function UpcomingPage({
  library,
  onOpenShow,
  onToggle,
}: {
  library: LibraryPayload;
  onOpenShow: (id: string) => void;
  onToggle: (showID: string, episodeID: string) => void;
}) {
  const today = dayStart(new Date()).valueOf();
  const upcoming = library.shows
    .filter((show) => show.libraryState === "active")
    .flatMap((show) =>
      show.episodes
        .filter((episode) => {
          const time = episode.airDate ? dayStart(new Date(episode.airDate)).valueOf() : Number.NaN;
          return !episode.isCanceled && episode.watchEvents.length === 0 && time >= today;
        })
        .map((episode) => ({ show, episode })),
    )
    .sort((a, b) => (a.episode.airDate ?? "").localeCompare(b.episode.airDate ?? ""));

  if (upcoming.length === 0) {
    return (
      <section className="emptyState panel smallEmpty">
        <div className="emptyOrb calendarOrb" aria-hidden="true">◷</div>
        <h2>No confirmed releases yet.</h2>
        <p>Future episodes from active shows will appear here after metadata is available.</p>
      </section>
    );
  }

  const groups = new Map<string, typeof upcoming>();
  for (const item of upcoming) {
    const key = formatDate(item.episode.airDate, { weekday: "long", month: "long", day: "numeric" });
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }
  return (
    <div className="pageStack">
      {[...groups.entries()].map(([label, items]) => (
        <section key={label}>
          <div className="dateHeading">
            <h2>{label}</h2>
            <span>{relativeRelease(items[0].episode.airDate)}</span>
          </div>
          <div className="episodeList panel">
            {items.map(({ show, episode }) => (
              <EpisodeRow
                key={episode.id}
                show={show}
                episode={episode}
                date
                onOpen={() => onOpenShow(show.id)}
                onToggle={() => onToggle(show.id, episode.id)}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function ShowsPage({ library, onOpenShow }: { library: LibraryPayload; onOpenShow: (id: string) => void }) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<LibraryState | "all">("all");
  const shows = library.shows
    .filter((show) => filter === "all" || show.libraryState === filter)
    .filter((show) => show.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))
    .sort((a, b) => a.title.localeCompare(b.title));
  return (
    <div className="pageStack">
      <div className="libraryTools">
        <label className="searchField">
          <span aria-hidden="true">⌕</span>
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search your shows" />
        </label>
        <div className="filterPills" aria-label="Filter shows">
          {(["all", "active", "stopped", "completed"] as const).map((value) => (
            <button key={value} className={filter === value ? "selected" : ""} onClick={() => setFilter(value)}>
              {value[0].toUpperCase() + value.slice(1)}
            </button>
          ))}
        </div>
      </div>
      {shows.length ? (
        <div className="showGrid">
          {shows.map((show, index) => (
            <button className="libraryCard" key={show.id} onClick={() => onOpenShow(show.id)}>
              <Poster show={show} priority={index < 4} />
              <div className="libraryCardCopy">
                <span className={`stateDot ${show.libraryState}`} />
                <strong>{show.title}</strong>
                <ProgressBar show={show} />
              </div>
            </button>
          ))}
        </div>
      ) : (
        <div className="noResults panel"><span>⌕</span><h2>No matching shows</h2><p>Try another title or filter.</p></div>
      )}
    </div>
  );
}

function StatisticsPage({ library }: { library: LibraryPayload }) {
  const summary = totals(library);
  const rows = statsByShow(library);
  const maxMinutes = Math.max(...rows.map((row) => row.minutes), 1);
  return (
    <div className="pageStack">
      <div className="metricGrid">
        <article className="metricCard coral"><span>✓</span><strong>{summary.uniqueEpisodes.toLocaleString()}</strong><small>episodes watched</small></article>
        <article className="metricCard plum"><span>◷</span><strong>{duration(summary.minutes)}</strong><small>viewing time</small></article>
        <article className="metricCard gold"><span>↻</span><strong>{Math.max(0, summary.watchEvents - summary.uniqueEpisodes)}</strong><small>rewatches</small></article>
      </div>
      {summary.unknownRuntime > 0 && <p className="infoLine">ⓘ {summary.unknownRuntime} watch events have unknown runtime and add zero minutes.</p>}
      <section>
        <div className="sectionHeading"><div><p className="eyebrow">Where the time went</p><h2>By series</h2></div></div>
        {rows.length ? (
          <div className="statsList panel">
            {rows.map((row, index) => (
              <article key={row.id} className="statsRow">
                <span className="rank">{String(index + 1).padStart(2, "0")}</span>
                <div className="statName"><strong>{row.title}</strong><small>{row.events} watch {row.events === 1 ? "event" : "events"}</small></div>
                <div className="statBar"><span style={{ width: `${Math.max(4, (row.minutes / maxMinutes) * 100)}%` }} /></div>
                <strong className="statTime">{duration(row.minutes)}</strong>
              </article>
            ))}
          </div>
        ) : (
          <div className="noResults panel"><span>▥</span><h2>No viewing history yet</h2><p>Watched episodes will shape this page.</p></div>
        )}
      </section>
    </div>
  );
}

function SettingsPage({
  library,
  importMode,
  setImportMode,
  onImport,
}: {
  library: LibraryPayload;
  importMode: ImportMode;
  setImportMode: (mode: ImportMode) => void;
  onImport: (file: File) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const episodeCount = library.shows.reduce((sum, show) => sum + show.episodes.length, 0);
  const watchCount = library.shows.reduce(
    (sum, show) => sum + show.episodes.reduce((episodeSum, episode) => episodeSum + episode.watchEvents.length, 0),
    0,
  );
  return (
    <div className="settingsGrid">
      <section className="settingsCard panel dataCard">
        <div className="settingsIcon">↗</div>
        <p className="eyebrow">Move without lock-in</p>
        <h2>Backup & transfer</h2>
        <p>Backups use the same format as the native iPhone app. Export here and import there—or the other way around.</p>
        <div className="libraryNumbers">
          <div><strong>{library.shows.length}</strong><span>shows</span></div>
          <div><strong>{episodeCount}</strong><span>episodes</span></div>
          <div><strong>{watchCount}</strong><span>watches</span></div>
        </div>
        <div className="buttonStack">
          <button className="button primary" onClick={() => void exportBackup(library)}>Export .tbtempo backup</button>
          <button className="button secondary" onClick={() => exportViewingHistory(library)}>Export viewing-history CSV</button>
        </div>
      </section>

      <section className="settingsCard panel">
        <div className="settingsIcon soft">↓</div>
        <p className="eyebrow">Bring your library in</p>
        <h2>Import a backup</h2>
        <p>Choose a TB Tempo backup. On iPhone, Files may label it as a ZIP; the package is validated completely before your local library changes.</p>
        <div className="modePicker" role="group" aria-label="Import behavior">
          <button className={importMode === "merge" ? "selected" : ""} onClick={() => setImportMode("merge")}><strong>Merge</strong><small>Keep local data</small></button>
          <button className={importMode === "replace" ? "selected" : ""} onClick={() => setImportMode("replace")}><strong>Replace</strong><small>Use backup only</small></button>
        </div>
        <input
          ref={input}
          type="file"
          aria-label="TB Tempo backup file"
          hidden
          onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) onImport(file);
            event.target.value = "";
          }}
        />
        <button className="button secondary full" onClick={() => input.current?.click()}>Choose backup file</button>
      </section>

      <section className="settingsCard panel installCard">
        <div className="settingsIcon soft">＋</div>
        <p className="eyebrow">Website, meet home screen</p>
        <h2>Install as an app</h2>
        <p>On iPhone, open this site in Safari, tap Share, then choose <strong>Add to Home Screen</strong>. Your library remains in this browser’s private storage.</p>
        <div className="privacyNote"><span>◉</span><div><strong>Local-first</strong><small>No account, analytics, ads, or cloud database.</small></div></div>
      </section>
    </div>
  );
}

function ShowDetail({
  show,
  onBack,
  onToggle,
  onSetSeason,
  onState,
}: {
  show: Show;
  onBack: () => void;
  onToggle: (episodeID: string) => void;
  onSetSeason: (season: number, watched: boolean) => void;
  onState: (state: LibraryState) => void;
}) {
  const seasons = [...new Set(show.episodes.map((episode) => episode.seasonNumber))].sort((a, b) => a - b);
  const [season, setSeason] = useState(seasons.find((value) => value > 0) ?? seasons[0] ?? 0);
  const episodes = sortEpisodes(show.episodes.filter((episode) => episode.seasonNumber === season));
  const backdrop = imageURL(show.backdropPath, 780);
  return (
    <div className="detailPage">
      <button className="backButton" onClick={onBack}>← Back to library</button>
      <section className="detailHero">
        {backdrop && <Image className="backdrop" src={backdrop} alt="" fill sizes="100vw" priority />}
        <div className="detailWash" />
        <div className="detailPoster"><Poster show={show} priority /></div>
        <div className="detailCopy">
          <p className="eyebrow">{show.status} · {show.genres.slice(0, 2).join(" / ") || "Series"}</p>
          <h1>{show.title}</h1>
          <p>{show.overview || "No synopsis available yet."}</p>
          <ProgressBar show={show} />
          <label className="stateSelect">Library state
            <select value={show.libraryState} onChange={(event) => onState(event.target.value as LibraryState)}>
              <option value="active">Active</option><option value="stopped">Stopped</option><option value="completed">Completed</option>
            </select>
          </label>
        </div>
      </section>
      <section className="seasonSection">
        <div className="seasonToolbar">
          <div className="seasonTabs" role="tablist" aria-label="Seasons">
            {seasons.map((value) => <button role="tab" aria-selected={season === value} className={season === value ? "selected" : ""} key={value} onClick={() => setSeason(value)}>{value === 0 ? "Specials" : `Season ${value}`}</button>)}
          </div>
          <div className="seasonActions">
            <button onClick={() => onSetSeason(season, true)}>Mark all watched</button>
            <button onClick={() => onSetSeason(season, false)}>Clear season</button>
          </div>
        </div>
        <div className="detailEpisodes panel">
          {episodes.map((episode) => {
            const watched = episode.watchEvents.length > 0;
            return (
              <article className={`detailEpisode ${watched ? "watched" : ""}`} key={episode.id}>
                <button className={`watchButton ${watched ? "isWatched" : ""}`} onClick={() => onToggle(episode.id)}>{watched ? "✓" : "○"}</button>
                <span className="episodeNumber">{String(episode.episodeNumber).padStart(2, "0")}</span>
                <div><strong>{episode.title || "Untitled episode"}</strong><p>{episode.overview || "No synopsis available."}</p><small>{formatDate(episode.airDate)}{episode.runtimeMinutes ? ` · ${episode.runtimeMinutes} min` : ""}</small></div>
              </article>
            );
          })}
        </div>
      </section>
    </div>
  );
}

function AddShowDialog({ onClose, onAdd, existing }: { onClose: () => void; onAdd: (show: CatalogShow) => void; existing: Set<number> }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<CatalogResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState<number>();
  const [error, setError] = useState("");

  async function search(event: React.FormEvent) {
    event.preventDefault();
    if (query.trim().length < 2) return;
    setBusy(true); setError("");
    try {
      const response = await fetch(`/api/catalog/search?q=${encodeURIComponent(query.trim())}&language=${encodeURIComponent(navigator.language)}`);
      const data = (await response.json()) as { results?: CatalogResult[]; error?: string };
      if (!response.ok) throw new Error(data.error ?? "Search failed.");
      setResults(data.results ?? []);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Search failed.");
    } finally {
      setBusy(false);
    }
  }

  async function add(result: CatalogResult) {
    setAdding(result.id); setError("");
    try {
      const response = await fetch(`/api/catalog/shows/${result.id}?language=${encodeURIComponent(navigator.language)}`);
      const data = (await response.json()) as CatalogShow & { error?: string };
      if (!response.ok) throw new Error(data.error ?? "Unable to add that series.");
      onAdd(data);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to add that series.");
    } finally {
      setAdding(undefined);
    }
  }

  return (
    <div className="dialogBackdrop" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="add-show-title">
        <div className="dialogHeader"><div><p className="eyebrow">Powered by TMDB</p><h2 id="add-show-title">Find a series</h2></div><button className="closeButton" onClick={onClose} aria-label="Close">×</button></div>
        <form className="catalogSearch" onSubmit={search}><input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Severance, The Bear, Dark…" /><button className="button primary" disabled={busy}>{busy ? "Searching…" : "Search"}</button></form>
        {error && <p className="errorBanner">{error}</p>}
        {!results.length && !busy && !error && <div className="searchPrompt"><span>⌕</span><p>Search TMDB, then add full seasons and episode metadata to your local library.</p></div>}
        <div className="catalogResults">
          {results.map((result) => {
            const alreadyAdded = existing.has(result.id);
            return (
              <article key={result.id} className="catalogResult">
                <div className="searchPoster">{imageURL(result.posterPath, 300) ? <Image src={imageURL(result.posterPath, 300)!} alt="" fill sizes="64px" /> : <span>TB</span>}</div>
                <div><strong>{result.title}</strong><small>{result.firstAirDate?.slice(0, 4) ?? "Year unknown"}</small><p>{result.overview || "No synopsis available."}</p></div>
                <button className="button secondary" disabled={alreadyAdded || adding === result.id} onClick={() => void add(result)}>{alreadyAdded ? "Added" : adding === result.id ? "Adding…" : "Add"}</button>
              </article>
            );
          })}
        </div>
      </section>
    </div>
  );
}

export function TBTempoWeb() {
  const [library, setLibrary] = useState<LibraryPayload>(cloneEmpty);
  const [ready, setReady] = useState(false);
  const [tab, setTab] = useState<Tab>("today");
  const [selectedShowID, setSelectedShowID] = useState<string>();
  const [showAdd, setShowAdd] = useState(false);
  const [importMode, setImportMode] = useState<ImportMode>("merge");
  const [notice, setNotice] = useState<string>();
  const [undo, setUndo] = useState<LibraryPayload>();
  const saveTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    let active = true;
    loadLibrary()
      .then((stored) => { if (active) { setLibrary(stored); setReady(true); } })
      .catch((error: unknown) => { if (active) { setNotice(error instanceof Error ? error.message : "Unable to load local data."); setReady(true); } });
    if (process.env.NODE_ENV === "production" && "serviceWorker" in navigator) {
      void navigator.serviceWorker.register("/sw.js");
    }
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!ready) return;
    clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      void saveLibrary(library).catch((error: unknown) => setNotice(error instanceof Error ? error.message : "Unable to save."));
    }, 180);
    return () => clearTimeout(saveTimer.current);
  }, [library, ready]);

  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => {
      setNotice(undefined);
      setUndo(undefined);
    }, 5_000);
    return () => clearTimeout(timer);
  }, [notice]);

  const selectedShow = library.shows.find((show) => show.id === selectedShowID);
  const existingTMDB = useMemo(
    () => new Set(library.shows.map((show) => show.tmdbID).filter((id): id is number => id != null)),
    [library.shows],
  );

  function commit(transform: (current: LibraryPayload) => LibraryPayload, message: string) {
    setUndo(structuredClone(library));
    setLibrary(transform(library));
    setNotice(message);
  }

  function toggleEpisode(showID: string, episodeID: string) {
    commit(
      (current) => ({
        ...current,
        shows: current.shows.map((show) => {
          if (show.id !== showID) return show;
          const now = new Date().toISOString();
          return {
            ...show,
            lastActivityAt: now,
            episodes: show.episodes.map((episode) => {
              if (episode.id !== episodeID) return episode;
              return {
                ...episode,
                watchEvents: episode.watchEvents.length
                  ? []
                  : [{ stableKey: `manual:web:${crypto.randomUUID()}`, watchedAt: now, source: "manual", isEstimatedDate: false }],
              };
            }),
          };
        }),
      }),
      "Progress updated",
    );
  }

  function setSeason(showID: string, season: number, watched: boolean) {
    commit(
      (current) => ({
        ...current,
        shows: current.shows.map((show) => {
          if (show.id !== showID) return show;
          const now = new Date().toISOString();
          return {
            ...show,
            lastActivityAt: now,
            episodes: show.episodes.map((episode) =>
              episode.seasonNumber !== season
                ? episode
                : {
                    ...episode,
                    watchEvents: watched
                      ? episode.watchEvents.length
                        ? episode.watchEvents
                        : [{ stableKey: `manual:web:${crypto.randomUUID()}`, watchedAt: now, source: "manual", isEstimatedDate: false }]
                      : [],
                  },
            ),
          };
        }),
      }),
      watched ? "Season marked watched" : "Season cleared",
    );
  }

  function setShowState(showID: string, state: LibraryState) {
    setLibrary((current) => ({
      ...current,
      shows: current.shows.map((show) => (show.id === showID ? { ...show, libraryState: state } : show)),
    }));
    setNotice("Library state updated");
  }

  function addCatalogShow(item: CatalogShow) {
    const now = new Date().toISOString();
    const show: Show = {
      id: crypto.randomUUID(),
      title: item.title,
      overview: item.overview,
      status: item.status,
      libraryState: "active",
      genres: item.genres,
      tmdbID: item.tmdbID,
      tvdbID: item.tvdbID,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      defaultRuntimeMinutes: item.defaultRuntimeMinutes,
      followedAt: now,
      lastActivityAt: now,
      notificationsEnabled: true,
      episodes: item.episodes.map((episode) => ({ ...episode, id: crypto.randomUUID(), watchEvents: [] })),
    };
    setLibrary((current) => ({ ...current, shows: [...current.shows, show] }));
    setShowAdd(false);
    setSelectedShowID(show.id);
    setNotice(`${show.title} added`);
  }

  async function importFile(file: File) {
    try {
      const incoming = await readBackup(file);
      const next = importMode === "replace" ? incoming : mergeLibraries(library, incoming);
      setUndo(structuredClone(library));
      setLibrary(next);
      setSelectedShowID(undefined);
      setNotice(`Imported ${incoming.shows.length} shows from ${file.name}`);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Import failed.");
    }
  }

  function openSettingsForImport() {
    setSelectedShowID(undefined);
    setTab("settings");
  }

  if (!ready) {
    return <main className="loadingScreen"><div className="brandMark">▶</div><p>Opening your library…</p></main>;
  }

  if (selectedShow) {
    return (
      <main className="detailShell">
        <ShowDetail
          show={selectedShow}
          onBack={() => setSelectedShowID(undefined)}
          onToggle={(episodeID) => toggleEpisode(selectedShow.id, episodeID)}
          onSetSeason={(season, watched) => setSeason(selectedShow.id, season, watched)}
          onState={(state) => setShowState(selectedShow.id, state)}
        />
        {notice && <div className="toast"><span>{notice}</span>{undo && <button onClick={() => { setLibrary(undo); setUndo(undefined); setNotice("Change undone"); }}>Undo</button>}</div>}
      </main>
    );
  }

  return (
    <main className="appShell">
      <aside className="sidebar">
        <div className="brand"><div className="brandMark">▶</div><div><strong>TB Tempo</strong><small>series, at your pace</small></div></div>
        <nav aria-label="Primary navigation">
          {NAVIGATION.map((item) => <button key={item.id} className={tab === item.id ? "active" : ""} onClick={() => setTab(item.id)}><span>{item.symbol}</span>{item.label}</button>)}
        </nav>
        <div className="localBadge"><span>●</span><div><strong>Local library</strong><small>Saved on this device</small></div></div>
      </aside>

      <div className="mainColumn">
        <header className="topbar">
          <div><p className="eyebrow">{new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date())}</p><h1>{NAVIGATION.find((item) => item.id === tab)?.label}</h1><p>{pageDescription(tab)}</p></div>
          <button className="button primary addButton" onClick={() => setShowAdd(true)}><span>＋</span> Find a series</button>
        </header>
        <div className="pageContent">
          {tab === "today" && <TodayPage library={library} onAdd={() => setShowAdd(true)} onImport={openSettingsForImport} onOpenShow={setSelectedShowID} onToggle={toggleEpisode} />}
          {tab === "upcoming" && <UpcomingPage library={library} onOpenShow={setSelectedShowID} onToggle={toggleEpisode} />}
          {tab === "shows" && <ShowsPage library={library} onOpenShow={setSelectedShowID} />}
          {tab === "statistics" && <StatisticsPage library={library} />}
          {tab === "settings" && <SettingsPage library={library} importMode={importMode} setImportMode={setImportMode} onImport={(file) => void importFile(file)} />}
        </div>
      </div>

      <nav className="mobileNav" aria-label="Primary navigation">
        {NAVIGATION.map((item) => <button key={item.id} className={tab === item.id ? "active" : ""} onClick={() => setTab(item.id)}><span>{item.symbol}</span><small>{item.label}</small></button>)}
      </nav>

      {showAdd && <AddShowDialog onClose={() => setShowAdd(false)} onAdd={addCatalogShow} existing={existingTMDB} />}
      {notice && <div className="toast"><span>{notice}</span>{undo && <button onClick={() => { setLibrary(undo); setUndo(undefined); setNotice("Change undone"); }}>Undo</button>}</div>}
    </main>
  );
}
