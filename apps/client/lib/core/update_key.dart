/// Ed25519 public key that signs the update catalog, in base64.
///
/// Pinned in the binary, so taking over the website or the download host is not
/// enough to ship an update. The private key never enters this repository.
const updateSigningPublicKey =
    'HmUOP/iw1AqjRKh6ZFncnBlF5uvDusxyXovqlGqS8D0=';
