import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:chalkdart/chalkstrings.dart';
import 'package:dart_console/dart_console.dart';
import '../cli.dart';
import '../extensions.dart';

enum Views {
  byteViewer,
  dataFooter,
  changeLog,
}

enum Formats { u8, u16, u32, u64 }

class HexEditor {
  final File _file;
  Views currentView = Views.byteViewer;
  HexEditor(this._file) {
    data = _file.readAsBytesSync().buffer.asByteData();
  }
  ByteData? data;
  Endian dataEndian = Endian.little;
  static const int _minDataHeight = 7;
  int address = 0;
  Formats currentFormat = Formats.u8;
  final List<int> byteColor = [255, 255, 255];
  final List<int> byte16Color = [140, 140, 140];
  final List<int> byte32Color = [100, 100, 100];
  final List<int> byte64Color = [80, 80, 80];

  /// # `String` getByteAt(int address)
  /// ## Get the byte at the given address as a hex string.
  String getByteAt(int address) {
    return data!.getUint8(address).toRadixString(16).padLeft(2, "0");
  }

  /// # `bool` isValidAddress(int address)
  /// ## Check if an address is valid.
  bool isValidAddress(int address) {
    return address >= 0 && address < data!.lengthInBytes;
  }

  /// # `void` render()
  /// ## Render the current state of the editor to the console.
  void render() {
    Cli.moveCursorToTopLeft();
    Cli.clearTerminal();
    // console.clearScreen();

    Cli.moveCursorToTopLeft();
    stdout.writeln(_file.path.getFilename().italic);
    stdout.writeln("");
    stdout.write(renderBody());
    stdout.writeln();

    // Write address at bottom left.
    Cli.moveCursorToBottomLeft();
    stdout.write("Address: 0x${address.toRadixString(16)} ");
    stdout.write(getValues(address));
  }

  String renderBody() {
    final full = StringBuffer();
    final body = StringBuffer();

    // Calculate start and end lines
    int usableRows = Cli.windowHeight - _minDataHeight;
    int linesAboveBelow = usableRows ~/ 2;
    int startLine = (address ~/ 16) - linesAboveBelow;
    int endLine = (address ~/ 16) + linesAboveBelow;

    // Adjust start and end to ensure full screen is used
    if (startLine < 0) {
      startLine = 0;
      endLine = startLine + usableRows;
    } else if (endLine >= ((data!.lengthInBytes / 16).ceil())) {
      endLine = (data!.lengthInBytes / 16).ceil();
      startLine = endLine - usableRows;
      if (startLine < 0) startLine = 0; // Ensure we don't go below zero
    }

    full.write("\t\t00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f\n"
        .padLeft(8, " ")); // Address Headers
    for (int x = startLine * 16 < 0 ? 0 : startLine * 16;
        x < data!.lengthInBytes && x < endLine * 16;
        x += 16) {
      final line = StringBuffer("");
      line.write("${x.toRadixString(16).padLeft(8, "0")}\t"); // Address Labels
      for (int leftHalf = 0; leftHalf < 8; leftHalf++) {
        // Left Half of 16 bytes
        int byteAddress = x + leftHalf;
        if (!isValidAddress(byteAddress)) {
          line.write("  ");
        } else {
          String byte = getByteAt(byteAddress);
          String value = getFormatted(byteAddress, byte);
          line.write(value);
        }
        if (leftHalf != 7) {
          line.write(isValidAddress(byteAddress) ? "│" : " ");
        }
      }
      line.write(" ");
      // Checks to see if there is a second half of 8 bytes
      for (int rightHalf = 8; rightHalf < 16; rightHalf++) {
        // Right Half of 16 bytes
        int byteAddress = x + rightHalf;
        if (!isValidAddress(byteAddress)) {
          line.write("  ");
        } else {
          String byte = getByteAt(byteAddress);
          String value = getFormatted(byteAddress, byte);
          line.write(value);
        }
        if (rightHalf != 15) {
          line.write(isValidAddress(byteAddress) ? "│" : " ");
        }
      }
      line.write("\t│");
      for (int j = 0; j < 16; j++) {
        if (isValidAddress(x + j)) {
          final char = data!.getUint8(x + j);
          final charString =
              _isPrintable(char) ? String.fromCharCode(char) : '.';
          line.write(getFormatted(x + j, charString));
        } else {
          line.write(' ');
        }
      }
      body.write("${line.toString()}\n");
    }
    if (startLine != 0) {
      //Notifies user that there is more data above
      full.write("\t".padLeft(16, " "));
      full.write("───────────────────────^───────────────────────\n");
    } else {
      full.write("\n");
    }
    full.write(body.toString());
    if (endLine < ((data!.lengthInBytes / 16).ceil())) {
      //Notifies user that there is more data below
      full.write("\t".padLeft(16, " "));
      full.write("───────────────────────v───────────────────────\n");
    } else {
      full.write("\n");
    }
    return full.toString();
  }

  String getValues(int byteAddress) {
    StringBuffer values = StringBuffer();
    for (Formats format in Formats.values) {
      // Add all the formats to the values buffer.
      String? value;
      String? header;
      switch (format) {
        case Formats.u8:
          header = "u8".bgRgb(byteColor[0], byteColor[1], byteColor[2]).black;
          value = data!.getUint8(address).toString();
          break;
        case Formats.u16:
          if (isValidAddress(byteAddress + 1)) {
            header = "u16"
                .bgRgb(byte16Color[0], byte16Color[1], byte16Color[2])
                .black;
            value = data!.getUint16(address, dataEndian).toString();
          }
          break;
        case Formats.u32:
          if (isValidAddress(byteAddress + 3)) {
            header = "u32"
                .bgRgb(byte32Color[0], byte32Color[1], byte32Color[2])
                .black;
            value =
                data!.getUint32(address, dataEndian).toStringAsExponential(2);
          }
          break;
        case Formats.u64:
          header =
              "u64".bgRgb(byte64Color[0], byte64Color[1], byte64Color[2]).black;
          if (isValidAddress(byteAddress + 7)) {
            value =
                data!.getUint64(address, dataEndian).toStringAsExponential(2);
          }
          break;
      }
      if (value == null || header == null) {
        continue;
      }
      if (currentView == Views.dataFooter && currentFormat == format) {
        value = value.bgMagentaBright.black;
      }
      values.write("$header $value| ");
    }
    if (currentView != Views.dataFooter) {
      values.write("Press E to edit any of these values.");
    }
    return values.toString();
  }

  String getFormatted(int byteAddress, String value) {
    if (byteAddress == address) {
      value = value.bgRgb(byteColor[0], byteColor[1], byteColor[2]).black;
    } else if (byteAddress == address + 1) {
      value = value.bgRgb(byte16Color[0], byte16Color[1], byte16Color[2]).black;
    } else if (byteAddress >= address + 2 && byteAddress <= address + 3) {
      value = value.bgRgb(byte32Color[0], byte32Color[1], byte32Color[2]).black;
    } else if (byteAddress >= address + 4 && byteAddress <= address + 7) {
      value = value.bgRgb(byte64Color[0], byte64Color[1], byte64Color[2]).black;
    }
    return value;
  }

  bool _isPrintable(int charCode) {
    return charCode >= 32 && charCode <= 126;
  }

  bool _hexView(Key key) {
    bool quit = false;
    if (!key.isControl) {
      switch (key.char) {
        case 'e':
          currentView = Views.dataFooter;
          currentFormat = Formats.u8;
          render();
          break;
      }
      return quit;
    }
    switch (key.controlChar) {
      case ControlCharacter.arrowUp:
        if (!(address - 0x10 < 0)) {
          address -= 0x10;
          render();
        }
        break;
      case ControlCharacter.arrowDown:
        if (!(address + 0x10 >= data!.lengthInBytes)) {
          address += 0x10;
          render();
        }
        break;
      case ControlCharacter.arrowLeft:
        if (!(address - 0x01 < 0)) {
          address -= 0x01;
          render();
        }
        break;
      case ControlCharacter.arrowRight:
        if (!(address + 0x01 >= data!.lengthInBytes)) {
          address += 0x01;
          render();
        }
        break;
      case ControlCharacter.ctrlQ:
        quit = true;
        break;
      default:
        break;
    }
    if (quit) {
      Cli.clearTerminal();
      Cli.moveCursorToTopLeft();
    }
    return quit;
  }

  void _dataFooterView(Key key) {
    switch (key.controlChar) {
      case ControlCharacter.ctrlQ:
        currentView = Views.byteViewer;
        render();
        break;
      case ControlCharacter.arrowLeft:
        int newIndex = currentFormat.index - 1;
        if (newIndex < 0) {
          break;
        }
        currentFormat = Formats.values[newIndex];
        render();
        break;
      case ControlCharacter.arrowRight:
        int newIndex = currentFormat.index + 1;
        if (newIndex >= Formats.values.length) {
          break;
        }
        currentFormat = Formats.values[newIndex];
        render();
        break;
      default:
        break;
    }
  }

  Future<ByteData> interact() async {
    int lastHeight = 1;
    int lastWidth = 1;
    bool quit = false;
    final keyboard = KeyboardInput();
    Cli.hideCursor();
    keyboard.onKeyPress.listen((key) {
      switch (currentView) {
        case Views.byteViewer:
          quit = _hexView(key);
          break;
        case Views.dataFooter:
          _dataFooterView(key);
          break;
        default:
          break;
      }
    });
    while (!quit) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (lastHeight != Cli.windowHeight || lastWidth != Cli.windowWidth) {
        lastHeight = Cli.windowHeight;
        lastWidth = Cli.windowWidth;
        render();
      }
    }
    Cli.showCursor();
    keyboard.dispose();
    return data!;
  }
}