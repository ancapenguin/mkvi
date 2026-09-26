/// Every Turkish string the workspace surface can produce, in one typed place.
///
/// `lib/chat/chat_messages.dart` already owns the words the *layer* produces —
/// a delivery receipt, a day label, a byte pair, a transfer state. This file owns
/// only the words the **screen** adds on top: the composer's helper sentence, the
/// discard action, the history button, the local-alias line, the transfer
/// decisions. Nothing here is a second copy of something `ChatMessages` already
/// spells, and the reuse is deliberate rather than accidental: "Okundu" and
/// "Yeniden dene" are read by this screen and they are the chat layer's to say,
/// so a copy here would be a second place for the same two words to drift.
///
/// ## Why the local alias line is a string *of this file*
///
/// `PeerNameView` (in `lib/session/names.dart`) hands the UI two slots and
/// answers every question about them: `displayName`, `hasAlias`,
/// `showsAnnouncedName`, `canRemoveAlias`. It also spells the *announced* line
/// ("Kendi seçtiği ad: …") because the TypeScript original did.
///
/// It does not spell the **local** line, and that omission is the fix for
/// ROADMAP defect 7 rather than a gap in it. In 0.1.x there was one string:
/// `const peerName = peerAlias || peerAnnouncedName` (`src/App.tsx:119`), so a
/// local note outranked the name the peer published about itself, and the
/// announced name became invisible the moment a note was typed. Two names need
/// two lines, so this file adds the second one — and the test in
/// `test/ui/workspace/header_test.dart` asserts the announced name is still on
/// screen while a note exists, including when the note happens to be identical
/// to it (the case `src/ChatCallWorkspace.tsx:490` could not render at all).
library;

/// One string this surface can show, to anyone, anywhere on it.
enum WorkspaceTr {
  /// The accessible name of the whole workspace. The screen is two things —
  /// a conversation and a file lane — and a screen reader should say so once
  /// rather than announce an unlabelled column.
  workspace('Sohbet ve dosya aktarımı'),

  /// The accessible name of the header region: who the peer is.
  headerRegion('Eşleştiğin cihaz'),

  /// The composer's placeholder, and its accessible name.
  composerHint('Bir mesaj yaz'),

  /// The permanent line under the composer, read when nothing is queued and the
  /// channel is up. It is not decoration: it is the sentence that tells the user
  /// where a message they write will go.
  ///
  /// Kept to one line's worth of characters on purpose. It sits under a field in
  /// the bottom 120 dp of the window, and a sentence that wraps to two lines at
  /// the largest type scale is 30 dp the conversation does not get — in a
  /// 400x720 window, which is the size this app has to survive, that is the
  /// difference between a header, a notice and a conversation and a header and a
  /// notice.
  composerHelper('Mesajların yalnızca eşleştiğin cihaza gider.'),

  /// The composer's permanent line while messages are held for a reconnect is
  /// [ChatMessages.holdingForReconnect] and is used verbatim: the chat layer
  /// already owns that sentence, and a second copy of it here is one more place
  /// for the two to drift. There is no entry for it in this catalogue, and that
  /// is deliberate.
  send('Gönder'),
  /// The accessible name of the send action, for a screen reader that is
  /// already inside the message field and would otherwise only hear "Gönder".
  sendHint('Mesajı karşı cihaza gönder'),

  /// The delivery state of a line that is written down and on its way.
  deliverySending('Gönderiliyor'),

  /// The delivery state of a line the channel has taken.
  deliverySent('Gönderildi'),

  /// The delivery state of a line the channel refused. Deliberately not
  /// [ChatMessages.failed] ("Başarısız"): that word is the *transfer* list's
  /// state, and a message that did not go out is its own sentence.
  deliveryFailed('Gönderilemedi'),

  /// The discard action on a line that did not go out.
  discard('Sil'),

  /// The accessible name of the discard action.
  discardLabel('Gönderilemeyen mesajı sil'),

  /// The transfer list's accept action on an announced offer.
  acceptTransfer('Kabul et'),

  /// The transfer list's decline action on an announced offer.
  declineTransfer('Reddet'),

  /// The transfer list's cancel action, on either side.
  cancelTransfer('İptal'),

  /// The transfer list's dismiss action on a settled row. The row's own
  /// `dismissLabel` (which names the file) is the accessible name; this is
  /// the visible word, because a bare cross with no label is the 0.1.x close
  /// button at 34 px.
  dismissTransfer('Kapat'),

  /// What a finished download says instead of its path.
  ///
  /// The path is the thing defect 8 is about in its other form: a full Windows
  /// path is 200-odd characters of unbroken text, and the notice that carried
  /// one grew down over the message list. So the row says the file is saved and
  /// stops. `TransferView.detail` still holds the path for whoever needs it as
  /// a *value*; it is simply not a thing the row paints.
  saved('Kaydedildi'),

  /// The history control: read an older page.
  loadOlder('Daha eski mesajları yükle'),

  /// The history control while a page is on its way. A disabled button rather
  /// than a spinning ring: this layer starts no clock, and
  /// `test/support/mkvi_test_app.dart` settles every pump.
  historyLoading('Eski mesajlar yükleniyor'),

  /// Shown once the history is exhausted and there is at least one line, so the
  /// control does not simply vanish with no explanation.
  historyComplete('Daha eski mesaj yok'),

  /// The screen's name for the forget action.
  forgetDevice('Bu cihazı unut'),

  /// The forget action's accessible name, which says what it costs, because
  /// this is the one control on the screen that cannot be undone.
  forgetDeviceLabel('Bu cihazı unut, eşleşme silinir'),

  /// The confirmation's title. It names the cost, not the button.
  forgetTitle('Bu cihaz unutulsun mu?'),

  /// The confirmation's body. It says exactly what is lost, because after this
  /// the two devices are strangers again and pairing has to be redone by hand.
  forgetBody(
    'Eşleşme silinir ve bu cihazı yeniden eşleştirmeniz gerekir. Mesaj '
    'geçmişi silinmez.',
  ),

  /// The confirmation's "never mind".
  forgetCancel('Vazgeç'),

  /// The confirmation's "go ahead", kept last so it reads as the destructive one.
  forgetConfirm('Unut');

  const WorkspaceTr(this.tr);

  /// The Turkish text, never empty.
  final String tr;
}

/// Every entry as a map, for tests, a debug overlay and a future translation
/// pass. The same shape `notice_strings.dart` uses, so a test that walks
/// catalogues has one shape to walk.
Map<WorkspaceTr, String> get workspaceTrCatalogue => <WorkspaceTr, String>{
  for (final WorkspaceTr entry in WorkspaceTr.values) entry: entry.tr,
};

/// The line that names **this device's** note about the peer.
///
/// The twin of `PeerNameView.announcedNameLabel`, and the pair is the whole of
/// defect 7: one name is what the peer calls itself, the other is what *this*
/// device calls it, and the second must never overwrite the first on screen.
String workspaceAliasLine(String alias) => 'Bu cihazdaki takma ad: $alias';

/// The line under the composer that says how many lines are waiting for a
/// reconnect. Turkish pluralisation is a number and a word, not a suffix rule
/// the screen should invent: MKVI's Turkish is the plain `N sırada` form that
/// `formatBytes` and `dayLabel` already use.
String workspaceQueuedLines(int count) => '$count sırada';
