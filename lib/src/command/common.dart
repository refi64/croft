/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:checked_yaml/checked_yaml.dart';
import 'package:meta/meta.dart';
import 'package:plade/dispatch.dart';
import 'package:plade/plade.dart';
import 'package:recase/recase.dart';

import 'package:croft/src/component.dart';
import 'package:croft/src/component/chromium.dart';
import 'package:croft/src/component/ffmpeg.dart';
import 'package:croft/src/config.dart';
import 'package:croft/src/docker.dart';
import 'package:croft/src/flatpak_builder.dart';
import 'package:croft/src/log.dart';
import 'package:croft/src/patch_set.dart';

ValueParser<T> kebabCaseEnumChoiceValueParser<T>(List<T> values) =>
    enumChoiceValueParser(values,
        interceptPrinter: (value) => ReCase(value).paramCase);

extension FlowLines on String {
  String flowLines() {
    var str = trimRight();

    // Remove a leading newline first.
    if (str.startsWith('\n')) {
      str = str.substring(1);
    }

    var result = <String>[];

    // Find the leading indentation and remove it from each line.
    int? leading = null;
    for (var line in str.split('\n')) {
      var lineLeading = line.length - line.trimLeft().length;
      leading ??= lineLeading;

      if (lineLeading < leading) {
        throw ArgumentError.value(line);
      }

      result.add(line.substring(leading));
    }

    return result.join(' ');
  }
}

class Container {
  final Config config;
  final Project project;

  Container({required this.config}) : project = _getProject(config);

  factory Container.withDefaultConfig() =>
      Container(config: _getDefaultConfig());

  static Config _getDefaultConfig() {
    try {
      return Config.parseDefaultFile();
    } on ConfigFileNotFound catch (ex) {
      log.fatal('Failed to locate config file: ${ex.file.path}');
    } on ParsedYamlException catch (ex) {
      log.fatal('Failed to parse config file:\n${ex.formattedMessage}');
    }
  }

  static Project _getProject(Config config) {
    var project = config.findProjectForDirectory() ?? config.defaultProject;
    if (project == null) {
      log.fatal('Current directory is not in a registered project.');
    }

    return project;
  }

  ChromiumComponent? _chromium;
  FFmpegComponent? _ffmpeg;

  ChromiumComponent get chromium {
    _chromium ??= ChromiumComponent(project.chromiumSourceRoot);
    return _chromium!;
  }

  FFmpegComponent get ffmpeg {
    _ffmpeg ??= FFmpegComponent(chromium, Docker(project.dockerCommand));
    return _ffmpeg!;
  }

  Component getComponent(ComponentType type) {
    switch (type) {
      case ComponentType.chromium:
        return chromium;
      case ComponentType.ffmpeg:
        return ffmpeg;
    }
  }

  PatchSet createPatchSet(Component component) => PatchSet(
      sourcesRoot: project.manifestDir,
      patchesSubdir: Config.patchesSubdir,
      component: component);

  FlatpakBuilder createFlatpakBuilder() => FlatpakBuilder(
      root: project.manifestDir,
      buildDirName: project.buildDirName,
      manifestName: project.manifestName);
}

abstract class ContainerHolder implements Handler {
  Container get container;
}

extension ContainerFromHandlerContext on HandlerContext {
  Container get container => parent<ContainerHolder>().container;
}

mixin ComponentCommand<T> on CommandHandler<T> {
  late Arg<ComponentType> componentType;

  @override
  @mustCallSuper
  void register(ArgParser parser) {
    componentType = parser.addPositional('component',
        description: 'Component for this command to use',
        parser: enumChoiceValueParser(ComponentType.values),
        printer: enumValuePrinter);
  }

  Component getComponent(HandlerContext context) =>
      context.container.getComponent(componentType.value);
}
