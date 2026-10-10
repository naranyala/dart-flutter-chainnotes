import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chainnotes/app/theme.dart';

/// Press feedback follows the platform: a ripple where taps are the pointer,
/// the flat ported look where hover answers (TODO-018).
void main() {
  test('touch platforms ripple, desktop stays flat', () {
    final original = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        buildWorkspaceTheme().splashFactory,
        same(InkSparkle.splashFactory),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        buildWorkspaceTheme().splashFactory,
        same(InkSparkle.splashFactory),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(buildWorkspaceTheme().splashFactory, same(NoSplash.splashFactory));
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(buildWorkspaceTheme().splashFactory, same(NoSplash.splashFactory));
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(buildWorkspaceTheme().splashFactory, same(NoSplash.splashFactory));
    } finally {
      debugDefaultTargetPlatformOverride = original;
    }
  });
}
