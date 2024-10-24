import 'dart:convert';
import 'dart:io';

import 'package:ansix/ansix.dart';

import '../uuid.dart';
import '../arceus.dart';
import '../extensions.dart';

import 'star.dart';
import 'dossier.dart';
import 'users.dart';

/// # `class` Constellation
/// ## Represents a constellation.
class Constellation {
  /// The name of the constellation.
  late String name;

  /// The path to the folder this constellation is in.
  late String path;

  /// The starmap of the constellation.
  Starmap? starmap;

  /// The user index of the constellation.
  UserIndex? userIndex;

  // Fetches a directory object from the path this constellation is in.
  Directory get directory => Directory(path);

  /// # `bool` doesStarExist(`String` hash)
  /// ## Checks if a star exists in the constellation.
  /// Returns `true` if the star exists, `false` otherwise.
  bool doesStarExist(String hash) => File(getStarPath(hash)).existsSync();

  /// The path to the folder the constellation stores its data in. (The `.constellation` folder)
  String get constellationPath => "$path/.constellation";

  /// Fetches a directory object that represents the `constellationPath` folder.
  Directory get constellationDirectory => Directory(constellationPath);

  Constellation(
      {String? path, String? name, Iterable<String> users = const ["host"]}) {
    if (path == null && name == null) {
      throw Exception("Must provide either a path or a name.");
    } else if (path == null &&
        name != null &&
        Arceus.doesConstellationExist(name)) {
      path = Arceus.getConstellationPath(name)!;
    } else {
      path = path;
    }
    this.path = path!.fixPath();
    userIndex = UserIndex(constellationPath);
    if (constellationDirectory.existsSync()) {
      load();
      if (starmap?.currentStarHash == null) {
        starmap?.currentStarHash = starmap?.rootHash;
        save();
      }
      if (!Arceus.doesConstellationExist(this.name)) {
        Arceus.addConstellation(this.name, path);
      }
      return;
    } else if (name != null) {
      _createConstellationDirectory();
      userIndex?.createUsers(users);
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
      // Makes constellation folder hidden on Windows.
      Process.runSync('attrib', ['+h', constellationPath]);
    }
  }

  void _createRootStar() {
    starmap?.root =
        Star(this, name: "Initial Star", user: userIndex?.getHostUser());
    starmap?.currentStar = starmap?.root;
    save();
  }

  String generateUniqueStarHash() {
    for (int i = 0; i < 100; i++) {
      String hash = generateUUID();
      if (!(doesStarExist(hash))) {
        return hash;
      }
    }
    throw Exception(
        "Unable to generate a unique star hash. Either you are extremely unlucky or there are zero unique hashes left.");
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

  Map<String, dynamic> toJson() => {"name": name, "map": starmap?.toJson()};
  // ============================================================================

  /// # `String?` grow(`String` name)
  /// ## Creates a new star with the given name and returns the hash of the new star at the current star.
  String? grow(String name) {
    return starmap?.currentStar?.createChild(name);
  }

  void delete() {
    Arceus.removeConstellation(name);
    constellationDirectory.deleteSync(recursive: true);
    starmap = null;
  }

  /// # `void` resetToCurrentStar()
  /// ## Restores the files from current star.
  /// This WILL discard any changes in files, so make sure you grown the constellation before calling this.

  void resetToCurrentStar() {
    starmap?.currentStar?.makeCurrent();
  }

  /// # `void` clear()
  /// ## Clears all files in the associated path, expect for the `.constellation` folder.
  void clear() {
    directory.listSync(recursive: true).forEach((entity) {
      if (entity is File &&
          !entity.path.fixPath().contains(constellationPath.fixPath())) {
        entity.deleteSync();
      }
    });
  }

  /// # `bool` checkForDifferences()
  /// ## Checks if the constellation has differences between the current star and the root star.
  /// Returns `true` if there are differences, `false` otherwise.
  bool checkForDifferences() {
    Star star = Star(this, hash: starmap?.currentStarHash);
    return Dossier(star).checkForDifferences();
  }

  /// # `bool` checkForConstellation(`String` path)
  /// ## Checks if the constellation exists at the given path.
  /// Returns `true` if the constellation exists, `false` otherwise.
  static bool checkForConstellation(String path) {
    return Directory("$path/.constellation").existsSync();
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

  Star _getMostRecentStar() {
    return root!.getMostRecentStar();
  }

  /// # `operator` `[]` jumpTo(`Star` star)
  /// ## Get the star with the given hash.
  /// You can pass a hash or a star object.
  operator [](Object hash) {
    if (hash is String) {
      if (hash == "recent") {
        return _getMostRecentStar();
      } else if (hash == "root") {
        return root;
      } else if (hash.startsWith("back")) {
        final x = hash.replaceFirst("back", "");
        if (x.isEmpty) return currentStar!.parent!;
        int i = int.parse(x);
        Star? star = currentStar;
        while (i > 0) {
          if (star!.parent == null) {
            break;
          }
          star = star.parent;
          i--;
        }
        return star;
      } else if (constellation.doesStarExist(hash)) {
        return Star(constellation, hash: hash);
      }
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
    String displayName = Star(constellation, hash: curHash)
        .name!; // Change this to what you want the display name to be.
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
