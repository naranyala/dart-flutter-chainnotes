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
  directory, created on demand, capped at **2000 files / 64 MiB** with
  oldest-first eviction (`pickTileEvictions` in
  `lib/core/map/tile_policy.dart`). A read-only cache directory is not fatal —
  it falls through to the network.
- **In-flight.** A `Future` per pending key, so panning across the same tile
  twice issues one request, not two.

## Network behaviour

- One `http.Client`, created by `TileCache` and closed by `dispose()`.
- At most **4 concurrent** fetches with **≥100 ms spacing** between starts
  (`TileRequestGate`); excess tiles are a miss, not a queue.
- A 429/5xx response triggers exponential backoff (1 s, doubling, max 30 s):
  cache still serves, network does not. Other non-200 responses are a miss.
- Any exception (offline, DNS failure, proxy refusal) is caught and treated as
  a miss with no backoff. **No user-visible error** — the map renders what it
  has.
- Failed tiles are **not** remembered, so re-entering an area retries them
  once backoff expires.

## Position on the tile usage policy

The OpenStreetMap tile usage policy asks client applications to send a valid
user agent, avoid parallel or bulk requests, cache responsibly, and display
attribution. Against that, honestly:

| Requirement | Status |
| --- | --- |
| Identifying user agent | **Met** — the constant above, sent on every request |
| Attribution on the map | **Met** — `© OpenStreetMap contributors` drawn in the viewport |
| Cache responsibly | **Met** — memory bounded at 512, disk at 2000 files / 64 MiB with oldest-first eviction |
| No bulk downloading | **Met** — the app fetches only tiles it renders, at the user's pan and zoom |
| Limit concurrent requests | **Met** — max 4 in flight, ≥100 ms spacing, backoff on 429/5xx |

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

**Tiles appear, then stop after a while.** A 429/5xx puts the network client
into backoff (cache still serves); other non-200 responses are a silent miss.
Backoff clears on the next success.

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
