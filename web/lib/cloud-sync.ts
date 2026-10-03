import type { LibraryPayload } from "./types";

export interface CloudLibraryRecord {
  user_id: string;
  payload: LibraryPayload;
  revision: number;
  device_id: string;
  updated_at: string;
}

export interface CloudSnapshot {
  id: number;
  payload: LibraryPayload;
  source_revision: number;
  reason: string;
  created_at: string;
}

export interface SyncMetadata {
  revision: number;
  fingerprint: string;
}

export type ReconciliationAction =
  | "create-cloud"
  | "in-sync"
  | "use-local"
  | "use-cloud"
  | "conflict";

function canonicalJSON(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object)
    .filter((key) => object[key] !== undefined)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJSON(object[key])}`)
    .join(",")}}`;
}

export async function libraryFingerprint(payload: LibraryPayload): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalJSON(payload));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function isLibraryEmpty(payload: LibraryPayload): boolean {
  return payload.shows.length === 0;
}

export function chooseReconciliationAction({
  local,
  cloud,
  localFingerprint,
  cloudFingerprint,
  metadata,
}: {
  local: LibraryPayload;
  cloud?: CloudLibraryRecord;
  localFingerprint: string;
  cloudFingerprint?: string;
  metadata?: SyncMetadata;
}): ReconciliationAction {
  if (!cloud || !cloudFingerprint) return "create-cloud";
  if (localFingerprint === cloudFingerprint) return "in-sync";

  if (isLibraryEmpty(local) && !isLibraryEmpty(cloud.payload)) return "use-cloud";
  if (!isLibraryEmpty(local) && isLibraryEmpty(cloud.payload)) return "use-local";

  if (metadata) {
    const cloudHasNotChanged =
      cloud.revision === metadata.revision && cloudFingerprint === metadata.fingerprint;
    if (cloudHasNotChanged) return "use-local";
    if (localFingerprint === metadata.fingerprint) return "use-cloud";
  }

  return "conflict";
}
