// Where this install connects to.
//
// The design decision these tests pin: MKVI embeds no server, so the default
// is EMPTY - not a hosted endpoint, not a placeholder that looks like an
// address. The old build shipped a production URL as a fallback, so a
// half-finished edit silently talked to somebody else's machine, and a user
// who configured nothing was connected to a server they had never chosen.
//
// So: an empty endpoint is the default state AND a refused input, and every
// refusal carries its own Turkish reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/connection_settings.dart';
import 'package:mkvi/settings/settings_messages.dart';

void main() {
  group('the default', () {
    test('is empty, and says so', () {
      expect(ConnectionSettings.initial.signalingEndpoint, isNull);
      expect(ConnectionSettings.initial.hasEndpoint, isFalse);
      expect(ConnectionSettings.initial.endpointText, '');
      expect(ConnectionSettings.initial.iceServersText, '');
    });
  });

  group('a refused endpoint', () {
    void expectRefused(String raw, EndpointProblem problem, String phrase) {
      final EndpointValidation validation = validateEndpoint(raw);
      expect(validation.isAccepted, isFalse, reason: 'for "$raw"');
      expect(validation.problem, problem, reason: 'for "$raw"');
      expect(validation.endpoint, isNull, reason: 'for "$raw"');
      expect(validation.errorTr, isNotNull, reason: 'for "$raw"');
      expect(validation.errorTr, contains(phrase), reason: 'for "$raw"');
      expect(validation.settingsProblem, isNotNull);
      // The stored text is kept so the field can show what was refused.
      expect(validation.received, raw.trim(), reason: 'for "$raw"');
      expect(
        validation.toIssue('yapılandırılmamış').messageTr,
        validation.errorTr,
      );
    }

    test('an empty address', () {
      expectRefused('', EndpointProblem.empty, 'boş olamaz');
      expectRefused('   ', EndpointProblem.empty, 'boş olamaz');
      expectRefused('\n\t', EndpointProblem.empty, 'boş olamaz');
    });

    test('a relative address', () {
      expectRefused('/signal', EndpointProblem.notAbsolute, 'tam bir adres');
      expectRefused(
        'signal.example.workers.dev',
        EndpointProblem.notAbsolute,
        'tam bir adres',
      );
      expectRefused(
        'workers.dev/signal',
        EndpointProblem.notAbsolute,
        'tam bir adres',
      );
    });

    test('an address with no host', () {
      expectRefused('https://', EndpointProblem.missingHost, 'alan adı yok');
      expectRefused(
        'http:///signal',
        EndpointProblem.missingHost,
        'alan adı yok',
      );
    });

    test('an address with the wrong scheme', () {
      expectRefused(
        'ftp://signal.example.dev',
        EndpointProblem.unsupportedScheme,
        'http://',
      );
      expectRefused(
        'ws://signal.example.dev',
        EndpointProblem.unsupportedScheme,
        'http://',
      );
      expectRefused(
        'file:///etc/passwd',
        EndpointProblem.unsupportedScheme,
        'http://',
      );
    });

    test('the Turkish reason is the same vocabulary a report uses', () {
      final EndpointValidation validation = validateEndpoint(
        'signal.example.dev',
      );
      expect(
        validation.errorTr,
        settingsProblemTr(validation.settingsProblem, key: endpointKey),
      );
      expect(
        validation.toIssue('yapılandırılmamış').problem,
        SettingsProblem.endpointNotAbsolute,
      );
    });
  });

  group('an accepted endpoint', () {
    void expectAccepted(String raw) {
      final EndpointValidation validation = validateEndpoint(raw);
      expect(validation.isAccepted, isTrue, reason: 'for "$raw"');
      expect(validation.problem, isNull, reason: 'for "$raw"');
      expect(validation.errorTr, isNull, reason: 'for "$raw"');
      expect(validation.endpoint, isNotNull);
      expect(validation.endpoint!.isAbsolute, isTrue);
    }

    test('an https Worker address', () {
      expectAccepted('https://signal.example.workers.dev');
      expectAccepted('http://localhost:8787');
      expectAccepted('https://signal.example.workers.dev/signal');
      expectAccepted('  https://signal.example.workers.dev  ');
    });

    test('it is stored as its own text, trimmed', () {
      final ConnectionSettings settings = ConnectionSettings(
        signalingEndpoint: validateEndpoint(
          '  https://signal.example.workers.dev/signal  ',
        ).endpoint,
      );
      expect(
        settings.endpointText,
        'https://signal.example.workers.dev/signal',
      );
      expect(settings.hasEndpoint, isTrue);
      expect(settings.iceServersText, '');
    });
  });

  group('a form', () {
    test('that is accepted produces a connection and keeps the ICE text', () {
      final ({ConnectionSettings? settings, EndpointValidation? validation})
      form = ConnectionSettings.fromForm(
        endpointText: ' https://signal.example.workers.dev ',
        iceServersText: '  stun:stun.example.dev:3478  ',
      );
      expect(form.validation!.isAccepted, isTrue);
      expect(form.settings, isNotNull);
      expect(
        form.settings!.signalingEndpoint,
        Uri.parse('https://signal.example.workers.dev'),
      );
      expect(form.settings!.iceServersText, 'stun:stun.example.dev:3478');
    });

    test('that is refused changes nothing at all', () {
      final ({ConnectionSettings? settings, EndpointValidation? validation})
      form = ConnectionSettings.fromForm(
        endpointText: '   ',
        iceServersText: 'stun:stun.example.dev:3478',
      );
      expect(form.validation!.isAccepted, isFalse);
      expect(
        form.settings,
        isNull,
        reason:
            'a refused form must not half-apply: the ICE text the user '
            'typed belongs to the endpoint they typed it with',
      );
      expect(form.validation!.errorTr, contains('boş olamaz'));
    });

    test('reports its refusal in Turkish, ready for a text field', () {
      final EndpointValidation validation = validateEndpoint(
        'signal.example.dev',
      );
      expect(
        validation.errorTr,
        'Sunucu adresi tam bir adres olmalı; '
        'örnek: https://signal.example.workers.dev',
      );
    });
  });

  test('two equal connections are equal, and copyWith keeps the rest', () {
    final ConnectionSettings a = ConnectionSettings(
      signalingEndpoint: Uri.parse('https://signal.example.workers.dev'),
      iceServersText: 'stun:stun.example.dev:3478',
    );
    final ConnectionSettings b = ConnectionSettings(
      signalingEndpoint: Uri.parse('https://signal.example.workers.dev'),
      iceServersText: 'stun:stun.example.dev:3478',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a.copyWith(iceServersText: 'x').signalingEndpoint,
      a.signalingEndpoint,
    );
    expect(a.copyWith(iceServersText: 'x'), isNot(a));
  });
}
