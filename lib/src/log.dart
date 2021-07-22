/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:logging/logging.dart';

final log = Logger('croft');

class FatalExit implements Exception {}

extension FatalLogging on Logger {
  Never fatal(String message) {
    severe(message);
    fine('Stack trace:', null, StackTrace.current);
    throw FatalExit();
  }
}

class _LogLevelFormat {
  final Level level;
  final String label;
  final AnsiPen pen;

  _LogLevelFormat(
      {required this.level, required this.label, required this.pen});
}

class ConsoleLogHandler {
  ConsoleLogHandler({required this.logger});

  final Logger logger;

  static const _boldText = '${ansiEscape}1m';

  // Sorted from highest level to lowest level.
  final _formats = [
    _LogLevelFormat(
      level: Level.SEVERE,
      label: 'ERROR',
      pen: AnsiPen()..red(bold: true),
    ),
    _LogLevelFormat(
      level: Level.WARNING,
      label: 'WARN',
      pen: AnsiPen()..magenta(bold: true),
    ),
    _LogLevelFormat(
      level: Level.INFO,
      label: 'INFO',
      pen: AnsiPen()..cyan(bold: true),
    ),
    _LogLevelFormat(
      level: Level.ALL,
      label: 'FINE',
      pen: AnsiPen()..green(bold: true),
    ),
  ];

  void log(LogRecord record) {
    var format = _formats
        .firstWhere((format) => record.level.value >= format.level.value);
    var output = record.level.value >= Level.SEVERE.value ? stdout : stderr;

    var parts = [record.message];
    if (record.error != null) {
      parts.add(record.error.toString());
    }
    if (record.stackTrace != null) {
      parts.add(record.stackTrace.toString());
    }

    var lines = <String>[];
    for (var part in parts) {
      lines.addAll(part.trim().split('\n'));
    }

    for (var line in lines) {
      output.write(_boldText);
      output.write('[');
      output.write(format.pen(format.label));

      // The pen resets our text formatting.
      output.write(_boldText);
      output.write('] ');
      output.write(line);
      output.writeln(format.pen.up);
    }

    output.flush();
  }

  // XXX: Ugly that this is manipulating global.
  static void disableColors() => ansiColorDisabled = true;

  void enableVerbose() => logger.level = Level.ALL;

  void attach() => logger.onRecord.listen(log);
}
