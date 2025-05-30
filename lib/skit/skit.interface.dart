part of 'skit.dart';

class SKitInterface extends SInterface<SKit> {
  @override
  get className => "SKit";

  @override
  get classDescription => """
SKits are the bread and butter of Arceus. They store a SHeader and any number of SRoots in a single file.
""";

  @override
  get statics => {
        LEntry(
            name: "open",
            descr: "Opens an SKit file.",
            args: const {
              "path": LArg<String>(
                descr: "The path to the SKit file.",
              ),
              "overrides":
                  LArg<Map>(descr: "Some more options.", required: false),
            },
            returnType: SKit,
            isAsync: true, (String path, [Map overrides = const {}]) async {
          String? encryptKey =
              overrides.containsKey("key") ? overrides["key"] : null;
          return await SKit.open(path, encryptKey: encryptKey ?? "");
        }),
        LEntry(
            name: "exists",
            descr: "Checks if an SKit exists.",
            args: const {
              "path": LArg<String>(
                descr: "The path to the SKit file.",
              )
            },
            returnType: bool,
            isAsync: true, (String path) async {
          return await SKit(path).exists();
        }),
        LEntry(
            name: "create",
            descr: "Creates a new SKit file.",
            args: const {
              "path": LArg<String>(
                descr: "The path to the SKit file.",
              ),
              "overrides":
                  LArg<Map>(descr: "Some more options.", required: false),
            },
            returnType: SKit,
            isAsync: true, (String path, [Map overrides = const {}]) async {
          bool? overwrite =
              overrides.containsKey("override") ? overrides["override"] : null;
          SKitType? type = overrides.containsKey("type")
              ? SKitType.values.firstWhere((e) => e.index == overrides["type"])
              : null;
          String? encryptKey =
              overrides.containsKey("key") ? overrides["key"] : null;
          final skit = SKit(path, encryptKey: encryptKey ?? "");
          await skit.create(
              overwrite: overwrite ?? false,
              type: type ?? SKitType.unspecified);
          return skit;
        }),
      };

  @override
  get exports => {
        LEntry(
            name: "path",
            descr: "Returns the path of the SKit file.",
            returnType: String,
            () => object!.path),
        LEntry(
            name: "isType",
            descr: "Returns whether the SKit is of the specified type.",
            args: const {"type": LArg<int>(descr: "The type to check for.")},
            returnType: bool,
            isAsync: true, (int type) async {
          return await object!.isType(SKitType.values[type]);
        }),
        LEntry(
            name: "header",
            descr: "Returns the SHeader of the SKit.",
            returnType: SHeader,
            isAsync: true,
            () => object!.getHeader()),
        LEntry(
            name: "createdOn",
            descr: "Returns the creation date of the SKit.",
            returnType: String,
            isAsync: true, () async {
          final header = await object!.getHeader();
          return header!.createdOn.toIso8601String();
        }),
        LEntry(
            name: "lastModified",
            descr: "Returns the last modified date of the SKit.",
            returnType: String,
            isAsync: true, () async {
          final header = await object!.getHeader();
          return header!.lastModified.toIso8601String();
        }),
        LEntry(
            name: "key",
            descr: "Sets and Gets the encryption key of the SKit.",
            args: const {
              "key":
                  LArg<String>(descr: "The encryption key.", required: false),
            },
            returnType: String, ([String? key]) async {
          if (key != null) {
            object!.key = key;
          }
          return object!.key;
        }),
        LEntry(
            name: "save",
            descr: "Saves changes to the SKit.",
            isAsync: true,
            () => object!.save()),
        LEntry(
            name: "discard",
            descr: "Discards changes to the SKit.",
            () => object!.discardChanges()),
        LEntry(
            name: "exportAs",
            descr: "Exports the SKit as an uncompressed, decrypted xml file.",
            args: const {"path": LArg<String>(descr: "The path to export to.")},
            isAsync: true,
            (String path) async => await object!.exportToXMLFile(path))
      };
}
