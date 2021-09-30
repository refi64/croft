/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:path/path.dart' as p;

import 'package:croft/src/log.dart';
import 'package:croft/src/tool_runner.dart';

extension _SplitLines on String {
  List<String> splitLines() =>
      split('\n').where((line) => line.isNotEmpty).toList();
}

class GitRepo {
  static const headRevision = 'HEAD';
  static const previousRevision = 'HEAD^';

  // The default value for -p that Git uses.
  static const defaultStripComponents = 1;

  final ToolRunner _git;

  GitRepo(String location)
      : _git = ToolRunner(executable: 'git', workingDirectory: location);

  Future<bool> isAncestor(
      {required String parent, required String commit}) async {
    var result =
        await _git.run(['merge-base', '--is-ancestor', parent, commit]);
    return result.exitCode == 0;
  }

  Future<String> formatAsSanitizedSubject(String rev) async {
    var result = await _git
        .runCapture(['show', '-s', '--format=%f', rev], exitOnFailure: true);
    return result.stdout.trim();
  }

  Future<String> getCommitPatch({required String rev, String? prefix}) async {
    if (prefix != null && !prefix.endsWith('/')) {
      prefix += '/';
    }

    var result = await _git.runCapture([
      'format-patch',
      '--stdout',
      '-N1',
      rev,
      if (prefix != null) '--src-prefix=a/$prefix',
      if (prefix != null) '--dst-prefix=b/$prefix',
    ], exitOnFailure: true);
    // Only trim on the left, because 'patch' always expects a trailing newline
    // when applying patches.
    return result.stdout.trimLeft();
  }

  Future<List<String>> getCommitsInRangeInclusive(
      {required String from, required String to, String? author}) async {
    var stdout = await _logPretty([
      if (author != null) '--author=$author',
      '$from..$to',
    ], format: '%H');
    // The commits are newest to oldest, so reverse the order.
    return stdout.splitLines().reversed.toList();
  }

  Future<String> getAuthor(String revision) async {
    var stdout = await _logPretty(['-1', revision], format: '%an <%ae>');
    return stdout.trim();
  }

  Future<String> _logPretty(List<String> args, {required String format}) async {
    var result = await _git.runCapture(
        ['log', '--pretty=$format']..addAll(args),
        exitOnFailure: true);
    return result.stdout;
  }

  Future<void> hardReset({required String to}) async =>
      await _git.run(['reset', '--hard', to], exitOnFailure: true);

  Future<void> deleteUntrackedFiles() async =>
      await _git.run(['clean', '-f'], exitOnFailure: true);

  Future<void> applyPatches(List<String> patches,
      {int additionalStripComponents = 0}) async {
    var stripComponents = defaultStripComponents + additionalStripComponents;
    var result = await _git.run(['am', '-3', '-p$stripComponents']..addAll(patches));
    if (result.exitCode != 0) {
      log.fatal(
          "'git am' returned an error, probably because of patch conflicts.");
    }
  }

  Future<bool> isClean() async {
    var result =
        await _git.runCapture(['diff-index', '--exit-code', headRevision]);
    return result.exitCode == 0;
  }

  Future<bool> hasUntrackedFiles() async {
    var result = await _git.runCapture(['ls-files', '-o', '--exclude-standard'],
        exitOnFailure: true);
    return result.stdout.trim().isNotEmpty;
  }

  Future<void> add(List<String> childPaths) async {
    for (var path in childPaths) {
      if (!p.isRelative(path)) {
        throw ArgumentError.value(
            path, 'childPaths', 'Child path must be relative');
      }
    }

    await _git.run(['add']..addAll(childPaths), exitOnFailure: true);
  }

  Future<void> commit({required String message, required String author}) async {
    await _git.run(['commit', '--message=$message', '--author=$author'],
        exitOnFailure: true);
  }

  Future<void> interactiveRebase({required String onto}) async {
    await _git.run(['rebase', '-i', onto], exitOnFailure: true);
  }
}
