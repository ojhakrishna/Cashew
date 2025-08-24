import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart' as main_app;
import 'package:budget/pages/editHomePage.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:budget/widgets/watchAllWallets.dart';
import 'package:flutter/scheduler.dart';
import 'package:budget/struct/databaseGlobal.dart' as db_global;
import 'package:budget/struct/defaultPreferences.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/colors.dart';
import 'package:flutter/material.dart' as flutter_widgets;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:budget/struct/languageMap.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/radioItems.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/pages/activityPage.dart';

Map<String, dynamic> appStateSettings = {};
bool isDatabaseCorrupted = false;
String databaseCorruptedError = "";
bool isDatabaseImportedOnThisSession = false;
PackageInfo? packageInfoGlobal;

Future<bool> initializeSettings() async {
  packageInfoGlobal = await PackageInfo.fromPlatform();

  Map<String, dynamic> userSettings = await getUserSettings();
  if (userSettings["databaseJustImported"] == true) {
    isDatabaseImportedOnThisSession = true;
    try {
      print("Settings were loaded from backup, trying to restore");
      // Safely get settings, handle potential null
      final settingsData = await db_global.database.getSettings();
      String storedSettings = settingsData.settingsJSON;
      await main_app.sharedPreferences
          .setString('userSettings', storedSettings);
      print(storedSettings);
      userSettings = json.decode(storedSettings);

      Map<String, dynamic> userPreferencesDefault =
          await getDefaultPreferences();
      userPreferencesDefault.forEach((key, value) {
        userSettings = attemptToMigrateCyclePreferences(userSettings, key);
        if (userSettings[key] == null) {
          userSettings[key] = userPreferencesDefault[key];
        }
      });
      // Always reset the language/locale when restoring a backup
      userSettings["locale"] = "System";
      userSettings["databaseJustImported"] = false;
      print("Settings were restored");
    } catch (e) {
      print("Error restoring imported settings: " + e.toString());
      // Check for Drift-specific exceptions if drift_remote is used
      // Note: DriftRemoteException is from 'package:drift/remote.dart'
      // if (e is DriftRemoteException) {
      //   if (e.remoteCause.toString().toLowerCase().contains("file is not a database")) {
      //     isDatabaseCorrupted = true;
      //     databaseCorruptedError = e.toString();
      //   }
      // }
      if (e.toString().toLowerCase().contains("file is not a database")) {
        isDatabaseCorrupted = true;
        databaseCorruptedError = e.toString();
      }
    }
  }

  appStateSettings = userSettings;
  print(
    "App settings loaded: if logging is enabled, logs will now be captured",
  );

  // Do some actions based on loaded settings
  if (appStateSettings["accentSystemColor"] == true) {
    appStateSettings["accentColor"] = await getAccentColorSystemString();
  }

  await attemptToMigrateSetLongTermLoansAmountTo0();
  attemptToMigrateCustomNumberFormattingSettings();

  if (appStateSettings["hasOnboarded"] == true) {
    // Safely increment numLogins, providing a default value if it's null
    appStateSettings["numLogins"] = (appStateSettings["numLogins"] ?? 0) + 1;
  }

  appStateSettings["appOpenedHour"] = DateTime.now().hour;
  appStateSettings["appOpenedMinute"] = DateTime.now().minute;

  String? retrievedClientID =
      await main_app.sharedPreferences.getString("clientID");
  // Ensure clientID is never null. If it doesn't exist, create a new one.
  db_global.clientID = retrievedClientID ?? db_global.uuid.v4();
  await main_app.sharedPreferences.setString("clientID", db_global.clientID);

  // Safely parse animation speed with a fallback
  timeDilation = double.tryParse(
          appStateSettings["animationSpeed"]?.toString() ?? '1.0') ??
      1.0;

  selectedWalletPkController.add(
    SelectedWalletPk(
      selectedWalletPk: appStateSettings["selectedWalletPk"]?.toString() ?? "0",
    ),
  );

  Map<String, dynamic> defaultPreferences = await getDefaultPreferences();

  fixHomePageOrder(defaultPreferences, "homePageOrder");
  fixHomePageOrder(defaultPreferences, "homePageOrderFullScreen");

  // save settings
  await main_app.sharedPreferences.setString(
    "userSettings",
    json.encode(appStateSettings),
  );

  try {
    globalCollapsedFutureID.value = (jsonDecode(
      main_app.sharedPreferences.getString("globalCollapsedFutureID") ?? "{}",
    ) as Map<String, dynamic>)
        .map((key, value) {
      return MapEntry(key, value is bool ? value : false);
    });
  } catch (e) {
    print(
      "There was an error restoring globalCollapsedFutureID preference: " +
          e.toString(),
    );
  }

  try {
    loadRecentlyDeletedTransactions();
  } catch (e) {
    print(
      "There was an error loading recently deleted transactions map: " +
          e.toString(),
    );
  }

  return true;
}

// setAppStateSettings
Future<bool> updateSettings(
  String setting,
  dynamic value, {
  // value can be of any type
  required bool updateGlobalState,
  List<int> pagesNeedingRefresh = const [],
  bool forceGlobalStateUpdate = false,
  bool setStateAllPageFrameworks = false,
}) async {
  bool isChanged = appStateSettings[setting] != value;

  appStateSettings[setting] = value;
  await main_app.sharedPreferences.setString(
    'userSettings',
    json.encode(appStateSettings),
  );

  if (updateGlobalState == true) {
    if (isChanged || forceGlobalStateUpdate) {
      print(
        "Rebuilt Main Request from: " +
            setting.toString() +
            " : " +
            value.toString(),
      );
      main_app.appStateKey.currentState?.refreshAppState();
    }
  } else {
    if (setStateAllPageFrameworks) {
      refreshPageFrameworks();
      transactionsListPageStateKey.currentState?.refreshState();
    }
    for (int page in pagesNeedingRefresh) {
      print("Pages Rebuilt and Refreshed: " + pagesNeedingRefresh.toString());
      if (page == 0) {
        homePageStateKey.currentState?.refreshState();
      } else if (page == 1) {
        transactionsListPageStateKey.currentState?.refreshState();
      } else if (page == 2) {
        budgetsListPageStateKey.currentState?.refreshState();
      } else if (page == 3) {
        settingsPageStateKey.currentState?.refreshState();
        settingsPageFrameworkStateKey.currentState?.refreshState();
        purchasesStateKey.currentState?.refreshState();
      }
    }
  }

  return true;
}

Map<String, dynamic> getSettingConstants(Map<String, dynamic> userSettings) {
  final Map<String, flutter_widgets.ThemeMode> themeSetting = {
    "system": flutter_widgets.ThemeMode.system,
    "light": flutter_widgets.ThemeMode.light,
    "dark": flutter_widgets.ThemeMode.dark,
    "black": flutter_widgets.ThemeMode.dark,
  };

  Map<String, dynamic> userSettingsNew = {...userSettings};
  // Provide a fallback value for theme and accentColor to prevent null errors
  userSettingsNew["theme"] =
      themeSetting[userSettings["theme"]] ?? flutter_widgets.ThemeMode.system;
  userSettingsNew["accentColor"] = HexColor(
    userSettings["accentColor"]?.toString() ?? '#0084F8', // Default color
  ).withOpacity(1);
  return userSettingsNew;
}

Future<Map<String, dynamic>> getUserSettings() async {
  Map<String, dynamic> userPreferencesDefault = await getDefaultPreferences();

  String? userSettingsString =
      main_app.sharedPreferences.getString('userSettings');

  // If no settings are stored, return the default preferences immediately.
  if (userSettingsString == null) {
    print("No user settings found, using defaults.");
    await main_app.sharedPreferences.setString(
      'userSettings',
      json.encode(userPreferencesDefault),
    );
    return userPreferencesDefault;
  }

  try {
    print("Found user settings on file");
    Map<String, dynamic> userSettingsJSON = json.decode(userSettingsString);

    // Ensure all default keys exist in the loaded settings.
    userPreferencesDefault.forEach((key, value) {
      userSettingsJSON = attemptToMigrateCyclePreferences(
        userSettingsJSON,
        key,
      );
      userSettingsJSON.putIfAbsent(key, () => value);
    });
    return userSettingsJSON;
  } catch (e) {
    print("Error parsing settings, reverting to defaults: " + e.toString());
    await main_app.sharedPreferences.setString(
      'userSettings',
      json.encode(userPreferencesDefault),
    );
    return userPreferencesDefault;
  }
}

String languageDisplayFilter(String languageKey) {
  if (languageNamesJSON[languageKey] != null) {
    return languageNamesJSON[languageKey].toString().capitalizeFirstofEach;
  }
  if (languageKey == "System") return "system".tr();
  return languageKey;
}

void openLanguagePicker(flutter_widgets.BuildContext context) {
  print(appStateSettings["locale"]);
  openBottomSheet(
    context,
    PopupFramework(
      title: "language".tr(),
      child: flutter_widgets.Column(
        children: [
          flutter_widgets.Padding(
            padding: flutter_widgets.EdgeInsetsDirectional.only(bottom: 10),
            child: TranslationsHelp(),
          ),
          RadioItems(
            items: [
              "System",
              for (String localeKey in supportedLocales.keys) localeKey,
            ],
            initial: appStateSettings["locale"]?.toString() ?? "System",
            displayFilter: languageDisplayFilter,
            onChanged: (value) async {
              appStateSettings["locale"] = value;
              if (value == "System") {
                await context.resetLocale();
              } else {
                if (supportedLocales[value] != null) {
                  await context.setLocale(supportedLocales[value]!);
                }
              }
              updateSettings(
                "locale",
                value,
                pagesNeedingRefresh: [3],
                updateGlobalState: false,
              );
              await Future.delayed(const Duration(milliseconds: 50));
              initializeLocalizedMonthNames();
              flutter_widgets.Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> resetLanguageToSystem(flutter_widgets.BuildContext context) async {
  if (appStateSettings["locale"]?.toString() == "System") return;
  await context.resetLocale();
  await updateSettings(
    "locale",
    "System",
    pagesNeedingRefresh: [],
    updateGlobalState: false,
  );
}

Future<void> backupSettings() async {
  String? userSettings = main_app.sharedPreferences.getString('userSettings');
  if (userSettings == null) throw ("No settings stored to backup");
  await db_global.database.createOrUpdateSettings(
    AppSetting(
      settingsPk:
          0, // Assuming 0 is the fixed key for the single settings entry
      settingsJSON: userSettings,
      dateUpdated: DateTime.now(),
    ),
  );
  print("Created settings entry in DB");
}

class TranslationsHelp extends flutter_widgets.StatelessWidget {
  const TranslationsHelp({
    super.key,
    this.showIcon = true,
    this.backgroundColor,
  });

  final bool showIcon;
  final flutter_widgets.Color? backgroundColor;

  @override
  @override
  flutter_widgets.Widget build(flutter_widgets.BuildContext context) {
    return Tappable(
      onTap: () {
        openUrl('mailto:dapperappdeveloper@gmail.com');
      },
      onLongPress: () {
        copyToClipboard("dapperappdeveloper@gmail.com");
      },
      color: backgroundColor ??
          flutter_widgets.Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withOpacity(0.7),
      borderRadius: getPlatform() == PlatformOS.isIOS ? 10 : 15,
      child: flutter_widgets.Padding(
        padding: const flutter_widgets.EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 12,
        ),
        child: flutter_widgets.Row(
          children: [
            if (showIcon)
              flutter_widgets.Padding(
                padding: const flutter_widgets.EdgeInsets.only(right: 12),
                child: flutter_widgets.Icon(
                  (appStateSettings["outlinedIcons"] ?? false)
                      ? flutter_widgets.Icons.connect_without_contact_outlined
                      : flutter_widgets.Icons.connect_without_contact_rounded,
                  color:
                      flutter_widgets.Theme.of(context).colorScheme.secondary,
                  size: 31,
                ),
              ),
            flutter_widgets.Expanded(
              child: TextFont(
                text: "", // Rich text is used instead
                textColor: getColor(context, "black"),
                textAlign: showIcon
                    ? flutter_widgets.TextAlign.start
                    : flutter_widgets.TextAlign.center,
                richTextSpan: [
                  flutter_widgets.TextSpan(
                    text: "translations-help".tr() + " ",
                    style: flutter_widgets.TextStyle(
                      color: getColor(context, "black"),
                      fontFamily: appStateSettings["font"]?.toString(),
                      fontFamilyFallback: const ['Inter'],
                    ),
                  ),
                  flutter_widgets.TextSpan(
                    text: 'dapperappdeveloper@gmail.com',
                    style: flutter_widgets.TextStyle(
                      decoration: flutter_widgets.TextDecoration.underline,
                      decorationStyle:
                          flutter_widgets.TextDecorationStyle.solid,
                      decorationColor: getColor(
                        context,
                        "unPaidOverdue",
                      ).withOpacity(0.8),
                      color: getColor(
                        context,
                        "unPaidOverdue",
                      ).withOpacity(0.8),
                      fontFamily: appStateSettings["font"]?.toString(),
                      fontFamilyFallback: const ['Inter'],
                    ),
                  ),
                ],
                maxLines: 5,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder for a function that needs to be updated for null safety
void attemptToMigrateCustomNumberFormattingSettings() {
  // Implement migration logic here if needed
}

// Placeholder for a function that needs to be updated for null safety
Future<void> attemptToMigrateSetLongTermLoansAmountTo0() async {
  // Implement migration logic here if needed
}

// Placeholder for a function that needs to be updated for null safety
Map<String, dynamic> attemptToMigrateCyclePreferences(
    Map<String, dynamic> userSettingsJSON, String key) {
  // Implement migration logic here if needed
  return userSettingsJSON;
}
