import 'dart:convert';

import 'package:budget/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String globalAppName = "Cashew";

Map<String, dynamic> languageNamesJSON = {};
loadLanguageNamesJSON() async {
  languageNamesJSON = await json
      .decode(await rootBundle.loadString('assets/static/language-names.json'));
}

Map<String, Locale> supportedLocales = {
  "en": const Locale("en"),
  "fr": const Locale("fr"),
  "es": const Locale("es"),
  "zh": const Locale.fromSubtags(languageCode: "zh", scriptCode: "Hans"),
  "zh_Hant": const Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"),
  "hi": const Locale("hi"),
  "ar": const Locale("ar"),
  "pt": const Locale("pt"),
  "pt_PT": const Locale.fromSubtags(languageCode: "pt", countryCode: "PT"),
  "ru": const Locale("ru"),
  "ja": const Locale("ja"),
  "de": const Locale("de"),
  "ko": const Locale("ko"),
  "tr": const Locale("tr"),
  "it": const Locale("it"),
  "vi": const Locale("vi"),
  "pl": const Locale("pl"),
  "nl": const Locale("nl"),
  "th": const Locale("th"),
  "cs": const Locale("cs"),
  "bn": const Locale("bn"),
  "da": const Locale("da"),
  "fil": const Locale("fil"),
  "fi": const Locale("fi"),
  "el": const Locale("el"),
  "gu": const Locale("gu"),
  "he": const Locale("he"),
  "hu": const Locale("hu"),
  "id": const Locale("id"),
  "ms": const Locale("ms"),
  "ml": const Locale("ml"),
  "mr": const Locale("mr"),
  "no": const Locale("no"),
  "fa": const Locale("fa"),
  "ro": const Locale("ro"),
  "sv": const Locale("sv"),
  "ta": const Locale("ta"),
  "te": const Locale("te"),
  "uk": const Locale("uk"),
  "ur": const Locale("ur"),
  "sr": const Locale("sr"),
  "sw": const Locale("sw"),
  "bg": const Locale("bg"),
  "sk": const Locale("sk"),
  "mk": const Locale("mk"),
  "af": const Locale("af"),
};

// In Material App to debug:
// localeListResolutionCallback: (systemLocales, supportedLocales) {
//   print("LOCALE:" + context.locale.toString());
//   print("LOCALE:" + Platform.localeName);
//   return null;
// },

// The custom LocaleLoader only references the LangCode
// Fix loading of zh_Hant and other special script languages
// Within easy_localization, supported locale checks the codes properly to see if its supported
// ...LocaleExtension on Locale {
//      bool supports(Locale locale) {...
// For e.g. if system was fr_CA it would check the language code, since we support fr it is marked as supported!
// So it is safe to set useOnlyLangCode to false even when we only support language codes
// Since only the logic for RootBundleAssetLoader relies on useOnlyLangCode, no other functionality of easy_localization does!
class RootBundleAssetLoaderCustomLocaleLoader extends RootBundleAssetLoader {
  const RootBundleAssetLoaderCustomLocaleLoader();

  @override
  String getLocalePath(String basePath, Locale locale) {
    print("Initial Locale: $locale");
    print("App Settings Locale: " + appStateSettings["locale"]);
    if (supportedLocales["zh_Hant"] == locale ||
        appStateSettings["locale"] == "zh_Hant") {
      locale = supportedLocales["zh_Hant"] ?? Locale(locale.languageCode);
    } else if (supportedLocales["pt_PT"] == locale ||
        appStateSettings["locale"] == "pt_PT") {
      locale = supportedLocales["pt_PT"] ?? Locale(locale.languageCode);
    } else {
      // We only support the language code right now
      // This implements EasyLocalization( useOnlyLangCode: true ... )
      locale = Locale(locale.languageCode);
    }

    print("Set Locale: $locale");

    return '$basePath/${locale.toStringWithSeparator(separator: "-")}.json';
  }
}

class InitializeLocalizations extends StatelessWidget {
  const InitializeLocalizations({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      useOnlyLangCode: false,
      assetLoader: const RootBundleAssetLoaderCustomLocaleLoader(),
      supportedLocales: supportedLocales.values.toList(),
      path: 'assets/translations/generated',
      useFallbackTranslations: true,
      fallbackLocale: supportedLocales.values.toList().first,
      child: child,
    );
  }
}

// Language names can be found in
// /budget/assets/static/language-names.json
