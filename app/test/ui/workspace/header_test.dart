/// The header: two names, a status strip, two actions — and the regression test
/// for ROADMAP kusur 7.
///
/// ## What 0.1.x did
///
/// ```ts
/// const peerName = peerAlias || peerAnnouncedName || defaultPeerName;   // App.tsx:119
/// const aliasIsSet = Boolean(peerAnnouncedName && peerAnnouncedName !== peerName);
/// ```
///
/// Two failures in three lines. A note typed on **this** device outranked the
/// name the peer published about itself, so the announced name became invisible
/// the moment a note existed; and because "is an alias set" was really "are the
/// two names different", typing the peer's own name as a note removed both the
/// announced-name line and the button that removes the note — the one case where
/// the peer is most likely to want to change it again.
///
/// The tests below go through [PeerNameView] and assert the *screen* honours it,
/// including the equal-name case the original could not render.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/names.dart';
import 'package:mkvi/session/peer_store.dart' show KnownPeer;
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/notice/notice.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../support/mkvi_test_app.dart';
import 'support/workspace_harness.dart';

/// A header over a real [NoticeController], in a 400 dp column.
Widget headerUnderTest(
  PeerNameView peer, {
  NoticeController? notice,
  VoidCallback? onRemoveAlias,
  VoidCallback? onForgetPeer,
  AppearanceSettings settings = AppearanceSettings.initial,
}) {
  final NoticeController channel = notice ?? NoticeController(clock: const DisabledNoticeClock());
  return workspaceColumn(
    WorkspaceHeader(
      peer: peer,
      notice: channel,
      palette: workspacePaletteFor(settings),
      metrics: workspaceMetricsFor(settings),
      onRemoveAlias: onRemoveAlias,
      onForgetPeer: onForgetPeer,
    ),
    width: 400,
  );
}

void main() {
  group('DEFECT 7, the two names are two names', () {
    testWidgets('a note never overwrites the name the peer announced', (
      WidgetTester tester,
    ) async {
      const PeerNameView peer = PeerNameView(
        announcedName: 'Ayşe Yılmaz',
        alias: 'Kübra',
      );
      await pumpMkvi(tester, headerUnderTest(peer));

      // The headline is the peer's own name. TS showed the note here, which is
      // the whole defect.
      expect(
        tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.name)).data,
        'Ayşe Yılmaz',
      );
      expect(peer.displayName, isNot('Kübra'));
      // And the note is on a line of its own, labelled as *ours*.
      expect(
        tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.aliasLine)).data,
        workspaceAliasLine('Kübra'),
      );
      expect(
        find.text(peer.announcedNameLabel),
        findsOneWidget,
        reason: 'the announced name is still on screen, under the note',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a note spelled like the announced name still shows both', (
      WidgetTester tester,
    ) async {
      // The case `aliasIsSet` made impossible: both lines and the button have to
      // be there, because this is exactly when the peer wants to change it.
      const PeerNameView peer = PeerNameView(
        announcedName: 'Ayşe Yılmaz',
        alias: 'Ayşe Yılmaz',
      );
      expect(peer.announcedName != peer.alias, isFalse, reason: 'they are equal');
      expect(peer.showsAnnouncedName, isTrue, reason: 'and the layer says show it');
      expect(peer.canRemoveAlias, isTrue);

      await pumpMkvi(
        tester,
        headerUnderTest(peer, onRemoveAlias: () {}, onForgetPeer: () {}),
      );
      expect(
        find.byKey(WorkspaceHeaderKeys.announcedLine),
        findsOneWidget,
        reason: 'the announced-name line does not vanish for an equal note',
      );
      expect(find.byKey(WorkspaceHeaderKeys.aliasLine), findsOneWidget);
      expect(find.byKey(WorkspaceHeaderKeys.removeAlias), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('with no note there is one name and no button', (
      WidgetTester tester,
    ) async {
      const PeerNameView peer = PeerNameView(announcedName: 'Ayşe Yılmaz');
      expect(peer.hasAlias, isFalse);
      expect(peer.canRemoveAlias, isFalse);
      expect(peer.showsAnnouncedName, isFalse, reason: 'nothing to show twice');

      await pumpMkvi(
        tester,
        headerUnderTest(peer, onRemoveAlias: () {}, onForgetPeer: () {}),
      );
      expect(tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.name)).data, 'Ayşe Yılmaz');
      expect(find.byKey(WorkspaceHeaderKeys.aliasLine), findsNothing);
      expect(find.byKey(WorkspaceHeaderKeys.announcedLine), findsNothing);
      expect(
        find.byKey(WorkspaceHeaderKeys.removeAlias),
        findsNothing,
        reason: 'a button that exists with nothing to do is the dead close button',
      );
      expect(
        find.byKey(WorkspaceHeaderKeys.forgetPeer),
        findsOneWidget,
        reason: 'and the other action is still there',
      );
      expectNoOverflow(tester);
    });

    testWidgets('an unknown announced name leaves the note as the second line', (
      WidgetTester tester,
    ) async {
      // TS: `peerAlias || peerAnnouncedName` would make the note the *headline*
      // here, and the placeholder disappear.
      const PeerNameView peer = PeerNameView(announcedName: '', alias: 'Kübra');
      expect(peer.announcedNameIsUnknown, isTrue);
      expect(peer.displayName, KnownPeer.defaultAnnouncedName);

      await pumpMkvi(tester, headerUnderTest(peer, onRemoveAlias: () {}));
      expect(
        tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.name)).data,
        KnownPeer.defaultAnnouncedName,
        reason: 'the placeholder stands in for the announcement, not the note',
      );
      expect(
        find.byKey(WorkspaceHeaderKeys.aliasLine),
        findsOneWidget,
        reason: 'and the note is still shown, labelled as ours',
      );
      expect(
        find.byKey(WorkspaceHeaderKeys.announcedLine),
        findsNothing,
        reason: 'there is no announced name to show a second time',
      );
      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });
  });

  group('the two actions', () {
    testWidgets('remove and forget, both wired, both real targets', (
      WidgetTester tester,
    ) async {
      int removed = 0;
      int forgotten = 0;
      const PeerNameView peer = PeerNameView(
        announcedName: 'Ayşe Yılmaz',
        alias: 'Kübra',
      );
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: headerUnderTest(
            peer,
            onRemoveAlias: () => removed += 1,
            onForgetPeer: () => forgotten += 1,
          ),
        ),
      );

      expect(find.text(peer.removeAliasLabel), findsOneWidget);
      expect(find.text(WorkspaceTr.forgetDevice.tr), findsOneWidget);
      expectHitTarget(tester, find.byKey(WorkspaceHeaderKeys.removeAlias), style: style);
      expectHitTarget(tester, find.byKey(WorkspaceHeaderKeys.forgetPeer), style: style);

      await tester.tap(find.byKey(WorkspaceHeaderKeys.removeAlias));
      await tester.tap(find.byKey(WorkspaceHeaderKeys.forgetPeer));
      await tester.pump();
      expect(removed, 1);
      expect(forgotten, 1);
      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('an action with no callback is not drawn', (
      WidgetTester tester,
    ) async {
      const PeerNameView peer = PeerNameView(
        announcedName: 'Ayşe Yılmaz',
        alias: 'Kübra',
      );
      await pumpMkvi(tester, headerUnderTest(peer));
      expect(find.byKey(WorkspaceHeaderKeys.removeAlias), findsNothing);
      expect(find.byKey(WorkspaceHeaderKeys.forgetPeer), findsNothing);
      expect(find.byKey(WorkspaceHeaderKeys.actions), findsNothing);
      // The names are still there: a screen that cannot act on a note is a
      // screen that still has to *say* it.
      expect(find.byKey(WorkspaceHeaderKeys.aliasLine), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('the connection state is a state, never a toast', () {
    testWidgets('all five states show, and none of them is a notice', (
      WidgetTester tester,
    ) async {
      final NoticeController notice = NoticeController(
        clock: const DisabledNoticeClock(),
      );
      addTearDown(notice.dispose);
      await pumpMkvi(
        tester,
        headerUnderTest(
          const PeerNameView(announcedName: 'Ayşe Yılmaz'),
          notice: notice,
        ),
      );

      expect(find.text(ConnectionStatus.idle.labelTr), findsOneWidget);
      for (final ConnectionStatus status in ConnectionStatus.values) {
        notice.setStatus(status);
        await tester.pump();
        expect(
          find.text(status.labelTr),
          findsOneWidget,
          reason: '${status.name} has a label of its own',
        );
        expect(
          find.byKey(NoticeKeys.surface),
          findsNothing,
          reason:
              '$status is not a toast — `setStatus` has no branch that builds '
              'one, and this is the assertion that would notice if it grew one',
        );
      }
      expectNoOverflow(tester);
    });

    testWidgets('the avatar uses Turkish casing, not the default pass', (
      WidgetTester tester,
    ) async {
      // `i` is `İ` and `ı` is `I` in Turkish; the default Unicode table gets the
      // second one wrong, which is what `turkishUpperCase` exists for.
      Text initialsInAvatar() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(WorkspaceHeaderKeys.avatar),
          matching: find.byType(Text),
        ),
      );
      await pumpMkvi(
        tester,
        headerUnderTest(const PeerNameView(announcedName: 'İpek')),
      );
      expect(initialsInAvatar().data, 'İP');
      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        headerUnderTest(const PeerNameView(announcedName: 'ısıl')),
      );
      expect(
        initialsInAvatar().data,
        'IS',
        reason: 'a dotless ı uppercases to a plain I, and the default pass is wrong here',
      );
      expectNoOverflow(tester);
    });
  });

  group('the Turkish catalogue', () {
    test('every entry has text, and no two say the same thing', () {
      expect(workspaceTrCatalogue.length, WorkspaceTr.values.length);
      for (final MapEntry<WorkspaceTr, String> entry
          in workspaceTrCatalogue.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: '${entry.key} has no text');
      }
      final Set<String> texts = workspaceTrCatalogue.values.toSet();
      expect(
        texts.length,
        WorkspaceTr.values.length,
        reason: 'two entries saying one thing is one string with two names',
      );
    });

    test('the local note line and the announced line are different sentences', () {
      // The pair is the whole of defect 7: if these were one string, one of the
      // two names would have to overwrite the other.
      expect(
        workspaceAliasLine('Kübra'),
        isNot(PeerNameView(announcedName: 'Kübra').announcedNameLabel),
      );
      expect(workspaceAliasLine('Ayşe'), contains('Ayşe'));
      expect(
        PeerNameView(announcedName: 'Ayşe').announcedNameLabel,
        contains('Ayşe'),
      );
    });
  });

  group('the header survives every palette', () {
    testWidgets('no overflow in any theme, accent, scale or switch', (
      WidgetTester tester,
    ) async {
      final Iterable<AppearanceSettings> everything = <Iterable<AppearanceSettings>>[
        mkviAppearanceMatrix(),
        mkviScaleMatrix(),
        mkviAccessibilityMatrix(),
      ].expand((Iterable<AppearanceSettings> m) => m);

      for (final AppearanceSettings settings in everything) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          headerUnderTest(
            const PeerNameView(announcedName: 'Ayşe Yılmaz', alias: 'Kübra'),
            onRemoveAlias: () {},
            onForgetPeer: () {},
            settings: settings,
          ),
          settings: settings,
          size: mkviPhoneWindowSize,
        );
        expectNoOverflow(tester);
      }
      await expectEveryControlLabelled(tester);
    });
  });
}
