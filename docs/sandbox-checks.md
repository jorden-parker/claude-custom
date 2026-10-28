# Sandbox checks

`bin/sandbox-probe` runs the installed sandbox-runtime (`srt`) on throwaway
policies and prints one `ok:`, `FAIL:` or `skip:` line per question. It only
sends `openssl rand` values and `GH_TOKEN=probe`, and talks to github.com,
api.github.com and httpbin.org. It never widens `ollama/sandbox.json`.

Rerun it after every sandbox-runtime upgrade:

    bin/sandbox-probe                  # every check
    bin/sandbox-probe --only CHECK     # one check
    bin/sandbox-probe --clipboard      # also the pasteboard check (writes the clipboard)

Append each dated run to this file.

## Run of 2026-10-28

sandbox-runtime version: 0.0.81
(`node_modules/@anthropic-ai/sandbox-runtime/package.json`)

Machine: macOS 26.5.2 (Darwin 25.5.0), `/usr/bin/sandbox-exec` present.

```
FAIL: a second Seatbelt sandbox is refused inside srt (exit 71): sandbox-exec: sandbox_apply: Operation not permitted
ok: github.com reachable (HTTP 200)
ok: api.github.com is blocked by allowedDomains ["github.com"] (curl exit 56)
ok: the session sees a placeholder, not the value
ok: the proxy swaps the header on an injectHosts host
FAIL: the proxy also rewrites request bodies (body-substitution is on): a model can post its sentinel and read the real value back
ok: narrowing injectHosts stops both header and body substitution
ok: a spelled-right denyRead holds
FAIL: a misspelled deny key is silently dropped: secret2.txt was readable
ok: the session cannot write ~/.config/claude-custom
ok: the session writes its own project
ok: gh honours HTTPS_PROXY (CONNECT api.github.com seen)
skip: pasteboard check needs --clipboard (it reads and writes the clipboard)
sandbox-probe: 13 checks, 3 failed
```

Pasteboard, run with `--clipboard` on the same day:

```
ok: pasteboard lookup grants read=yes write=yes
```

The clipboard was unchanged afterwards.

## Host matching rule

`allowedDomains` entries match a request host as follows
(`dist/sandbox/domain-pattern.js`, `matchesDomainPattern`, lines 168-179):

- A `*.X` entry matches any host that ends in `.X` (subdomains only, never IP
  addresses).
- Every other entry is an exact match: `return h === pattern.toLowerCase();`
  (line 178).

So `github.com` does not cover `api.github.com`. The probe agrees: the request
to api.github.com was blocked (curl exit 56).

## Policy notes

- srt requires `filesystem.denyRead`, `filesystem.denyWrite` and
  `network.deniedDomains` even when they are empty. The probe policies set them
  to `[]`. This adds no reachable host or readable path.
- srt rejects an `injectHosts` entry that `allowedDomains` does not cover
  (`dist/sandbox/sandbox-config.js`, around line 1092). The narrowing sub-check
  therefore lists `example.invalid` in `allowedDomains`. It is never requested,
  so the session still reaches only httpbin.org.
- A misspelled key is not rejected. srt starts with the policy and ignores the
  misspelled key, so no error shows.

## What this means for the default

- api.github.com: `allowedDomains: ["github.com"]` does not reach
  api.github.com, so the masked `GH_BASIC` is not injected into requests to that
  host through this entry.
- Request bodies: srt does rewrite the masked value in request bodies sent to an
  `injectHosts` host. Narrowing `injectHosts` to a host the request does not
  match stops both header and body substitution; narrowing to a host the request
  does match was not tested.
- Unknown keys: a misspelled deny key (`denyReads`) is silently dropped and its
  target stays readable, so a typo in `ollama/sandbox.json` opens that path. In
  this run srt accepted the policy with the misspelled key and rejected policies
  that lacked required fields.
