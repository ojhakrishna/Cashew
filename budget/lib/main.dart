import 'package:budget/functions.dart';
import 'package:budget/pages/accountsPage.dart';
import 'package:budget/pages/autoTransactionsPageEmail.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/iconObjects.dart';
import 'package:budget/struct/keyboardIntents.dart';
import 'package:budget/struct/logging.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/struct/languageMap.dart';
import 'package:budget/struct/initializeBiometrics.dart';
import 'package:budget/widgets/util/appLinks.dart';
import 'package:budget/widgets/util/onAppResume.dart';
import 'package:budget/widgets/util/watchForDayChange.dart';
import 'package:budget/widgets/watchAllWallets.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart' as db_global;
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/notificationsGlobal.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/globalLoadingProgress.dart';
import 'package:budget/struct/scrollBehaviorOverride.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/restartApp.dart';
import 'package:budget/struct/customDelayedCurve.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:budget/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_preview/device_preview.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'firebase_options.dart';
import 'package:easy_localization/easy_localization.dart';

// Requires hot restart when changed
bool enableDevicePreview = false && kDebugMode;
bool allowDebugFlags = true || kIsWeb;
bool allowDangerousDebugFlags = kDebugMode;

// These variables are initialized in main before the app runs.
// Using 'late' tells Dart that we promise they will not be null when they are first used.
late SharedPreferences sharedPreferences;
late FinanceDatabase database;
// This might need to be nullable depending on its implementation
NotificationPayload? notificationPayload;

void main() async {
  captureLogs(() async {
    // This is now the standard way to ensure bindings are initialized.
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize packages before the app runs
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await EasyLocalization.ensureInitialized();

    // Initialize local app components
    sharedPreferences = await SharedPreferences.getInstance();
    database = db_global.constructDb();
    final notifPayloadString = await initializeNotifications();
    if (notifPayloadString != null) {
      notificationPayload =
          NotificationPayload(id: 0, payload: notifPayloadString);
    } else {
      notificationPayload = null;
    }
    entireAppLoaded = false;
    await loadCurrencyJSON();
    await loadLanguageNamesJSON();
    await initializeSettings();

    // Timezone initialization
    tz.initializeTimeZones();
    try {
      final String locationName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(locationName));
    } catch (e) {
      // Fallback if timezone cannot be determined
      tz.setLocalLocation(tz.getLocation("America/New_York"));
      print("Could not get local timezone: $e");
    }

    // Sorting icon objects
    iconObjects.sort((a, b) => (a.mostLikelyCategoryName ?? a.icon)
        .compareTo((b.mostLikelyCategoryName ?? b.icon)));

    // This function likely needs updates for modern Android/iOS APIs
    setHighRefreshRate();

    runApp(
      EasyLocalization(
        supportedLocales: const [
          Locale('en'),
          Locale('fr'),
          // Add other supported locales here
        ],
        path: 'assets/translations/generated', // path to your translation files
        fallbackLocale: const Locale('en'),
        child: DevicePreview(
          enabled: enableDevicePreview,
          builder: (context) => RestartApp(
            child: InitializeApp(key: appStateKey),
          ),
        ),
      ),
    );
  });
}

GlobalKey<_InitializeAppState> appStateKey = GlobalKey();
GlobalKey<PageNavigationFrameworkState> pageNavigationFrameworkKey =
    GlobalKey();

class InitializeApp extends StatefulWidget {
  const InitializeApp({Key? key}) : super(key: key);

  @override
  State<InitializeApp> createState() => _InitializeAppState();
}

class _InitializeAppState extends State<InitializeApp> {
  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Using a ValueKey helps Flutter know when to rebuild the widget.
    return const App(key: ValueKey("Main App"));
  }
}

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print("Rebuilt Material App");
    return MaterialApp(
      // Device Preview settings
      // useInheritedMediaQuery is deprecated, builder handles this.
      locale:
          enableDevicePreview ? DevicePreview.locale(context) : context.locale,
      builder: (context, child) {
        // The builder is the recommended way to wrap your app with helpers.
        // It also allows DevicePreview to work correctly.
        final previewedChild = enableDevicePreview
            ? DevicePreview.appBuilder(context, child)
            : child;

        if (kReleaseMode) {
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            // A simple error widget for release mode.
            return const Center(
              child: Text("An unexpected error occurred."),
            );
          };
        }

        Widget mainWidget = OnAppResume(
          updateGlobalAppLifecycleState: true,
          onAppResume: () async {
            await setHighRefreshRate();
          },
          child: InitializeBiometrics(
            child: InitializeNotificationService(
              child: InitializeAppLinks(
                child: WatchForDayChange(
                  child: WatchSelectedWalletPk(
                    child: WatchAllWallets(
                      child: previewedChild ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        return kIsWeb
            ? FadeIn(
                duration: const Duration(milliseconds: 1000), child: mainWidget)
            : mainWidget;
      },
      // Localization settings from EasyLocalization
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,

      // Keyboard shortcuts and actions (ensure these are defined in a null-safe way)
      shortcuts: shortcuts,
      actions: keyboardIntents,

      // Theming
      themeAnimationDuration: const Duration(milliseconds: 400),
      themeAnimationCurve: CustomDelayedCurve(),
      key: const ValueKey('CashewAppMain'),
      title: 'Cashew',
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      scrollBehavior: ScrollBehaviorOverride(),
      // Null-safe way to get the theme. It defaults to system theme if the setting is not found.
      themeMode:
          getSettingConstants(appStateSettings)["theme"] ?? ThemeMode.system,

      // Main app content
      home: HandleWillPopScope(
        child: Stack(
          children: [
            Row(
              children: [
                NavigationSidebar(key: sidebarStateKey),
                Expanded(
                  child: Stack(
                    children: [
                      const InitialPageRouteNavigator(),
                      GlobalSnackbar(key: snackbarKey),
                    ],
                  ),
                ),
              ],
            ),
            const EnableSignInWithGoogleFlyIn(),
            GlobalLoadingIndeterminate(key: loadingIndeterminateKey),
            GlobalLoadingProgress(key: loadingProgressKey),
          ],
        ),
      ),
    );
  }
}

// Placeholder for your custom widget. Ensure its implementation is also updated.
class InitialPageRouteNavigator extends StatelessWidget {
  const InitialPageRouteNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    // This should navigate to your app's home page, e.g., AccountsPage.
    return AccountsPage();
  }
}
