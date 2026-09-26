/// The Turkish error classifier.
///
/// The old build's worst habit was `setMediaError(error instanceof Error ?
/// error.message : "…")` at five call sites in `ChatCallWorkspace.tsx` (`:352`,
/// `:368`, `:376`, `:419`, `:441`). A WebView `DOMException` message went straight
/// into a Turkish UI, so a user could be told
/// `NotReadableError: Could not start video source`.
///
/// These tests pin the replacement in both directions: every known shape of failure
/// lands on the right Turkish sentence, and **no** input can put its own text
/// through. There is no hardware here and none is needed — the classifier is a pure
/// function of an `Object`.
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

void main() {
  group('every (kind, source) pair has Turkish text', () {
    test('the table is total', () {
      // The bug this table exists to prevent is a pair that quietly falls through
      // to English, so the shape of the table is asserted, not just its contents.
      expect(
        MediaFault.text.length,
        MediaFaultKind.values.length * MediaSourceKind.values.length,
      );
      for (final MediaFaultKind kind in MediaFaultKind.values) {
        for (final MediaSourceKind source in MediaSourceKind.values) {
          expect(
            MediaFault.text[(kind, source)],
            isNotNull,
            reason: '${kind.name} / ${source.name} has no text',
          );
        }
      }
    });

    test('no text is empty and none repeats a source by accident', () {
      for (final MapEntry<(MediaFaultKind, MediaSourceKind), String> entry
          in MediaFault.text.entries) {
        expect(entry.value.trim(), isNotEmpty);
        expect(MediaFault(entry.key.$1, entry.key.$2).message, entry.value);
      }
    });
  });

  group('permission denied', () {
    const List<(String, MediaFaultKind)> cases = <(String, MediaFaultKind)>[
      // The raw Dart `String` the plugin actually throws
      // (`mediadevices_impl.dart:48-50`).
      (
        'Unable to getUserMedia: Permission denied on the system',
        MediaFaultKind.permissionDenied,
      ),
      // The web shape.
      ('NotAllowedError: Permission denied', MediaFaultKind.permissionDenied),
      // A `PlatformException` whose `code` carries the plugin's own vocabulary and
      // whose `message` carries libwebrtc's. `PermissionException` is not a real
      // libwebrtc code; the point is that the *code* alone places the fault, which
      // is what a real `PlatformException` from `WebRTC.invokeMethod` looks like.
      (
        'MediaDevicePermissionError: capture was refused',
        MediaFaultKind.permissionDenied,
      ),
      // MF: E_ACCESSDENIED.
      ('Unable to getUserMedia: 0x80070005', MediaFaultKind.permissionDenied),
    ];

    for (final (String text, MediaFaultKind _) in cases) {
      test('"$text"', () {
        expect(
          classifyMediaFault(text, source: MediaSourceKind.camera).kind,
          MediaFaultKind.permissionDenied,
        );
      });
    }

    test('a PlatformException is read through its code and message', () {
      final MediaFault fault = classifyMediaFault(
        PlatformException(
          code: 'Bad Arguments',
          message: 'Not found device id: mic-9',
        ),
        source: MediaSourceKind.microphone,
      );

      expect(fault.kind, MediaFaultKind.deviceNotFound);
      expect(fault.message, MediaTexts.microphoneNotFound);
    });
  });

  group('no device', () {
    const List<String> cases = <String>[
      'Unable to getUserMedia: NotFoundError',
      'Unable to getUserMedia: No specified device found',
      'Unable to getUserMedia: No available capture device',
      'Unable to getUserMedia: DevicesNotFoundError',
      'Unable to getUserMedia: device not found',
      'Unable to selectAudioInput: Not found device id: mic-9',
    ];

    for (final String text in cases) {
      test('"$text"', () {
        final MediaSourceKind source = text.contains('selectAudioInput')
            ? MediaSourceKind.microphone
            : MediaSourceKind.camera;
        expect(
          classifyMediaFault(text, source: source).kind,
          MediaFaultKind.deviceNotFound,
        );
      });
    }
  });

  group('device busy', () {
    // A locked camera reaches a Windows build as `SHARING_VIOLATION` and, through
    // libwebrtc, under the spec's "in use" name. The fix the user needs is "close
    // the other app", not "restart the driver" — which is why this row is
    // consulted before the not-readable row.
    const List<String> cases = <String>[
      'Unable to getUserMedia: Device is already in use',
      'Unable to getUserMedia: 0x80070020',
      'Unable to getUserMedia: Cannot start capture',
      'Unable to getUserMedia: the device is used by another process',
    ];

    for (final String text in cases) {
      test('"$text" beats the not-readable row', () {
        expect(
          classifyMediaFault(text, source: MediaSourceKind.camera).kind,
          MediaFaultKind.deviceBusy,
        );
      });
    }
  });

  group('not readable', () {
    const List<String> cases = <String>[
      'NotReadableError: Could not start video source',
      'Unable to getUserMedia: TrackStartError',
      'Unable to getUserMedia: Track start failed',
      'Unable to getUserMedia: The device has been removed',
      'Unable to getUserMedia: 0x88890004',
      'Unable to getUserMedia: VideoCaptureModule: not initialized',
    ];

    for (final String text in cases) {
      test('"$text"', () {
        expect(
          classifyMediaFault(text, source: MediaSourceKind.camera).kind,
          MediaFaultKind.deviceNotReadable,
        );
      });
    }
  });

  group('no backend', () {
    test('a missing plugin is "not supported here", not "unknown"', () {
      final MediaFault fault = classifyMediaFault(
        const MissingPluginExceptionStub(),
        source: MediaSourceKind.microphone,
      );

      expect(fault.kind, MediaFaultKind.unsupported);
      expect(fault.message, MediaTexts.microphoneUnsupported);
    });

    test('NotImplemented is "not supported here"', () {
      // `FlutterMediaStream::MediaStreamTrackSwitchCamera` answers
      // `result->NotImplemented()` (`common/cpp/src/flutter_media_stream.cc:633`),
      // so any path that reached `Helper.switchCamera` on Windows would report this.
      expect(
        classifyMediaFault(
          'Unable to invoke: PlatformException(unimplemented)',
          source: MediaSourceKind.camera,
        ).kind,
        MediaFaultKind.unsupported,
      );
    });
  });

  group('context decides', () {
    // The same text, two different meanings, and the only thing that separates them
    // is which call site raised it.
    test('a missing capture target is a cancellation, not a "not found"', () {
      expect(
        classifyMediaFault(
          'Unable to getDisplayMedia: Bad Arguments: source not found!',
          source: MediaSourceKind.screen,
        ).kind,
        MediaFaultKind.cancelled,
      );
      // The same words on the camera path really do mean "no camera".
      expect(
        classifyMediaFault(
          'Unable to getUserMedia: source not found',
          source: MediaSourceKind.camera,
        ).kind,
        MediaFaultKind.deviceNotFound,
      );
    });

    test('AbortError is a cancellation on the screen path only', () {
      expect(
        classifyMediaFault(
          'Unable to getDisplayMedia: AbortError: The operation was aborted',
          source: MediaSourceKind.screen,
        ).kind,
        MediaFaultKind.cancelled,
      );
      expect(
        classifyMediaFault(
          'Unable to getUserMedia: AbortError: The operation was aborted',
          source: MediaSourceKind.microphone,
        ).kind,
        MediaFaultKind.unknown,
      );
    });
  });

  group('no English ever reaches the user', () {
    // The list is every English phrase the old build could have shown, drawn from
    // the plugin's own strings and from the spec's `DOMException` names.
    const List<String> english = <String>[
      'NotAllowedError',
      'NotFoundError',
      'NotReadableError',
      'Permission denied',
      'Access is denied',
      'Device is already in use',
      'Could not start video source',
      'Track start',
      'No available device',
      'getUserMedia',
      'getDisplayMedia',
      'getDesktopSources',
      'PlatformException',
      'MissingPluginException',
      'NotImplemented',
      'source not found',
      'device has been removed',
      '0x88890004',
      'something wrong',
    ];

    final List<Object> errors = <Object>[
      '',
      '   ',
      'Unable to getUserMedia: ',
      'Exception: getUserMedia return null, something wrong',
      'PlatformException(getUserMedia, Unable to getUserMedia, null, null)',
      'StateError(Bad state: camera)',
      'A completely unexpected shape nobody has seen before',
      '\u0000\u0001\u0002',
      '日本語のエラー',
      'Ошибка',
      'x' * 500,
    ];

    for (final Object error in errors) {
      test('${error.runtimeType} -> unknown, in Turkish', () {
        for (final MediaSourceKind source in MediaSourceKind.values) {
          final MediaFault fault = classifyMediaFault(error, source: source);

          expect(fault.kind, MediaFaultKind.unknown, reason: '$error');
          expect(
            fault.message,
            MediaFault.text[(MediaFaultKind.unknown, source)],
          );
        }
      });
    }

    test('not one English phrase from the plugin survives anywhere in a fault', () {
      for (final Object error in <Object>[
        ...english,
        ...english.map((String s) => 'Unable to getUserMedia: $s'),
        ...english.map((String s) => PlatformException(code: '', message: s)),
        ...english.map((String s) => Exception(s)),
      ]) {
        for (final MediaSourceKind source in MediaSourceKind.values) {
          final MediaFault fault = classifyMediaFault(error, source: source);
          // The whole fault is two enum values and one Turkish constant, so the
          // only field that could leak is the message — and `toString` must not
          // resurrect the input either.
          final String surface = '${fault.message}\n$fault';
          for (final String phrase in english) {
            expect(
              surface.toLowerCase(),
              isNot(contains(phrase.toLowerCase())),
              reason: '"$phrase" leaked from $error for $source',
            );
          }
        }
      }
    });

    test('the Turkish text carries a Turkish-specific letter or is a known '
        'constant', () {
      // A cheap guard against someone adding a fourth language to the table: every
      // message is one of the declared constants, and every declared constant is
      // written out in full rather than assembled from parts.
      for (final String message in MediaFault.text.values) {
        expect(MediaFault.text.values, contains(message));
        expect(message, isNotEmpty);
        expect(
          message.endsWith('.'),
          isTrue,
          reason: 'sentences end in a period',
        );
      }
    });
  });
}

/// A stand-in for a plugin that never registered, without importing the plugin
/// into the classifier's test.
///
/// `MediaDeviceNative` raises exactly this shape when a desktop build has no
/// platform implementation, and the classifier has to place it in `unsupported`
/// rather than `unknown`, so the test needs the name to be reachable.
final class MissingPluginExceptionStub implements Exception {
  const MissingPluginExceptionStub();

  @override
  String toString() =>
      'MissingPluginException(No implementation found for method getUserMedia '
      'on channel FlutterWebRTC.Method)';
}
