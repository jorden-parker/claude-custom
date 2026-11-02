import { useSyncExternalStore } from "react";

const MOBILE_QUERY = "(max-width: 767px)";

function subscribeToMobileQuery(onChange: () => void): () => void {
  const mediaQueryList = window.matchMedia(MOBILE_QUERY);
  mediaQueryList.addEventListener("change", onChange);
  return () => mediaQueryList.removeEventListener("change", onChange);
}

function isMobileViewport(): boolean {
  return window.matchMedia(MOBILE_QUERY).matches;
}

export function useIsMobile(): boolean {
  return useSyncExternalStore(
    subscribeToMobileQuery,
    isMobileViewport,
    () => false,
  );
}
