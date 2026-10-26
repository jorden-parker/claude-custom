const LOOPBACK_HOST_PATTERN = /^(127\.0\.0\.1|localhost)(:\d+)?$/i;

export function isLoopbackHost(host: string | null): boolean {
  return host !== null && LOOPBACK_HOST_PATTERN.test(host);
}
