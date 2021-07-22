/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:plade/plade.dart';
import 'package:plade/dispatch.dart';

import 'package:croft/src/command/common.dart';
import 'package:croft/src/component/ffmpeg.dart';
import 'package:croft/src/log.dart';

class ApplyPatchesCommand extends CommandHandler<String> with ComponentCommand {
  @override
  final String id = 'apply-patches';

  @override
  final String description = '''
      Applies the patches saved in the manifest repo onto the component source
      tree.
      '''
      .flowLines();

  late Arg<bool> skipFFmpegConfig;

  @override
  void register(ArgParser parser) {
    super.register(parser);

    skipFFmpegConfig = parser.addFlag(
      'skip-ffmpeg-config',
      description: """
          Don't apply the FFmpeg config patch (only valid for the FFmpeg
          component)
          """
          .flowLines(),
    );
  }

  @override
  Future<void> run(HandlerContext context) async {
    var component = getComponent(context);
    if (skipFFmpegConfig.value && component is! FFmpegComponent) {
      log.fatal(
          '--skip-ffmpeg-config can only be used with the FFmpeg component');
    }

    var patchset = context.container.createPatchSet(component);
    await patchset.applyAllPatches(skipFFmpegConfig: skipFFmpegConfig.value);
  }
}

class ExportPatchesCommand extends CommandHandler<String>
    with ComponentCommand {
  @override
  final String id = 'export-patches';

  @override
  final String description = '''
      Exports all the patches in the component source tree into the manifest folder.
      '''
      .flowLines();

  @override
  void register(ArgParser parser) {
    super.register(parser);
  }

  @override
  Future<void> run(HandlerContext context) async {
    var component = getComponent(context);
    var patchset = context.container.createPatchSet(component);
    await patchset.exportAllPatches();
  }
}
