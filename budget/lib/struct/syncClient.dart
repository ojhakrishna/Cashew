import 'dart:async';
import 'package:async/async.dart';
import 'dart:convert';
import 'package:budget/database/binary_string_conversion.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart' as db_global;
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/util/debouncer.dart';
import 'package:budget/widgets/walletEntry.dart';
// import 'package:drift/web.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:googleapis/drive/v3.dart' as drive;
import 'dart:io';
import 'package:http/http.dart' as http;

// Lightweight authenticated HTTP client wrapper for Google APIs.
// If you already have this class defined elsewhere in your project,
// remove this definition to avoid duplicate-symbol errors.
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

bool isSyncBackupFile(String? backupFileName) {
  if (backupFileName == null) return false;
  return backupFileName.contains("sync-");
}

bool isCurrentDeviceSyncBackupFile(String? backupFileName) {
  if (backupFileName == null) return false;
  return backupFileName == getCurrentDeviceSyncBackupFileName();
}

String getCurrentDeviceSyncBackupFileName({String? clientIDForSync}) {
  final id = clientIDForSync ?? db_global.clientID;
  return 'sync-' + id + '.sqlite';
}

String getDeviceFromSyncBackupFileName(String? backupFileName) {
  if (backupFileName == null) return "";
  final stripped = backupFileName.replaceAll('sync-', '');
  // If file name includes client id followed by other parts separated by '-', return the first segment
  return stripped.split('-').first;
}

String getCurrentDeviceName() {
  return db_global.clientID.split('-').first;
}

Future<DateTime> getDateOfLastSyncedWithClient(String clientIDForSync) async {
  final string =
      db_global.sharedPreferences.getString('dateOfLastSyncedWithClient') ??
          '{}';
  final parsed = jsonDecode(string) as Map<String, dynamic>;
  final lastTimeSynced = (parsed[clientIDForSync] ?? '').toString();
  if (lastTimeSynced.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  try {
    return DateTime.parse(lastTimeSynced);
  } catch (e) {
    debugPrint('Error getting time of last sync: $e');
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

Future<bool> setDateOfLastSyncedWithClient(
    String clientIDForSync, DateTime dateTimeSynced) async {
  final string =
      db_global.sharedPreferences.getString('dateOfLastSyncedWithClient') ??
          '{}';
  final parsed = jsonDecode(string) as Map<String, dynamic>;
  parsed[clientIDForSync] = dateTimeSynced.toIso8601String();
  await db_global.sharedPreferences
      .setString('dateOfLastSyncedWithClient', jsonEncode(parsed));
  return true;
}

// if changeMadeSync show loading and check if syncEveryChange is turned on
Timer? syncTimeoutTimer;
Debouncer backupDebounce = Debouncer(milliseconds: 5000);

Future<bool> createSyncBackup({
  bool changeMadeSync = false,
  bool changeMadeSyncWaitForDebounce = true,
}) async {
  if (appStateSettings['hasSignedIn'] == false) return false;
  if (errorSigningInDuringCloud == true) return false;
  if (appStateSettings['backupSync'] == false) return false;
  if (changeMadeSync == true && appStateSettings['syncEveryChange'] == false)
    return false;

  // create the auto syncs after debounce when running on web and syncEveryChange is true
  if (changeMadeSync == true &&
      (appStateSettings['syncEveryChange'] == true && kIsWeb) &&
      changeMadeSyncWaitForDebounce == true) {
    debugPrint('Running sync debouncer');
    backupDebounce.run(() {
      createSyncBackup(
          changeMadeSync: true, changeMadeSyncWaitForDebounce: false);
    });
    return true;
  }

  debugPrint('Creating sync backup');
  if (changeMadeSync)
    loadingIndeterminateKey.currentState?.setVisibility(true, opacity: 0.4);

  if (syncTimeoutTimer?.isActive == true) {
    if (changeMadeSync)
      loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  } else {
    syncTimeoutTimer = Timer(const Duration(milliseconds: 5000), () {
      syncTimeoutTimer?.cancel();
    });
  }

  bool hasSignedIn = false;
  if (googleUser == null) {
    hasSignedIn = await signInGoogle(
        gMailPermissions: false, waitForCompletion: false, silentSignIn: true);
  } else {
    hasSignedIn = true;
  }
  if (!hasSignedIn) {
    if (changeMadeSync)
      loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  }

  final authHeaders = await googleUser!.authHeaders;
  final authenticateClient = GoogleAuthClient(authHeaders);
  final driveApi = drive.DriveApi(authenticateClient);

  try {
    final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        $fields: 'files(id, name, modifiedTime, size)');
    final files = fileList.files ?? <drive.File>[];

    for (final file in files) {
      if (isCurrentDeviceSyncBackupFile(file.name)) {
        try {
          await deleteBackup(driveApi, file.id ?? '');
        } catch (e) {
          debugPrint('Error deleting old sync backup: $e');
        }
      }
    }
  } catch (e) {
    debugPrint('Error listing drive files: $e');
  }

  await createBackup(null,
      silentBackup: true,
      deleteOldBackups: true,
      clientIDForSync: db_global.clientID);

  if (changeMadeSync)
    loadingIndeterminateKey.currentState?.setVisibility(false);
  return true;
}

class SyncLog {
  SyncLog({
    this.deleteLogType,
    this.updateLogType,
    required this.transactionDateTime,
    required this.pk,
    this.itemToUpdate,
  });

  DeleteLogType? deleteLogType;
  UpdateLogType? updateLogType;
  DateTime? transactionDateTime;
  String pk;
  dynamic itemToUpdate;

  @override
  String toString() {
    return 'SyncLog(deleteLogType: $deleteLogType, updateLogType: $updateLogType, transactionDateTime: $transactionDateTime, pk: $pk, itemToUpdate: $itemToUpdate)';
  }
}

// Only allow one sync at a time
bool canSyncData = true;

bool requestSyncDataCancel = false;

CancelableCompleter<bool> syncDataCompleter = CancelableCompleter(onCancel: () {
  requestSyncDataCancel = true;
});

Future<dynamic> cancelAndPreventSyncOperation() async {
  requestSyncDataCancel = true;
  return await syncDataCompleter.operation.cancel();
}

Future<bool> runForceSignIn(BuildContext context) async {
  if (appStateSettings['forceAutoLogin'] == false) return false;
  if (appStateSettings['hasSignedIn'] == false) return false;
  return await signInGoogle(
      gMailPermissions: false,
      waitForCompletion: false,
      silentSignIn: true,
      context: context);
}

Future<bool> syncData(BuildContext context) async {
  // Create a new instance of the completer if the previous one completed
  if (syncDataCompleter.isCompleted) {
    syncDataCompleter = CancelableCompleter(onCancel: () {
      requestSyncDataCancel = true;
    });
  }

  syncDataCompleter.complete(Future.value(_syncData(context)));
  return syncDataCompleter.operation.value;
}

// load the latest backup and import any newly modified data into the db
Future<bool> _syncData(BuildContext context) async {
  if (canSyncData == false) return false;

  if (appStateSettings['backupSync'] == false) return false;
  if (appStateSettings['hasSignedIn'] == false) return false;
  if (errorSigningInDuringCloud == true) return false;

  // Prevent silent background sign-in on web until app is fully loaded in some configurations
  if (kIsWeb &&
      !entireAppLoaded &&
      appStateSettings['webForceLoginPopupOnLaunch'] != true) return false;

  canSyncData = false;

  bool hasSignedIn = false;
  if (googleUser == null) {
    hasSignedIn = await signInGoogle(
        gMailPermissions: false, waitForCompletion: false, silentSignIn: true);
  } else {
    hasSignedIn = true;
  }
  if (!hasSignedIn) {
    canSyncData = true;
    return false;
  }

  final authHeaders = await googleUser!.authHeaders;
  final authenticateClient = GoogleAuthClient(authHeaders);
  final driveApi = drive.DriveApi(authenticateClient);

  // Ensure a backup exists locally before attempting to list/download
  await createSyncBackup();

  drive.FileList fileList;
  try {
    fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        $fields: 'files(id, name, modifiedTime, size)');
  } catch (e) {
    debugPrint('Failed to list drive files: $e');
    canSyncData = true;
    return false;
  }

  final files = fileList.files;
  if (files == null) {
    debugPrint('No backups found.');
    canSyncData = true;
    return false;
  }

  final filesToDownloadSyncChanges = <drive.File>[];
  for (final file in files) {
    if (isSyncBackupFile(file.name)) filesToDownloadSyncChanges.add(file);
  }

  debugPrint('LOADING SYNC DB');
  final syncStarted = DateTime.now();
  final List<SyncLog> syncLogs = [];
  final List<drive.File> filesSyncing = [];

  int currentFileIndex = 0;
  loadingProgressKey.currentState?.setProgressPercentage(0);

  for (final file in filesToDownloadSyncChanges) {
    if (requestSyncDataCancel == true) {
      loadingProgressKey.currentState?.setProgressPercentage(0);
      loadingIndeterminateKey.currentState?.setVisibility(false);
      debugPrint('Cancelling sync!');
      requestSyncDataCancel = false;
      canSyncData = true;
      return false;
    }

    loadingIndeterminateKey.currentState?.setVisibility(true);

    // Skip restoring from this client's own backup
    if (isCurrentDeviceSyncBackupFile(file.name)) continue;

    final lastSynced = await getDateOfLastSyncedWithClient(
        getDeviceFromSyncBackupFileName(file.name));

    debugPrint('COMPARING TIMES');
    debugPrint('Drive modified: ${file.modifiedTime?.toLocal()}');
    debugPrint('Last synced: $lastSynced');

    if (file.modifiedTime == null ||
        lastSynced.isAfter(file.modifiedTime!.toLocal()) ||
        lastSynced == file.modifiedTime!.toLocal()) {
      debugPrint(
          'No need to restore backup from this client, no new backup file to pull data from');
      continue;
    }

    final fileId = file.id;
    if (fileId == null) continue;
    debugPrint('SYNCING WITH ${file.name ?? ''}');
    filesSyncing.add(file);

    final dataStore = <int>[];
    dynamic response;
    try {
      response = await driveApi.files
          .get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
    } catch (e) {
      debugPrint('Failed to download file $fileId: $e');
      continue;
    }

    await for (final data in response.stream) {
      dataStore.insertAll(dataStore.length, data);
    }

    FinanceDatabase databaseSync;

    if (kIsWeb) {
      final dataEncoded = bin2str.encode(Uint8List.fromList(dataStore));
      try {
        databaseSync = await db_global.constructDb(
            dbName: 'syncdb'); // Removed initialDataWeb, not a valid param
      } catch (e) {
        final megabytes = dataEncoded.length / (1024 * 1024);
        await openPopup(
          context,
          title: 'syncing-failed'.tr(),
          description: e.toString() +
              '\n\n' +
              megabytes.toString() +
              ' MB in size' +
              ' when syncing with ' +
              (file.name ?? ''),
          icon: appStateSettings['outlinedIcons']
              ? Icons.sync_problem_outlined
              : Icons.sync_problem_rounded,
          onSubmit: () => popRoute(context),
          onSubmitLabel: 'ok'.tr(),
        );
        throw e;
      }
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'syncdb.sqlite'));
      await dbFile.writeAsBytes(dataStore);
      databaseSync = await db_global.constructDb(dbName: 'syncdb');
    }

    try {
      final newWallets = await databaseSync.getAllNewWallets(lastSynced);
      for (final newEntry in newWallets) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionWallet,
          pk: newEntry.walletPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newCategories = await databaseSync.getAllNewCategories(lastSynced);
      for (final newEntry in newCategories) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionCategory,
          pk: newEntry.categoryPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newBudgets = await databaseSync.getAllNewBudgets(lastSynced);
      for (final newEntry in newBudgets) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Budget,
          pk: newEntry.budgetPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newCategoryBudgetLimits =
          await databaseSync.getAllNewCategoryBudgetLimits(lastSynced);
      for (final newEntry in newCategoryBudgetLimits) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.CategoryBudgetLimit,
          pk: newEntry.categoryLimitPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newTransactions =
          await databaseSync.getAllNewTransactions(lastSynced);
      for (final newEntry in newTransactions) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Transaction,
          pk: newEntry.transactionPk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newTitles =
          await databaseSync.getAllNewAssociatedTitles(lastSynced);
      for (final newEntry in newTitles) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.TransactionAssociatedTitle,
          pk: newEntry.associatedTitlePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final scannerTemplates =
          await databaseSync.getAllNewScannerTemplates(lastSynced);
      for (final newEntry in scannerTemplates) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.ScannerTemplate,
          pk: newEntry.scannerTemplatePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final newObjectives = await databaseSync.getAllNewObjectives(lastSynced);
      for (final newEntry in newObjectives) {
        syncLogs.add(SyncLog(
          deleteLogType: null,
          updateLogType: UpdateLogType.Objective,
          pk: newEntry.objectivePk,
          itemToUpdate: newEntry,
          transactionDateTime: newEntry.dateTimeModified,
        ));
      }

      final deleteLogs = await databaseSync.getAllNewDeleteLogs(lastSynced);
      for (final deleteLog in deleteLogs) {
        syncLogs.add(SyncLog(
          deleteLogType: deleteLog.type,
          updateLogType: null,
          pk: deleteLog.entryPk,
          transactionDateTime: deleteLog.dateTimeModified,
        ));
      }
    } catch (e) {
      debugPrint('Syncing error and failed: $e');
      filesSyncing.remove(file);
      await databaseSync.close();
      loadingProgressKey.currentState?.setProgressPercentage(1);
      canSyncData = true;
      await openPopup(
        context,
        title: 'syncing-failed'.tr(),
        description: 'sync-fail-reason'.tr() + '\n\n' + (file.name ?? ''),
        descriptionWidget: Padding(
          padding: const EdgeInsetsDirectional.only(top: 8, bottom: 12),
          child: CodeBlock(text: e.toString()),
        ),
        icon: appStateSettings['outlinedIcons']
            ? Icons.sync_problem_outlined
            : Icons.sync_problem_rounded,
        onCancel: () => popRoute(context),
        onCancelLabel: 'close'.tr(),
        onSubmit: () =>
            chooseBackup(context, isManaging: true, isClientSync: true),
        onSubmitLabel: 'manage'.tr(),
      );
      return false;
    }

    currentFileIndex += 1;
    loadingProgressKey.currentState?.setProgressPercentage(
        currentFileIndex / filesToDownloadSyncChanges.length);

    await databaseSync.close();
  }

  await db_global.database.processSyncLogs(syncLogs);
  for (final file in filesSyncing) {
    await setDateOfLastSyncedWithClient(
        getDeviceFromSyncBackupFileName(file.name),
        file.modifiedTime?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0));
  }

  try {
    debugPrint('UPDATED WALLET CURRENCY');
    await db_global.database
        .getWalletInstance(appStateSettings['selectedWalletPk']);
  } catch (e) {
    debugPrint('Selected wallet not found: $e');
    final wallets = await db_global.database.getAllWallets();
    if (wallets.isNotEmpty) await setPrimaryWallet(wallets[0].walletPk);
  }

  updateSettings(
    'lastSynced',
    syncStarted.toString(),
    pagesNeedingRefresh: [],
    updateGlobalState: getIsFullScreen(context) ? true : false,
  );

  loadingProgressKey.currentState?.setProgressPercentage(0.999);

  Future.delayed(const Duration(milliseconds: 300), () {
    loadingProgressKey.currentState?.setProgressPercentage(1);
  });

  canSyncData = true;

  debugPrint('DONE SYNCING');
  return true;
}
