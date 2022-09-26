/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:croft/src/log.dart';
import 'package:plade/plade.dart';
import 'package:plade/dispatch.dart';

import 'package:croft/src/command/common.dart';

class BuildFFmpegToolchainCommand extends CommandHandler<String> {
  @override
  String id = 'build-ffmpeg-toolchain';

  @override
  final String description = '''
      Builds a new toolchain to be used by generate-ffmpeg-config. Only valid if
      use-custom-ffmpeg-toolchain in the config is set to true.
      '''
      .flowLines();

  @override
  void register(ArgParser parser) {}

  @override
  Future<void> run(HandlerContext context) async {
    if (!context.container.project.useCustomFFmpegToolchain) {
      log.fatal('Project does not have custom FFmpeg toolchains enabled');
    }

    var ffmpeg = context.container.ffmpeg;
    await ffmpeg.buildCustomToolchain();
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

  late Arg<bool> noCommit;

  @override
  void register(ArgParser parser) {
    noCommit = parser.addFlag('no-commit',
        description: "Don't commit the FFmpeg config");
  }

  @override
  Future<void> run(HandlerContext context) async {
    var ffmpeg = context.container.ffmpeg;
    await ffmpeg.generateConfiguration(
        commit: !noCommit.value,
        useCustomToolchain: context.container.project.useCustomFFmpegToolchain);
  }
}
