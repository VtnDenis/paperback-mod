# Construire et installer

## Prérequis (une fois) — déjà en place sur cette machine

WSL2 Ubuntu + Theos dans `~/theos` :

```
export THEOS=~/theos
git clone https://github.com/theos/theos.git $THEOS
$THEOS/bin/update-theos                      # sous-modules (vendor/lib, logos…)
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks /tmp/sdks
cd /tmp/sdks && git sparse-checkout set iPhoneOS16.5.sdk && mv iPhoneOS16.5.sdk $THEOS/sdks/
```

Deux contournements Linux, faits par `_tools/build_dylib.sh` (pas besoin de sudo) :

- Le `ld64.lld` du toolchain Swift ne linke que x86_64 → on récupère celui d'Ubuntu
  (`apt-get download lld-21`, extrait dans `~/.local/llvm21`).
- `substrate.h` inclut `<CydiaSubstrate/CydiaSubstrate.h>` → lien symbolique posé
  dans `$THEOS/vendor/include/CydiaSubstrate/`.

## Compiler le dylib

```
wsl -d Ubuntu -e bash /mnt/c/Users/vtnde/Projets/paperback-re/_tools/build_dylib.sh
```

Sortie : `mod/PaperbackMod.dylib` (arm64, `@executable_path/PaperbackMod.dylib`).
Le script enchaîne Logos → `clang -c` → `ld64.lld` ; il n'utilise pas `make`
parce que le clang Linux n'émet pas les arguments de link Apple.

## Fabriquer l'IPA

```
C:\Python314\python.exe mod\pack_ipa.py ^
  "C:\Users\vtnde\AppData\Local\Temp\oc_paperback\Payload\Paperback.app" ^
  "C:\Users\vtnde\Projets\paperback-re\build\PaperbackMod.ipa"
```

Le script patche `Info.plist` (`UIBackgroundModes` + `audio`,
`UIDesignRequiresCompatibility = false`), puis laisse `_tools\zsign\zsign.exe`
injecter `PaperbackMod.dylib`, **signer en ad-hoc tous les Mach-O** et régénérer
`_CodeSignature`. Le `_CodeSignature` livré par le développeur est périmé dès
qu'on touche au plist et à l'exécutable : un signataire strict (Feather,
Sideloadly) refuse alors l'installation, et un dylib non signé se fait tuer par
AMFI au lancement. L'IPA ad-hoc n'est pas installable tel quel : c'est l'outil de
sideload qui remplace notre signature par la sienne.

## Installer

- **Sideload (pas de jailbreak)** : ouvrir `build/PaperbackMod.ipa` dans Sideloadly
  ou AltStore avec ton Apple ID ; l'outil re-signe le bundle et le dylib. Le profil
  expire en 7 jours (compte gratuit).
- **Appareil jailbreaké** : `make package` puis `dpkg -i`, ou déposer le dylib dans
  `/Library/TweakInject/` — dans ce cas le shim `SubstrateShim.m` est inutile,
  Substrate fournit `MSHookMessageEx`.

## Vérifier

`Console.app`, filtre `PaperbackMod` (processus `Paperback`). `xcrun simctl` ne
suffit pas : le binaire est arm64 device.
