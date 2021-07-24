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

  static const _mergedSourcesJson = 'all.json';
  static const _componentSourcesJson = '_sources.json';

  final Directory sourcesRoot;
  final String patchesSubdir;
  final Component component;

  final Directory patchesRoot;

  final _indentedEncoder = JsonEncoder.withIndent(' ' * _indentation);

  PatchSet(
      {required String sourcesRoot,
      required this.patchesSubdir,
      required this.component})
      : sourcesRoot = Directory(sourcesRoot),
        patchesRoot = Directory(p.join(sourcesRoot, patchesSubdir));

  String _getPatchFilename(String subject) {
    if (subject.length + _patchSuffix.length > _maxPatchNameLength) {
      subject = subject.substring(0, _maxPatchNameLength - _patchSuffix.length);
    }

    return '$subject.patch';
  }

  Directory _getComponentPatchesDir(ComponentType type) =>
      Directory(p.join(patchesRoot.path, type.description));

  File _getComponentSourcesFile(ComponentType type) =>
      File(p.join(_getComponentPatchesDir(type).path, _componentSourcesJson));

  Future<void> _writeRelativePatchFilesToSources(
      File sourcesFile, List<String> patches) async {
    var source = {'type': 'patch', 'paths': patches};
    await sourcesFile.writeAsString(_indentedEncoder.convert([source]));
  }

  Future<List<String>> _readPatchNamesFromSources(File sourcesFile) async {
    if (!await sourcesFile.exists()) {
      log.fatal('$sourcesFile does not exist');
    }

    var source = json.decode(await sourcesFile.readAsString()) as List;
    return (source[0]['paths'] as List).cast<String>();
  }

  // As a workaround for https://github.com/flatpak/flatpak-builder/issues/282
  // we can merge all the individual source manifests together into a single
  // one. In theory, we could have done this from the start instead of using
  // individual files, but the time for that decision has mostly passed.
  Future<void> _mergeSourceManifests() async {
    var allPatchNames = <String>[];

    for (var type in ComponentType.values) {
      var sourcesFile = _getComponentSourcesFile(type);
      var patchNames = await _readPatchNamesFromSources(sourcesFile);
      allPatchNames.addAll(patchNames);
    }

    var mergedSourcesFile = File(p.join(patchesRoot.path, _mergedSourcesJson));
    await _writeRelativePatchFilesToSources(mergedSourcesFile, allPatchNames);
  }

  Future<void> _clearOutputDirectory(Directory patchesDir) async {
    if (await patchesDir.exists()) {
      await patchesDir.delete(recursive: true);
    }
  }

  Future<void> exportAllPatches() async {
    var patchesDir = _getComponentPatchesDir(component.type);
    var sourcesFile = _getComponentSourcesFile(component.type);

    var relativePatchesDir =
        p.relative(patchesDir.path, from: sourcesRoot.path);

    await _clearOutputDirectory(patchesDir);
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
      // sources manifest.
      var patchRelativeToSourcesRoot =
          p.join(relativePatchesDir, patchFilename);
      relativePatches.add(patchRelativeToSourcesRoot);

      var patchFile =
          File(p.join(sourcesRoot.path, patchRelativeToSourcesRoot));
      var content = await component.repo
          .getCommitPatch(rev: commit, prefix: component.patchPrefix);
      await patchFile.writeAsString(content);
    }

    log.info('Saving patch list...');
    await _writeRelativePatchFilesToSources(sourcesFile, relativePatches);
    await _mergeSourceManifests();
  }

  Future<void> applyAllPatches({bool skipFFmpegConfig = false}) async {
    var sourcesFile = _getComponentSourcesFile(component.type);
    var patchNames = await _readPatchNamesFromSources(sourcesFile);
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
