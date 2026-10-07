# Map sources and attribution

`Map Explorer` fetches raster tiles itself — there is no mapping library in
the project. This page is the whole of that surface: where tiles come from,
how they are cached, what the app sends, and what that implies.

## The host

```text
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

One hardcoded URL, in one place:

[`lib/core/map/tile_source.dart`](../lib/core/map/tile_source.dart) (`TileCache._readBytes`).

```dart
static const String userAgent =
    'chainnotes/1.0 (desktop workspace; flutter tile client)';
```

Both the host and the user agent are constants in that file, so switching
providers — or pointing at a self-hosted tile server — is a one-line change in
one file. Nothing else in the tree constructs a tile URL.

| Property | Value |
| --- | --- |
| Zoom range | 1–19 (`minZoom` / `maxZoom` in `lib/core/map/projection.dart`; committed zoom is an integer) |
| Tile size | 256 × 256, decoded to a `ui.Image` at that exact size |
| Attribution | `© OpenStreetMap contributors`, drawn on the map and shown in the corner |
| Format | PNG, as returned by the host |

## Caching

Three levels, checked in order:

```text
memory (LRU, 512 tiles)  →  disk (<cache>/tiles/{z}/{x}/{y}.png)  →  network
```

- **Memory.** A map of decoded images plus an insertion-order list capped at
  **512 tiles**; the oldest is disposed when the cap is reached, so a long pan
  session cannot grow without bound.
- **Disk.** `writeAsBytes(..., flush: true)` under the application cache
  directory, created on demand. A read-only cache directory is not fatal — it
  falls through to the network.
- **In-flight.** A `Future` per pending key, so panning across the same tile
  twice issues one request, not two.

There is **no cap on the disk cache** and no eviction of old tiles from it —
that is a real gap against the host's own guidance and is tracked as
[TODO-008](../TODOS.md).

## Network behaviour

- One `http.Client`, created by `TileCache` and closed by `dispose()`.
- A non-200 response is a miss, not an error: the tile simply does not
  appear.
- Any exception (offline, DNS failure, proxy refusal) is caught and treated as
  a miss. **No retry, no backoff, no user-visible error** — the map renders
  what it has.
- Failed tiles are **not** remembered, so re-entering an area retries them.

## Position on the tile usage policy

The OpenStreetMap tile usage policy asks client applications to send a valid
user agent, avoid parallel or bulk requests, cache responsibly, and display
attribution. Against that, honestly:

| Requirement | Status |
| --- | --- |
| Identifying user agent | **Met** — the constant above, sent on every request |
| Attribution on the map | **Met** — `© OpenStreetMap contributors` drawn in the viewport |
| Cache responsibly | **Partly** — memory is bounded at 512, disk is unbounded (TODO-008) |
| No bulk downloading | **Met** — the app fetches only tiles it renders, at the user's pan and zoom |
| Limit concurrent requests | **Not guaranteed** — each visible tile fetches independently with no global concurrency cap; only per-tile in-flight dedup (part of TODO-008) |

This is an acceptable position for a single user panning a desktop map, and a
poor one for anything that sweeps zoom levels or pre-fetches. If you add
pre-fetching or a batch export, fix the concurrency limit and the disk cap
first.

If your use would be anything more than interactive personal use, the correct
move is a different tile host (your own server, a paid provider, or one whose
policy fits), which is a one-line change to the URL constant.

## Troubleshooting

**No tiles at all.** Check connectivity, then confirm the request is reaching
`tile.openstreetmap.org` with the user agent above. Behind a corporate proxy
or a VPN that rewrites traffic, tiles are the first thing to fail, and the app
will show an empty map rather than an error.

**Tiles appear, then stop after a while.** A rate-limit response is a miss like
any other non-200: tiles silently stop appearing. There is no back-off or
message for this yet (TODO-008).

**The disk cache keeps growing.** Expected: `<cache>/tiles` has no eviction.
Delete the directory to reclaim the space.

**A tile looks wrong or stale.** The cache is keyed by `z/x/y` only, never by
content or date. Deleting `<cache>/tiles` forces a refetch.

## Google Maps

Not ported. The record section `googleMap` is normalized and persisted so an
exported workspace from the original loads intact, but no view renders it and
no Google endpoint is contacted. The original's viewer fetched tiles from an
unlicensed endpoint; deciding whether to build that here — with proper API
keys, billing, and terms — is an open question, not an oversight
([TODO-013](../TODOS.md)).

## Places and layers

Imported data is local and user-supplied; it never reaches the network:

| Input | Parser | Notes |
| --- | --- | --- |
| `.csv` places file | `_parsePlacesCsv` in `lib/sessions/map_session.dart` | Header row required; duplicate ids dropped, 200-place cap |
| GeoJSON features | `_parsePlacesGeoJson` | Point features become places; the same caps apply |
| GeoJSON layer | `loadGeojson` in `MapSession` | Drawn over the tiles; `Clear` removes it |

Distances are great-circle (`lib/core/geo/geo.dart`), bearings are true north
with compass points derived from the bearing, and both are shown in the
bearing readout on the map.

## Location

`MapSession.locate()` uses `geolocator`: check permission, request it if
needed, then fly to the position. A denial or an unavailable provider is
reported in the tool status line — never thrown, never fatal.

| Platform | Permission declared |
| --- | --- |
| Android | `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` in the manifest |
| iOS | `NSLocationWhenInUseUsageDescription` in `Info.plist` |

Location runs on the device only: no coordinates are written to the record
unless the user saves them as a place.
