# 0001 The dictionary comes from the SignDict API

Status: accepted

## Context

The app ships no dictionary of its own. Every sign, every video and every
license line comes from signdict.org, which is run by volunteers. The corpus
changes upstream, entries are added and single files go missing.

## Decision

The GraphQL endpoint is the only source. Metadata is cached in the local
database, footage is downloaded on request. The client holds at most four
requests in flight with a 60 millisecond gap between them.

`integration_test/` runs on a device against the live endpoint and checks that
it still answers the way the app expects. `test/` never touches the network.

## Consequences

A first start needs a connection. Everything already cached or downloaded keeps
working without one.

A 403 on a single thumbnail is normal and must not fail a whole package,
otherwise the job disappears from the offline list and the download looks like
it stopped.

A schema change upstream surfaces in the integration tests rather than on a
phone.
