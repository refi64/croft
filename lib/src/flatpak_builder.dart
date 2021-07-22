/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:croft/src/log.dart';
import 'package:croft/src/tool_runner.dart';

class FlatpakBuilder {
  final ToolRunner _flatpakBuilder;
  final String root;
  final String buildDirName;
  final String manifestName;

  static const _stateDirName = '.flatpak-builder';

  FlatpakBuilder(
      {required this.root,
      required this.buildDirName,
      required this.manifestName})
      : _flatpakBuilder = ToolRunner(executable: 'flatpak-builder');

  String get _stateDirPath => p.join(root, _stateDirName);
  String get _buildDirPath => p.join(root, buildDirName);
  String get _manifestPath => p.join(root, manifestName);

  List<String> get _sharedArgs => [
        _buildDirPath,
        _manifestPath,
      ];

  Future<void> clearSavedBuildDirs({required String module}) async {
    var buildDirs = Directory(p.join(_stateDirPath, 'build'));
    var toDelete = <Directory>[];

    await for (var entry in buildDirs.list(followLinks: false)) {
      if (entry is Directory && p.basename(entry.path).startsWith('$module-')) {
        log.fine('Deleting ${entry.path}');
        toDelete.add(entry);
      }
    }

    await Future.wait(toDelete.map((e) => e.delete(recursive: true)));
  }

  Future<void> build({String? stopAtModule, int? jobs}) async {
    await _flatpakBuilder.run(
        [
          '--force-clean',
          '--state-dir=$_stateDirPath',
          if (stopAtModule != null) '--stop-at=$stopAtModule',
          if (jobs != null) '--jobs=$jobs',
        ]..addAll(_sharedArgs),
        exitOnFailure: true);
  }

  Future<void> openShell() async {
    await _flatpakBuilder.run(
        ['--run']
          ..addAll(_sharedArgs)
          ..add('bash'),
        exitOnFailure: true);
  }
}
