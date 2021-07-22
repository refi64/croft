/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:convert';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import 'package:croft/src/component.dart';
import 'package:croft/src/git_repo.dart';
import 'package:croft/src/log.dart';
import 'package:croft/src/tool_runner.dart';

part 'chromium.g.dart';

@JsonSerializable()
class _RevInfo {
  final String url;
  final String rev;

  _RevInfo({required this.url, required this.rev});

  factory _RevInfo.fromJson(Map<String, dynamic> json) =>
      _$RevInfoFromJson(json);
  Map<String, dynamic> toJson() => _$RevInfoToJson(this);
}

class _Gclient {
  final ToolRunner _gclient;

  _Gclient(String location)
      : _gclient =
            ToolRunner(executable: 'gclient', workingDirectory: location);

  Future<Map<String, _RevInfo>> revinfo(
      {List<String> filter = const []}) async {
    var result = await _gclient.runCapture(
        ['revinfo', '--output-json=-']
          ..addAll(filter.map((dep) => '--filter=$dep')),
        exitOnFailure: true);
    var info = json.decode(result.stdout) as Map;
    return {
      for (var entry in info.entries)
        entry.key as String:
            _RevInfo.fromJson(entry.value as Map<String, dynamic>)
    };
  }

  Future<_RevInfo> depRevinfo(String dep) async =>
      (await revinfo(filter: [dep]))[dep]!;
}

enum Arch { x64, arm64 }

extension ArchUtils on Arch {
  String get ffmpegName => toString().split('.')[1];

  String get sysrootArchName {
    switch (this) {
      case Arch.arm64:
        return 'arm64';
      case Arch.x64:
        return 'amd64';
    }
  }

  String get debianArchName {
    switch (this) {
      case Arch.arm64:
        return 'aarch64';
      case Arch.x64:
        return 'x86_64';
    }
  }
}

class ChromiumComponent extends Component {
  static const llvmToolchainBin = 'third_party/llvm-build/Release+Asserts/bin';

  static const _versionFileKeys = ['MAJOR', 'MINOR', 'BUILD', 'PATCH'];

  @override
  final type = ComponentType.chromium;
  @override
  final GitRepo repo;

  final String path;
  final _Gclient _gclient;

  ChromiumComponent(this.path)
      : repo = GitRepo(path),
        _gclient = _Gclient(path);

  @override
  Future<String> getUpstreamRevision() async {
    var versionFile = File(p.join(path, 'chrome', 'VERSION'));
    var versionData = <String, String>{};

    for (var line in await versionFile.readAsLines()) {
      var parts = line.split('=');
      if (!_versionFileKeys.contains(parts[0])) {
        log.fatal('Unknown line in ${versionFile.path} file: $line');
      }

      versionData[parts[0]] = parts[1];
    }

    var version = _versionFileKeys.map((k) => versionData[k]!).join('.');
    if (!await repo.isAncestor(parent: version, commit: GitRepo.headRevision)) {
      log.fatal('Bad version in VERSION file');
    }

    return version;
  }

  Future<String> getDependencyRevision(String dep) async =>
      (await _gclient.depRevinfo(dep)).rev;

  String getSysrootRelativePath(Arch arch) => p.join(
        'build',
        'linux',
        'debian_sid_${arch.sysrootArchName}-sysroot',
      );
}
