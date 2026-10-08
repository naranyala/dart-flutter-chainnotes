# Map sources and attribution

`Map Explorer` downloads its own map tiles — there's no mapping package in
the project. This page covers all of that: where tiles come from, how they're
cached, what the app sends, and what that means.

## Where tiles come from

```text
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

One URL, in one place:

[`lib/core/map/tile_source.dart`](../lib/core/map/tile_source.dart) (`TileCache._readBytes`).

```dart
static const String userAgent =
    'chainnotes/1.0 (desktop workspace; flutter tile client)';
```

Host and user agent are both constants in that file, so switching providers —
or pointing at your own tile server — is a one-line change. Nothing else
builds a tile URL.

| Property | Value |
| --- | --- |
| Zoom range | 1–19 (`minZoom` / `maxZoom` in `lib/core/map/projection.dart`; zoom steps are whole numbers) |
| Tile size | 256 × 256, decoded to a `ui.Image` at that size |
| Attribution | `© OpenStreetMap contributors`, drawn on the map |
| Format | PNG, as the host sends it |

## Caching

Three layers, checked in order:

```text
memory (keeps 512 tiles)  →  disk (<cache>/tiles/{z}/{x}/{y}.png)  →  network
```

- **Memory.** Decoded images in a map plus an ordering list capped at
  **512 tiles**. The oldest gets dropped when it's full, so a long wander
  can't grow forever.
- **Disk.** Written with `writeAsBytes(..., flush: true)` under the app cache
  folder, created as needed, capped at **2000 files / 64 MiB** with
  oldest-first cleanup (`pickTileEvictions` in
  `lib/core/map/tile_policy.dart`). If the cache folder is read-only, that's
  fine — it just skips to network.
- **In flight.** One `Future` per tile being fetched, so crossing the same
  tile twice sends one request, not two.

## How it uses the network

- One `http.Client`, made by `TileCache` and closed by `dispose()`.
- At most **4 downloads at once** with **at least 100 ms between starts**
  (`TileRequestGate`); extra tiles just miss instead of queueing.
- A 429/5xx reply backs off (1 s, doubling, up to 30 s): cached tiles still
  show, network pauses. Other non-200 replies are a quiet miss.
- Anything else going wrong (offline, DNS, proxy) is caught and treated as a
  miss with no backoff. **You won't see an error** — the map just draws what
  it has.
- Failed tiles aren't remembered, so going back there retries them once the
  backoff lifts.

## Staying within the tile rules

OpenStreetMap asks apps to send a real user agent, avoid parallel or bulk
downloads, cache sensibly, and show attribution. Here's where this app stands:

| Ask | Status |
| --- | --- |
| Recognisable user agent | **Yes** — the constant above, sent every time |
| Attribution on the map | **Yes** — `© OpenStreetMap contributors` in the corner |
| Cache sensibly | **Yes** — 512 in memory, 2000 files / 64 MiB on disk, oldest dropped first |
| No bulk downloading | **Yes** — only fetches tiles you're actually looking at |
| Keep requests gentle | **Yes** — max 4 at once, 100 ms apart, backs off on 429/5xx |

That's reasonable for one person panning a desktop map, and not suitable for
anything that sweeps zoom levels or pre-downloads. If you add pre-fetching or
bulk export, raise the limits and the cache size first.

If you'll use this for more than personal tinkering, the right move is a
different tile host (your own server, a paid provider, or one whose terms fit)
— a one-line change to the URL.

## When tiles misbehave

**Nothing at all.** Check your connection, then check the request is reaching
`tile.openstreetmap.org` with the user agent above. Behind a corporate proxy
or a VPN that rewrites traffic, tiles are usually the first thing to break,
and the app shows an empty map rather than an error.

**Tiles load, then stop.** A 429/5xx puts the downloader on a break (cache
still works); other bad replies are silent misses. It recovers on the next
success.

**The disk cache keeps growing.** Check `<cache>/tiles` — old versions had no
cleanup. Deleting the folder reclaims the space.

**A tile looks wrong or old.** The cache is keyed by `z/x/y` only, never by
date. Deleting `<cache>/tiles` forces fresh downloads.

## Google Maps

Not included. The `googleMap` record section still loads and saves so a
workspace from elsewhere keeps its data, but nothing draws it and no Google
address is contacted. Whether to build that here — with proper keys, billing,
and terms — is still open ([TODO-013](../TODOS.md)).

## Places and layers

Imported data stays on your machine; it never touches the network:

| Input | Parser | Notes |
| --- | --- | --- |
| `.csv` places file | `_parsePlacesCsv` in `lib/sessions/map_session.dart` | Needs a header row; duplicate ids dropped, 200-place cap |
| GeoJSON places | `_parsePlacesGeoJson` | Points become places; same caps |
| GeoJSON layer | `loadGeojson` in `MapSession` | Drawn over the tiles; `Clear` removes it |

Distances are great-circle (`lib/core/geo/geo.dart`), bearings are true north
with compass points, and both show in the readout on the map.

## Location

`MapSession.locate()` uses `geolocator`: check permission, ask if needed,
then fly there. Saying no, or a missing provider, shows in the status line —
it never throws.

| Platform | Permission |
| --- | --- |
| Android | `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` in the manifest |
| iOS | `NSLocationWhenInUseUsageDescription` in `Info.plist` |

Location stays on the device: nothing is saved unless you save it as a place.
