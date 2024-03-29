/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:posix/posix.dart';

import 'package:croft/src/component.dart';
import 'package:croft/src/component/chromium.dart';
import 'package:croft/src/docker.dart';
import 'package:croft/src/git_repo.dart';
import 'package:croft/src/log.dart';

const _repoPath = 'third_party/ffmpeg';

enum _DockerImage {
  configGenerator('croft-ffmpeg-config', _repoPath),
  toolchainBuilder('croft-ffmpeg-toolchain-builder');

  final String name;
  final String? workingDirectory;
  const _DockerImage(this.name, [this.workingDirectory]);
}

class FFmpegComponent extends Component {
  static const _configCommitAuthor = 'CroFT <croft@refi64.com>';
  static const _configCommitMessage = 'Update build configuration';

  static const _imageBase = 'debian:10';
  static const _configImagePackages = [
    'build-essential',
    'libfdk-aac-dev:amd64',
    'libfdk-aac-dev:arm64',
    'libopenh264-dev:amd64',
    'libopenh264-dev:arm64',
    'libxml2',
    'nasm',
    'pkgconf',
    'python3',
  ];

  static const _toolchainBuilderImagePackages = [
    'build-essential',
    'clang-11',
    'cmake',
    'git',
    'libxml2-dev',
    'libz-dev',
    'lld-11',
    'ninja-build',
  ];

  static const _arm64CrossCompiler = 'gcc-aarch64-linux-gnu';
  static const _x64CrossCompiler = 'gcc-x86-64-linux-gnu';

  static const _imageChromiumMount = '/chromium';

  static const _chromiumScriptsRoot = 'chromium/scripts';
  static const _ffmpegBuildScript = '$_chromiumScriptsRoot/build_ffmpeg.py';
  static const _copyConfigScript = '$_chromiumScriptsRoot/copy_config.sh';
  static const _generateGNScript = '$_chromiumScriptsRoot/generate_gn.py';

  static const _depName = 'src/$_repoPath';

  @override
  final type = ComponentType.ffmpeg;
  @override
  final GitRepo repo;

  @override
  String get patchPrefix => _repoPath;

  final ChromiumComponent _chromium;
  final Docker _docker;

  FFmpegComponent(this._chromium, this._docker)
      : repo = GitRepo(p.join(_chromium.path, _repoPath));

  @override
  Future<String> getUpstreamRevision() async =>
      await _hackyGetUpstreamRevision() ??
      await _chromium.getDependencyRevision('$_depName');

  @override
  Future<void> ensurePatchListIsComplete(
      {required String from, required String to}) async {
    var configCommit = await _getConfigCommit(from: from, to: to);
    if (configCommit == null) {
      log.fatal('The FFmpeg configuration patch has not been created yet');
    }

    var latestCommitAuthor = await repo.getAuthor(to);
    if (latestCommitAuthor != _configCommitAuthor) {
      log.fatal('The config commit MUST be the most recent one');
    }
  }

  // The "proper" way to get the revision is asking gclient, but gclient can be
  // *very* slow here. As a faster workaround, we parse the DEPS file manually,
  // find the line setting the FFmpeg dependency, then keep scanning lines until
  // we reach its supposed commit.
  Future<String?> _hackyGetUpstreamRevision() async {
    var deps = await File(p.join(_chromium.path, 'DEPS')).readAsLines();
    var commitAtLineEnd = RegExp(r"'([^']+)',$");

    var waitingForCommit = false;
    for (var line in deps) {
      if (line.contains('ffmpeg_revision')) {
        waitingForCommit = true;
      }

      if (waitingForCommit && line.endsWith(',')) {
        var match = commitAtLineEnd.firstMatch(line);
        if (match != null) {
          return match.group(1);
        }
      }
    }

    log.warning('Could not find FFmpeg commit using fast path,'
        ' now trying slow path...');
    return null;
  }

  Future<String?> getLastConfigCommit() async => await _getConfigCommit(
      from: GitRepo.previousRevision, to: GitRepo.headRevision);

  Future<void> buildCustomToolchain() async {
    log.info('Building docker image...');
    var dockerfile = DockerfileBuilder.from(_imageBase)
      ..run('apt-get update')
      ..run('apt-get install -y ${_toolchainBuilderImagePackages.join(' ')}');

    await _docker.buildWithTransientContext(
        name: _DockerImage.toolchainBuilder.name, dockerfile: dockerfile);

    var imageToolchainRoot = _getImageToolchainRoot(useCustomToolchain: true);

    await _runImageCommand(_DockerImage.toolchainBuilder, [
      'python3',
      'tools/clang/scripts/build.py',
      '--build-dir=$imageToolchainRoot',
      '--disable-asserts',
      '--gcc-toolchain=/usr',
      '--host-cc=/usr/bin/clang-11',
      '--host-cxx=/usr/bin/clang++-11',
      '--with-ml-inliner-model=',
      '--without-android',
      '--without-fuchsia',
      '--use-system-cmake',
      '--use-system-libxml',
    ]);
  }

  Future<void> generateConfiguration(
      {required bool commit, required bool useCustomToolchain}) async {
    if (commit) {
      if (!await repo.isClean() || await repo.hasUntrackedFiles()) {
        log.fatal('FFmpeg repo is dirty or has untracked files, try'
            " 'croft destructive-reset ffmpeg' first");
      }

      var existingConfigCommit = await getLastConfigCommit();
      if (existingConfigCommit != null) {
        log.fatal('An FFmpeg configuration commit is already present'
            " (use 'croft descructive-reset ffmpeg pre-config' to undo it)");
      }
    }

    log.info('Building docker image...');
    await _buildImage(useCustomToolchain: useCustomToolchain);

    log.info('Copying libraries into Chromium sysroot...');
    for (var arch in Arch.values) {
      var archLibdir = '${arch.debianArchName}-linux-gnu';

      for (var includeDir in ['fdk-aac', 'wels']) {
        await _copyIntoSysroot(arch, '/usr/include/$includeDir');
      }

      for (var lib in ['fdk-aac', 'openh264']) {
        await _copyIntoSysroot(arch, '/usr/lib/$archLibdir/lib$lib.so');
      }
    }

    for (var arch in Arch.values) {
      log.info('Building FFmpeg for ${arch.ffmpegName}...');
      await _runImageCommand(_DockerImage.configGenerator,
          [_ffmpegBuildScript, 'linux', arch.ffmpegName]);
    }

    log.info('Copying configs...');
    await _runImageCommand(_DockerImage.configGenerator, [_copyConfigScript]);

    log.info('Generating GN files...');
    await _runImageCommand(_DockerImage.configGenerator, [_generateGNScript]);

    if (commit) {
      log.info('Committing changes...');
      await repo.add(['.']);
      await repo.commit(
          message: _configCommitMessage, author: _configCommitAuthor);
    }
  }

  Future<String?> _getConfigCommit(
      {required String from, required String to}) async {
    var commits = await repo.getCommitsInRangeInclusive(
        from: from, to: to, author: _configCommitAuthor);
    if (commits.length > 1) {
      log.fatal(
          'Multiple commits to generate the FFmpeg configuration were found!');
    }

    return commits.isNotEmpty ? commits.first : null;
  }

  Future<void> _buildImage({required bool useCustomToolchain}) async {
    var packages = List.of(_configImagePackages);

    var machine = uname().machine;

    if (machine != Arch.arm64.debianArchName) {
      packages.add(_arm64CrossCompiler);
    }
    if (machine != Arch.x64.debianArchName) {
      packages.add(_x64CrossCompiler);
    }

    var imageToolchainRoot =
        _getImageToolchainRoot(useCustomToolchain: useCustomToolchain);
    var imageToolchainBin = '$imageToolchainRoot/bin';
    var dockerfile = DockerfileBuilder.from(_imageBase)
      ..run('dpkg --add-architecture amd64')
      ..run('dpkg --add-architecture arm64')
      ..run(r"sed -i 's/main$/\0 non-free/' /etc/apt/sources.list")
      ..run(r"echo 'deb http://www.deb-multimedia.org buster main non-free'"
          ' >> /etc/apt/sources.list')
      ..run('apt-get update -oAcquire::AllowInsecureRepositories=true')
      ..run('apt-get install -y --allow-unauthenticated deb-multimedia-keyring')
      ..run('apt-get update')
      ..run('apt-get install -y ${packages.join(' ')}')
      ..run('update-alternatives --install /usr/bin/python python'
          ' /usr/bin/python3 1')
      ..run('rm -rf /var/lib/apt/lists/*')
      ..runtimeEnv('PATH', imageToolchainBin + r':$PATH');

    await _docker.buildWithTransientContext(
        name: _DockerImage.configGenerator.name, dockerfile: dockerfile);

    // Sanity check that PATH was set correctly
    var pathResult = await _docker.runCapture(
        _DockerImage.configGenerator.name, ['bash', '-c', r'echo $PATH']);
    if (!pathResult.stdout.trim().startsWith(imageToolchainBin + ':')) {
      log.fatal('PATH was not set correctly in the resulting image');
    }
  }

  String _getImageToolchainRoot({required bool useCustomToolchain}) {
    var dir = ChromiumComponent.getLLVMToolchainDirectory(
        id: useCustomToolchain ? 'ffmpeg' : null);
    return '$_imageChromiumMount/$dir';
  }

  Future<void> _runImageCommand(_DockerImage image, List<String> command,
      {Map<String, String> env = const {}}) async {
    await _docker.run(image.name, command,
        env: env,
        volumes: [Volume(source: _chromium.path, dest: _imageChromiumMount)],
        workingDirectory: image.workingDirectory != null
            ? p.join(_imageChromiumMount, image.workingDirectory)
            : _imageChromiumMount);
  }

  Future<void> _copyIntoSysroot(Arch arch, String path) async {
    if (!p.isAbsolute(path)) {
      throw ArgumentError.value(path, 'path', 'Must be absolute');
    }

    var sysrootPath = p.join(
      _imageChromiumMount,
      _chromium.getSysrootRelativePath(arch),
      p.relative(path, from: '/'),
    );

    // Running these in one docker invocation is faster than splitting it into
    // multiple.
    await _runImageCommand(_DockerImage.configGenerator, [
      'sh',
      '-c',
      r'rm -rf "$DEST" && mkdir -p "$DEST_PARENT" && cp -Lr "$SOURCE" "$DEST"'
    ], env: {
      'SOURCE': path,
      'DEST_PARENT': p.dirname(sysrootPath),
      'DEST': sysrootPath
    });
  }
}
