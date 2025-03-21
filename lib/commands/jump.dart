import 'package:arceus/arceus.dart';
import 'package:arceus/main.dart';
import 'package:arceus/skit/skit.dart';
import 'package:arceus/version_control/constellation.dart';
import 'package:args/command_runner.dart';

import 'package:cli_spin/cli_spin.dart';
import 'package:interact/interact.dart';
import 'package:arceus/extensions.dart';

class JumpCommand extends Command with GetRest {
  @override
  String get name => "jump";

  @override
  String get description => """
Jump to a different star in a constellation. Will check for changes in the tracked folder.
Actions with X will default to 1, and you can chain all of these commands with a comma.

Available Actions:
  - recent: Jump to most recent star.
  - root: Jump to root star.
  - forward X: Jump forward by X stars.
  - back X: Jump backward by X stars.
  - above X: Jump up by X levels.
  - below X: Jump down by X levels.
  - next X: Jump to the next X child.
  - depth X: Jump to the star at depth X.
""";

  @override
  String get summary => "Jump to a different star in a constellation.";

  JumpCommand() {
    argParser.addOption("const",
        abbr: "c", help: "The constellation to jump in.", mandatory: true);
  }

  @override
  Future<void> run() async {
    final constName = findOption("const").fixFilename();
    final commands = getRest("Enter the star to jump to.");
    CliSpin spinner =
        CliSpin(text: "Checking for changes...", spinner: CliSpinners.moon)
            .start();
    final kit = await SKit.open(
        "${Arceus.constFolderPath}/$constName.skit", SKitType.constellation);
    if (!await kit.exists()) {
      spinner.fail("Constellation does not exist.");
      return;
    }
    final constellation = await kit.getConstellation();
    if (await constellation!.checkForChanges()) {
      spinner.warn("There are changes in the tracked folder. ");
      final confirm = Confirm(
              prompt:
                  "Do you want to overwrite the changes in the tracked folder?",
              defaultValue: false)
          .interact();
      if (!confirm) {
        return;
      }
    }
    spinner = CliSpin(
            text: "Attempting jump to $commands...", spinner: CliSpinners.moon)
        .start();
    final star = constellation.getStarAt(commands);
    final extractStream = await star.makeCurrent();
    await extractStream.forEach((filename) {
      spinner.text = "Extracting $filename...";
      Arceus.talker.log("Extracting $filename...");
    });
    spinner.text = "Saving changes...";
    await kit.save();
    spinner.success("Jumped to '${constellation.getCurrentStar().name}'!");
  }
}
