/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:posix/posix.dart';

import 'package:croft/src/tool_runner.dart';

extension _WithTemp on Directory {
  Future<T> withTemp<T>(
      String prefix, Future<T> Function(Directory) func) async {
    var temp = await createTemp(prefix);
    try {
      return await func(temp);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}

extension _WithFile on File {
  Future<T> withWrite<T>(Future<T> Function(IOSink sink) func) async {
    var sink = openWrite();
    try {
      return await func(sink);
    } finally {
      await sink.close();
    }
  }
}

class Volume {
  final String source;
  final String dest;
  final bool ro;

  Volume({required this.source, required this.dest, this.ro = false});

  String toString() => [
        source,
        dest,
        if (ro) ro,
      ].join(':');
}

class DockerfileBuilder {
  final String from;
  final List<String> _commands = [];

  DockerfileBuilder.from(this.from);

  Map<String, String> _runtimeEnv = {};
  List<String>? entrypoint;

  void run(String command) => _commands.add(command);
  void runtimeEnv(String key, String value) => _runtimeEnv[key] = value;

  void write(StringSink sink) {
    sink.writeln('FROM $from');

    for (var command in _commands) {
      sink.writeln('RUN $command');
    }

    for (var entry in _runtimeEnv.entries) {
      sink.writeln('ENV ${entry.key}=${entry.value}');
    }
  }
}

class Docker {
  static const _tempPrefix = 'croft-transient-build';

  ToolRunner _docker;

  Docker(String executable) : _docker = ToolRunner(executable: executable);

  Future<void> build({required String name, required Directory context}) async {
    await _docker.run([
      'build',
      '--tag=$name',
      context.path,
    ], exitOnFailure: true);
  }

  Future<void> buildWithTransientContext(
      {required String name, required DockerfileBuilder dockerfile}) async {
    await Directory.systemTemp.withTemp(_tempPrefix, (temp) async {
      await File(p.join(temp.path, 'Dockerfile')).withWrite((sink) async {
        dockerfile.write(sink);
        await build(name: name, context: temp);
      });
    });
  }

  List<String> _getRunCommand(String image, List<String> command,
          {required List<Volume> volumes,
          required String? workingDirectory,
          required Map<String, String> env}) =>
      [
        'run',
        '--security-opt=label=disable',
        '--rm',
        '-i',
        '--user=${getuid()}',
        for (var volume in volumes) '--volume=$volume',
        if (workingDirectory != null) '--workdir=$workingDirectory',
        for (var entry in env.entries) '--env=${entry.key}=${entry.value}',
        image,
      ]..addAll(command);

  Future<void> run(String image, List<String> command,
      {List<Volume> volumes = const [],
      String? workingDirectory,
      Map<String, String> env = const {}}) async {
    await _docker.run(
        _getRunCommand(image, command,
            volumes: volumes, workingDirectory: workingDirectory, env: env),
        exitOnFailure: true);
  }

  Future<StringProcessResult> runCapture(String image, List<String> command,
      {List<Volume> volumes = const [],
      String? workingDirectory,
      Map<String, String> env = const {}}) async {
    return await _docker.runCapture(
        _getRunCommand(image, command,
            volumes: volumes, workingDirectory: workingDirectory, env: env),
        exitOnFailure: true);
  }

  Future<bool> doesImageExist(String name, {String tag = 'latest'}) async {
    if (name.contains(':')) {
      throw ArgumentError.value(name, 'name', 'Should not contain a tag');
    }

    var result = await _docker
        .runCapture(['images', '-q', '$name:$tag'], exitOnFailure: true);
    return result.stdout.trim().isNotEmpty;
  }
}
