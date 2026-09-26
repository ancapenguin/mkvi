/// The notice channel: dedup, a close that sticks, the severity rule and the
/// rate limit, each against the five defects of the TypeScript toast.
///
/// No test here waits. The clock is [FakeNoticeClock] and the timer seam is the
/// controller's constructor parameter, so the production 5.5 s and the production
/// 1.5 s rate limit are both exercised in microseconds.
///
/// | defect | what the TS did | the test |
/// |---|---|---|
/// | 1, immortal toast | `setNotice` from six places, timer re-armed per write | "six writes one second apart still expire on schedule" |
/// | 1, dead close button | `onClose={() => setNotice("")}` refilled by the loop | "a manual close is not undone by the next write of the same text" |
/// | 4, a condition as an event | "reconnecting" went through `notice` | "a status change never produces a toast" |
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/ui/notice/notice.dart';

import 'support/fake_notice_clock.dart';
import 'support/notice_test_screen.dart';

void main() {
  group('DEFECT 1, the same text does not extend its own lifetime', () {
    test('the same text written repeatedly keeps the first deadline', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      expect(harness.controller.showText('Yeniden bağlanılıyor.'), isTrue);
      final DateTime shownAt = harness.clock.now();
      final DateTime deadline = shownAt.add(harness.policy.transientLifetime);

      // The reconnect loop, roughly once a second.
      for (int tick = 1; tick <= 5; tick += 1) {
        harness.clock.advance(const Duration(seconds: 1));
        expect(
          harness.controller.showText('Yeniden bağlanılıyor.'),
          isFalse,
          reason: 'write $tick is the same sentence, so it is not a new notice',
        );
        expect(
          harness.controller.notice!.expiresAt,
          deadline,
          reason: 'write $tick must not move the deadline',
        );
        expect(
          harness.controller.notice!.sequence,
          1,
          reason: 'and must not be a second notice',
        );
      }

      expect(
        harness.clock.requestedDelays,
        <Duration>[harness.policy.transientLifetime],
        reason: 'TS re-armed the 5.5 s timer on every write; this arms it once',
      );
    });

    test('six writes one second apart still expire on schedule', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      // src/App.tsx:289 wrote this from inside the reconnect loop, about once a
      // second, on top of a 5.5 s deadline.
      for (int tick = 0; tick < 6; tick += 1) {
        if (tick > 0) harness.clock.advance(const Duration(seconds: 1));
        harness.controller.showText('Yeniden bağlanılıyor: bağlantı koptu.');
      }
      expect(
        harness.clock.now(),
        DateTime.utc(2026, 9, 26, 12, 0, 5),
        reason: 'six writes, five one-second gaps',
      );

      // Six writes, five seconds, one deadline: 0 s + 5.5 s.
      harness.clock.advance(const Duration(milliseconds: 499));
      expect(
        harness.controller.hasNotice,
        isTrue,
        reason: 'the notice is still 1 ms from its own deadline',
      );

      harness.clock.advance(const Duration(milliseconds: 1));
      expect(
        harness.controller.hasNotice,
        isFalse,
        reason: 'and gone one millisecond later, which is the reported bug',
      );
      expect(
        harness.clock.requested,
        hasLength(1),
        reason: 'six writes, one timer, and it has now fired',
      );
      expect(
        harness.clock.requestedDelays,
        <Duration>[harness.policy.transientLifetime],
        reason: 'and the 5.5 s of src/App.tsx:185 was requested exactly once',
      );
    });

    test('a text that is different is a new notice, with a new deadline', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.clock.advance(const Duration(seconds: 2));
      expect(harness.controller.showText('İkinci.'), isTrue);

      expect(harness.controller.notice!.sequence, 2);
      expect(harness.controller.notice!.text, 'İkinci.');
      expect(
        harness.controller.notice!.expiresAt,
        harness.clock.now().add(harness.policy.transientLifetime),
      );
    });
  });

  group('DEFECT 1, a close that stays closed', () {
    test('a manual close is not undone by the next write of the same text', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Yerel geçmiş açılamadı.');
      harness.controller.dismiss();
      expect(harness.controller.hasNotice, isFalse);

      // The loop, one second later, with the same sentence and nothing new.
      harness.clock.advance(const Duration(seconds: 1));
      expect(
        harness.controller.showText('Yerel geçmiş açılamadı.'),
        isFalse,
        reason: 'TS refilled the field and the button looked dead',
      );
      expect(
        harness.controller.hasNotice,
        isFalse,
        reason: 'so the close button did not close anything',
      );
      expect(
        harness.controller.snapshot.dismissedText,
        'Yerel geçmiş açılamadı.',
      );
    });

    test('a manual close is undone by different text', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.controller.dismiss();
      harness.controller.dismiss();

      expect(
        harness.controller.showText('İkinci.'),
        isTrue,
        reason: 'the text actually changed, so the close is forgotten',
      );
      expect(harness.controller.notice!.text, 'İkinci.');
      expect(harness.controller.snapshot.dismissedText, isNull);

      // And the sentence the user closed is allowed back once something else
      // has been said in between.
      harness.controller.dismiss();
      expect(harness.controller.showText('Üçüncü.'), isTrue);
      harness.controller.dismiss();
      expect(harness.controller.showText('Birinci.'), isTrue);
    });

    test('an empty text closes rather than resurrecting', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      expect(
        harness.controller.showText(''),
        isFalse,
        reason: 'the TS idiom setNotice("") to close, so "" must still close',
      );
      expect(harness.controller.hasNotice, isFalse);
    });

    test('a close with nothing on screen is a no-op, not an error', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.dismiss();
      expect(harness.controller.hasNotice, isFalse);
      expect(harness.controller.snapshot.dismissedText, isNull);
    });
  });

  group('the severity rule', () {
    test('an error survives its timeout', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText(
        'Cihaz kimliği açılamadı.',
        kind: NoticeKind.error,
      );
      expect(harness.controller.notice!.isSticky, isTrue);
      expect(harness.controller.notice!.expiresAt, isNull);
      expect(harness.controller.pendingAutoDismiss, isNull);
      expect(harness.clock.pending, 0, reason: 'an error arms no timer at all');

      // A whole working day, and then some.
      harness.clock.advance(const Duration(hours: 12));
      expect(
        harness.controller.hasNotice,
        isTrue,
        reason: 'only the user may take an error away',
      );
      expect(harness.controller.notice!.text, 'Cihaz kimliği açılamadı.');
    });

    test('an info does not', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Bağlantı ayarları kaydedildi.');
      expect(harness.controller.notice!.isSticky, isFalse);
      expect(
        harness.controller.notice!.expiresAt,
        harness.clock.now().add(harness.policy.transientLifetime),
      );

      harness.clock.advance(
        harness.policy.transientLifetime + const Duration(milliseconds: 1),
      );
      expect(harness.controller.hasNotice, isFalse);
    });

    test('a warning outlives an info and still goes away', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Uyarı.', kind: NoticeKind.warning);
      expect(
        harness.controller.notice!.lifetime,
        harness.policy.warningLifetime,
      );
      expect(
        harness.policy.warningLifetime,
        greaterThan(harness.policy.transientLifetime),
        reason: 'otherwise severity buys nothing over info',
      );

      harness.clock.advance(harness.policy.transientLifetime);
      expect(
        harness.controller.hasNotice,
        isTrue,
        reason: 'still up when an info would be gone',
      );
      harness.clock.advance(
        harness.policy.warningLifetime - harness.policy.transientLifetime,
      );
      expect(harness.controller.hasNotice, isFalse);
    });

    test('the lifetime of a severity is decided in one place', () {
      const NoticePolicy policy = NoticePolicy();
      expect(NoticeKind.info.lifetime(policy), policy.transientLifetime);
      expect(NoticeKind.success.lifetime(policy), policy.transientLifetime);
      expect(NoticeKind.warning.lifetime(policy), policy.warningLifetime);
      expect(NoticeKind.error.lifetime(policy), isNull);
      expect(NoticeKind.error.isSticky(policy), isTrue);
      expect(NoticeKind.info.isSticky(policy), isFalse);
    });
  });

  group('the rate limit between two automatic dismissals', () {
    test('a second automatic dismissal waits out the spacing', () {
      // A denser policy than the shipped one: 100 ms notices, 1 s apart. This is
      // the case the rule exists for — with the shipped 5.5 s lifetime and 1.5 s
      // spacing every notice is already further apart than the spacing, and the
      // rule is a guard for a policy that is configured that way rather than a
      // step on the normal path. See `NoticePolicy.minimumDismissSpacing`.
      final NoticeHarness harness = NoticeHarness(
        policy: const NoticePolicy(
          transientLifetime: Duration(milliseconds: 100),
          warningLifetime: Duration(milliseconds: 200),
          minimumDismissSpacing: Duration(seconds: 1),
        ),
      );
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.clock.advance(const Duration(milliseconds: 100));
      expect(harness.controller.hasNotice, isFalse);
      expect(
        harness.controller.snapshot.lastAutomaticDismissal,
        harness.clock.now(),
      );

      // A second notice 10 ms later would be due 100 ms after that, which is
      // 90 ms after the previous dismissal.
      harness.clock.advance(const Duration(milliseconds: 10));
      harness.controller.showText('İkinci.');
      harness.clock.advance(const Duration(milliseconds: 100));

      expect(
        harness.controller.hasNotice,
        isTrue,
        reason: 'its own lifetime is over, but the spacing is not',
      );
      expect(
        harness.controller.snapshot.lastAutomaticDismissal,
        isNot(harness.clock.now()),
        reason: 'so the first dismissal is still the most recent one',
      );

      // 1 s of spacing from the first dismissal at 0.100 s, so 0.100 s + 1 s.
      harness.clock.advance(
        harness.policy.minimumDismissSpacing -
            const Duration(milliseconds: 110),
      );
      expect(
        harness.controller.hasNotice,
        isFalse,
        reason: 'gone exactly one spacing after the previous dismissal',
      );
      expect(
        harness.controller.snapshot.lastAutomaticDismissal,
        harness.clock.now(),
      );
    });

    test('with the shipped policy every notice dies on its own deadline', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.clock.advance(harness.policy.transientLifetime);
      harness.clock.advance(const Duration(milliseconds: 1));
      harness.controller.showText('İkinci.');
      harness.clock.advance(harness.policy.transientLifetime);

      expect(
        harness.controller.hasNotice,
        isFalse,
        reason:
            '5.5 s is already more than the 1.5 s spacing, so nothing is '
            'deferred and the rate limit costs no visible time',
      );
    });

    test('a manual dismissal is never deferred by the rate limit', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.clock.advance(harness.policy.transientLifetime);
      expect(harness.controller.hasNotice, isFalse);

      harness.clock.advance(const Duration(milliseconds: 10));
      harness.controller.showText('İkinci.');
      harness.controller.dismiss();
      expect(
        harness.controller.hasNotice,
        isFalse,
        reason: 'the user outranks the policy',
      );
    });

    test('a manual dismissal does not push the next one out', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Birinci.');
      harness.controller.dismiss();
      harness.clock.advance(const Duration(seconds: 4));
      harness.controller.showText('İkinci.');
      harness.clock.advance(harness.policy.transientLifetime);
      expect(
        harness.controller.hasNotice,
        isFalse,
        reason: 'a hand-closed toast may not make its successor sticky',
      );
    });
  });

  group('DEFECT 4, a status change never produces a toast', () {
    test('no status value puts a notice on screen, at any clock time', () {
      for (final ConnectionStatus status in ConnectionStatus.values) {
        final NoticeHarness harness = NoticeHarness();
        addTearDown(harness.dispose);

        harness.controller.setStatus(status);
        expect(harness.controller.status, status);
        expect(
          harness.controller.hasNotice,
          isFalse,
          reason: '$status is a state, not an event',
        );
        expect(harness.clock.requested, isEmpty, reason: 'no timer either');

        // And it is still not a toast a minute later, which is what the
        // reconnect loop's "Yeniden bağlanılıyor" notice was.
        harness.clock.advance(const Duration(minutes: 1));
        expect(harness.controller.hasNotice, isFalse, reason: '$status');
        expect(harness.clock.requested, isEmpty, reason: '$status');
      }
    });

    test('a status change leaves a notice on screen exactly as it was', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.showText('Mesaj gönderildi.');
      final NoticeSnapshot before = harness.controller.snapshot;

      harness.controller.setStatus(ConnectionStatus.offline);
      harness.controller.setStatus(ConnectionStatus.error);

      expect(harness.controller.snapshot.notice, before.notice);
      expect(
        harness.controller.notice!.expiresAt,
        before.notice!.expiresAt,
        reason: 'a status change must not touch the notice deadline',
      );
      expect(
        harness.controller.notice!.sequence,
        before.notice!.sequence,
        reason: 'nor may it count as another notice',
      );
    });

    test('the same status twice notifies once', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      int notifications = 0;
      harness.controller.addListener(() => notifications += 1);

      harness.controller.setStatus(ConnectionStatus.online);
      harness.controller.setStatus(ConnectionStatus.online);
      expect(notifications, 1);

      harness.controller.setStatus(ConnectionStatus.connecting);
      expect(notifications, 2);
    });

    test('a status survives any amount of clock, unlike a notice', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.setStatus(ConnectionStatus.offline);
      harness.clock.advance(const Duration(days: 7));
      expect(harness.controller.status, ConnectionStatus.offline);
      expect(harness.controller.hasNotice, isFalse);
    });
  });

  group('the catalogue as an entry point', () {
    test('a catalogue entry can be shown, and is Turkish', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);

      harness.controller.show(NoticeTr.statusOffline);
      expect(harness.controller.notice!.text, 'Bağlantı yok');
      expect(harness.controller.notice!.kind, NoticeKind.info);
    });
  });

  group('the controller as a listener source', () {
    test('publishes only on a real change', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      int notifications = 0;
      harness.controller.addListener(() => notifications += 1);

      harness.controller.showText('Birinci.');
      expect(notifications, 1);

      harness.controller.showText('Birinci.');
      harness.clock.advance(const Duration(seconds: 1));
      harness.controller.showText('Birinci.');
      expect(notifications, 1, reason: 'dedup must not rebuild the UI');

      harness.controller.dismiss();
      expect(notifications, 2);
      harness.controller.dismiss();
      expect(notifications, 2, reason: 'closing nothing is not a change');
    });

    test('an expiry publishes once, with the clock as the timestamp', () {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      int notifications = 0;
      harness.controller.addListener(() => notifications += 1);

      harness.controller.showText('Birinci.');
      final DateTime shownAt = harness.clock.now();
      harness.clock.advance(harness.policy.transientLifetime);

      expect(notifications, 2);
      expect(
        harness.controller.snapshot.lastAutomaticDismissal,
        shownAt.add(harness.policy.transientLifetime),
      );
    });

    test('disposing cancels the outstanding timer', () {
      final FakeNoticeClock clock = FakeNoticeClock();
      final NoticeController controller = NoticeController(clock: clock);

      controller.showText('Birinci.');
      expect(clock.pending, 1);
      controller.dispose();

      expect(
        clock.requested.single.cancelled,
        isTrue,
        reason: 'a disposed controller must not leave a callback behind',
      );
      expect(clock.pending, 0);
      clock.advance(const Duration(minutes: 1));
    });
  });

  group('the state model on its own', () {
    test('a notice is a value, and two with the same fields are equal', () {
      final DateTime at = DateTime.utc(2026, 9, 26, 12);
      final Notice a = Notice(
        text: 'Birinci.',
        kind: NoticeKind.info,
        shownAt: at,
        expiresAt: at.add(const Duration(seconds: 5)),
        sequence: 1,
      );
      final Notice b = Notice(
        text: 'Birinci.',
        kind: NoticeKind.info,
        shownAt: at,
        expiresAt: at.add(const Duration(seconds: 5)),
        sequence: 1,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.isDueAt(at.add(const Duration(seconds: 4))), isFalse);
      expect(a.isDueAt(a.expiresAt!), isTrue, reason: 'the deadline itself');
    });

    test('the empty snapshot is idle, blank and never dismissed', () {
      expect(NoticeSnapshot.empty.notice, isNull);
      expect(NoticeSnapshot.empty.status, ConnectionStatus.idle);
      expect(NoticeSnapshot.empty.dismissedText, isNull);
      expect(NoticeSnapshot.empty.lastAutomaticDismissal, isNull);
    });
  });
}
