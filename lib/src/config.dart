/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:file/file.dart' show ErrorCodes;
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

part 'config.g.dart';

String _getHome() {
  return Platform.environment['HOME']!;
}

String _expandTilde(String path) {
  if (path.startsWith('~/')) {
    return p.join(_getHome(), path.substring(2));
  }

  return path;
}

enum XdgDir { cache, config }

String? _getXdgDirEnv(XdgDir dir) {
  switch (dir) {
    case XdgDir.cache:
      return 'XDG_CACHE_HOME';
    case XdgDir.config:
      return 'XDG_CONFIG_HOME';
  }
}

String? _getXdgDirFallback(XdgDir dir) {
  switch (dir) {
    case XdgDir.cache:
      return '.cache';
    case XdgDir.config:
      return '.config';
  }
}

String getXdgDir(XdgDir dir) {
  var env = Platform.environment[_getXdgDirEnv(dir)];
  return env ?? p.join(_getHome(), _getXdgDirFallback(dir));
}

@JsonSerializable(
    anyMap: true,
    checked: true,
    createToJson: false,
    disallowUnrecognizedKeys: true,
    fieldRename: FieldRename.kebab)
class Project {
  static const defaultBuildDirName = '_build';
  static const defaultDockerCommand = 'docker';

  @JsonKey(fromJson: _expandTilde)
  final String manifestDir;
  @JsonKey(fromJson: _expandTilde)
  final String chromiumSourceRoot;

  final String mainModule;
  final String manifestName;
  final String buildDirName;

  final String dockerCommand;

  @JsonKey(name: 'use-custom-ffmpeg-toolchain')
  final bool useCustomFFmpegToolchain;

  Project(
      {required this.manifestDir,
      required this.chromiumSourceRoot,
      required this.mainModule,
      required this.manifestName,
      // 'Config.' prefix is a workaround for:
      // https://github.com/google/json_serializable.dart/issues/946
      this.buildDirName = Project.defaultBuildDirName,
      this.dockerCommand = Project.defaultDockerCommand,
      this.useCustomFFmpegToolchain = false});

  factory Project.fromJson(Map json) => _$ProjectFromJson(json);

  List<String> get associatedDirectories => [manifestDir, chromiumSourceRoot];
}

class ConfigFileNotFound implements Exception {
  final File file;
  ConfigFileNotFound(this.file);

  String toString() => 'Failed to find config file ${file.path}';
}

@JsonSerializable(
    anyMap: true,
    checked: true,
    createToJson: false,
    disallowUnrecognizedKeys: true,
    fieldRename: FieldRename.kebab)
class Config {
  static const patchesSubdir = 'patches';

  final Map<String, Project> projects;
  @JsonKey(name: 'default-project')
  final String? defaultProjectName;

  Config({required this.projects, this.defaultProjectName}) {
    if (defaultProjectName != null) {
      var defaultProject = projects[defaultProjectName];
      if (defaultProject == null) {
        throw ArgumentError.value(defaultProjectName, 'default-project',
            'Project name does not exist');
      }

      _defaultProject = defaultProject;
    }
  }

  factory Config.fromJson(Map json) => _$ConfigFromJson(json);

  factory Config.parseString(String contents, {Uri? sourceUrl}) =>
      checkedYamlDecode(contents, (json) => Config.fromJson(json!),
          sourceUrl: sourceUrl);

  factory Config.parseFile(File file) {
    String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException catch (ex) {
      if ((ex.osError?.errorCode ?? 0) == ErrorCodes.ENOENT) {
        throw ConfigFileNotFound(file);
      } else {
        rethrow;
      }
    }

    return Config.parseString(contents, sourceUrl: Uri.file(file.path));
  }

  factory Config.parseDefaultFile() {
    var configPath = p.join(getXdgDir(XdgDir.config), 'croft.yaml');
    return Config.parseFile(File(configPath));
  }

  Project? _defaultProject;
  Project? get defaultProject => _defaultProject;

  Project? findProjectForDirectory([Directory? directory]) {
    directory ??= Directory.current;
    var path = directory.resolveSymbolicLinksSync();

    for (var project in projects.values) {
      for (var associated in project.associatedDirectories) {
        associated = Directory(associated).resolveSymbolicLinksSync();
        if (path == associated || p.isWithin(associated, path)) {
          return project;
        }
      }
    }
  }
}
