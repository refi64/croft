/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:plade/plade.dart';
import 'package:plade/dispatch.dart';
import 'package:posix/posix.dart';

import 'package:croft/src/command/common.dart';
import 'package:croft/src/command/flatpak.dart';
import 'package:croft/src/command/git.dart';
import 'package:croft/src/command/patches.dart';
import 'package:croft/src/log.dart';

class _CroftHandler extends AppHandler
    implements ContainerHolder, WithCommands<String> {
  _CroftHandler(this.logHandler);

  final ConsoleLogHandler logHandler;

  @override
  final usageInfo =
      UsageInfo(application: 'croft', prologue: 'ChROmium Flatpak Toolkit');

  @override
  final commands = CommandHandlerSet.from([
    ApplyPatchesCommand(),
    BuildReleaseCommand(),
    BuildShellCommand(),
    DestructiveResetCommand(),
    ExportPatchesCommand(),
    GenerateFFmpegConfigCommand(),
    GetUpstreamRevisionCommand(),
    RebaseOnUpstreamCommand(),
  ]);

  late Container _container;
  @override
  Container get container => _container;

  late Arg<bool> verbose;
  late Arg<bool> disableColors;

  @override
  void register(ArgParser parser) {
    verbose = parser.addFlag(
      'verbose',
      short: 'v',
      description: 'Show verbose output',
    );

    disableColors = parser.addFlag('disable-colors',
        description: 'Disable all printed colors');
  }

  @override
  FutureOr<void> run(HandlerContext context) async {
    if (disableColors.value) {
      ConsoleLogHandler.disableColors();
    }

    if (verbose.value) {
      logHandler.enableVerbose();
    }

    _container = Container.withDefaultConfig();
  }
}

Future<void> runApp(List<String> args) async {
  var logHandler = ConsoleLogHandler(logger: Logger.root)..attach();

  try {
    await _CroftHandler(logHandler).runApp(args);
  } on FatalExit {
    exit(1);
  } on ArgParsingError catch (ex) {
    log.severe("${ex.message} (use 'croft --help' for help)");
    exit(1);
  } catch (ex, stackTrace) {
    log.severe('An exception has occurred!', ex, stackTrace);
    exit(1);
  }
}
