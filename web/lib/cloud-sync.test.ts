import { describe, expect, it } from "vitest";
import { chooseReconciliationAction, libraryFingerprint, type CloudLibraryRecord } from "./cloud-sync";
import { EMPTY_LIBRARY, type LibraryPayload } from "./types";

function library(title?: string): LibraryPayload {
  const payload = structuredClone(EMPTY_LIBRARY);
  if (title) {
    payload.shows.push({
      id: `show:${title}`,
      title,
      overview: "",
      status: "Returning Series",
      libraryState: "active",
      genres: [],
      notificationsEnabled: true,
      episodes: [],
    });
  }
  return payload;
}

function cloud(payload: LibraryPayload, revision = 2): CloudLibraryRecord {
  return {
    user_id: "user:one",
    payload,
    revision,
    device_id: "device:one",
    updated_at: "2026-10-03T10:00:00Z",
  };
}

describe("cloud reconciliation", () => {
  it("creates the first cloud copy without replacing local data", async () => {
    const local = library("Local");
    const localHash = await libraryFingerprint(local);
    expect(chooseReconciliationAction({ local, localFingerprint: localHash })).toBe("create-cloud");
  });

  it("downloads cloud data onto an empty device", async () => {
    const local = library();
    const remote = cloud(library("Cloud"));
    expect(
      chooseReconciliationAction({
        local,
        cloud: remote,
        localFingerprint: await libraryFingerprint(local),
        cloudFingerprint: await libraryFingerprint(remote.payload),
      }),
    ).toBe("use-cloud");
  });

  it("uploads local edits when the known cloud revision did not change", async () => {
    const previous = library("Previous");
    const local = library("Local edit");
    const remote = cloud(previous, 7);
    const previousHash = await libraryFingerprint(previous);
    expect(
      chooseReconciliationAction({
        local,
        cloud: remote,
        localFingerprint: await libraryFingerprint(local),
        cloudFingerprint: previousHash,
        metadata: { revision: 7, fingerprint: previousHash },
      }),
    ).toBe("use-local");
  });

  it("does not overwrite when both copies changed", async () => {
    const previous = library("Previous");
    const local = library("Local edit");
    const remote = cloud(library("Cloud edit"), 8);
    expect(
      chooseReconciliationAction({
        local,
        cloud: remote,
        localFingerprint: await libraryFingerprint(local),
        cloudFingerprint: await libraryFingerprint(remote.payload),
        metadata: { revision: 7, fingerprint: await libraryFingerprint(previous) },
      }),
    ).toBe("conflict");
  });
});
