import { EMPTY_LIBRARY, type LibraryPayload } from "./types";

const DATABASE_NAME = "tbtempo-web";
const STORE_NAME = "library";
const RECORD_KEY = "current";

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        database.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("Unable to open local storage."));
  });
}

export async function loadLibrary(): Promise<LibraryPayload> {
  const database = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).get(RECORD_KEY);
    request.onsuccess = () => {
      const value = request.result as LibraryPayload | undefined;
      resolve(value ?? structuredClone(EMPTY_LIBRARY));
    };
    request.onerror = () => reject(request.error ?? new Error("Unable to read your library."));
    transaction.oncomplete = () => database.close();
  });
}

export async function saveLibrary(payload: LibraryPayload): Promise<void> {
  const database = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put(payload, RECORD_KEY);
    transaction.oncomplete = () => {
      database.close();
      resolve();
    };
    transaction.onerror = () => {
      database.close();
      reject(transaction.error ?? new Error("Unable to save your library."));
    };
  });
}
