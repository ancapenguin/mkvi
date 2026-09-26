/// Where this install talks to, and the refusal that keeps it honest.
///
/// MKVI embeds no server. Every user runs their own Cloudflare Worker, so the
/// default here is EMPTY - not a hosted endpoint, not a placeholder that looks
/// like an address. The old build shipped
/// `https://mkvi-signal.12orgcom09.workers.dev` as a fallback, which meant a
/// half-finished edit silently talked to somebody else's machine, and a user
/// who never configured anything was connected to a server they had not
/// chosen.
///
/// An empty endpoint is therefore both the default AND a refused input, which
/// sounds contradictory until you see the two callers: the store reader
/// accepts "nothing is configured yet" as a state, and the settings form
/// refuses to accept "nothing" as a value the user typed.
library;

import 'settings_issue.dart';
import 'settings_messages.dart';

/// How the signaling endpoint is validated, and the Turkish reason when it is
/// not acceptable.
enum EndpointProblem {
  /// Blank, or blank after trimming.
  empty,

  /// No scheme, so not an absolute URL.
  notAbsolute,

  /// A scheme, but no host.
  missingHost,

  /// A scheme other than http or https.
  unsupportedScheme,
}

/// The outcome of validating one endpoint string.
///
/// Exactly one of [endpoint] and [problem] is set. A rejected value is never
/// coerced into a different URL: the caller decides what to do, and the reason
/// is already in Turkish.
final class EndpointValidation {
  const EndpointValidation.accepted(this.endpoint)
    : problem = null,
      received = '';

  const EndpointValidation.rejected(this.problem, this.received)
    : endpoint = null;

  /// The parsed address, when it was accepted.
  final Uri? endpoint;

  /// Why it was refused, when it was.
  final EndpointProblem? problem;

  /// What the caller passed, kept for the message.
  final String received;

  /// Whether the value was accepted.
  bool get isAccepted => problem == null;

  /// The Turkish sentence to show under the field, or null when accepted.
  String? get errorTr => problem == null
      ? null
      : settingsProblemTr(_problemOf(problem!), key: endpointKey);

  /// The reason as a [SettingsIssue] problem, so a report and a field error
  /// are the same vocabulary.
  SettingsProblem get settingsProblem => _problemOf(problem!);

  /// The full report form, for a decode that had to correct a stored value.
  SettingsIssue toIssue(String? applied) => SettingsIssue(
    problem: settingsProblem,
    key: endpointKey,
    received: received,
    applied: applied,
  );

  static SettingsProblem _problemOf(EndpointProblem value) => switch (value) {
    EndpointProblem.empty => SettingsProblem.endpointEmpty,
    EndpointProblem.notAbsolute => SettingsProblem.endpointNotAbsolute,
    EndpointProblem.missingHost => SettingsProblem.endpointMissingHost,
    EndpointProblem.unsupportedScheme =>
      SettingsProblem.endpointUnsupportedScheme,
  };

  @override
  String toString() => endpoint == null
      ? 'EndpointValidation.rejected(${problem!.name})'
      : 'EndpointValidation($endpoint)';
}

/// The key the endpoint is stored under.
const String endpointKey = 'endpoint';

/// Validates a signaling endpoint.
///
/// Accepted: an absolute `http` or `https` URL with a host. Refused, each with
/// its own Turkish reason: blank, scheme-less, host-less, or another scheme.
///
/// The stored form is the URI's own text, so a value that came from the
/// settings screen and a value that came from an older build normalise to the
/// same string.
EndpointValidation validateEndpoint(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return const EndpointValidation.rejected(EndpointProblem.empty, '');
  }
  final Uri? parsed = Uri.tryParse(text);
  if (parsed == null || !parsed.hasScheme) {
    return EndpointValidation.rejected(EndpointProblem.notAbsolute, text);
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    return EndpointValidation.rejected(EndpointProblem.unsupportedScheme, text);
  }
  if (parsed.host.isEmpty) {
    return EndpointValidation.rejected(EndpointProblem.missingHost, text);
  }
  return EndpointValidation.accepted(parsed);
}

/// The connection half of the settings: the signaling endpoint, and the ICE
/// server text the user pasted.
///
/// Immutable, and EMPTY by default. [signalingEndpoint] is null when nothing
/// is configured yet, which is the state a fresh install is in and the state
/// the setup screen has to handle.
final class ConnectionSettings {
  const ConnectionSettings({this.signalingEndpoint, this.iceServersText = ''});

  /// Nothing configured. MKVI ships no server of its own.
  static const ConnectionSettings initial = ConnectionSettings();

  /// The signaling endpoint, or null when nothing is configured.
  final Uri? signalingEndpoint;

  /// The ICE server list as the user typed it, one per line. Free text here:
  /// it is a paste target, and parsing it strictly would reject the formats
  /// `flutter_webrtc` accepts.
  final String iceServersText;

  /// Whether an endpoint has been configured at all.
  ///
  /// The question the setup screen asks, and the reason
  /// [signalingEndpoint] is nullable: "not configured yet" and "configured to
  /// an address" are different states and must not share a representation.
  bool get hasEndpoint => signalingEndpoint != null;

  /// The stored text of [signalingEndpoint], or '' when there is none.
  String get endpointText => signalingEndpoint?.toString() ?? '';

  /// Builds a connection from form text, keeping the ICE text only when the
  /// endpoint was accepted: a rejected form changes nothing.
  static ({ConnectionSettings? settings, EndpointValidation? validation})
  fromForm({required String endpointText, String iceServersText = ''}) {
    final EndpointValidation validation = validateEndpoint(endpointText);
    if (!validation.isAccepted) {
      return (settings: null, validation: validation);
    }
    return (
      settings: ConnectionSettings(
        signalingEndpoint: validation.endpoint,
        iceServersText: iceServersText.trim(),
      ),
      validation: validation,
    );
  }

  ConnectionSettings copyWith({
    Uri? signalingEndpoint,
    String? iceServersText,
  }) {
    return ConnectionSettings(
      signalingEndpoint: signalingEndpoint ?? this.signalingEndpoint,
      iceServersText: iceServersText ?? this.iceServersText,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionSettings &&
      other.signalingEndpoint == signalingEndpoint &&
      other.iceServersText == iceServersText;

  @override
  int get hashCode => Object.hash(signalingEndpoint, iceServersText);

  @override
  String toString() =>
      'ConnectionSettings(${signalingEndpoint ?? 'yapılandırılmamış'})';
}
