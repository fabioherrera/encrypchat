import 'dart:ui';

/// Public legal pages served by encrypchat.com (see `apps/web`).
///
/// The site publishes ES and EN only; any other device language falls back to
/// ES, which is the language of the app UI.
class LegalLinks {
  const LegalLinks._();

  static const site = 'https://encrypchat.com';
  static const supportedLocales = {'es', 'en'};

  static String localeFor(Locale locale) =>
      supportedLocales.contains(locale.languageCode)
      ? locale.languageCode
      : 'es';

  static String privacy(Locale locale) => '$site/${localeFor(locale)}/privacy';

  static String terms(Locale locale) => '$site/${localeFor(locale)}/terms';

  static String download(Locale locale) =>
      '$site/${localeFor(locale)}/download';

  /// Language of the device as reported by the OS.
  ///
  /// Deliberately not `Localizations.localeOf(context)`: the app ships a single
  /// Spanish UI without localization delegates, so that call would always
  /// answer `en` and send Spanish users to the English pages.
  static Locale get deviceLocale => PlatformDispatcher.instance.locale;
}
