import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:arceus/cli.dart';
import 'package:args/command_runner.dart';
import 'package:chalkdart/chalkstrings.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:arceus/version_control/constellation.dart';
import 'package:arceus/version_control/star.dart';
import 'package:arceus/arceus.dart';
import 'package:arceus/scripting/addon.dart';
import 'package:interact/interact.dart';
import 'package:arceus/hex_editor/editor.dart';
import 'package:arceus/version_control/plasma.dart';
import 'package:arceus/extensions.dart';
import 'package:arceus/server.dart';
import 'package:arceus/updater.dart';
import 'package:arceus/widget_system.dart';

/// # `void` main(List<String> arguments)
/// ## Main entry point.
/// Runs the CLI.

Future<dynamic> main(List<String> arguments) async {
  final newUpdate = await Updater().checkForUpdate();
  if (newUpdate) {
    final confirm = Confirm(
      prompt: " A new update is available! Would you like to update?",
    ).interact();
    if (confirm) {
      final spinner =
          CliSpin(text: "Updating...", spinner: CliSpinners.moon).start();
      await Updater.update();
      spinner.success("Update complete!");
      exit(0);
    } else {
      print(
          "If you change your mind, you can update at any time by running 'arceus update'.");
      Arceus.skipUpdate((await Updater.getLatestVersion()).toString());
    }
  }
  var runner = CommandRunner('arceus', """
The ultimate save manager and editor.

Current Version:
v${Updater.currentVersion}""");
  runner.argParser.addOption(
    "path",
    abbr: "p",
    defaultsTo: Directory.current.path,
  );
  runner.argParser.addOption("const",
      abbr: "c",
      help:
          "Use a constellation name instead of an path. Only works after using --path to create the constellation.");
  runner.argParser.addFlag("internal", defaultsTo: false, hide: true);
  Arceus.currentPath = Directory.current.path.fixPath();
  if (arguments.contains("--path") || arguments.contains("-p")) {
    Arceus.currentPath =
        arguments[arguments.indexWhere((e) => e == "--path" || e == "-p") + 1];
  }
  if (arguments.contains("--const") || arguments.contains("-c")) {
    final constellationName =
        arguments[arguments.indexWhere((e) => e == "--const" || e == "-c") + 1];
    if (!Arceus.doesConstellationExist(name: constellationName)) {
      print(
          "Constellation with the name of '$constellationName' does not exist.");
      print("Did you mean '${Arceus.getClosestConstName(constellationName)}'?"
          .brightBlue);
      exit(1);
    }
    Arceus.currentPath = Arceus.getConstellationPath(constellationName)!;
  }
  if (arguments.contains("--internal") || arguments.contains("-i")) {
    Arceus.isInternal = true;
  } else {
    Arceus.isInternal = false;
  }

  Arceus.talker.info("Arceus has started successfully.");
  if (!Constellation.exists(Arceus.currentPath)) {
    runner.addCommand(CreateConstellationCommand());
  } else {
    runner.addCommand(ShowMapConstellationCommand());
    runner.addCommand(CheckForDifferencesCommand());
    runner.addCommand(ConstellationJumpToCommand());
    runner.addCommand(ConstellationGrowCommand());
    runner.addCommand(ConstellationDeleteCommand());
    runner.addCommand(TrimCommand());
    runner.addCommand(ResyncCommand());
    runner.addCommand(LoginUserCommand());
    runner.addCommand(TagCommands());
    runner.addCommand(EditStarCommand());
    runner.addCommand(OpenFolderInExplorerCommand());
  }
  runner.addCommand(StartServerCommand());
  runner.addCommand(ShareCommands());
  runner.addCommand(UsersCommands());
  runner.addCommand(RecoverCommand());
  runner.addCommand(DoesConstellationExistCommand());
  runner.addCommand(ReadFileCommand());
  runner.addCommand(OpenFileInHexCommand());
  runner.addCommand(ArceusConstellationsCommand());
  runner.addCommand(AddonsCommand());
  runner.addCommand(UpdateCommand());
  runner.addCommand(GrowAllCommand());

  if (arguments.isNotEmpty) {
    dynamic result = await runner.run(arguments);
    if (result != null && Arceus.isInternal) {
      stdout.write(result.toString());
    }
  }
  exit(0);
}

/// # `ArceusCommand`
/// ## An abstract class that represents a command for the Arceus CLI.
/// Use `getRest()` to get the user input.
abstract class ArceusCommand extends Command {
  @override
  String get invocation {
    var parents = [name];
    for (var command = parent; command != null; command = command.parent) {
      parents.add(command.name);
    }
    parents.add(
        "${runner!.executableName} ${globalFlags.isNotEmpty ? "[${globalFlags.join(", ")}]" : ""}");

    var invocation = parents.reversed.join(' ');
    return subcommands.isNotEmpty
        ? '$invocation <subcommand> [arguments]'
        : '$invocation [arguments] ${showInputID ? '<$inputID>' : ''}';
  }

  List<String> get globalFlags => [];

  String get inputID => "example-input";

  bool get showInputID => true;

  String getRest() {
    return argResults?.rest.join(" ") ?? "";
  }
}

abstract class ConstellationArceusCommand extends ArceusCommand {
  Constellation get constellation => Constellation(path: Arceus.currentPath);

  @override
  List<String> get globalFlags =>
      ["--path <path-to-location>", "--const <name-of-const>"];

  @override
  dynamic run() {
    if (!Constellation.exists(Arceus.currentPath)) {
      print(
          "No constellation found! The constellation might be corrupted. Try running 'recover' to fix the problem.");
    } else {
      return _run();
    }
  }

  dynamic _run();
}

class UpdateCommand extends Command {
  @override
  String get description => "Checks for updates.";
  @override
  String get name => "update";

  UpdateCommand();

  @override
  void run() async {
    final spinnerForUpdateCheck =
        CliSpin(text: " Checking for updates...", spinner: CliSpinners.moon)
            .start();
    final newUpdate = await Updater().checkForUpdate(skip: false);
    if (newUpdate) {
      final version = await Updater.getLatestVersion();
      spinnerForUpdateCheck.success(" A new update is available!");
      final confirm = Confirm(
        prompt:
            " Do you want to update to the latest version? (v${version.toString()})",
      ).interact();
      if (confirm) {
        final spinner =
            CliSpin(text: " Updating...", spinner: CliSpinners.moon).start();
        await Updater.update();
        spinner.success(" Update complete!");
        exit(0);
      }
    } else {
      spinnerForUpdateCheck.success(" You are up to date!");
    }
  }
}

class CreateConstellationCommand extends ArceusCommand {
  @override
  String get description => """
Creates a new constellation at a given, or current, path.

--const is not available here.

""";

  @override
  String get summary =>
      "Creates a new constellation at a given, or current, path.";

  @override
  String get name => "create";

  @override
  String get inputID => "name-of-constellation";

  CreateConstellationCommand() {
    argParser.addMultiOption("user", abbr: "u", defaultsTo: Iterable.empty());
  }

  @override
  void run() {
    if (getRest().isEmpty) {
      print("Please provide a name for the constellation!");
      return;
    }
    final spinner =
        CliSpin(text: " Creating constellation...", spinner: CliSpinners.moon)
            .start();
    try {
      List<String>? users = argResults?["user"];
      if (users?.isEmpty ?? true) {
        Constellation(path: Arceus.currentPath, name: getRest());
      } else {
        Constellation(path: Arceus.currentPath, name: getRest());
      }
    } catch (e) {
      spinner.fail(" Unable to create constellation.");
      rethrow;
    }
    spinner.success(" Constellation created.");
  }
}

class ShowMapConstellationCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Shows the map of the constellation.";

  @override
  String get description => """
Shows the map of the constellation.

Legend:

✨ - The current star.
${Badge("👤User", badgeColor: "aqua")} - The assigned user to a star.
${Badge("🏷️Tag")} - The assigned tag.
${Badge("📅1990/1/1", badgeColor: "grey", textColor: "white")} - Date when created.
${Badge("🕒0:00 AM", badgeColor: "grey", textColor: "white")} - Time when created.
↪ - A star is the only child of its parent.
""";

  @override
  String get name => "map";

  @override
  String get category => "Constellation";

  @override
  bool get showInputID => false;

  ShowMapConstellationCommand();

  @override
  void _run() {
    print("Currently signed in as ${constellation.loggedInUser.name.italic}.");
    CliSpin spinner =
        CliSpin(text: " Loading map...", spinner: CliSpinners.moon);
    final changes = constellation.checkForDifferences();
    spinner.stop();
    print(changes ? "Changes found.".bold : "No changes found.".bold);
    constellation.starmap.printMap();
    constellation.printSumOfCurStar();
  }
}

class CheckForDifferencesCommand extends ConstellationArceusCommand {
  @override
  String get description => """
Checks for new changes.
""";

  @override
  String get summary => "Checks for new changes.";

  @override
  String get name => "check";

  @override
  String get category => "Constellation";

  @override
  bool get hidden => true;

  CheckForDifferencesCommand();

  @override
  bool get showInputID => false;

  @override
  Future<bool> _run() async {
    final spinner = CliSpin(
            text:
                " Checking for differences between current directory and provided star...",
            spinner: CliSpinners.moon)
        .start();
    bool result = constellation.checkForDifferences(false);
    if (!result) {
      spinner.success(" No differences found.");
    } else {
      spinner.fail(" Differences found.");
    }
    return result;
  }
}

class ResyncCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Resyncs files to the current star.";

  @override
  String get description => """
Resyncs files to the current star.
""";

  @override
  String get name => "resync";

  @override
  String get category => "Constellation";

  @override
  bool get showInputID => false;

  ResyncCommand();

  @override
  void _run() {
    final confirm = Confirm(
      prompt:
          " Are you sure you want to resync? This will discard any changes to tracked files.",
    ).interact();
    if (!confirm) {
      return;
    }
    constellation.resyncToCurrentStar();
    print("Resync complete ✔️");
  }
}

class RecoverCommand extends ArceusCommand {
  @override
  String get description => """
Recover from from a broken constellation.
""";

  @override
  String get summary => "Recover from from a broken constellation.";

  @override
  String get name => "recover";

  @override
  bool get showInputID => false;

  @override
  String get category => "Constellation";

  RecoverCommand();

  @override
  Future<void> run() async {
    final starfiles = Constellation.listStarFiles(Arceus.currentPath);
    if (starfiles == null) {
      print(
          "No constellation folder found! Unfortunately, there is nothing to recover from.");
      return;
    }
    final options = starfiles.map((e) => e.getDisplayName()).toList();
    final selected = Select(
      prompt:
          " Select a star to recover from (this will overwrite the current data).",
      options: [...options, "Cancel"],
    ).interact();
    if (selected == options.length) {
      return;
    }
    final star = starfiles[selected];
    final user = Arceus.userIndex.getUser(star.userHash);
    star.extract(Arceus.currentPath);
    final confirm = Confirm(
      prompt:
          " Do you also want to recreate the constellation? All other stars will be lost.",
    ).interact();
    if (confirm) {
      final name = Input(prompt: " Name of the new constellation.").interact();
      Constellation.deleteStatic(Arceus.currentPath);
      Constellation(
        path: Arceus.currentPath,
        name: name,
        user: user,
      );
    }
    print("Recovery complete ✔️");
  }
}

class ConstellationJumpToCommand extends ConstellationArceusCommand {
  @override
  String get description => """
Jump to stars in the constellation.

Give it either a star hash, or use the commands below. Replace X to specify the number of repeats/children/siblings. 
X defaults to 1 if not provided.

Commands:
- root: Jumps to the root star
- recent: Jumps to the most recent star

- back: Jumps to the parent of the current star. Will be clamped to the root star.
- back X:  Will jump to the parent of every star preceeding the current star by X. Will be clamped to the the root star.
- forward`: Will jump to the first child of the current star. Will be clamped to any ending stars.
- forward X: Will jump to the Xth child of the current star. Will be clamped to a valid index of the current star's children.

- above X: Will jump to the Xth sibling above the current star. Will wrap around to lowest star.
- below: Jumps to the sibling below the current star. Will wrap around to highest star.
- below X: Will jump to the Xth sibling above the current star. Will wrap around to lowest star. If X is not provided, it will default to 1.

- next X: Will jump to the Xth child of the current star. Will be wrapped to a valid index of the current star's children.
- depth X: Jumps to the first star at the given depth.

You can also chain multiple commands together by adding a comma between each.
""";

  @override
  String get summary => "Jump to stars in the constellation.";

  @override
  String get name => "jump";

  @override
  String get category => "Constellation";

  @override
  String get inputID => "commands";

  ConstellationJumpToCommand() {
    argParser.addFlag("print",
        abbr: "p", defaultsTo: false, help: "Print the tree after jumping.");
    argParser.addFlag("force", abbr: "f", defaultsTo: false);
  }

  @override
  Future<void> _run() async {
    if (!argResults!["force"] && constellation.checkForDifferences()) {
      final confirm = Confirm(
        prompt:
            "If you jump now before growing, all changes will be lost! Are you sure you want to continue?",
      ).interact();
      if (!confirm) {
        return;
      }
    }
    CliSpin? spinner =
        CliSpin(text: "Jumping to star...", spinner: CliSpinners.moon).start();
    if (argResults!.rest.isEmpty) {
      spinner.fail(" Please provide a star hash or command to jump.");
      return;
    }
    String hash = getRest();

    try {
      final star = constellation.starmap[hash] as Star;
      star.makeCurrent();
      spinner.success(" Jumped to \"${star.name}\".");
      if (argResults!["print"]) {
        constellation.starmap.printMap();
      }
    } catch (e) {
      spinner.fail(" Star with the hash of \"$hash\" not found.");
      rethrow;
    }
  }
}

class ConstellationGrowCommand extends ConstellationArceusCommand {
  @override
  String get summary =>
      "Grow from the current star to a new star with a given name.";

  @override
  String get description => """
Grow from the current star to a new star with a given name.

Growing will commit changes from tracked files into a new star in the constellation. Will branch if necessary. 
This will fail if there no changes to commit, unless '--force' is provided.
""";
  @override
  String get name => "grow";

  @override
  String get inputID => "name";

  @override
  String get category => "Constellation";

  ConstellationGrowCommand() {
    argParser.addFlag("force", abbr: "f", defaultsTo: false);
    argParser.addFlag("sign-in", abbr: "s", defaultsTo: false);
  }

  @override
  void _run() {
    if (getRest().isEmpty) {
      throw Exception("Please provide a name for the new star.");
    }
    final star = constellation.grow(getRest(),
        force: argResults!["force"], signIn: argResults!["sign-in"]);
    print("Created child star: ${star!.name}");
  }
}

class TrimCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Trims a star and its descendants off of the starmap. ";

  @override
  String get description => """
Trims the current star and its descendants off of the starmap.

Trimming will not delete the current files.
Will confirm before proceeding, unless --force is provided.
""";
  @override
  String get name => "trim";

  @override
  String get category => "Constellation";

  @override
  bool get showInputID => false;

  TrimCommand() {
    argParser.addFlag("force", abbr: "f", defaultsTo: false);
  }

  @override
  Future<void> _run() async {
    if (!argResults!["force"]) {
      final confirm = Confirm(
        prompt: " Are you sure you want to trim off the current star?",
      ).interact();
      if (!confirm) {
        return;
      }
    }
    constellation.trim();
  }
}

class UsersCommands extends ArceusCommand {
  @override
  String get description => "Contains commands for users in Arceus.";

  @override
  String get name => "user";

  @override
  String get category => "Global";

  UsersCommands() {
    addSubcommand(UsersListCommand());
    addSubcommand(UsersRenameCommand());
    addSubcommand(NewUserCommand());
  }
}

class UsersListCommand extends Command {
  @override
  String get summary => "Lists the users in Arceus.";
  @override
  String get description => """
Lists the users in Arceus.
""";
  @override
  String get name => "list";

  @override
  void run() {
    Arceus.userIndex.displayUsers();
  }
}

class UsersRenameCommand extends Command {
  @override
  String get summary => "Renames a user in Arceus.";

  @override
  String get description => """
Renames a user in Arceus.
""";
  @override
  String get name => "rename";

  UsersRenameCommand() {
    argParser.addOption("user-hash", abbr: "u", hide: true);
    argParser.addOption("new-name", abbr: "n", hide: true);
  }

  @override
  void run() {
    String? name = argResults?["new-name"];
    String? hash = argResults?["user-hash"];
    if (argResults?["user-hash"] == null) {
      final users = Arceus.userIndex.users;
      final names = users.map((e) => e.name).toList();
      final selected = Select(
          prompt: " Select a user to rename.",
          options: [...names, "Cancel"]).interact();
      if (selected == names.length) {
        return;
      }
      hash = users[selected].hash;
    }

    if (argResults?["new-name"] == null) {
      name = Input(
        prompt: " New name.",
        validator: (p0) => p0.isNotEmpty,
      ).interact();
    }

    Arceus.userIndex.getUser(hash!).name = name!;
  }
}

class NewUserCommand extends ArceusCommand {
  @override
  String get summary => "Creates a new user in Arceus.";

  @override
  String get description => """
Creates a new user in Arceus.
""";

  @override
  String get inputID => "name";

  @override
  String get name => "new";

  @override
  void run() {
    String name = getRest();
    if (name.isEmpty) {
      print("Please provide a name for the new user.");
    } else {
      Arceus.userIndex.createUser(name);
    }
  }
}

class LoginUserCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Login as a user in a constellation.";

  @override
  String get description => """
Login as a user in a constellation.
""";

  @override
  String get name => "login";

  @override
  String get category => "Constellation";

  @override
  bool get showInputID => false;

  LoginUserCommand() {
    argParser.addOption("user-hash", abbr: "u", hide: true);
    argParser.addFlag("stay",
        abbr: "s",
        defaultsTo: false,
        help:
            "Stay at current star, instead of jumping to the most recent star owned by the user.");
  }

  @override
  void _run() {
    String? hash = argResults?["user-hash"];
    if (hash != null) {
      constellation.loginAs(Arceus.userIndex.getUser(hash));
    } else {
      final user = Arceus.userSelect(prompt: "Login as:");
      if (user == null) {
        return;
      }
      constellation.loginAs(user);
    }
    print("Logged in as ${constellation.loggedInUser.name.italic}.");
    if (!argResults!["stay"]) {
      constellation.starmap
          .getMostRecentStar(forceUser: true)
          .makeCurrent(login: false);
    }
  }
}

class ConstellationDeleteCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Deletes the constellation.";

  @override
  String get description => """
Deletes the constellation.
""";

  @override
  String get name => "delete";

  @override
  String get category => "Constellation";

  @override
  bool get showInputID => false;

  ConstellationDeleteCommand() {
    argParser.addFlag("force", abbr: "f", defaultsTo: false);
  }

  @override
  void _run() {
    if (!argResults!["force"]) {
      final confirm = Confirm(
              prompt:
                  "Are you sure you want to delete the constellation? (Will delete EVERYTHING in the constellation.)")
          .interact();
      if (!confirm) {
        return;
      }
    }
    constellation.delete();
  }
}

class AddonCompileCommand extends ArceusCommand {
  @override
  String get summary => "Packages an addon for distribution.";
  @override
  String get description => """
Packages an addon for distribution.
""";
  @override
  String get name => "compile";

  @override
  String get inputID => "project-path";

  AddonCompileCommand() {
    argParser.addOption("output",
        abbr: "o", help: "The output folder the addon should be compiled to.");
    argParser.addFlag("install-global",
        abbr: "g", help: "Install globally after compiling.");
  }

  @override
  void run() async {
    if (getRest().isEmpty) {
      throw Exception(" Please provide the project path for the addon.");
    }
    String projectPath = getRest();
    String outputPath = projectPath;

    if (argResults!["output"] != null) {
      outputPath = argResults!["output"]!;
    }
    CliSpin spinner =
        CliSpin(text: " Packaging addon... 🍱", spinner: CliSpinners.moon)
            .start();
    final addon = Addon.package(projectPath, outputPath);
    spinner.success(" Addon packaged successfully at ${addon.path}! 🎉");
    final testFile = File("$projectPath/test.yaml");
    if (testFile.existsSync()) {
      spinner = CliSpin(text: " Testing addon... 🍱", spinner: CliSpinners.moon)
          .start();
      try {
        addon.testRun(testFile);
      } catch (e) {
        spinner.fail(" Test run failed! 🚫");
        rethrow;
      }
      spinner.success(" Test run passed! 🎉");
    } else {
      print(
          "No test file found! It is recommended to have a test.yaml file to test the addon before distribution.");
    }

    await addon.context
        .memCheck(); // Check memory for any leaks or compile errors

    if (argResults!["install-global"]) {
      spinner = CliSpin(
              text: " Installing addon globally... 🍱",
              spinner: CliSpinners.moon)
          .start();
      Addon.installGlobally(addon.path);
      spinner.success(" Addon installed globally successfully! 🎉");
    }
  }
}

class InstallPackagedAddonCommand extends ArceusCommand {
  @override
  String get summary => "Installs a packaged addon.";
  @override
  String get description => """
Installs a packaged addon.
""";
  @override
  String get name => "install";

  @override
  String get inputID => "addon-path";

  InstallPackagedAddonCommand() {
    argParser.addFlag("global",
        abbr: "g", help: "Install the addon globally for all constellations.");
    // argParser.addFlag("copy",
    //     abbr: "c", help: "Copy the addon instead of moving it.");
  }

  @override
  void run() {
    if (getRest().isEmpty) {
      print(
          "Please provide the path to the addon. Addon files must end in .arcaddon.");
    }
    String addonFile = getRest();
    CliSpin? spinner;
    if (!Arceus.isInternal) {
      spinner =
          CliSpin(text: "Installing addon... 🍱", spinner: CliSpinners.moon)
              .start();
    }
    if (argResults!["global"]) {
      Addon.installGlobally(addonFile);
    } else if (Constellation.exists(Arceus.currentPath)) {
      Addon.installLocally(addonFile);
    } else {
      print(
          "Please either install as a global addon or give a valid constellation first.");
    }
    if (!Arceus.isInternal) {
      spinner!.success("Addon installed successfully! 🎉");
    }
  }
}

class UninstallAddonCommand extends ArceusCommand {
  @override
  String get summary => "Uninstalls an addon.";

  @override
  String get description => """
Uninstalls an addon.
""";
  @override
  String get name => "uninstall";

  @override
  String get inputID => "addon-name";

  @override
  void run() {
    if (getRest().isEmpty) {
      final addons = Addon.getInstalledAddons();
      if (addons.isEmpty) {
        print(" No addons installed. 🚫");
        return;
      } else {
        final names = addons.map((e) => e.name).toList();
        final selected = Select(
          prompt: " Select an addon to uninstall.",
          options: [...names, "Cancel"],
        ).interact();
        if (selected == names.length) {
          return;
        }
        addons[selected].uninstall();
      }
    } else {}
    String addonName = getRest();
    CliSpin? spinner;
    if (!Arceus.isInternal) {
      spinner =
          CliSpin(text: " Uninstalling addon... 🗑️", spinner: CliSpinners.moon)
              .start();
    }

    final found = Addon.uninstallByName(addonName);

    if (!Arceus.isInternal && found) {
      spinner!.success(" Addon uninstalled successfully! 🎉");
    } else if (!Arceus.isInternal) {
      spinner!.fail(" Addon not found! 🚫");
    }
  }
}

class ListAddonsCommand extends ArceusCommand {
  @override
  String get summary => "Lists all installed addons.";

  @override
  String get description => """
Lists all installed addons.
""";
  @override
  String get name => "list";

  @override
  bool get showInputID => false;

  @override
  void run() {
    List<Addon> addons = Addon.getInstalledAddons();
    if (addons.isEmpty) {
      print("No addons installed.");
    } else {
      for (Addon addon in addons) {
        print("🍱 ${addon.name} - ${addon.isGlobal ? "Global" : "Local"}");
      }
    }
  }
}

class AddonsCommand extends Command {
  @override
  String get description => "Commands for working with addons.";
  @override
  String get name => "addons";

  @override
  String get category => "Addons";

  AddonsCommand() {
    addSubcommand(InstallPackagedAddonCommand());
    addSubcommand(UninstallAddonCommand());
    addSubcommand(ListAddonsCommand());
    addSubcommand(AddonCompileCommand());
  }
}

class ReadFileCommand extends ArceusCommand {
  @override
  String get summary => "Read a file with an associated addon.";
  @override
  String get description => """
Reads a file with an addon associated with it, so you can see a simplified view of its data.""";

  @override
  String get inputID => "filepath";

  @override
  List<String> get globalFlags =>
      ["--path <path-to-location>", "--const <name-of-const>"];

  @override
  String get name => "read";

  @override
  String get category => "Addons";

  @override
  dynamic run() async {
    if (getRest().isEmpty) {
      throw Exception("Please provide a file to read.");
    }
    String filepath = getRest();
    File file = File(filepath.fixPath());
    Plasma plasma = Plasma.fromFile(file);

    final result = plasma.readWithAddon()!;
    if (!Arceus.isInternal) {
      print(TreeWidget(result.data));
    }
    return jsonEncode(result.data);
  }
}

class ArceusConstellationsCommand extends Command {
  @override
  String get summary => "Lists all constellations.";

  @override
  String get description => """
Lists all constellations.""";

  @override
  String get name => "consts";

  @override
  String get category => "Global";

  @override
  void run() {
    if (Arceus.empty()) {
      if (!Arceus.isInternal) {
        print("No constellations found! Create one with the 'create' command.");
      }
    }
    Arceus.getConstellationEntries()
        .forEach((e) => print("🌃 ${e.name} - ${e.path}"));
  }
}

class OpenFileInHexCommand extends ArceusCommand {
  @override
  String get summary => "Opens a file in the Héx Editor.";
  @override
  String get description => """
Opens a file in the Héx Editor.""";

  @override
  String get inputID => "filepath";

  @override
  String get name => "hex";

  @override
  String get category => "Tools";

  @override
  Future<void> run() async {
    if (getRest().isEmpty) {
      throw Exception("Please provide the file to open.");
    }
    String file = getRest();
    if (!File(file).existsSync()) {
      throw Exception("File $file not found.");
    }
    await HexEditor(Plasma.fromFile(File(file))).interact();
    exit(0);
  }
}

class DoesConstellationExistCommand extends ArceusCommand {
  @override
  String get summary => "Checks if a constellation exists.";

  @override
  String get description => """
Checks if a constellation exists.
""";

  @override
  String get inputID => "path";

  @override
  String get name => "exists";

  @override
  String get category => "Tools";

  @override
  dynamic run() {
    final spinner = CliSpin(
            text: "Checking for constellation...", spinner: CliSpinners.moon)
        .start();
    if (getRest().isEmpty) {
      if (Arceus.doesConstellationExist(path: Arceus.currentPath)) {
        spinner.success("Constellation exists.");
      } else {
        spinner.fail("Constellation does not exist.");
      }
    } else {
      if (Arceus.doesConstellationExist(path: getRest())) {
        spinner.success("Constellation exists.");
      } else {
        spinner.fail("Constellation does not exist.");
      }
    }
  }
}

class StartServerCommand extends Command {
  @override
  String get summary => "Starts the Arceus server.";

  @override
  String get description => """
Starts the Arceus server.""";

  @override
  String get name => "server";

  @override
  String get category => "Tools";

  @override
  bool get hidden => true;

  @override
  Future<void> run() async => await ArceusServer().start();
}

class TagCommands extends Command {
  @override
  String get summary => "Commands for working with tags for stars.";

  @override
  String get description => """
Commands for working with tags for stars.
""";

  @override
  String get name => "tag";

  @override
  String get category => "Constellation";

  TagCommands() {
    addSubcommand(TagAddCommand());
    addSubcommand(TagRemoveCommand());
    addSubcommand(TagListCommand());
  }
}

class TagAddCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Adds a tag to the current star.";

  @override
  String get description => """
Adds a tag to the current star.""";

  @override
  String get inputID => "name-of-new-tag";

  @override
  String get name => "add";

  @override
  void _run() {
    if (getRest().isEmpty) {
      print("Please provide a name for the tag to add.");
    }
    final spinner =
        CliSpin(text: "Adding tag...", spinner: CliSpinners.moon).start();
    final success = constellation.starmap.currentStar.addTag(getRest());
    if (success) {
      spinner.success("Tag added successfully.");
    } else {
      spinner.fail("Tag already exists.");
    }
  }
}

class TagRemoveCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Removes a tag from the current star.";

  @override
  String get description => """
Removes a tag from the current star.
""";

  @override
  String get name => "remove";

  @override
  String get inputID => "name-of-tag-to-remove";

  @override
  void _run() {
    String tag = getRest();
    if (tag.isEmpty) {
      final tags = constellation.starmap.currentStar.tags;
      final selected = Select(
        prompt: " Select a tag to remove.",
        options: [...tags, "Cancel"],
      ).interact();
      if (selected == tags.length) {
        return;
      }
      tag = tags.elementAt(selected);
    }
    final spinner =
        CliSpin(text: "Removing tag...", spinner: CliSpinners.moon).start();
    if (constellation.starmap.currentStar.removeTag(tag)) {
      spinner.success("Tag removed successfully.");
    } else {
      spinner.fail("Tag not found.");
    }
  }
}

class TagListCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Lists all tags for the current star.";

  @override
  String get description => """
Lists all tags for the current star.""";

  @override
  String get name => "list";

  @override
  bool get showInputID => false;

  @override
  void _run() {
    if (constellation.starmap.currentStar.tags.isEmpty) {
      print("No tags found for ${constellation.starmap.currentStar.name}.");
    }
    print("Tags for ${constellation.starmap.currentStar.name}:");
    for (String tag in constellation.starmap.currentStar.tags) {
      print(Badge(tag));
    }
  }
}

class GrowAllCommand extends Command {
  @override
  String get summary => "Grows all stars for every constellation.";

  @override
  String get description => """
Grows all stars for every constellation.""";

  @override
  String get name => "grow-all";

  @override
  String get category => "Global";

  @override
  void run() {
    CliSpin spinner =
        CliSpin(text: " Starting...", spinner: CliSpinners.moon).start();
    bool noChanges = true;
    for (ConstellationEntry entry in Arceus.getConstellationEntries()) {
      try {
        final constellation = Constellation(path: entry.path);
        spinner.text = " Checking ${entry.name.italic} for changes...";
        if (!constellation.checkForDifferences()) {
          continue;
        }
        spinner.text = " Growing ${entry.name.italic}...";
        constellation.grow(constellation.getAutoStarName(), signIn: false);

        spinner.success(" Successfully grown ${entry.name.italic}!");
        noChanges = false;
        spinner =
            CliSpin(text: " Starting...", spinner: CliSpinners.moon).start();
      } catch (e) {
        continue;
      }
    }
    if (noChanges) {
      spinner.fail(" No changes found.");
    } else {
      spinner.stop();
    }
  }
}

class EditStarCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Edits the current star.";

  @override
  String get description => """
Edits the current star.
""";

  @override
  String get name => "edit";

  @override
  String get category => "Constellation";

  Map<String, Function(Star)> get fields =>
      {"Name": _editName, "User": _editUser};

  @override
  void _run() {
    editor(constellation.starmap.currentStar);
  }

  void editor(Star star) {
    while (true) {
      Cli.clearTerminal();
      print("Currently editing: ${star.file.getDisplayName()} - ${star.hash}");
      final selected = Select(
        prompt: "Select a field to edit.",
        options: [...fields.keys, "Exit"],
      ).interact();

      if (selected == fields.keys.length) {
        return;
      }

      fields[fields.keys.elementAt(selected)]!(star);
    }
  }

  void _editName(Star star) {
    String name = Input(
      prompt: "Enter the new name for the star.",
      validator: (p0) => p0.isNotEmpty,
    ).interact();
    star.name = name;
  }

  void _editUser(Star star) {
    final user =
        Arceus.userSelect(prompt: "Select a new user to assign to this star.");
    if (user != null) {
      star.user = user;
      if (star.hasChildren) {
        final confirm = Confirm(
          prompt:
              "This star has descendants, do you want to assign them to the same user?",
        ).interact();
        if (confirm) {
          star.getDescendants().forEach((element) => element.user = user);
        }
      }
    }
  }
}

class ShareCommands extends Command {
  @override
  String get summary => "Commands for sharing constellations with others.";

  @override
  String get description => """
Commands for sharing constellations with others.
""";

  @override
  String get name => "share";

  @override
  String get category => "Constellation";

  ShareCommands() {
    if (Constellation.exists(Arceus.currentPath)) {
      addSubcommand(PackageCommand());
    }
    addSubcommand(UnpackageCommand());
  }
}

class PackageCommand extends ConstellationArceusCommand {
  @override
  String get summary => "Packages the current constellation.";

  @override
  String get description => """
Packages the current constellation.
""";

  @override
  String get name => "pack";

  @override
  String get inputID => "output-path";

  @override
  void _run() {
    if (getRest().isEmpty) {
      print("Please provide an output path!");
    }
    final spinner =
        CliSpin(text: " Packaging...", spinner: CliSpinners.moon).start();
    final package = constellation.package(getRest().fixPath());
    spinner
        .success(" Packaged ${constellation.name.italic} to ${package.path}!");
  }
}

class UnpackageCommand extends ArceusCommand {
  @override
  String get summary => "Unpackages a .constpack file.";

  @override
  String get description => """
Unpackages a .constpack file into a new constellation or merges into an existing constellation.
""";

  @override
  String get name => "unpack";

  @override
  String get inputID => "input-path";

  @override
  void run() {
    if (getRest().isEmpty) {
      print("Please provide a path to a .constpack file!");
      return;
    }
    final spinner =
        CliSpin(text: "Unpacking...", spinner: CliSpinners.moon).start();
    try {
      final constellation = Constellation.unpackage(
          ConstellationPackage(getRest().fixPath()), Arceus.currentPath);
      spinner.success(
          " Unpackaged ${constellation.name.italic} at ${constellation.path}!");
    } catch (e) {
      spinner.fail(" Unable to unpack constellation.");
      rethrow;
    }
  }
}

class OpenFolderInExplorerCommand extends ConstellationArceusCommand {
  @override
  String get description => """
Open the location, or hidden folder, of the current constellation.

Options:
  current (default) - Open the tracked folder of the current constellation.
  hidden - Open the hidden folder, where the constellation data is actually stored.
""";

  @override
  String get summary =>
      "Open the location, or hidden folder, of the current constellation.";

  @override
  String get name => "open";

  @override
  String get inputID => "option";

  @override
  String get category => "Constellation";

  @override
  Future<void> _run() async {
    String option = getRest().isNotEmpty ? getRest() : "current";
    String pathToOpen = Arceus.currentPath;
    switch (option) {
      case "current":
        pathToOpen = constellation.path;
        break;
      case "hidden":
        pathToOpen = constellation.constellationPath;
        break;
    }
    await Arceus.openURLInExplorer(pathToOpen);
  }
}
