/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:plade/plade.dart';
import 'package:plade/dispatch.dart';

import 'package:croft/src/command/common.dart';
import 'package:croft/src/component/ffmpeg.dart';
import 'package:croft/src/git_repo.dart';
import 'package:croft/src/log.dart';

enum ResetTarget { latest, upstream, preConfig }

class DestructiveResetCommand extends CommandHandler<String>
    with ComponentCommand {
  @override
  final String id = 'destructive-reset';

  @override
  final String description = '''
      Performs a hard reset of the given component source tree, reverting all
      uncommitted changes and removing all untracked files.
      '''
      .flowLines();

  late Arg<ResetTarget> target;

  @override
  void register(ArgParser parser) {
    super.register(parser);

    target = parser.addPositional('target',
        requires: Requires.optional(ResetTarget.latest),
        description: """
            One of 'latest' (resets to the latest commit), 'upstream' (resets to
            the upstream commit as shown by 'get-upstream-revision'), or
            'pre-config' (FFmpeg-only, resets to the commit right before the
            configuration commit)
            """
            .flowLines(),
        parser: kebabCaseEnumChoiceValueParser(ResetTarget.values),
        printer: enumValuePrinter);
  }

  @override
  Future<void> run(HandlerContext context) async {
    var component = getComponent(context);

    late String rev;
    switch (target.value) {
      case ResetTarget.latest:
        rev = GitRepo.headRevision;
        break;
      case ResetTarget.preConfig:
        if (component is! FFmpegComponent) {
          log.fatal('pre-config target can only be used with FFmpeg');
        }

        var configCommit = await component.getLastConfigCommit();
        if (configCommit == null) {
          log.fatal('No config commit found');
        }
        rev = '$configCommit^';
        break;
      case ResetTarget.upstream:
        log.info('Finding upstream commit...');
        rev = await component.getUpstreamRevision();
        break;
    }

    log.info('Resetting to $rev...');
    await component.repo.hardReset(to: rev);

    log.info('Clearing untracked files...');
    await component.repo.deleteUntrackedFiles();
  }
}

class GenerateFFmpegConfigCommand extends CommandHandler<String> {
  @override
  final String id = 'generate-ffmpeg-config';

  @override
  final String description = '''
      Re-generates and commits the FFmpeg codec configuration.
      '''
      .flowLines();

  @override
  void register(ArgParser parser) {}

  @override
  Future<void> run(HandlerContext context) async {
    var ffmpeg = context.container.ffmpeg;
    await ffmpeg.generateConfiguration();
  }
}

class GetUpstreamRevisionCommand extends CommandHandler<String>
    with ComponentCommand {
  @override
  final String id = 'get-upstream-revision';

  @override
  final String description = '''
      Prints the upstream revision (that is, the revision before any patches
      were applied) for the given component.
      '''
      .flowLines();

  @override
  void register(ArgParser parser) {
    super.register(parser);
  }

  @override
  Future<void> run(HandlerContext context) async {
    print(await getComponent(context).getUpstreamRevision());
  }
}

class RebaseOnUpstreamCommand extends CommandHandler<String>
    with ComponentCommand {
  @override
  final String id = 'rebase-on-upstream';

  @override
  final String description = '''
      Launches an interactive rebase, with the upstream set to the upstream
      revision as shown by get-upstream-revision.
      '''
      .flowLines();

  @override
  void register(ArgParser parser) {
    super.register(parser);
  }

  @override
  Future<void> run(HandlerContext context) async {
    var component = getComponent(context);

    log.info('Determining rebase target...');
    var latestRev = await component.getUpstreamRevision();

    log.info('Launching rebase...');
    await component.repo.interactiveRebase(onto: latestRev);
  }
}
