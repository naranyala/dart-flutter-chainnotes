import 'dart:convert';

import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeWorkspace', () {
    test('defaults are safe when the record is empty or corrupt', () {
      for (final raw in [null, '{', 42, 'not-an-object', <String, Object?>{}]) {
        final workspace = normalizeWorkspace(raw);
        expect(workspace.version, workspaceVersion);
        expect(workspace.savedAt, 0);
        expect(workspace.view, 'menu');
        expect(workspace.tocItems, isEmpty);
        expect(workspace.activeTocId, isNull);
        expect(workspace.editorContent, '');
        expect(workspace.pdf.page, 1);
        expect(workspace.pdf.url, '');
        expect(workspace.pdf.zoom, 1.1);
        expect(workspace.images.selectedGroup, 'All Images');
        expect(workspace.map.places, isEmpty);
        expect(workspace.map.sidebarOpen, isTrue);
        expect(workspace.map.renderer, 'dom');
        expect(workspace.googleMap.layer, 'm');
      }
    });

    test('unknown views are rejected and the session is clamped', () {
      final workspace = normalizeWorkspace({
        'view': 'root-shell',
        'activeTocId': 42,
        'editor': {'content': 7},
        'pdf': {'name': 'report.pdf', 'size': -5, 'page': 0, 'zoom': 99},
        'images': {'selectedGroup': ''},
      });
      expect(workspace.view, 'menu');
      expect(workspace.activeTocId, isNull);
      expect(workspace.editorContent, '');
      expect(workspace.pdf.size, 0);
      expect(workspace.pdf.page, 1);
      expect(workspace.pdf.zoom, 2.5);
      expect(workspace.images.selectedGroup, 'All Images');
    });

    test('known views are kept', () {
      for (final view in workspaceViews) {
        expect(normalizeWorkspace({'view': view}).view, view);
      }
    });

    test('remembered paths are trimmed, de-duplicated, and capped in order', () {
      final workspace = normalizeWorkspace({
        'pdf': {
          'recentPaths': [
            ' /docs/first.pdf ',
            '/docs/first.pdf',
            '',
            '   ',
            null,
            7,
            for (var i = 0; i < maxRecentPaths + 5; i++) '/docs/gen-$i.pdf',
          ],
        },
      });
      final paths = workspace.pdf.recentPaths;
      expect(paths.first, '/docs/first.pdf');
      expect(paths.where((p) => p == '/docs/first.pdf').length, 1);
      expect(paths.length, maxRecentPaths);
      expect(paths[1], '/docs/gen-0.pdf');
      expect(paths.contains('/docs/gen-${maxRecentPaths + 4}.pdf'), isFalse);
    });

    test('a corrupt path list degrades to empty', () {
      for (final value in [null, 'not-a-list', 42, {'a': 1}]) {
        final workspace = normalizeWorkspace({
          'pdf': {'recentPaths': value},
          'images': {'recentPaths': value},
        });
        expect(workspace.pdf.recentPaths, isEmpty);
        expect(workspace.images.recentPaths, isEmpty);
      }
    });

    test('outline items with no title are dropped', () {
      final workspace = normalizeWorkspace({
        'tocItems': [
          {'title': ''},
          {'title': 42},
          {
            'id': 'toc-1',
            'title': '  Chapter one  ',
            'level': 9,
            'content': 'body',
            'links': {
              'pdfPage': 3,
              'pdfName': ' report.pdf ',
              'images': ['/a.jpg', '', null],
              'location': {'lat': 51.5, 'lon': -0.12},
            },
            'updatedAt': 1234,
          },
        ],
      });
      expect(workspace.tocItems.length, 1);
      final item = workspace.tocItems.single;
      expect(item.id, 'toc-1');
      expect(item.title, 'Chapter one');
      expect(item.level, 3);
      expect(item.content, 'body');
      expect(item.links.pdfPage, 3);
      expect(item.links.pdfName, 'report.pdf');
      expect(item.links.images, ['/a.jpg']);
      expect(item.links.location!.lat, 51.5);
      expect(item.updatedAt, 1234);
    });

    test('a corrupt location reads as no location', () {
      final workspace = normalizeWorkspace({
        'tocItems': [
          {
            'title': 'Section',
            'links': {
              'location': {'lat': 400, 'lon': 0},
            },
          },
        ],
        'map': {
          'places': [
            {'label': 'Broken', 'lat': 'nope', 'lon': 1},
            {'label': 'Valid', 'lat': '51.5', 'lon': '-0.12'},
            {'label': ''},
            {'lat': 1, 'lon': 2},
          ],
        },
      });
      expect(workspace.tocItems.single.links.location, isNull);
      expect(workspace.map.places.length, 1);
      expect(workspace.map.places.single.label, 'Valid');
      expect(workspace.map.places.single.lat, 51.5);
    });

    test('places keep order, drop duplicate ids, and cap at 200', () {
      final places = [
        for (var i = 0; i < maxSavedPlaces + 10; i++)
          {'id': 'place-$i', 'label': 'P$i', 'lat': 1, 'lon': 2},
        {'id': 'place-0', 'label': 'Duplicate', 'lat': 3, 'lon': 4},
      ];
      final workspace = normalizeWorkspace({
        'map': {'places': places},
      });
      expect(workspace.map.places.length, maxSavedPlaces);
      expect(workspace.map.places.first.id, 'place-0');
      expect(workspace.map.places.first.label, 'P0');
      expect(
        workspace.map.places.where((place) => place.id == 'place-0').length,
        1,
      );
    });

    test('map and google options degrade to their defaults', () {
      final workspace = normalizeWorkspace({
        'map': {
          'sidebarOpen': false,
          'filter': 'sepia',
          'renderer': 'canvas',
          'showGrid': true,
          'showCursor': false,
        },
        'googleMap': {'layer': 's', 'renderer': 'weird'},
      });
      expect(workspace.map.sidebarOpen, isFalse);
      expect(workspace.map.filter, 'sepia');
      expect(workspace.map.renderer, 'canvas');
      expect(workspace.map.showGrid, isTrue);
      expect(workspace.map.showCursor, isFalse);
      expect(workspace.googleMap.layer, 's');
      expect(workspace.googleMap.renderer, 'dom');

      final corrupt = normalizeWorkspace({
        'map': {'filter': 'neon', 'renderer': 'svg'},
        'googleMap': {'layer': 'z'},
      });
      expect(corrupt.map.filter, 'none');
      expect(corrupt.map.renderer, 'dom');
      expect(corrupt.googleMap.layer, 'm');
    });
  });

  group('serializeWorkspace', () {
    test('round-trips through normalize', () {
      final original = normalizeWorkspace({
        'view': 'toc',
        'activeTocId': 'toc-9',
        'tocItems': [
          {'id': 'toc-9', 'title': 'One', 'level': 2, 'content': 'draft'},
        ],
        'editor': {'content': 'draft'},
        'savedAt': 1700000000000,
      });
      final decoded = normalizeWorkspace(jsonDecode(serializeWorkspace(original.toJson())));
      expect(decoded.view, 'toc');
      expect(decoded.activeTocId, 'toc-9');
      expect(decoded.tocItems.single.title, 'One');
      expect(decoded.editorContent, 'draft');
      expect(decoded.savedAt, 1700000000000);
    });

    test('a corrupt state still serializes to a valid record', () {
      final payload = serializeWorkspace({'view': 'nope', 'savedAt': -4});
      final decoded = normalizeWorkspace(jsonDecode(payload));
      expect(decoded.view, 'menu');
      expect(decoded.savedAt, 0);
    });
  });

  group('helpers', () {
    test('countWords matches whitespace splitting', () {
      expect(countWords(null), 0);
      expect(countWords('   '), 0);
      expect(countWords('one two  three'), 3);
    });

    test('clampLevel accepts numbers and strings', () {
      expect(clampLevel(0), 1);
      expect(clampLevel(5), 3);
      expect(clampLevel('2'), 2);
      expect(clampLevel('abc'), 1);
      expect(clampLevel(null), 1);
      expect(clampLevel(true), 1);
    });

    test('createTocItem-style ids are unique', () {
      final first = nextTocId();
      final second = nextTocId();
      expect(first, startsWith('toc-'));
      expect(second, startsWith('toc-'));
      expect(first == second, isFalse);
    });
  });
}
