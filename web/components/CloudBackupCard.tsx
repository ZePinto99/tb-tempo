"use client";

import { useState } from "react";
import type { CloudBackupController } from "@/hooks/useCloudBackup";
import type { CloudSnapshot } from "@/lib/cloud-sync";

function statusCopy(status: CloudBackupController["status"]): string {
  switch (status) {
    case "unavailable":
      return "Not configured";
    case "signed-out":
      return "Local only";
    case "connecting":
      return "Checking backup…";
    case "syncing":
      return "Backing up…";
    case "synced":
      return "Backed up";
    case "offline":
      return "Offline — local saves continue";
    case "conflict":
      return "Needs your choice";
    case "error":
      return "Backup needs attention";
  }
}

function reasonCopy(reason: string): string {
  switch (reason) {
    case "initial-backup":
      return "First backup";
    case "automatic-sync":
      return "Automatic backup";
    case "manual-sync":
      return "Manual backup";
    case "before-merge":
      return "Before safe merge";
    case "before-keep-device":
      return "Before keeping device copy";
    case "before-cloud-restore":
      return "Device copy before cloud restore";
    case "before-version-restore":
      return "Before version restore";
    default:
      return "Saved version";
  }
}

function formatTimestamp(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? value
    : new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

export function CloudBackupCard({ cloud }: { cloud: CloudBackupController }) {
  const [email, setEmail] = useState("");
  const [linkSent, setLinkSent] = useState(false);
  const [busy, setBusy] = useState(false);

  async function requestSignInLink(event: React.FormEvent) {
    event.preventDefault();
    if (!email.trim()) return;
    setBusy(true);
    const sent = await cloud.sendSignInLink(email);
    setLinkSent(sent);
    setBusy(false);
  }

  async function restore(snapshot: CloudSnapshot) {
    const accepted = window.confirm(
      `Restore the version from ${formatTimestamp(snapshot.created_at)}? Your current cloud copy will be kept in version history.`,
    );
    if (!accepted) return;
    setBusy(true);
    await cloud.restoreSnapshot(snapshot);
    setBusy(false);
  }

  return (
    <section className="settingsCard panel cloudCard">
      <div className="settingsIcon cloudIcon">☁</div>
      <div className="cloudHeading">
        <div>
          <p className="eyebrow">Optional private copy</p>
          <h2>Cloud backup</h2>
        </div>
        <span className={`cloudStatus ${cloud.status}`}>{statusCopy(cloud.status)}</span>
      </div>
      <p>
        Your library still saves on this device first. Sign in by email to keep an additional private copy and
        restore earlier versions.
      </p>

      {!cloud.configured ? (
        <div className="cloudNotice">
          Cloud backup is not connected in this deployment yet. Local storage and manual .tbtempo exports keep
          working.
        </div>
      ) : !cloud.userEmail ? (
        <div className="cloudAuth">
          <form onSubmit={requestSignInLink}>
            <label htmlFor="cloud-email">Email</label>
            <div className="cloudInputRow">
              <input
                id="cloud-email"
                type="email"
                inputMode="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="you@example.com"
                required
              />
              <button className="button primary" disabled={busy}>
                {busy && !linkSent ? "Sending…" : linkSent ? "Send again" : "Email sign-in link"}
              </button>
            </div>
          </form>
          {linkSent && (
            <div className="cloudNotice">
              Open the link in your email on this device. TB Tempo will sign you in and start the first backup
              automatically.
            </div>
          )}
        </div>
      ) : (
        <div className="cloudAccount">
          <div className="cloudIdentity">
            <div>
              <strong>{cloud.userEmail}</strong>
              <small>
                {cloud.lastSyncedAt ? `Last backed up ${formatTimestamp(cloud.lastSyncedAt)}` : "Preparing backup…"}
              </small>
            </div>
            <button className="textButton" onClick={() => void cloud.signOut()} disabled={busy}>Sign out</button>
          </div>

          {cloud.conflict && (
            <div className="conflictBox">
              <strong>Two copies have changes</strong>
              <p>Nothing was overwritten. Merge keeps shows and watch history from both copies.</p>
              <div className="buttonStack">
                <button className="button primary" onClick={() => void cloud.resolveConflict("merge")}>Merge safely</button>
                <button className="button secondary" onClick={() => void cloud.resolveConflict("local")}>Keep this device</button>
                <button className="button secondary" onClick={() => void cloud.resolveConflict("cloud")}>Use cloud backup</button>
              </div>
            </div>
          )}

          {!cloud.conflict && (
            <div className="buttonRow cloudActions">
              <button className="button primary" onClick={() => void cloud.syncNow()} disabled={cloud.status === "syncing" || cloud.status === "connecting"}>
                Back up now
              </button>
              <button className="button secondary" onClick={() => void cloud.refresh()} disabled={cloud.status === "syncing" || cloud.status === "connecting"}>
                Check cloud
              </button>
            </div>
          )}

          {cloud.snapshots.length > 0 && (
            <details className="versionHistory">
              <summary>Version history</summary>
              <div className="versionList">
                {cloud.snapshots.map((snapshot) => (
                  <div key={snapshot.id}>
                    <span><strong>{reasonCopy(snapshot.reason)}</strong><small>{formatTimestamp(snapshot.created_at)}</small></span>
                    <button className="textButton" onClick={() => void restore(snapshot)} disabled={busy}>Restore</button>
                  </div>
                ))}
              </div>
            </details>
          )}
        </div>
      )}

      {(cloud.message || cloud.error) && (
        <p className={cloud.error ? "cloudMessage error" : "cloudMessage"} aria-live="polite">
          {cloud.error ?? cloud.message}
        </p>
      )}
      <div className="privacyNote"><span>◉</span><div><strong>Local-first</strong><small>Offline changes stay on this device and sync when the connection returns.</small></div></div>
    </section>
  );
}
