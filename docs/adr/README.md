# Karar Günlüğü (ADR)

MKVI'de alınan mimari kararların kalıcı kaydı. Her karar: **ne karar verildi, hangi
kanıta dayandı, ne tersine döner.**

Kural: bir kararı değiştirmek yeni bir ADR yazmakla olur. Eski ADR **silinmez**, `Dönüştü`
başlığıyla bağlanır — böylece "neden öyle yapmamıştık" sorusu cevaplanabilir.

| # | Karar | Durum |
|---|---|---|
| [0001](0001-flutter-migration.md) | Arayüz ve kabuk React+Tauri'dan Flutter'a taşınıyor | Kabul |
| [0002](0002-transport-architecture.md) | Taşıma mimarisi: kısa ömürlü rendezvous bileti, trickle ICE, DTLS parmak izi SAS | Öneri |
