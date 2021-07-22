/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import 'package:croft/src/git_repo.dart';

enum ComponentType { chromium, ffmpeg }

String _componentTypeString(ComponentType type) =>
    type.toString().split('.')[1];

abstract class Component {
  GitRepo get repo;
  ComponentType get type;
  String? get patchPrefix => null;

  String get typeDescription => _componentTypeString(type);

  Future<String> getUpstreamRevision();
  Future<void> ensurePatchListIsComplete(
      {required String from, required String to}) async {}
}
