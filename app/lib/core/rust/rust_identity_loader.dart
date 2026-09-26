/// The device identity and the pairing verifier, both over the Rust core.
///
/// The two seams exist because `identity.dart` keeps signing and hashing as
/// injected functions, and the bridge already has exactly the two calls they
/// need. Nothing about the transcripts changes: they stay Dart strings built by
/// the named functions in `identity.dart`, and only the Ed25519 operation crosses
/// into Rust.
library;

import 'dart:convert';

import 'package:mkvi/session/identity.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok ve README'i tüketiciden tam olarak bu yolu istiyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart' as bridge;

import 'rust_core.dart';

/// Loads this device's identity from the core the bridge already opened.
///
/// Throws [RustCoreUnavailable] rather than minting anything: an identity is
/// created exactly once, inside `Core::open`, and an unavailable bridge means the
/// keyring was never read. `identity.dart` says a throw from [DeviceIdentityLoader]
/// is a retryable attempt failure, which is the correct destination for this.
final class RustIdentityLoader implements DeviceIdentityLoader {
  const RustIdentityLoader(this._core);

  final RustCore _core;

  @override
  Future<DeviceIdentity> load() async {
    if (!_core.isAvailable) {
      throw RustCoreUnavailable(
        '${_core.unavailableMessageTr} ${_core.unavailableRecoveryTr}',
      );
    }
    final bridge.Core core = _core.requireCore();
    final String publicKey = await bridge.devicePublicKey(core: core);
    return DeviceIdentity(
      publicKey: publicKey,
      // The transcript is UTF-8 encoded here rather than in Rust, because the
      // transcript itself is a Dart string built by `identity.dart` and the two
      // sides must hash the same bytes.
      sign: (String transcript) =>
          bridge.sign(core: core, message: utf8.encode(transcript)),
    );
  }
}

/// Verifies a peer's transcript signature with the core's `verify_strict`.
///
/// The bridge answers `false` for an unparseable key *and* for a wrong signature,
/// on purpose (`api.rs:188-193`): a peer must not be able to tell those apart.
/// This typedef passes that through unchanged rather than turning `false` into a
/// typed refusal.
final class RustPairingVerifier {
  const RustPairingVerifier(this._core);

  final RustCore _core;

  /// Matches [PairingVerifier].
  Future<bool> call(
    String publicKey,
    String transcript,
    String signature,
  ) {
    if (!_core.isAvailable) {
      throw RustCoreUnavailable(
        '${_core.unavailableMessageTr} ${_core.unavailableRecoveryTr}',
      );
    }
    return bridge.verify(
      publicKey: publicKey,
      message: utf8.encode(transcript),
      signature: signature,
    );
  }
}
