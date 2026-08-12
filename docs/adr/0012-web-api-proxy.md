# 0012 The web build reaches the API through a proxy

Status: accepted

## Context

The app has no backend. Android and iOS call signdict.org directly, which is
what [0001](0001-signdict-api.md) settled.

A browser cannot. signdict.org answers without an `access-control-allow-origin`
header, so the response never reaches the code:

```
$ curl -i -X POST https://signdict.org/graphql-api -H 'Origin: https://dgs.example'
HTTP/2 200
content-type: application/json; charset=utf-8
server: Cowboy
```

The same holds for a GET with the query in the URL, which needs no preflight.
CORS governs reading the answer, so no shape of request gets around it. Neither
does `no-cors` mode, which yields an opaque response, and neither does a
service worker, which is bound by the same rule.

That leaves three ways out. SignDict sends the header, and the site is Elixir
under MPL-2.0 and takes contributions, so this is a few lines of `corsica` for
someone. The app is hosted on signdict.org itself. Or something in between
carries the call.

## Decision

The web build talks to an address of its own, given at build time:

```bash
flutter build web --dart-define=api=/api
```

Without the define the endpoint stays signdict.org, so the phone builds are
untouched.

The videos and the stills are not proxied. A media element plays cross origin
without CORS, so they keep coming from assets.wishlephant.com and no bandwidth
of ours carries them.

Asking SignDict for the header stays the preferred fix. It removes the proxy
for everyone, not only here.

## Consequences

"No backend" no longer holds for the web. The phone builds keep their promise,
a browser needs a machine in between, and any statement about the app has to
say which one it means.

Whoever hosts the web version carries the API traffic of its users. The proxy
therefore rate limits per client, since signdict.org is volunteer run.

The proxy is a second place where the API address is written down. A move of
the endpoint has to reach the define and the proxy configuration together.

The stills go through an `img` element rather than through CanvasKit's own
fetch, because assets.wishlephant.com has no CORS header either. `AGENTS.md`
carries that under platform traps.
