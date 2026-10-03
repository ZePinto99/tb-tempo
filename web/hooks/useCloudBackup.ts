"use client";

import type { Dispatch, SetStateAction } from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { assertLibraryPayload, mergeLibraries } from "@/lib/backup";
import {
  chooseReconciliationAction,
  type CloudLibraryRecord,
  type CloudSnapshot,
  libraryFingerprint,
  type SyncMetadata,
} from "@/lib/cloud-sync";
import { applyAutomaticCompletions } from "@/lib/library";
import { getSupabaseBrowserClient, isCloudBackupConfigured } from "@/lib/supabase";
import type { LibraryPayload } from "@/lib/types";

export type CloudBackupStatus =
  | "unavailable"
  | "signed-out"
  | "connecting"
  | "syncing"
  | "synced"
  | "offline"
  | "conflict"
  | "error";

export interface CloudConflict {
  cloud: CloudLibraryRecord;
  local: LibraryPayload;
}

export interface CloudBackupController {
  configured: boolean;
  status: CloudBackupStatus;
  userEmail?: string;
  lastSyncedAt?: string;
  message?: string;
  error?: string;
  conflict?: CloudConflict;
  snapshots: CloudSnapshot[];
  sendSignInLink: (email: string) => Promise<boolean>;
  signOut: () => Promise<void>;
  syncNow: () => Promise<void>;
  refresh: () => Promise<void>;
  resolveConflict: (choice: "merge" | "local" | "cloud") => Promise<void>;
  restoreSnapshot: (snapshot: CloudSnapshot) => Promise<void>;
}

type CloudWriteResult = "saved" | "conflict" | "failed" | "skipped";

const DEVICE_KEY = "tbtempo-cloud-device";
const METADATA_PREFIX = "tbtempo-cloud-metadata:";

function deviceID(): string {
  const existing = window.localStorage.getItem(DEVICE_KEY);
  if (existing) return existing;
  const created = crypto.randomUUID();
  window.localStorage.setItem(DEVICE_KEY, created);
  return created;
}

function readMetadata(userID: string): SyncMetadata | undefined {
  try {
    const value = window.localStorage.getItem(`${METADATA_PREFIX}${userID}`);
    if (!value) return undefined;
    const parsed = JSON.parse(value) as Partial<SyncMetadata>;
    return typeof parsed.revision === "number" && typeof parsed.fingerprint === "string"
      ? { revision: parsed.revision, fingerprint: parsed.fingerprint }
      : undefined;
  } catch {
    return undefined;
  }
}

function writeMetadata(userID: string, metadata: SyncMetadata): void {
  window.localStorage.setItem(`${METADATA_PREFIX}${userID}`, JSON.stringify(metadata));
}

function parseCloudRecord(value: unknown): CloudLibraryRecord {
  if (!value || typeof value !== "object") throw new Error("Cloud backup returned an invalid library.");
  const row = value as Record<string, unknown>;
  assertLibraryPayload(row.payload);
  if (
    typeof row.user_id !== "string" ||
    typeof row.revision !== "number" ||
    typeof row.device_id !== "string" ||
    typeof row.updated_at !== "string"
  ) {
    throw new Error("Cloud backup returned an invalid library.");
  }
  return row as unknown as CloudLibraryRecord;
}

function parseSnapshot(value: unknown): CloudSnapshot | undefined {
  try {
    if (!value || typeof value !== "object") return undefined;
    const row = value as Record<string, unknown>;
    assertLibraryPayload(row.payload);
    if (
      typeof row.id !== "number" ||
      typeof row.source_revision !== "number" ||
      typeof row.reason !== "string" ||
      typeof row.created_at !== "string"
    ) {
      return undefined;
    }
    return row as unknown as CloudSnapshot;
  } catch {
    return undefined;
  }
}

function statusForFailure(): CloudBackupStatus {
  return typeof navigator !== "undefined" && !navigator.onLine ? "offline" : "error";
}

export function useCloudBackup(
  library: LibraryPayload,
  ready: boolean,
  setLibrary: Dispatch<SetStateAction<LibraryPayload>>,
): CloudBackupController {
  const configured = isCloudBackupConfigured();
  const client = getSupabaseBrowserClient();
  const [session, setSession] = useState<Session | null | undefined>(configured ? undefined : null);
  const [status, setStatus] = useState<CloudBackupStatus>(configured ? "connecting" : "unavailable");
  const [lastSyncedAt, setLastSyncedAt] = useState<string>();
  const [message, setMessage] = useState<string>();
  const [error, setError] = useState<string>();
  const [conflict, setConflict] = useState<CloudConflict>();
  const [snapshots, setSnapshots] = useState<CloudSnapshot[]>([]);
  const libraryRef = useRef(library);
  const cloudRef = useRef<CloudLibraryRecord | undefined>(undefined);
  const lastSyncedFingerprint = useRef<string | undefined>(undefined);
  const reconciledUser = useRef<string | undefined>(undefined);
  const autoSyncTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    libraryRef.current = library;
  }, [library]);

  const fail = useCallback((caught: unknown) => {
    setStatus(statusForFailure());
    setError(caught instanceof Error ? caught.message : "Cloud backup failed.");
  }, []);

  const fetchCloudRecord = useCallback(async (activeClient: SupabaseClient, userID: string) => {
    const { data, error: queryError } = await activeClient
      .from("tbtempo_libraries")
      .select("user_id,payload,revision,device_id,updated_at")
      .eq("user_id", userID)
      .maybeSingle();
    if (queryError) throw queryError;
    return data ? parseCloudRecord(data) : undefined;
  }, []);

  const loadSnapshots = useCallback(async (activeClient: SupabaseClient, userID: string) => {
    const { data, error: queryError } = await activeClient
      .from("tbtempo_library_snapshots")
      .select("id,payload,source_revision,reason,created_at")
      .eq("user_id", userID)
      .order("created_at", { ascending: false })
      .limit(10);
    if (queryError) throw queryError;
    setSnapshots((data ?? []).map(parseSnapshot).filter((item): item is CloudSnapshot => Boolean(item)));
  }, []);

  const pruneSnapshots = useCallback(async (activeClient: SupabaseClient, userID: string) => {
    const { data, error: queryError } = await activeClient
      .from("tbtempo_library_snapshots")
      .select("id")
      .eq("user_id", userID)
      .order("created_at", { ascending: false })
      .range(30, 999);
    if (queryError) throw queryError;
    const ids = (data ?? [])
      .map((row) => (typeof row.id === "number" ? row.id : undefined))
      .filter((id): id is number => id !== undefined);
    if (!ids.length) return;
    const { error: deleteError } = await activeClient
      .from("tbtempo_library_snapshots")
      .delete()
      .eq("user_id", userID)
      .in("id", ids);
    if (deleteError) throw deleteError;
  }, []);

  const rememberSynced = useCallback(async (userID: string, row: CloudLibraryRecord) => {
    const fingerprint = await libraryFingerprint(row.payload);
    cloudRef.current = row;
    lastSyncedFingerprint.current = fingerprint;
    writeMetadata(userID, { revision: row.revision, fingerprint });
    setLastSyncedAt(row.updated_at);
    setConflict(undefined);
    setError(undefined);
    setStatus("synced");
  }, []);

  const saveSnapshot = useCallback(
    async (
      activeClient: SupabaseClient,
      userID: string,
      payload: LibraryPayload,
      sourceRevision: number,
      reason: string,
    ) => {
      const { error: insertError } = await activeClient.from("tbtempo_library_snapshots").insert({
        user_id: userID,
        payload,
        source_revision: sourceRevision,
        device_id: deviceID(),
        reason,
      });
      if (insertError) throw insertError;
    },
    [],
  );

  const writeCloud = useCallback(
    async (payload: LibraryPayload, reason: string, expected?: CloudLibraryRecord): Promise<CloudWriteResult> => {
      const userID = session?.user.id;
      if (!client || !userID) return "skipped";
      setStatus("syncing");
      setError(undefined);
      const current = expected ?? cloudRef.current;

      try {
        let saved: CloudLibraryRecord;
        if (!current) {
          const { data, error: insertError } = await client
            .from("tbtempo_libraries")
            .insert({
              user_id: userID,
              payload,
              revision: 1,
              device_id: deviceID(),
            })
            .select("user_id,payload,revision,device_id,updated_at")
            .single();
          if (insertError) throw insertError;
          saved = parseCloudRecord(data);
        } else {
          await saveSnapshot(client, userID, current.payload, current.revision, reason);
          const { data, error: updateError } = await client
            .from("tbtempo_libraries")
            .update({
              payload,
              revision: current.revision + 1,
              device_id: deviceID(),
              updated_at: new Date().toISOString(),
            })
            .eq("user_id", userID)
            .eq("revision", current.revision)
            .select("user_id,payload,revision,device_id,updated_at")
            .maybeSingle();
          if (updateError) throw updateError;
          if (!data) {
            const latest = await fetchCloudRecord(client, userID);
            if (!latest) throw new Error("The cloud library changed while it was being saved.");
            cloudRef.current = latest;
            setConflict({ cloud: latest, local: payload });
            setStatus("conflict");
            setMessage("This device and the cloud both changed. Choose which copy to keep.");
            return "conflict";
          }
          saved = parseCloudRecord(data);
        }

        await rememberSynced(userID, saved);
        setMessage("Your local library is backed up.");
        await pruneSnapshots(client, userID);
        await loadSnapshots(client, userID);
        return "saved";
      } catch (caught) {
        fail(caught);
        return "failed";
      }
    },
    [client, fail, fetchCloudRecord, loadSnapshots, pruneSnapshots, rememberSynced, saveSnapshot, session?.user.id],
  );

  const reconcile = useCallback(async () => {
    const userID = session?.user.id;
    if (!client || !userID || !ready) return;
    setStatus("connecting");
    setError(undefined);
    try {
      const local = libraryRef.current;
      const cloud = await fetchCloudRecord(client, userID);
      const localHash = await libraryFingerprint(local);
      const cloudHash = cloud ? await libraryFingerprint(cloud.payload) : undefined;
      const action = chooseReconciliationAction({
        local,
        cloud,
        localFingerprint: localHash,
        cloudFingerprint: cloudHash,
        metadata: readMetadata(userID),
      });

      if (action === "create-cloud" || action === "use-local") {
        cloudRef.current = cloud;
        await writeCloud(local, action === "create-cloud" ? "initial-backup" : "automatic-sync", cloud);
        return;
      }
      if (!cloud || !cloudHash) throw new Error("Cloud backup could not be read.");

      if (action === "use-cloud") {
        const restored = applyAutomaticCompletions(structuredClone(cloud.payload));
        setLibrary(restored);
        await rememberSynced(userID, { ...cloud, payload: restored });
        setMessage("This device was updated from your cloud backup.");
      } else if (action === "in-sync") {
        await rememberSynced(userID, cloud);
        setMessage("Your local library and cloud backup match.");
      } else {
        cloudRef.current = cloud;
        setConflict({ cloud, local });
        setStatus("conflict");
        setMessage("This device and the cloud both contain changes. Nothing was overwritten.");
      }
      await loadSnapshots(client, userID);
    } catch (caught) {
      fail(caught);
    }
  }, [client, fail, fetchCloudRecord, loadSnapshots, ready, rememberSynced, session?.user.id, setLibrary, writeCloud]);

  useEffect(() => {
    if (!client) return;
    let active = true;
    const applySession = (nextSession: Session | null) => {
      if (!active) return;
      setSession(nextSession);
      if (nextSession) return;
      reconciledUser.current = undefined;
      cloudRef.current = undefined;
      lastSyncedFingerprint.current = undefined;
      setSnapshots([]);
      setConflict(undefined);
      setStatus("signed-out");
    };
    void client.auth.getSession().then(({ data, error: authError }) => {
      if (!active) return;
      if (authError) {
        applySession(null);
        fail(authError);
      } else {
        applySession(data.session);
      }
    });
    const { data } = client.auth.onAuthStateChange((_event, nextSession) => {
      applySession(nextSession);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [client, fail]);

  useEffect(() => {
    const userID = session?.user.id;
    if (!userID || !ready) return;
    if (reconciledUser.current === userID) return;
    reconciledUser.current = userID;
    void reconcile();
  }, [ready, reconcile, session]);

  useEffect(() => {
    clearTimeout(autoSyncTimer.current);
    if (!ready || !session?.user.id || status !== "synced") return;
    let cancelled = false;
    void libraryFingerprint(library).then((fingerprint) => {
      if (cancelled || fingerprint === lastSyncedFingerprint.current) return;
      autoSyncTimer.current = setTimeout(() => {
        void writeCloud(libraryRef.current, "automatic-sync");
      }, 2_000);
    });
    return () => {
      cancelled = true;
      clearTimeout(autoSyncTimer.current);
    };
  }, [library, ready, session?.user.id, status, writeCloud]);

  useEffect(() => {
    if (!session?.user.id) return;
    const retry = () => {
      reconciledUser.current = undefined;
      void reconcile();
    };
    window.addEventListener("online", retry);
    return () => window.removeEventListener("online", retry);
  }, [reconcile, session?.user.id]);

  const sendSignInLink = useCallback(
    async (email: string) => {
      if (!client) return false;
      setError(undefined);
      setMessage(undefined);
      const { error: authError } = await client.auth.signInWithOtp({
        email: email.trim(),
        options: { shouldCreateUser: true, emailRedirectTo: window.location.origin },
      });
      if (authError) {
        fail(authError);
        return false;
      }
      setStatus("signed-out");
      setMessage("Check your email and open the secure TB Tempo sign-in link.");
      return true;
    },
    [client, fail],
  );

  const signOut = useCallback(async () => {
    if (!client) return;
    const { error: authError } = await client.auth.signOut();
    if (authError) {
      fail(authError);
      return;
    }
    setMessage("Signed out. Your local library is still on this device.");
  }, [client, fail]);

  const resolveConflict = useCallback(
    async (choice: "merge" | "local" | "cloud") => {
      const currentConflict = conflict;
      const userID = session?.user.id;
      if (!currentConflict || !client || !userID) return;
      setError(undefined);

      if (choice === "cloud") {
        try {
          await saveSnapshot(
            client,
            userID,
            libraryRef.current,
            currentConflict.cloud.revision,
            "before-cloud-restore",
          );
          const restored = applyAutomaticCompletions(structuredClone(currentConflict.cloud.payload));
          setLibrary(restored);
          await rememberSynced(userID, { ...currentConflict.cloud, payload: restored });
          setMessage("Cloud backup restored. The previous device copy is in version history.");
          await pruneSnapshots(client, userID);
          await loadSnapshots(client, userID);
        } catch (caught) {
          fail(caught);
        }
        return;
      }

      const next =
        choice === "merge"
          ? applyAutomaticCompletions(mergeLibraries(libraryRef.current, currentConflict.cloud.payload))
          : libraryRef.current;
      setLibrary(next);
      setConflict(undefined);
      await writeCloud(next, choice === "merge" ? "before-merge" : "before-keep-device", currentConflict.cloud);
    },
    [client, conflict, fail, loadSnapshots, pruneSnapshots, rememberSynced, saveSnapshot, session?.user.id, setLibrary, writeCloud],
  );

  const restoreSnapshot = useCallback(
    async (snapshot: CloudSnapshot) => {
      const current = cloudRef.current;
      if (!current) return;
      const restored = applyAutomaticCompletions(structuredClone(snapshot.payload));
      setLibrary(restored);
      const result = await writeCloud(restored, "before-version-restore", current);
      if (result === "saved") setMessage("Version restored to this device and the cloud.");
    },
    [setLibrary, writeCloud],
  );

  return {
    configured,
    status,
    userEmail: session?.user.email,
    lastSyncedAt,
    message,
    error,
    conflict,
    snapshots,
    sendSignInLink,
    signOut,
    syncNow: reconcile,
    refresh: reconcile,
    resolveConflict,
    restoreSnapshot,
  };
}
