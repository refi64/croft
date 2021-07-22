/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:croft/src/component.dart';
import 'package:croft/src/git_repo.dart';
import 'package:croft/src/log.dart';

class PatchSet {
  static const _safetyMaxPatchCount = 50;
  static const _indentation = 2;

  // XXX: Git actually does 63 in practice, even though the man page says 64, I
  // think it counts the null terminator as part of this?
  static const _maxPatchNameLength = 64;
  static const _patchSuffix = '.patch';

  final Directory sourcesRoot;
  final String patchesSubdir;
  final Component component;

  final _indentedEncoder = JsonEncoder.withIndent(' ' * _indentation);

  PatchSet(
      {required String sourcesRoot,
      required this.patchesSubdir,
      required this.component})
      : sourcesRoot = Directory(sourcesRoot);

  factory PatchSet.forSourcesRoot(
          {required String sourcesRoot,
          required String patchesSubdir,
          required Component component}) =>
      PatchSet(
          sourcesRoot: sourcesRoot,
          patchesSubdir: p.join(patchesSubdir, component.typeDescription),
          component: component);

  Directory get patchesDir =>
      Directory(p.join(sourcesRoot.path, patchesSubdir));

  String _getPatchFilename(String subject) {
    if (subject.length + _patchSuffix.length > _maxPatchNameLength) {
      subject = subject.substring(0, _maxPatchNameLength - _patchSuffix.length);
    }

    return '$subject.patch';
  }

  File get _sourcesFile => File(p.join(patchesDir.path, '_sources.json'));

  Future<void> _writeRelativePatchFilesToSources(List<String> patches) async {
    var source = {'type': 'patch', 'paths': patches};
    await _sourcesFile.writeAsString(_indentedEncoder.convert([source]));
  }

  Future<List<String>> _readPatchNamesFromSources() async {
    if (!await _sourcesFile.exists()) {
      log.fatal('$_sourcesFile does not exist');
    }

    var source = json.decode(await _sourcesFile.readAsString()) as List;
    return (source[0]['paths'] as List).cast<String>();
  }

  Future<void> _clearOutputDirectory() async {
    if (await patchesDir.exists()) {
      await patchesDir.delete(recursive: true);
    }
  }

  Future<void> exportAllPatches() async {
    await _clearOutputDirectory();
    await patchesDir.create(recursive: true);

    log.info('Finding parent revision...');
    var parentRev = await component.getUpstreamRevision();

    var commits = await component.repo
        .getCommitsInRangeInclusive(from: parentRev, to: GitRepo.headRevision);
    if (commits.length > _safetyMaxPatchCount) {
      log.fatal(
          "${commits.length} is too many patches, are you sure you're on the " +
              'right commit?');
    } else if (commits.isEmpty) {
      log.fatal('No patches to export found');
    }

    await component.ensurePatchListIsComplete(
        from: commits.first, to: commits.last);

    log.info('Exporting ${commits.length} patches...');

    var relativePatches = <String>[];
    for (var commit in commits) {
      var subject = await component.repo.formatAsSanitizedSubject(commit);
      var patchFilename = _getPatchFilename(subject);

      // Due to flatpak-builder intricacies, the patch file names in the sources
      // file must be relative to the sources root, not the location of the
      // sources JSON.
      var patchRelativeToSourcesRoot = p.join(patchesSubdir, patchFilename);
      relativePatches.add(patchRelativeToSourcesRoot);

      var patchFile =
          File(p.join(sourcesRoot.path, patchRelativeToSourcesRoot));
      var content = await component.repo
          .getCommitPatch(rev: commit, prefix: component.patchPrefix);
      await patchFile.writeAsString(content);
    }

    log.info('Saving patch list...');
    await _writeRelativePatchFilesToSources(relativePatches);
  }

  Future<void> applyAllPatches({bool skipFFmpegConfig = false}) async {
    var patchNames = await _readPatchNamesFromSources();
    if (skipFFmpegConfig) {
      // This should have been checked by the caller.
      assert(component.type == ComponentType.ffmpeg);

      // We always try to guarantee the FFmpeg patch the last one on the list,
      // so it can easily be skipped here.
      if (patchNames.isNotEmpty) {
        patchNames.removeLast();
      }
    }

    if (patchNames.isEmpty) {
      log.fatal('No patches to apply found.');
    }

    var patches = patchNames
        .map((relative) => p.join(sourcesRoot.path, relative))
        .toList();
    log.info('Applying ${patches.length} patch(es)...');

    var stripPrefix = component.patchPrefix?.split(p.separator).length ?? 0;
    await component.repo
        .applyPatches(patches, additionalStripComponents: stripPrefix);
  }
}
