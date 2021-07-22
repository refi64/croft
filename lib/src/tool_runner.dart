/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:croft/src/log.dart';

class BasicProcessResult {
  final int pid;
  final int exitCode;

  BasicProcessResult({required this.pid, required this.exitCode});
}

class StringProcessResult extends BasicProcessResult {
  final String stdout;

  StringProcessResult(
      {required int pid, required int exitCode, required this.stdout})
      : super(pid: pid, exitCode: exitCode);
}

class ToolRunner {
  final String executable;
  final String? workingDirectory;

  ToolRunner({required this.executable, this.workingDirectory});

  Future<Process> _startProcess(List<String> args,
      {required bool captureOutput}) async {
    try {
      return await Process.start(executable, args,
          workingDirectory: workingDirectory,
          mode: captureOutput
              ? ProcessStartMode.normal
              : ProcessStartMode.inheritStdio);
    } on ProcessException catch (ex) {
      log.fatal("Failed to start '$executable': ${ex.message}");
    }
  }

  Future<int> _getProcessResult(Process process, List<String> args,
      {required bool exitOnFailure}) async {
    var exitCode = await process.exitCode;
    if (exitCode != 0 && exitOnFailure) {
      log.fatal(
          "'$executable ${args.join(' ')}' failed with exit status $exitCode");
    }

    return exitCode;
  }

  Future<BasicProcessResult> run(List<String> args,
      {bool exitOnFailure = false}) async {
    var process = await _startProcess(args, captureOutput: false);
    var exitCode =
        await _getProcessResult(process, args, exitOnFailure: exitOnFailure);
    return BasicProcessResult(pid: process.pid, exitCode: exitCode);
  }

  Future<StringProcessResult> runCapture(List<String> args,
      {bool exitOnFailure = false}) async {
    var process = await _startProcess(args, captureOutput: true);
    process.stderr.transform(utf8.decoder).listen(stderr.write);

    var stdoutDone = Completer<void>();

    var stdoutBuffer = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write,
        onDone: stdoutDone.complete, onError: stdoutDone.completeError);

    var exitCode =
        await _getProcessResult(process, args, exitOnFailure: exitOnFailure);
    await stdoutDone.future;

    return StringProcessResult(
        pid: pid, exitCode: exitCode, stdout: stdoutBuffer.toString());
  }
}
