import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/geo/geo.dart';

import '../core/workspace/workspace_models.dart';
import '../core/workspace/workspace_persistence.dart';

class RemovedTocRecord {
  RemovedTocRecord({required this.item, required this.index, required this.wasActive});

  final TocItem item;
  final int index;
  final bool wasActive;
}

/// One status sentence per tool, the `StatusLine` of the original UI.
class ToolStatus {
  String message;
  bool isError;

  ToolStatus(this.message, {this.isError = false});

  void set(String message, {bool error = false}) {
    this.message = message;
    isError = error;
  }
}

/// The single record every tool reads and writes.
///
/// The controller owns the shared state plus the outline, editor, and link
/// operations; viewer state that never reaches disk lives in the tool sessions.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required WorkspaceRecord boot})
      : view = boot.view,
        tocItems = boot.tocItems,
        activeTocId = boot.tocItems.any((item) => item.id == boot.activeTocId)
            ? boot.activeTocId
            : null,
        linkTargetId = boot.activeTocId ??
            (boot.tocItems.isNotEmpty ? boot.tocItems.first.id : null),
        editorContent = boot.editorContent,
        pdf = boot.pdf,
        images = boot.images,
        map = boot.map,
        googleMap = boot.googleMap;

  WorkspacePersistence? persistence;

  /// Set before the first user gesture; hydration never wins over a state the
  /// user has already changed.
  bool userInteracted = false;

  String view;
  List<TocItem> tocItems;
  String? activeTocId;
  String? linkTargetId;
  String editorContent;
  PdfSessionData pdf;
  ImageSessionData images;
  MapSessionData map;
  GoogleMapSessionData googleMap;

  /* --- shared status ------------------------------------------------------- */

  final ToolStatus tocStatus =
      ToolStatus('Declare an outline item, then select it to start writing.');
  final ToolStatus editorStatus = ToolStatus('');
  final ToolStatus editorNotice = ToolStatus('');

  String editorCursorPosition = 'Line 1, Col 1';

  /* --- transient TOC manager state ----------------------------------------- */

  String tocDraftTitle = '';
  int tocDraftLevel = 1;
  String tocFilterQuery = '';
  String? editingTocId;
  String tocEditTitle = '';
  int tocEditLevel = 1;
  RemovedTocRecord? lastRemoved;

  /* --- derived ------------------------------------------------------------- */

  PersistenceMode get persistenceMode =>
      persistence?.mode ?? PersistenceMode.none;

  String get saveLabel => saveLabelFor(persistenceMode);

  PersistenceReport? get report => persistence?.report;

  TocItem? get activeTocItem {
    for (final item in tocItems) {
      if (item.id == activeTocId) return item;
    }
    return null;
  }

  int get activeTocIndex => tocItems.indexWhere((item) => item.id == activeTocId);

  TocItem? get linkTarget {
    for (final item in tocItems) {
      if (item.id == linkTargetId) return item;
    }
    return activeTocItem;
  }

  TocItem? get previousTocItem {
    final index = activeTocIndex;
    return index > 0 ? tocItems[index - 1] : null;
  }

  TocItem? get nextTocItem {
    final index = activeTocIndex;
    if (index < 0 || index >= tocItems.length - 1) return null;
    return tocItems[index + 1];
  }

  bool get showTocFilter => tocItems.length >= 8;

  List<TocItem> get filteredTocItems {
    final query = tocFilterQuery.trim().toLowerCase();
    if (query.isEmpty) return tocItems;
    return tocItems
        .where((item) => item.title.toLowerCase().contains(query))
        .toList();
  }

  String get tocItemLabel =>
      '${tocItems.length} item${tocItems.length == 1 ? '' : 's'} declared';

  /* --- snapshot / apply ---------------------------------------------------- */

  WorkspaceRecord snapshot() => WorkspaceRecord(
        savedAt: DateTime.now().millisecondsSinceEpoch,
        view: view,
        tocItems: tocItems,
        activeTocId: activeTocId,
        editorContent: editorContent,
        pdf: pdf,
        images: images,
        map: map,
        googleMap: googleMap,
      );

  void apply(WorkspaceRecord record) {
    view = record.view;
    tocItems = record.tocItems;
    activeTocId = record.activeTocId;
    editorContent = record.editorContent;
    pdf = record.pdf;
    images = record.images;
    map = record.map;
    googleMap = record.googleMap;
    notifyListeners();
  }

  void markUserInteracted() {
    userInteracted = true;
  }

  /// Every state change funnels through here: interaction latch first, then
  /// the debounced write, then the widgets.
  void touch({bool save = true}) {
    markUserInteracted();
    if (save) persistence?.schedule();
    notifyListeners();
  }

  void selectView(String nextView) {
    if (!workspaceViews.contains(nextView)) return;
    markUserInteracted();
    if (view == 'editor' && nextView != 'editor') syncTocDraft();
    view = nextView;
    persistence?.schedule();
    notifyListeners();
  }

  bool flushNow() => persistence?.flush() ?? false;

  /// Lets a tool session announce a change it made to shared state without
  /// marking the user as having interacted.
  void notifyChanged() => notifyListeners();

  /* --- editor binding ------------------------------------------------------ */

  /// Copies the editor buffer into the active item without switching views.
  void syncTocDraft() {
    final item = activeTocItem;
    if (item == null || item.content == editorContent) return;
    markUserInteracted();
    item.content = editorContent;
    item.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistence?.schedule();
  }

  void setEditorContent(String value) {
    if (editorContent == value) return;
    markUserInteracted();
    editorContent = value;
    syncTocDraft();
    notifyListeners();
  }

  void setCursorPosition(String value) {
    if (editorCursorPosition == value) return;
    editorCursorPosition = value;
    notifyListeners();
  }

  void setEditorNotice(String message, {bool error = false}) {
    editorNotice.set(message, error: error);
    notifyListeners();
  }

  /* --- outline CRUD -------------------------------------------------------- */

  void _clearPendingUndo() => lastRemoved = null;

  bool _saveOutline() {
    markUserInteracted();
    final saved = flushNow();
    if (!saved) {
      tocStatus.set('The workspace could not be saved on this device.',
          error: true);
    }
    return saved;
  }

  void addTocItem({String? title, int? level}) {
    _clearPendingUndo();
    final heading = asString(title ?? tocDraftTitle, maxTocTitleLength);
    if (heading.isEmpty) {
      tocStatus.set('Enter a heading title before declaring an item.',
          error: true);
      notifyListeners();
      return;
    }
    final item = TocItem(
      id: nextTocId(),
      title: heading,
      level: clampLevel(level ?? tocDraftLevel),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    tocItems.add(item);
    tocDraftTitle = '';
    if (_saveOutline()) tocStatus.set('“$heading” declared.');
    notifyListeners();
  }

  void removeTocItem(TocItem item) {
    final index = tocItems.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return;
    lastRemoved = RemovedTocRecord(
      item: item,
      index: index,
      wasActive: activeTocId == item.id,
    );
    tocItems.removeAt(index);
    if (activeTocId == item.id) activeTocId = null;
    if (linkTargetId == item.id) linkTargetId = null;
    if (_saveOutline()) {
      tocStatus.set('“${item.title}” removed from the outline.');
    }
    notifyListeners();
  }

  void undoTocRemoval() {
    final record = lastRemoved;
    if (record == null) return;
    lastRemoved = null;
    tocItems.insert(
        record.index.clamp(0, tocItems.length), record.item);
    if (record.wasActive) activeTocId = record.item.id;
    if (_saveOutline()) {
      tocStatus.set('“${record.item.title}” restored to the outline.');
    }
    notifyListeners();
  }

  void startTocEdit(TocItem item) {
    _clearPendingUndo();
    editingTocId = item.id;
    tocEditTitle = item.title;
    tocEditLevel = item.level;
    notifyListeners();
  }

  void cancelTocEdit() {
    editingTocId = null;
    tocEditTitle = '';
    tocEditLevel = 1;
    notifyListeners();
  }

  void saveTocEdit(TocItem item) {
    if (editingTocId != item.id) return;
    final title = tocEditTitle.trim();
    if (title.isEmpty) {
      tocStatus.set('Enter a heading title before saving.', error: true);
      notifyListeners();
      return;
    }
    item.title =
        title.length > maxTocTitleLength ? title.substring(0, maxTocTitleLength) : title;
    item.level = clampLevel(tocEditLevel);
    item.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (_saveOutline()) tocStatus.set('“${item.title}” updated.');
    cancelTocEdit();
  }

  void moveTocItem(TocItem item, int delta) {
    final index = tocItems.indexWhere((entry) => entry.id == item.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= tocItems.length) return;
    if (tocFilterQuery.trim().isNotEmpty) return;
    _clearPendingUndo();
    tocItems.insert(target, tocItems.removeAt(index));
    if (_saveOutline()) {
      tocStatus
          .set('Moved “${item.title}” ${delta < 0 ? 'up' : 'down'}.');
    }
    notifyListeners();
  }

  void selectTocItem(TocItem item) {
    syncTocDraft();
    activeTocId = item.id;
    linkTargetId ??= item.id;
    editorContent = item.content;
    editorNotice.set('');
    markUserInteracted();
    view = 'editor';
    persistence?.schedule();
    tocStatus.set('Writing “${item.title}”.');
    notifyListeners();
  }

  /* --- link actions (write side) ------------------------------------------- */

  bool attachPdfPage(int page, String name) {
    final target = linkTarget;
    if (target == null) return false;
    target.links.pdfPage = page;
    target.links.pdfName = name;
    target.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final saved = _saveOutline();
    if (saved) {
      tocStatus.set('Page $page attached to “${target.title}”.');
    }
    notifyListeners();
    return saved;
  }

  bool attachLocation(Location location) {
    final target = linkTarget;
    if (target == null) return false;
    target.links.location = location;
    target.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final saved = _saveOutline();
    if (saved) {
      tocStatus.set('Location attached to “${target.title}”.');
    }
    notifyListeners();
    return saved;
  }

  bool attachImages(List<String> paths) {
    final target = linkTarget;
    if (target == null) return false;
    final merged = <String>{...target.links.images};
    for (final path in paths) {
      if (path.trim().isEmpty) continue;
      if (merged.length >= maxImagesPerItem) break;
      merged.add(path);
    }
    target.links.images
      ..clear()
      ..addAll(merged.take(maxImagesPerItem));
    target.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final saved = _saveOutline();
    notifyListeners();
    return saved;
  }

  void setLinkTarget(String? id) {
    linkTargetId = id;
    notifyListeners();
  }

  /* --- outline JSON transfer ------------------------------------------------ */

  /// Versioned envelope for the outline export; ids are rebuilt on import.
  String exportTocJson() {
    final items = tocItems
        .map((item) => {
              'title': item.title,
              'level': item.level,
              'content': item.content,
              'links': item.links.toJson(),
              'updatedAt': item.updatedAt,
            })
        .toList();
    return JsonEncoder.withIndent('  ').convert({
      'format': 'metrics-toc',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items,
    });
  }

  /// Appends sections after the existing ones (never destructive). Returns the
  /// number imported, or -1 when the payload is not an outline export.
  int importTocJson(String source) {
    Object? parsed;
    try {
      parsed = jsonDecode(source);
    } on FormatException {
      tocStatus.set('That file is not an outline export.', error: true);
      notifyListeners();
      return -1;
    }
    if (parsed is! Map) {
      tocStatus.set('That file is not an outline export.', error: true);
      notifyListeners();
      return -1;
    }
    if (parsed['format'] != 'metrics-toc') {
      tocStatus.set('That file is not an outline export.', error: true);
      notifyListeners();
      return -1;
    }
    if ((parsed['version'] as num?)?.toInt() != 1) {
      tocStatus.set('That outline export uses an unsupported version.',
          error: true);
      notifyListeners();
      return -1;
    }
    final entries = parsed['items'];
    final imported = <TocItem>[];
    if (entries is List) {
      for (final entry in entries) {
        final item = normalizeTocItem({
          'id': nextTocId(),
          if (entry is Map) ...entry,
        });
        if (item != null) imported.add(item);
      }
    }
    if (imported.isEmpty) {
      tocStatus.set('That outline export contains no usable sections.',
          error: true);
      notifyListeners();
      return 0;
    }
    _clearPendingUndo();
    tocItems.addAll(imported);
    final saved = _saveOutline();
    if (saved) {
      tocStatus.set(
          'Imported ${imported.length} section${imported.length == 1 ? '' : 's'}.');
    }
    notifyListeners();
    return imported.length;
  }

  /* --- PDF headings import -------------------------------------------------- */

  int importPdfHeadings(List<Map<String, Object?>> headings, String pdfName) {
    if (headings.isEmpty) return 0;
    var added = 0;
    var skipped = 0;
    for (final heading in headings) {
      final title = asString(heading['title'], maxTocTitleLength);
      if (title.isEmpty) continue;
      final rawPage = heading['page'];
      final page = rawPage is num ? rawPage.toInt() : null;
      final normalizedPage = page == null ? null : (page < 1 ? 1 : page);
      final duplicate = tocItems.any((item) =>
          item.title == title && item.links.pdfPage == normalizedPage);
      if (duplicate) {
        skipped += 1;
        continue;
      }
      tocItems.add(TocItem(
        id: nextTocId(),
        title: title,
        level: clampLevel(heading['level']),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        links: ItemLinks(pdfPage: normalizedPage, pdfName: pdfName),
      ));
      added += 1;
    }
    if (added > 0) {
      _clearPendingUndo();
      _saveOutline();
      tocStatus.set(
          'Imported $added heading${added == 1 ? '' : 's'}${
              skipped > 0 ? ', skipped $skipped' : ''}.');
      notifyListeners();
    }
    return added;
  }

  /* --- map places ----------------------------------------------------------- */

  /// Add or re-top a saved place. Re-saving the same coordinate keeps the old
  /// label and moves the entry to the top instead of duplicating it.
  Place? addPlace({required double lat, required double lon, String? label}) {
    final normalized = normalizeLocation({'lat': lat, 'lon': lon, 'label': label ?? ''});
    if (normalized == null) return null;
    final existingIndex = map.places.indexWhere((place) =>
        place.lat == normalized.lat && place.lon == normalized.lon);
    if (existingIndex >= 0) {
      final existing = map.places.removeAt(existingIndex);
      map.places.insert(0, existing);
      touch();
      return existing;
    }
    if (map.places.length >= maxSavedPlaces) return null;
    final text = (label ?? '').trim();
    if (text.isEmpty) return null;
    final place = Place(
      id: nextPlaceId(),
      label: text.length > maxPlaceLabel ? text.substring(0, maxPlaceLabel) : text,
      lat: normalized.lat,
      lon: normalized.lon,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    map.places.insert(0, place);
    touch();
    return place;
  }

  int addPlaces(List<Place> candidates) {
    var imported = 0;
    for (final candidate in candidates) {
      if (addPlace(lat: candidate.lat, lon: candidate.lon, label: candidate.label) !=
          null) {
        imported++;
      }
      if (map.places.length >= maxSavedPlaces) break;
    }
    notifyListeners();
    return imported;
  }

  void renamePlace(Place place, String label) {
    final text = label.trim();
    if (text.isEmpty) return;
    place.label =
        text.length > maxPlaceLabel ? text.substring(0, maxPlaceLabel) : text;
    touch();
  }

  void removePlace(Place place) {
    map.places.removeWhere((entry) => entry.id == place.id);
    touch();
  }

  void clearPlaces() {
    map.places.clear();
    touch();
  }

  /* --- remembered paths ----------------------------------------------------- */

  void rememberPdfPath(String path) {
    if (path.trim().isEmpty) return;
    pdf.recentPaths.remove(path);
    pdf.recentPaths.insert(0, path);
    if (pdf.recentPaths.length > maxRecentPaths) {
      pdf.recentPaths = pdf.recentPaths.sublist(0, maxRecentPaths);
    }
    touch();
  }

  void forgetPdfPath(String path) {
    if (!pdf.recentPaths.contains(path)) return;
    pdf.recentPaths.remove(path);
    touch();
  }

  void rememberImageDirectory(String path) {
    if (path.trim().isEmpty) return;
    images.recentPaths.remove(path);
    images.recentPaths.insert(0, path);
    if (images.recentPaths.length > maxRecentPaths) {
      images.recentPaths = images.recentPaths.sublist(0, maxRecentPaths);
    }
    touch();
  }

  void forgetImageDirectory(String path) {
    if (!images.recentPaths.contains(path)) return;
    images.recentPaths.remove(path);
    touch();
  }
}
