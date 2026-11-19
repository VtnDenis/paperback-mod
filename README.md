# PaperbackMod

Tweak pour Paperback (iOS, `dev.faizandurrani.moe.paperback.app`) construit sur
l'IPA officielle non chiffrée.

- notifications système réelles quand l'updater trouve des chapitres, fusionnées
  par source (une seule notif, débat 4 s, plafond 3 sources)
- refresh périodique (30 min) + keep-alive audio pour les téléchargements en
  arrière-plan
- boutons Liquid Glass (iOS 26+)
- ouverture sur l'onglet Library

`build/PaperbackMod.ipa` = Paperback 0.8.11 + `PaperbackMod.dylib`, signée
ad-hoc : il faut la re-signer (Feather / Sideloadly) pour l'installer.
