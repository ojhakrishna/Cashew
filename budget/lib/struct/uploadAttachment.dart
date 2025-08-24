import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart'
    show googleUser, signInGoogle, signOutGoogle, GoogleAuthClient;
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';

Future<String?> getPhotoAndUpload({required ImageSource source}) async {
  dynamic result = await openLoadingPopupTryCatch(
    () async {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: source);
      if (photo == null) {
        if (source == ImageSource.camera) throw ("no-photo-taken".tr());
        if (source == ImageSource.gallery) throw ("no-file-selected".tr());
        throw ("error-getting-photo".tr());
      }

      final Uint8List fileBytes = await photo.readAsBytes();
      final Stream<List<int>> mediaStream = photo.openRead();

      try {
        return await uploadFileToDrive(
          fileBytes: fileBytes,
          fileName: photo.name,
          mediaStream: mediaStream,
        );
      } catch (e) {
        print(
          "Error uploading file, trying again and requesting new permissions: $e",
        );
        await signOutGoogle();
        await signInGoogle(drivePermissionsAttachments: true);
        return await uploadFileToDrive(
          fileBytes: fileBytes,
          fileName: photo.name,
          mediaStream: mediaStream,
        );
      }
    },
    onError: (e) {
      openSnackbar(
        SnackbarMessage(
          title: "error-attaching-file".tr(),
          description: e.toString(),
          icon: (appStateSettings["outlinedIcons"] ?? false)
              ? Icons.error_outlined
              : Icons.error_rounded,
        ),
      );
    },
  );
  if (result is String) return result;
  return null;
}

Future<String?> getFileAndUpload() async {
  dynamic result = await openLoadingPopupTryCatch(
    () async {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.single.path == null) {
        throw ("no-file-selected".tr());
      }

      final file = result.files.single;
      final Uint8List fileBytes;

      if (kIsWeb) {
        fileBytes = file.bytes!;
      } else {
        fileBytes = await File(file.path!).readAsBytes();
      }

      final Stream<List<int>> mediaStream = Stream.value(fileBytes);

      try {
        return await uploadFileToDrive(
          fileBytes: fileBytes,
          fileName: file.name,
          mediaStream: mediaStream,
        );
      } catch (e) {
        print(
          "Error uploading file, trying again and requesting new permissions: $e",
        );
        await signOutGoogle();
        await signInGoogle(drivePermissionsAttachments: true);
        return await uploadFileToDrive(
          fileBytes: fileBytes,
          fileName: file.name,
          mediaStream: mediaStream,
        );
      }
    },
    onError: (e) {
      openSnackbar(
        SnackbarMessage(
          title: "error-attaching-file".tr(),
          description: e.toString(),
          icon: (appStateSettings["outlinedIcons"] ?? false)
              ? Icons.error_outlined
              : Icons.error_rounded,
        ),
      );
    },
  );
  if (result is String) return result;
  return null;
}

Future<String?> uploadFileToDrive({
  required Stream<List<int>> mediaStream,
  required Uint8List fileBytes,
  required String fileName,
}) async {
  if (googleUser == null) {
    await signInGoogle(drivePermissionsAttachments: true);
    if (googleUser == null) {
      throw ("google-sign-in-required".tr());
    }
  }

  final authHeaders = await googleUser!.authHeaders;
  final authenticateClient = GoogleAuthClient(authHeaders);
  final driveApi = drive.DriveApi(authenticateClient);

  const String folderName = "Cashew";
  String? folderId;

  final fileList = await driveApi.files.list(
    q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed = false",
    $fields: "files(id, name)",
  );

  if (fileList.files != null && fileList.files!.isNotEmpty) {
    folderId = fileList.files!.first.id;
  }

  if (folderId == null) {
    final folder = drive.File()
      ..name = folderName
      ..mimeType = "application/vnd.google-apps.folder";
    final createdFolder = await driveApi.files.create(folder);
    folderId = createdFolder.id;
  }

  if (folderId == null) {
    throw ("could-not-create-drive-folder".tr());
  }

  final media = drive.Media(mediaStream, fileBytes.length);
  final timestamp = DateFormat("yyyy-MM-dd-HHmmss").format(DateTime.now());

  final driveFile = drive.File()
    ..name = '$timestamp-$fileName'
    ..modifiedTime = DateTime.now().toUtc()
    ..parents = [folderId];

  final createdFile = await driveApi.files.create(
    driveFile,
    uploadMedia: media,
    $fields: "id, webViewLink",
  );

  return createdFile.webViewLink;
}
