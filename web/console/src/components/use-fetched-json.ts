"use client";

import { useEffect, useState } from "react";

export type FetchedJson<T> = { value: T | null; error: string | null };

export function useFetchedJson<T>(url: string): FetchedJson<T> {
  const [value, setValue] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void loadJson<T>(url).then((result) => {
      if (result.ok) {
        setValue(result.value);
      } else {
        setError(result.message);
      }
    });
  }, [url]);

  return { value, error };
}

export async function loadJson<T>(
  url: string,
): Promise<{ ok: true; value: T } | { ok: false; message: string }> {
  const response = await fetch(url, { cache: "no-store" });
  const body = (await response.json()) as T & { message?: string };
  if (!response.ok) {
    return {
      ok: false,
      message: body.message ?? `${url} failed with status ${response.status}`,
    };
  }
  return { ok: true, value: body };
}
