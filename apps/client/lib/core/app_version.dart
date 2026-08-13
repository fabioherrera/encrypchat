/// Marketing / package version of this binary.
///
/// Keep in lockstep with `version:` in `pubspec.yaml` (the `+build` number is
/// ignored). A test compares the two so a bump cannot ship with a stale
/// string: [UpdateChecker] uses this, not a plugin, so it works in tests
/// without extra native code.
const encrypchatVersion = '1.0.2';
