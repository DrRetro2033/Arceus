import 'dart:io';
import 'package:arceus/arceus.dart';
import 'package:arceus/skit/sobjects/author/author.dart';
import 'package:yaml/yaml.dart';

class Author {
  final File _file;

  const Author(this._file);

  static Future<Author> initialize() async {
    final file = File("${Arceus.appDataPath}/me.yaml");
    if (!await file.exists()) {
      await file.writeAsString(
          """# This file contains everything about you, and is used to indentify your kit files.
name: Default Author
""");
    }
    return Author(file);
  }

  Future<SAuthor> toSAuthor() async {
    YamlMap doc = loadYaml(await _file.readAsString());
    final author = await SAuthorCreator(
            name: doc["name"], publicKey: await Arceus.publicKey)
        .create();
    return author;
  }
}
