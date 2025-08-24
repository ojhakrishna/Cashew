import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_theme/system_theme.dart';

// Safely gets a color from the custom theme extension.
Color getColor(BuildContext context, String colorName) {
  // Access the custom AppColors theme extension and find the color by its name.
  // If the color isn't found, it returns Colors.red as a fallback to make errors visible.
  return Theme.of(context).extension<AppColors>()?.colors[colorName] ??
      Colors.red;
}

// Generates the map of custom colors based on brightness and accent color.
AppColors getAppColors({
  required Brightness brightness,
  required ThemeData themeData,
  required Color accentColor,
}) {
  // Determine the background color for containers based on Material You settings.
  // Uses null-safe access to appStateSettings with default values.
  Color lightDarkAccentHeavyLight = brightness == Brightness.light
      ? (appStateSettings["accentSystemColor"] == true &&
              (appStateSettings["materialYou"] ?? false) &&
              (appStateSettings["batterySaver"] ?? false) == false)
          ? lightenPastel(themeData.colorScheme.primary, amount: 0.96)
          : (appStateSettings["materialYou"] ?? false)
              ? ((appStateSettings["batterySaver"] ?? false)
                  ? lightenPastel(accentColor, amount: 0.8)
                  : lightenPastel(accentColor, amount: 0.92))
              : ((appStateSettings["batterySaver"] ?? false)
                  ? Color(0xFFF3F3F3)
                  : Color(0xFFFFFFFF))
      : (appStateSettings["accentSystemColor"] == true &&
              (appStateSettings["materialYou"] ?? false) &&
              (appStateSettings["batterySaver"] ?? false) == false)
          ? darkenPastel(themeData.colorScheme.primary, amount: 0.85)
          : (appStateSettings["materialYou"] ?? false)
              ? darkenPastel(accentColor, amount: 0.8)
              : Color(0xFF242424);

  // Return the appropriate color set for either light or dark mode.
  return brightness == Brightness.light
      ? AppColors(
          colors: {
            "white": Colors.white,
            "black": Colors.black,
            "textLight": (appStateSettings["increaseTextContrast"] ?? false)
                ? Colors.black.withOpacity(0.7)
                : (appStateSettings["materialYou"] ?? false)
                    ? Colors.black.withOpacity(0.4)
                    : Color(0xFF888888),
            "lightDarkAccent": (appStateSettings["materialYou"] ?? false)
                ? lightenPastel(accentColor, amount: 0.6)
                : Color(0xFFF7F7F7),
            "lightDarkAccentHeavyLight": lightDarkAccentHeavyLight,
            "canvasContainer": const Color(0xFFEBEBEB),
            "lightDarkAccentHeavy": Color(0xFFEBEBEB),
            "shadowColor": const Color(0x655A5A5A),
            "shadowColorLight": const Color(0x2D5A5A5A),
            "unPaidUpcoming": Color(0xFF58A4C2),
            "unPaidOverdue": Color(0xFF6577E0),
            "incomeAmount": Color(0xFF59A849),
            "expenseAmount": Color(0xFFCA5A5A),
            "warningOrange": Color(0xFFCA995A),
            "starYellow": Color(0xFFFFD723),
            "dividerColor": (appStateSettings["materialYou"] ?? false)
                ? Color(0x0F000000)
                : Color(0xFFF0F0F0),
            "standardContainerColor": getPlatform() == PlatformOS.isIOS
                ? themeData.colorScheme.surface
                : (appStateSettings["materialYou"] ?? false)
                    ? lightenPastel(
                        themeData.colorScheme.secondaryContainer,
                        amount: 0.3,
                      )
                    : lightDarkAccentHeavyLight,
          },
        )
      : AppColors(
          colors: {
            "white": Colors.black,
            "black": Colors.white,
            "textLight": (appStateSettings["increaseTextContrast"] ?? false)
                ? Colors.white.withOpacity(0.65)
                : (appStateSettings["materialYou"] ?? false)
                    ? Colors.white.withOpacity(0.25)
                    : Color(0xFF494949),
            "lightDarkAccent": (appStateSettings["materialYou"] ?? false)
                ? darkenPastel(accentColor, amount: 0.83)
                : Color(0xFF161616),
            "lightDarkAccentHeavyLight": lightDarkAccentHeavyLight,
            "canvasContainer": const Color(0xFF242424),
            "lightDarkAccentHeavy": const Color(0xFF444444),
            "shadowColor": const Color(0x69BDBDBD),
            "shadowColorLight": (appStateSettings["materialYou"] ?? false)
                ? Colors.transparent
                : Color(0x28747474),
            "unPaidUpcoming": Color(0xFF7DB6CC),
            "unPaidOverdue": Color(0xFF8395FF),
            "incomeAmount": Color(0xFF62CA77),
            "expenseAmount": Color(0xFFDA7272),
            "warningOrange": Color(0xFFDA9C72),
            "starYellow": Colors.yellow,
            "dividerColor": (appStateSettings["materialYou"] ?? false)
                ? Color(0x13FFFFFF)
                : Color(0x6F363636),
            "standardContainerColor": getPlatform() == PlatformOS.isIOS
                ? themeData.colorScheme.surface
                : (appStateSettings["materialYou"] ?? false)
                    ? darkenPastel(
                        themeData.colorScheme.secondaryContainer,
                        amount: 0.6,
                      )
                    : lightDarkAccentHeavyLight,
          },
        );
}

// Extension to add custom selectable colors to the ColorScheme
extension ColorsDefined on ColorScheme {
  Color get selectableColorRed => Colors.red.shade400;
  Color get selectableColorGreen => Colors.green.shade400;
  Color get selectableColorBlue => Colors.blue.shade400;
  Color get selectableColorPurple => Colors.purple.shade400;
  Color get selectableColorOrange => Colors.orange.shade400;
  Color get selectableColorBlueGrey => Colors.blueGrey.shade400;
  Color get selectableColorYellow => Colors.yellow.shade400;
  Color get selectableColorAqua => Colors.teal.shade400;
  Color get selectableColorInidigo => Colors.indigo.shade500;
  Color get selectableColorGrey => Colors.grey.shade400;
  Color get selectableColorBrown => Colors.brown.shade400;
  Color get selectableColorDeepPurple => Colors.deepPurple.shade400;
  Color get selectableColorDeepOrange => Colors.deepOrange.shade400;
  Color get selectableColorCyan => Colors.cyan.shade400;
}

// Custom ThemeExtension to provide app-specific colors.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.colors});

  final Map<String, Color?> colors;

  @override
  AppColors copyWith({Map<String, Color?>? colors}) {
    return AppColors(colors: colors ?? this.colors);
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }

    final Map<String, Color?> lerpColors = {};
    colors.forEach((key, value) {
      lerpColors[key] = Color.lerp(colors[key], other.colors[key], t);
    });

    return AppColors(colors: lerpColors);
  }
}

Color darken(Color color, [double amount = .1]) {
  assert(amount >= 0 && amount <= 1);
  final hsl = HSLColor.fromColor(color);
  final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return hslDark.toColor();
}

Color lighten(Color color, [double amount = .1]) {
  assert(amount >= 0 && amount <= 1);
  final hsl = HSLColor.fromColor(color);
  final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
  return hslLight.toColor();
}

Color lightenPastel(Color color, {double amount = 0.1}) {
  return Color.alphaBlend(Colors.white.withOpacity(amount), color);
}

Color darkenPastel(Color color, {double amount = 0.1}) {
  return Color.alphaBlend(Colors.black.withOpacity(amount), color);
}

Color blend(Color colorToBlend, Color baseColor, {double amount = 0.1}) {
  return Color.alphaBlend(baseColor.withOpacity(amount), colorToBlend);
}

Color dynamicPastel(
  BuildContext context,
  Color color, {
  double amount = 0.1,
  bool inverse = false,
  double? amountLight,
  double? amountDark,
}) {
  amountLight ??= amount;
  amountDark ??= amount;
  if (amountLight > 1) amountLight = 1;
  if (amountDark > 1) amountDark = 1;
  if (amount > 1) amount = 1;

  final isLight = Theme.of(context).brightness == Brightness.light;

  if (inverse) {
    return isLight
        ? darkenPastel(color, amount: amountDark)
        : lightenPastel(color, amount: amountLight);
  } else {
    return isLight
        ? lightenPastel(color, amount: amountLight)
        : darkenPastel(color, amount: amountDark);
  }
}

// A helper class to create a Color from a hex string.
class HexColor extends Color {
  static int _getColorFromHex(String? hexColor, Color? defaultColor) {
    hexColor = hexColor?.replaceAll("#", "").replaceAll("0x", "");
    if (hexColor == null || hexColor.isEmpty) {
      return defaultColor?.value ?? Colors.grey.value;
    }
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.tryParse(hexColor, radix: 16) ??
        defaultColor?.value ??
        Colors.grey.value;
  }

  HexColor(final String? hexColor, {final Color? defaultColor})
      : super(_getColorFromHex(hexColor, defaultColor));
}

String? toHexString(Color? color) {
  if (color == null) {
    return null;
  }
  // Returns a hex string like "FF00FF00"
  return color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
}

List<Color> selectableColors(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return [
    colors.selectableColorGreen,
    colors.selectableColorAqua,
    colors.selectableColorCyan,
    colors.selectableColorBlue,
    colors.selectableColorInidigo,
    colors.selectableColorDeepPurple,
    colors.selectableColorPurple,
    colors.selectableColorRed,
    colors.selectableColorOrange,
    colors.selectableColorYellow,
    colors.selectableColorDeepOrange,
    colors.selectableColorBrown,
    colors.selectableColorGrey,
    colors.selectableColorBlueGrey,
  ];
}

List<Color> selectableAccentColors(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return [
    colors.selectableColorGreen,
    colors.selectableColorCyan,
    colors.selectableColorBlue,
    colors.selectableColorInidigo,
    colors.selectableColorDeepPurple,
    colors.selectableColorPurple,
    colors.selectableColorRed,
    colors.selectableColorOrange,
    colors.selectableColorYellow,
  ];
}

const ColorFilter greyScale = ColorFilter.matrix(<double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

Future<String?> getAccentColorSystemString() async {
  if (supportsSystemColor() &&
      (appStateSettings["accentSystemColor"] ?? false)) {
    SystemTheme.fallbackColor = Colors.blue;
    await SystemTheme.accentColor.load();
    Color accentColor = SystemTheme.accentColor.accent;
    if (accentColor.toString() == "Color(0xff80cbc4)") {
      // A default cyan color returned from an unsupported accent color Samsung device
      return null;
    }
    print("System color loaded");
    return toHexString(accentColor);
  } else {
    return null;
  }
}

Future<bool> systemColorByDefault() async {
  if (getPlatform() == PlatformOS.isAndroid) {
    if (supportsSystemColor()) {
      int? androidVersion = await getAndroidVersion();
      print("Android version: " + androidVersion.toString());
      if (androidVersion != null && androidVersion >= 12) {
        return true;
      }
    }
    return false;
  }
  return supportsSystemColor();
}

bool supportsSystemColor() {
  return defaultTargetPlatform.supportsAccentColor &&
      !kIsWeb &&
      getPlatform() != PlatformOS.isIOS;
}

bool isGrayScale(Color color, {int threshold = 10}) {
  int red = color.red;
  int green = color.green;
  int blue = color.blue;

  return (red - green).abs() <= threshold &&
      (red - blue).abs() <= threshold &&
      (green - blue).abs() <= threshold;
}

ColorScheme getColorScheme(Brightness brightness) {
  final accentColor =
      getSettingConstants(appStateSettings)["accentColor"] as Color;

  if (isGrayScale(accentColor, threshold: 15)) {
    return getGrayScaleColorScheme(brightness);
  }

  if (brightness == Brightness.light) {
    return ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.light,
      background: (appStateSettings["materialYou"] ?? false)
          ? lightenPastel(accentColor, amount: 0.91)
          : Colors.white,
    );
  } else {
    return ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
      background: (appStateSettings["forceFullDarkBackground"] ?? false)
          ? Colors.black
          : (appStateSettings["materialYou"] ?? false)
              ? darkenPastel(accentColor, amount: 0.92)
              : Colors.black,
    );
  }
}

ColorScheme getGrayScaleColorScheme(Brightness brightness) {
  // This function seems correct, leaving as is.
  // Just ensuring null-safe access for appStateSettings.
  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: Colors.blueGrey[700]!,
      onPrimary: Colors.white,
      primaryContainer: Colors.blueGrey[300]!,
      onPrimaryContainer: Colors.black,
      secondary: Colors.blueGrey[800]!,
      onSecondary: Colors.white,
      secondaryContainer: Colors.blueGrey[100]!,
      onSecondaryContainer: Colors.black,
      tertiary: Colors.blueGrey[500]!,
      onTertiary: Colors.white,
      tertiaryContainer: Colors.teal[100],
      onTertiaryContainer: Colors.blueGrey[900]!,
      error: Colors.red[700]!,
      onError: Colors.white,
      errorContainer: Colors.red[100],
      onErrorContainer: Colors.black,
      surface: Colors.grey[200]!,
      onSurface: Colors.black,
      surfaceContainerHighest: Colors.grey[100]!,
      onSurfaceVariant: Colors.black,
      outline: Colors.grey[500]!,
      outlineVariant: Colors.grey[400],
      shadow: Colors.black,
      scrim: Colors.black.withOpacity(0.5),
      inverseSurface: Colors.grey[800],
      onInverseSurface: Colors.white,
      inversePrimary: Colors.blueGrey[300],
      surfaceTint: Colors.blueGrey[700],
    );
  } else {
    return ColorScheme(
      brightness: Brightness.dark,
      primary: Colors.blueGrey[200]!,
      onPrimary: Colors.black,
      primaryContainer: Colors.grey[700]!,
      onPrimaryContainer: Colors.white,
      secondary: Colors.grey[500]!,
      onSecondary: Colors.black,
      secondaryContainer: Colors.grey[800]!,
      onSecondaryContainer: Colors.white,
      tertiary: Colors.blueGrey[300],
      onTertiary: Colors.black,
      tertiaryContainer: Colors.blueGrey[700],
      onTertiaryContainer: Colors.blueGrey[200]!,
      error: Colors.red[300]!,
      onError: Colors.black,
      errorContainer: Colors.red[900],
      onErrorContainer: Colors.white,
      surface: Colors.grey[900]!,
      onSurface: Colors.white,
      surfaceContainerHighest: Colors.grey[800]!,
      onSurfaceVariant: Colors.white,
      outline: Colors.grey[600]!,
      outlineVariant: Colors.grey[500],
      shadow: Colors.black,
      scrim: Colors.black.withOpacity(0.7),
      inverseSurface: Colors.grey[100],
      onInverseSurface: Colors.black,
      inversePrimary: Colors.blueGrey[800],
      surfaceTint: Colors.blueGrey[200],
    );
  }
}

SystemUiOverlayStyle getSystemUiOverlayStyle(
  AppColors? colors,
  Brightness brightness,
) {
  if (brightness == Brightness.light) {
    return SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.dark,
      statusBarColor: kIsWeb ? Colors.black : Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: getBottomNavbarBackgroundColor(
        colorScheme: getColorScheme(brightness),
        brightness: Brightness.light,
        lightDarkAccent: colors?.colors["lightDarkAccent"] ?? Colors.white,
      ),
    );
  } else {
    return SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: kIsWeb ? Colors.black : Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarColor: getBottomNavbarBackgroundColor(
        colorScheme: getColorScheme(brightness),
        brightness: Brightness.dark,
        lightDarkAccent: colors?.colors["lightDarkAccent"] ?? Colors.black,
      ),
    );
  }
}

Color getBottomNavbarBackgroundColor({
  required ColorScheme colorScheme,
  required Brightness brightness,
  required Color lightDarkAccent,
}) {
  if (getPlatform() == PlatformOS.isIOS) {
    return brightness == Brightness.light
        ? lightenPastel(
            colorScheme.secondaryContainer,
            amount: (appStateSettings["materialYou"] ?? false) ? 0.4 : 0.55,
          )
        : darkenPastel(
            colorScheme.secondaryContainer,
            amount: (appStateSettings["materialYou"] ?? false) ? 0.4 : 0.55,
          );
  } else if (appStateSettings["materialYou"] == true) {
    if (brightness == Brightness.light) {
      return lightenPastel(colorScheme.secondaryContainer, amount: 0.4);
    } else {
      return darkenPastel(colorScheme.secondaryContainer, amount: 0.45);
    }
  } else {
    return lightDarkAccent;
  }
}

// For Android widget hex color code conversion
String colorToHex(Color color) {
  return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
}

class CustomColorTheme extends StatelessWidget {
  const CustomColorTheme({
    required this.child,
    required this.accentColor,
    super.key,
  });
  final Widget child;
  final Color? accentColor;
  @override
  Widget build(BuildContext context) {
    if (accentColor == null) return child;

    final currentBrightness = determineBrightnessTheme(context);

    ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor!,
      brightness: currentBrightness,
      background: currentBrightness == Brightness.dark
          ? ((appStateSettings["forceFullDarkBackground"] ?? false)
              ? Colors.black
              : (appStateSettings["materialYou"] ?? false)
                  ? darkenPastel(accentColor!, amount: 0.92)
                  : Colors.black)
          : ((appStateSettings["materialYou"] ?? false)
              ? lightenPastel(accentColor!, amount: 0.91)
              : Colors.white),
    );
    return Theme(
      data: generateThemeDataWithExtension(
        accentColor: accentColor!,
        brightness: Theme.of(context).brightness,
        themeData: Theme.of(context).copyWith(colorScheme: colorScheme),
      ),
      child: child,
    );
  }
}

ThemeData generateThemeDataWithExtension({
  required ThemeData themeData,
  required Brightness brightness,
  required Color accentColor,
}) {
  AppColors colors = getAppColors(
    accentColor: accentColor,
    brightness: brightness,
    themeData: themeData,
  );

  return themeData.copyWith(
    extensions: <ThemeExtension<dynamic>>[colors],
    appBarTheme: AppBarTheme(
      systemOverlayStyle: getSystemUiOverlayStyle(colors, brightness),
    ),
  );
}

ThemeData getLightTheme() {
  Brightness brightness = Brightness.light;
  final accentColor =
      getSettingConstants(appStateSettings)["accentColor"] as Color;

  ThemeData themeData = ThemeData(
    fontFamily: appStateSettings["font"]?.toString(),
    fontFamilyFallback: const ['Inter'],
    colorScheme: getColorScheme(brightness),
    useMaterial3: true,
    applyElevationOverlayColor: false,
    typography: Typography.material2014(),
    splashColor: getPlatform() == PlatformOS.isIOS
        ? Colors.transparent
        : (appStateSettings["materialYou"] ?? false)
            ? darkenPastel(
                lightenPastel(accentColor, amount: 0.8),
                amount: 0.2,
              ).withOpacity(0.5)
            : null,
  );
  return generateThemeDataWithExtension(
    themeData: themeData,
    brightness: brightness,
    accentColor: accentColor,
  );
}

ThemeData getDarkTheme() {
  Brightness brightness = Brightness.dark;
  final accentColor =
      getSettingConstants(appStateSettings)["accentColor"] as Color;

  ThemeData themeData = ThemeData(
    fontFamily: appStateSettings["font"]?.toString(),
    fontFamilyFallback: const ['Inter'],
    colorScheme: getColorScheme(brightness),
    useMaterial3: true,
    typography: Typography.material2014(),
    splashColor: getPlatform() == PlatformOS.isIOS
        ? Colors.transparent
        : (appStateSettings["materialYou"] ?? false)
            ? darkenPastel(
                lightenPastel(accentColor, amount: 0.86),
                amount: 0.1,
              ).withOpacity(0.2)
            : null,
  );
  return generateThemeDataWithExtension(
    themeData: themeData,
    brightness: brightness,
    accentColor: accentColor,
  );
}
