import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arceus/arceus.dart';
import 'package:arceus/scripting/lua.dart';
import 'package:arceus/skit/skit.dart';
import 'package:chalkdart/chalkstrings.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:version/version.dart';
import 'package:http/http.dart' as http;

typedef ArceusSession = (Lua, WebSocket);

Future<void> main(List<String> args) async {
  /// Check if the version of this Arceus executable is already running.
  final isRunningSpinner = CliSpin(spinner: CliSpinners.bounce)
      .start("Checking if running...".skyBlue);
  if (await isRunning(Arceus.currentVersion)) {
    isRunningSpinner.fail('Already Running.'.skyBlue);
    exit(0);
  }

  isRunningSpinner.success("Ready to Start!".skyBlue);

  /// If not, create a lock file to indicate that this version of Arceus is running.
  File lockFile = File(
      "${Arceus.appDataPath}/locks/${Arceus.currentVersion.toString()}.lock");

  final spinner =
      CliSpin(spinner: CliSpinners.bounce).start("Generating Docs...".skyBlue);

  /// Regenerate the lua documentation.
  await Lua.generateDocs().listen((doc) {
    spinner.text = "Generating $doc...".skyBlue;
  }).asFuture();

  spinner.success(
      "Generated Lua Docs at \"${Arceus.appDataPath}/docs/${Arceus.currentVersion.toString()}/\""
          .skyBlue);

  /// Verify the signature of the user.
  await Arceus.verifySignature();

  final serverSpinner =
      CliSpin(spinner: CliSpinners.bounce).start("Starting Server...".skyBlue);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 7274);
  serverSpinner.success("Server Started!".skyBlue);

  Map<String, ArceusSession> sessions = {};

  await for (HttpRequest request in server) {
    try {
      /// Check if the requested version is the same as this program's version.
      if (request.uri.pathSegments.firstOrNull !=
          Arceus.currentVersion.toString()) {
        /// If not, check if the requested version is running.
        if (await isRunning(
            Version.parse(request.uri.pathSegments.firstOrNull!))) {
          /// The requested version is running.
          request.response.statusCode = HttpStatus.movedPermanently;
          await request.response.close();
          continue;
        } else {
          /// The requested version is not running.
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          Arceus.talker.error(
              "Version not found. ${request.uri.pathSegments.firstOrNull} not found.");
          continue;
        }
      }

      final requestUrl = request.uri.pathSegments.sublist(1).join('/');

      /// If the requested version is the same as this program's version, continue as normal.
      switch (requestUrl) {
        case "heartbeat":
          request.response.statusCode = HttpStatus.ok;
          Arceus.talker.info(
              "Heartbeat checked at ${DateTime.now().toIso8601String()}.");
          await request.response.close();
        case "close":
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          for (final session in sessions.entries) {
            await session.value.$1.awaitForCompletion();
            await session.value.$2
                .close(WebSocketStatus.goingAway, "Server closed.");
          }
          await server.close();
          exit(0);
        case "lua":
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            final socket = await WebSocketTransformer.upgrade(request);
            sessions[request.session.id] = (Lua(socket: socket), socket);
            await sessions[request.session.id]!.$1.init();

            Arceus.printToConsole(
                'Client (${request.session.id}) connected.'.skyBlue);

            Arceus.talker.info("Client (${request.session.id}) connected.");
            socket.listen((data) async {
              final requestProgress = CliSpin(spinner: CliSpinners.bounce).start(
                  "Processing request from client (${request.session.id})..."
                      .aqua);
              try {
                final result = await sessions[request.session.id]!.$1.run(data);
                socket.add(jsonEncode({
                  "type": "response",
                  "successful": true,
                  "processTime": sessions[request.session.id]!
                      .$1
                      .stopwatch
                      .elapsedMilliseconds,
                  "return": result
                }));
                requestProgress.success(
                    "Completed request in ${sessions[request.session.id]!.$1.stopwatch.elapsedMilliseconds}ms (${request.session.id})!"
                        .limeGreen);
              } catch (e, st) {
                requestProgress.fail(
                    "There was a crash on this request (Session ID: ${request.session.id}), please check the log folder (${Arceus.appDataPath}/logs) for more information."
                        .red);
                Arceus.talker.critical("Crash Handler", e, st);
                socket.add(jsonEncode({
                  "type": "response",
                  "successful": false,
                  "processTime": sessions[request.session.id]!
                      .$1
                      .stopwatch
                      .elapsedMilliseconds,
                  "return": null
                }));
              }
            }, onDone: () {
              Arceus.printToConsole(
                  'Client (${request.session.id}) disconnected'.skyBlue);
              Arceus.talker
                  .info("Client (${request.session.id}) disconnected.");
              socket.close();
              sessions.remove(request.session.id);
              return;
            }, onError: (error, stack) {
              Arceus.talker.error("Error", error, stack);
            }, cancelOnError: false);
          } else {
            request.response
              ..statusCode = HttpStatus.forbidden
              ..close();
          }
      }
    } catch (e, st) {
      Arceus.printToConsole(
          "There was a crash on a websocket, please check the log folder (${Arceus.appDataPath}/logs) for more information."
              .red);
      Arceus.talker.critical("Crash Handler", e, st);
    }
  }
  await lockFile.delete();
  exit(0);
}

/// This function checks if the version of this Arceus executable is already running.
/// If it is, it will return true, otherwise it will return false.
Future<bool> isRunning(Version version) async {
  /// If the file does exist, double check to see if the version has a heartbeat.
  File lockFile =
      File("${Arceus.appDataPath}/locks/${version.toString()}.lock");
  if (await lockFile.exists()) {
    final uri = Uri.http("127.0.0.1:7274", "${version.toString()}/heatbeat");
    try {
      var response = await http.get(uri);
      if (response.statusCode == 200) return true;
      return false;
    } catch (e) {
      Arceus.talker
          .info("Failed to check heartbeat. Assuming it's not running.");
      return false;
    }
  } else {
    return false;
  }
}
