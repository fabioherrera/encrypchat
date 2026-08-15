/// Public Encrypchat blind relay. Ciphertext + dest token + TTL only.
///
/// This is how two devices that are not on the same LAN exchange sealed
/// messages and contact intros. It is not a chat host: it cannot read bodies.
const encrypchatDefaultRelayUrl = 'https://relay.encrypchat.com';

/// Written when the person turns the relay off. Distinct from "never set",
/// which means use [encrypchatDefaultRelayUrl].
const encrypchatRelayOff = 'off';

/// Resolves the URL the client should talk to.
///
/// [stored] is whatever sits in the secure store: a custom URL, [encrypchatRelayOff],
/// or null/empty (first run, or after a wipe).
String? resolveRelayUrl({
  required String? stored,
  required String? defaultUrl,
}) {
  final value = stored?.trim();
  if (value == encrypchatRelayOff) return null;
  if (value != null && value.isNotEmpty) return value;
  return defaultUrl;
}

/// Body of the ☁ dialog. Three states, no "the relay is P2P".
String relayCloudDialogBody({
  required bool configured,
  required bool usesDefault,
}) {
  if (!configured) {
    return 'El relay está apagado. Solo hay ruta P2P: misma Wi‑Fi o un puerto '
        'abierto. No hay entrega entre redes distintas. Para hablar por '
        'internet, usa el de Encrypchat o pega el tuyo (los dos tienen que '
        'usar la misma URL).';
  }
  if (usesDefault) {
    return 'Buzón de Encrypchat. No leemos el chat. Vemos el token de destino, '
        'el tamaño, la hora y tu IP. El P2P se intenta primero; el sobre solo '
        'viaja si no hay ruta directa.';
  }
  return 'Usas tu relay. Encrypchat no recibe esos sobres. El P2P se intenta '
      'primero. La otra persona tiene que poner la misma URL. Quien opera el '
      'buzón ve token, tamaño, hora e IP; no el contenido.';
}
