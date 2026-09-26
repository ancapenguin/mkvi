/// Every user-facing string the pairing screen can produce, in Turkish, in one
/// typed place — and the closed set of reasons a pairing exchange can fail.
///
/// ## Why a catalogue and not constructor arguments
///
/// `src/App.tsx` had no catalogue. The pairing screen's wording lived in the
/// render branches (`src/App.tsx:545-610`), so "Pair a device", "Send this code"
/// and "Are you sure?" were three `String`s in three branches of the same file,
/// and a branch that reached the pairing screen for the wrong reason showed the
/// first-run wording with no way to tell. This file is the other half of
/// `SetupState`: the state gives the headline, and [PairingTr] gives everything
/// under it.
///
/// Each entry carries its own Turkish text, so a new string without wording is a
/// compile error rather than a blank button, and [pairingTrCatalogue] is the
/// iterable form the tests walk. The same argument `lib/ui/notice` and
/// `lib/ui/widgets/mkvi_code_field.dart` make, kept in the same shape.
///
/// ## Why the failures are an enum and not strings
///
/// [PairingRefusal] is the same shape as `PeerReadFailure`
/// (`lib/session/peer_store.dart`): one Turkish sentence for what happened, one
/// for what the user can do, and a separate case per cause. The two "the code did
/// not work" answers — expired, and nobody waiting — look identical from the
/// outside and need different things from the user, which is exactly why a
/// single `String reason` is not enough: it would be a sentence nobody can act
/// on, the defect `MkviErrorState`'s required `reason` argument was written to
/// remove.
library;

/// One string the pairing screen can show, to anyone, anywhere in it.
enum PairingTr {
  // -- the code this device shows -------------------------------------------

  /// The heading of the block that holds the generated code.
  codeDisplayLabel('Bu cihazın eşleştirme kodu'),

  /// What the user does with the code.
  sendCodeNote(
    'Bu kodu karşı tarafa gönder. Karşı taraf kendi cihazında bu kodu girsin.',
  ),

  /// Why the code is safe to send over an ordinary channel.
  codeLifetimeNote('Kod tek kullanımlıktır ve 15 dakika sonra geçersiz olur.'),

  /// How long the code is, as a caption under it. `%d` is the character count.
  codeLengthCaption('%d karakterlik kod'),

  /// The copy control's label. Also its accessible name.
  copyLabel('Kodu kopyala'),

  /// The line under the block after a successful copy.
  copiedNote('Kod panoya kopyalandı.'),

  /// The line under the block after a copy the platform refused.
  copyFailedNote('Kod kopyalanamadı; yukarıdaki kutudan elle yazabilirsin.'),

  /// Mints a different code, because the current one may already have been read.
  regenerateLabel('Yeni kod üret'),

  // -- entering a code -------------------------------------------------------

  /// One line under the field, before anything is typed.
  enterHint('Karşı tarafın gönderdiği kodu gir.'),

  /// The promise the product makes about the code, and the reason the field is
  /// not a repeatable form.
  enterOnceNote('Bu cihazda bir kez kod girersin; aynı kod ikinci kez işe yaramaz.'),

  /// The submit control's label.
  submitLabel('Eşleş'),

  /// The submit control's label while an exchange is in flight.
  submittingLabel('Kod gönderiliyor…'),

  /// The reason an empty field cannot be sent.
  emptyCode('Henüz kod girilmedi.'),

  /// A code that is not finished yet: `%d` characters still missing.
  tooShort('Kod eksik: %d karakter daha gerekiyor.'),

  /// A non-empty code `isAcceptedPairingCode` still refuses.
  ///
  /// Unreachable from the gate today, and deliberately kept: `normalizePairingCode`
  /// drops everything outside the alphabet and truncates at 16, so every value it
  /// produces is one the Worker accepts. A change to
  /// `lib/signaling/pairing_code.dart` that let a rejected value reach the field
  /// must not leave the screen with nothing to say. `pairing_enter_test.dart`
  /// says which branch is reachable and which is the guard.
  invalidCode('Bu kod geçersiz.'),

  // -- the exchange in flight ------------------------------------------------

  /// The headline of the progress block.
  progressTitle('Eşleşme tamamlanıyor'),

  /// What is happening, and why the screen is not accepting anything.
  progressNote('Kod karşı tarafa gönderildi. Cevap bekleniyor…'),

  /// The progress bar's accessible name.
  progressLabel('Eşleşme tamamlanıyor'),

  /// The headline of the block a failed exchange produces.
  failedTitle('Eşleşme kurulamadı'),

  /// Sends the same code again, for a failure that is about the network rather
  /// than about the code.
  retryLabel('Yeniden dene'),

  // -- backing out ------------------------------------------------------------

  /// The control that asks before leaving the pairing screen.
  cancelLabel('Vazgeç'),

  /// The confirmation's headline.
  cancelTitle('Eşleştirmeden vazgeçilsin mi?'),

  /// What leaving costs, said before the user pays it.
  cancelMessage(
    'Bu cihazdaki kayıtlı eş kaydın korunur ve sohbete dönersin.',
  ),

  /// The confirmation's affirmative button.
  cancelConfirmLabel('Evet, vazgeç'),

  /// The confirmation's negative button — staying is the default, so it is the
  /// one that carries the emphasis.
  cancelDismissLabel('Eşleştirmeye devam et'),

  // -- the peer this device already has --------------------------------------

  /// The heading of the block naming the peer that pairing would replace.
  peerHeading('Bu cihazdaki mevcut eş'),

  /// The label of the peer's own announced name.
  announcedNameLabel('Karşı tarafın seçtiği ad'),

  /// The label of this device's local note about the peer.
  aliasLabel('Bu cihazdaki takma ad');

  const PairingTr(this.tr);

  /// The Turkish text, with `%d` holes.
  final String tr;

  /// [tr] with its `%d` holes filled by [first] and then [second].
  String format(Object? first, [Object? second]) {
    String out = tr;
    for (final Object? value in <Object?>[first, second]) {
      final int hole = out.indexOf('%d');
      if (hole < 0) break;
      out = out.replaceRange(hole, hole + 2, '$value');
    }
    return out;
  }
}

/// Every entry as a map, for tests, for a debug overlay and for a future
/// translation pass.
Map<PairingTr, String> get pairingTrCatalogue => <PairingTr, String>{
  for (final PairingTr entry in PairingTr.values) entry: entry.tr,
};

/// Why a pairing exchange ended without a peer.
///
/// The same two-sentence shape as `PeerReadFailure`, and for the same reason: a
/// failed peer read and a failed pairing are both "something you can act on",
/// and both used to be one screen with no sentence in it at all.
enum PairingRefusal {
  /// The room's window closed. The code is dead; a new one is needed.
  expired(
    'Eşleştirme kodu artık geçerli değil.',
    'Yeni bir kod üret ve karşı tarafa yeniden gönder.',
  ),

  /// Nobody is waiting in that room: the two codes do not match, or the other
  /// device is not there any more.
  noSuchRoom(
    'Bu kodla bekleyen bir cihaz bulunamadı.',
    'Kodu karşı tarafın ekranıyla karşılaştır. Farklıysa yenisini gönder.',
  ),

  /// The signaling server could not be reached. The code may still be good, so
  /// this is the one refusal whose answer is "try the same code again".
  unreachable(
    'Eşleşme sunucusuna ulaşılamadı.',
    'Bağlantını kontrol edip aynı kodla yeniden dene.',
  ),

  /// The peer's signature did not verify. Nothing is stored, and nothing should
  /// be: this is the refusal that must never be retried with the same code.
  verificationFailed(
    'Karşı tarafın kimliği doğrulanamadı.',
    'Bu bağlantı güvenli değil. Yeni bir kod üretip başka bir cihazla eşleş.',
  ),

  /// The pair succeeded but the encrypted record could not be written, so
  /// nothing was adopted: the app is still showing the previous peer, if any.
  recordNotWritten(
    'Eş kaydı bu cihazın güvenli deposuna yazılamadı.',
    'Cihazdaki güvenli depoyu kontrol et ve yeniden dene.',
  ),

  /// The user backed out, or the other side did. Not an error, and it says so.
  cancelled(
    'Eşleşme tamamlanmadı.',
    'Yeni bir kod üretip yeniden deneyebilirsin.',
  );

  const PairingRefusal(this.messageTr, this.recoveryTr);

  /// One Turkish sentence saying what happened.
  final String messageTr;

  /// One Turkish sentence saying what the user can do about it.
  final String recoveryTr;

  /// Whether re-sending the **same** code is worth offering.
  ///
  /// True for the transport failure and false for everything else, which is the
  /// whole reason this is on the value rather than decided in a widget: a code
  /// that was spent must never be offered again as "just try once more".
  bool get isWorthRetrying => this == PairingRefusal.unreachable;
}
