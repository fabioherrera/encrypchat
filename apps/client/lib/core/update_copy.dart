/// User-facing copy for the in-app update offer.
///
/// The point of this file is that the dialog, the banner and the tests quote
/// the same sentences: the update is the app binary only, nothing is hidden,
/// and chats/keys stay on the device.
abstract final class UpdateCopy {
  static const title = 'Nueva actualización';

  static String headline(String latest, String current) =>
      'Hay Encrypchat $latest (esta copia es $current).';

  static const body =
      'Esto actualiza solo la aplicación: seguridad, estabilidad y mejoras '
      'de funciones. No hay nada oculto.\n\n'
      'Tus chats, fotos y claves privadas no se suben ni se tocan: siguen '
      'en este dispositivo.\n\n'
      'El paquete se descarga del catálogo público y se comprueba su '
      'SHA-256 antes de instalar. El sistema puede pedirte confirmación '
      '(contraseña en Fedora, instalador en Android).';

  static const later = 'Ahora no';
  static const apply = 'Actualizar la app';
  static const openSite = 'Abrir descargas';
  static const downloading = 'Descargando la app…';
  static const verifying = 'Comprobando el archivo…';
  static const installing = 'Instalando…';
  static const done =
      'Listo. Si el sistema no reinició Encrypchat, cerrala y volvé a abrirla.';
  static const hashMismatch =
      'El archivo no coincide con la suma publicada. No se instala. '
      'Nada de tus datos se tocó.';
  static const noPackage =
      'En este sistema no hay instalador automático. Te llevamos a la '
      'página de descargas.';
}
