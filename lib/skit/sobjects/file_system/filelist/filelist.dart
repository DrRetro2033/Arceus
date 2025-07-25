import 'dart:convert';

import 'package:arceus/skit/sobject.dart';
import 'package:glob/glob.dart';

part 'filelist.creators.dart';
part 'filelist.interfaces.dart';
part 'filelist.g.dart';

/// Represents a list of file patterns that can be used to filter files
/// based on their paths. This class supports both whitelisting and blacklisting.
sealed class Globs extends SObject {
  Globs(super._node);

  List<Glob> get _list => utf8
      .decode(base64Decode(innerText!))
      .split("\n")
      .toSet() // Removes duplicates
      .where((e) => e.isNotEmpty)
      .map((e) => Glob(e))
      .toList();
  set _list(List<Glob> value) => innerText =
      base64Encode(utf8.encode(value.map((e) => e.pattern).toSet().join("\n")));

  void add(String pattern) => _list = _list..add(Glob(pattern));

  void remove(String pattern) => _list = _list..remove(Glob(pattern));

  List<String> filter(List<String> filepaths) =>
      filepaths.where((f) => included(f)).toList();

  bool included(String filepath);
}

@SGen("whitelist")
final class Whitelist extends Globs {
  Whitelist(super._node);

  @override
  bool included(String filepath) => _list.any((f) => f.matches(filepath));
}

@SGen("blacklist")
final class Blacklist extends Globs {
  Blacklist(super._node);

  @override
  bool included(String filepath) => !_list.any((f) => f.matches(filepath));
}
