/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:meta/meta.dart';
import 'package:plade/plade.dart';
import 'package:plade/dispatch.dart';

import 'package:croft/src/command/common.dart';
import 'package:croft/src/log.dart';

mixin _FlatpakBuilderCommand<T> on CommandHandler<T> {
  late Arg<int?> jobs;

  @override
  @mustCallSuper
  void register(ArgParser parser) {
    jobs = parser.addOptionN(
      'jobs',
      short: 'j',
      description: 'Number of parallel build jobs to pass to flatpak-builder',
      parser: intValueParser,
    );
  }
}

class BuildReleaseCommand extends CommandHandler<String>
    with _FlatpakBuilderCommand {
  @override
  final String id = 'build-release';

  @override
  final String description = 'Runs a full Flatpak release build.';

  @override
  void register(ArgParser parser) {
    super.register(parser);
  }

  @override
  Future<void> run(HandlerContext context) async {
    var flatpakBuilder = context.container.createFlatpakBuilder();

    log.info('Clearing old build directories...');
    await flatpakBuilder.clearSavedBuildDirs(
        module: context.container.project.mainModule);

    log.info('Running build...');
    await flatpakBuilder.build(jobs: jobs.value);
  }
}

class BuildShellCommand extends CommandHandler<String>
    with _FlatpakBuilderCommand {
  @override
  final String id = 'build-shell';

  @override
  final String description =
      "Opens a Flatpak shell with all of Chromium's dependencies present.";

  @override
  void register(ArgParser parser) {
    super.register(parser);
  }

  @override
  Future<void> run(HandlerContext context) async {
    var flatpakBuilder = context.container.createFlatpakBuilder();

    log.info('Building predecessor modules...');
    await flatpakBuilder.build(
      stopAtModule: context.container.project.mainModule,
      jobs: jobs.value,
    );

    log.info('Opening shell!');
    await flatpakBuilder.openShell();
  }
}
