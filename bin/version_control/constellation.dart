import 'dart:convert';
import 'dart:io';

import 'package:ansix/ansix.dart';

import '../uuid.dart';
import '../extensions.dart';

import 'star.dart';
import 'dossier.dart';

/// # `class` Constellation
/// ## Represents a constellation.
/// Is similar to how a normal Git repository works, with an initial commit acting as the root star.
/// However, the plan is for Arceus to be able to do more with stars in the future,
/// so just using Git as a backbone would limit the scope of this project.
class Constellation {
  String? name; // The name of the constellation.
  String path; // The path to the folder this constellation is in.

  late Starmap starmap;

  Directory get directory => Directory(
      path); // Fetches a directory object from the path this constellation is in.

  bool doesStarExist(String hash) => File(getStarPath(hash)).existsSync();

  String get constellationPath =>
      "$path/.constellation"; // The path to the folder the constellation stores its data in.
  Directory get constellationDirectory => Directory(
      constellationPath); // Fetches a directory object from the path the constellation stores its data in.

  Constellation(this.path, {this.name}) {
    path = path.fixPath();
    if (constellationDirectory.existsSync()) {
      load();
      if (starmap.currentStarHash == null) {
        starmap.currentStarHash = starmap.rootHash;
        save();
      }
      return;
    } else if (name != null) {
      _createConstellationDirectory();
      starmap = Starmap(this);
      _createRootStar();
      save();
      return;
    }
    throw Exception(
        "Constellation not found: $constellationPath. If the constellation does not exist, you must provide a name.");
  }

  /// # `void` _createConstellationDirectory()
  /// ## Creates the directory the constellation stores its data in.
  void _createConstellationDirectory() {
    constellationDirectory.createSync();
    if (Platform.isWindows) {
      Process.runSync('attrib', ['+h', constellationPath]);
    }
  }

  void _createRootStar() {
    starmap.root = Star(this, name: "Initial Star");
    starmap.currentStar = starmap.root;
    save();
  }

  String generateUniqueStarHash() {
    while (true) {
      String hash = generateUUID();
      if (!(doesStarExist(hash))) {
        return hash;
      }
    }
  }

  /// # `String` getStarPath(`String` hash)
  /// ## Returns a path for a star with the given hash.
  String getStarPath(String hash) => "$constellationPath/$hash.star";

  // ============================================================================
  // These methods are for saving and loading the constellation.

  /// # `void` save()
  /// ## Saves the constellation to disk.
  /// This includes the root star and the current star hashes.
  void save() {
    File file = File("$constellationPath/starmap");
    file.createSync();
    file.writeAsStringSync(jsonEncode(toJson()));
  }

  void load() {
    File file = File("$constellationPath/starmap");
    if (file.existsSync()) {
      fromJson(jsonDecode(file.readAsStringSync()));
    }
  }

  void fromJson(Map<String, dynamic> json) {
    name = json["name"];
    starmap = Starmap(this, map: json["map"]);
  }

  Map<String, dynamic> toJson() => {"name": name, "map": starmap.toJson()};
  // ============================================================================

  String? branch(String name) {
    return starmap.currentStar?.createChild(name);
  }

  // List<String> listChildren(String hash) {}

  bool checkForDifferences(String? hash) {
    hash ??= starmap.currentStarHash;
    Star star = Star(this, hash: hash);
    return Dossier(star).checkForDifferences();
  }
}

/// # `class` Starmap
/// ## Represents the relationship between stars.
/// This now contains the root star and the current star.
/// It also contains the children and parents of each star, in two separate maps, for performance and ease reading and writing.
class Starmap {
  Constellation constellation;

  // Maps for storing children and parents.
  Map<String, List<dynamic>> childMap = {}; // Format: {parent: [children]}
  Map<String, dynamic> parentMap = {}; // Format: {child: parent}

  Starmap(this.constellation, {Map<dynamic, dynamic>? map}) {
    if (map == null) {
      childMap = {};
      parentMap = {};
    } else {
      fromJson(map);
    }
  }

  String? rootHash; // The hash of the root star.
  Star? get root => Star(constellation,
      hash: rootHash!); // Fetches the root star as a Star object.
  set root(Star? value) => rootHash =
      value?.hash; // Sets the root star hash with the given Star object.
  String? currentStarHash; // The hash of the current star.
  Star? get currentStar => Star(constellation,
      hash: currentStarHash!); // Fetches the current star as a Star object.
  set currentStar(Star? value) => currentStarHash =
      value?.hash; // Sets the current star hash with the given Star object.

  /// # `void` initEntry(`String` hash)
  /// ## Initializes the entry for the given hash.
  /// Called by `Star` when a new star is created.
  void initEntry(String hash) {
    if (childMap[hash] != null) {
      return;
    }
    childMap[hash] = [];
  }

  /// # `void` jumpTo(`String?` hash)
  /// ## Changes the current star to the star with the given hash.
  void jumpTo(String? hash) {
    if (constellation.doesStarExist(hash ?? rootHash!)) {
      currentStar = Star(constellation, hash: hash ?? rootHash!);
    }
  }

  /// # `operator` `[]` jumpTo(`Star` star)
  /// ## Changes the current star to the given star.
  /// You can pass a hash or a star object.
  operator [](Object to) {
    if (to is String && constellation.doesStarExist(to)) {
      jumpTo(to);
    } else if (to is Star) {
      currentStar = to;
    }
  }

  Map<dynamic, dynamic> toJson() {
    return {
      "root": rootHash,
      "current": currentStarHash,
      "children": childMap,
      "parents": parentMap
    };
  }

  void fromJson(Map<dynamic, dynamic> json) {
    rootHash = json["root"];
    currentStarHash = json["current"];
    for (String hash in json["children"].keys) {
      childMap[hash] = json["children"][hash];
    }
    for (String hash in json["parents"].keys) {
      parentMap[hash] = json["parents"][hash];
    }
  }

  /// # `List<Star>` getChildren(`Star` parent)
  /// ## Returns a list of all children of the given parent.
  /// The list will be empty if the parent has no children.
  List<Star> getChildren(Star parent) {
    List<Star> children = [];
    for (String hash in getChildrenHashes(parent.hash!)) {
      children.add(Star(constellation, hash: hash));
    }
    return children;
  }

  /// # `List<String>` getChildrenHashes(`String` parent)
  /// ## Returns a list of all children hashes of the given parent.
  /// The list will be empty if the parent has no children.
  List getChildrenHashes(String parent) {
    return childMap[parent] ?? <String>[];
  }

  /// # `void` addRelationship(`Star` parent, `Star` child)
  /// ## Adds the given child to the given parent.
  void addRelationship(Star parent, Star child) {
    if (parentMap[child.hash] != null) {
      throw Exception("Star already has a parent.");
    }

    if (childMap[parent.hash] == null) {
      childMap[parent.hash!] = [];
    }
    childMap[parent.hash!]?.add(child.hash!);
    parentMap[child.hash!] = parent.hash!;
    constellation.save();
  }

  /// # `Map<String, dynamic>` getReadableTree(`String` curHash)
  /// ## Returns a tree view of the constellation.
  Map<String, dynamic> getReadableTree(String curHash) {
    Map<String, dynamic> list = {};
    String displayName = "Star $curHash";
    if (currentStarHash == curHash) {
      displayName += "✨";
    }
    list[displayName] = {};
    for (int x = 1; x < ((getChildrenHashes(curHash).length)); x++) {
      list[displayName].addAll(getReadableTree(getChildrenHashes(curHash)[x]));
    }
    if (getChildrenHashes(curHash).isNotEmpty) {
      list.addAll(getReadableTree(getChildrenHashes(curHash)[0]));
    }
    return list;
  }

  /// # `void` showMap()
  /// ## Shows the map of the constellation.
  /// This is a tree view of the constellation's stars and their children.
  void showMap() {
    AnsiX.printTreeView(getReadableTree(rootHash!),
        theme: AnsiTreeViewTheme(
          showListItemIndex: false,
          headerTheme: AnsiTreeHeaderTheme(hideHeader: true),
          valueTheme: AnsiTreeNodeValueTheme(hideIfEmpty: true),
          anchorTheme: AnsiTreeAnchorTheme(
              style: AnsiBorderStyle.rounded, color: AnsiColor.blueViolet),
        ));
  }
}