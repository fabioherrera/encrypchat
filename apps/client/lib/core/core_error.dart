/// Mirrors `CoreError::as_code` from `crates/core`.
class CoreException implements Exception {
  CoreException(this.code, [this.message]);

  final int code;
  final String? message;

  static const int invalidToken = 1;
  static const int invalidPublicKey = 2;
  static const int decryptionFailed = 3;
  static const int ciphertextTooShort = 4;
  static const int emptyPlaintext = 5;
  static const int bufferTooSmall = 6;
  static const int nullPointer = 7;
  static const int peerOffline = 8;
  static const int empty = 9;
  static const int invalidFrame = 10;
  static const int authFailed = 11;
  static const int internal = 255;

  String get label => switch (code) {
        invalidToken => 'InvalidToken',
        invalidPublicKey => 'InvalidPublicKey',
        decryptionFailed => 'DecryptionFailed',
        ciphertextTooShort => 'CiphertextTooShort',
        emptyPlaintext => 'EmptyPlaintext',
        bufferTooSmall => 'BufferTooSmall',
        nullPointer => 'NullPointer',
        peerOffline => 'PeerOffline',
        empty => 'Empty',
        invalidFrame => 'InvalidFrame',
        authFailed => 'AuthFailed',
        internal => 'Internal',
        _ => 'Unknown($code)',
      };

  @override
  String toString() =>
      message == null ? 'CoreException($label)' : 'CoreException($label): $message';
}
