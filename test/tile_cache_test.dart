import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chainnotes/core/map/tile_source.dart';

import 'fakes.dart';

/// The tile network path: fetch, decode, memory, and disk — previously only
/// the gate and eviction math had tests while `TileCache` itself only ever
/// saw a 404 mock.
void main() {
  late Directory root;
  var requests = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('chainnotes-tilecache');
    requests = 0;
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  TileCache cache(http.Client client) => TileCache(
    cacheDirectory: Directory('${root.path}/tiles')..createSync(),
    client: client,
  );

  MockClient okClient() => MockClient((_) async {
    requests++;
    return http.Response.bytes(kTinyPng, 200);
  });

  test('a network fetch decodes to a 256px tile and is remembered', () async {
    final tiles = cache(okClient());
    addTearDown(tiles.dispose);
    final image = await tiles.tile(1, 0, 0);
    expect(image, isNotNull);
    expect(image!.width, 256);
    expect(image.height, 256);
    expect(requests, 1);
    expect(tiles.contains(1, 0, 0), isTrue);
  });

  test('memory serves the tile without touching the network', () async {
    final tiles = cache(okClient());
    addTearDown(tiles.dispose);
    final first = await tiles.tile(2, 1, 1);
    expect(requests, 1);
    final second = await tiles.tile(2, 1, 1);
    expect(requests, 1);
    expect(identical(second, first), isTrue);
  });

  test('the disk cache serves a fresh cache without the network', () async {
    final first = cache(okClient());
    addTearDown(first.dispose);
    await first.tile(3, 2, 2);
    expect(requests, 1);

    var secondRequests = 0;
    final second = TileCache(
      cacheDirectory: Directory('${root.path}/tiles'),
      client: MockClient((_) async {
        secondRequests++;
        return http.Response('gone', 404);
      }),
    );
    addTearDown(second.dispose);
    final image = await second.tile(3, 2, 2);
    expect(image, isNotNull);
    expect(secondRequests, 0);
  });

  test('a 404 is a miss and is not remembered', () async {
    final tiles = cache(
      MockClient((_) async {
        requests++;
        return http.Response('gone', 404);
      }),
    );
    addTearDown(tiles.dispose);
    expect(await tiles.tile(4, 3, 3), isNull);
    // The request gate enforces spacing between fetches; wait it out so the
    // retry is a real second request, proving misses are not remembered.
    await Future.delayed(const Duration(milliseconds: 150));
    expect(await tiles.tile(4, 3, 3), isNull);
    expect(requests, 2);
    expect(tiles.contains(4, 3, 3), isFalse);
  });

  test('corrupt bytes are a miss, not a crash', () async {
    final tiles = cache(
      MockClient((_) async {
        requests++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    addTearDown(tiles.dispose);
    expect(await tiles.tile(5, 4, 4), isNull);
    expect(requests, 1);
  });
}
