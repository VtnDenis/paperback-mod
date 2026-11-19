# Paperback 0.8.11 — carte du binaire (reconstruction niveau 2)

Source des artefacts : IPA officiel non chiffré `v0.8.11-r2`
(`https://github.com/Paperback-iOS/app/releases/download/v0.8.11-r2/Paperback.ipa`,
13 597 210 o), déballé dans
`C:\Users\vtnde\AppData\Local\Temp\oc_paperback\Payload\Paperback.app\`.
Binaire analysé : `Payload\Paperback.app\Paperback`, Mach-O arm64 thin,
20 077 504 o, `cryptid=0`, bundle `dev.faizandurrani.moe.paperback.app`.

## État des artefacts

| Fichier | Contenu |
|---|---|
| `headers\` | 918 en-têtes bruts (`ipsw class-dump --headers`), noms Swift manglés |
| `headers_src\` | mêmes en-têtes, noms démanglés, types de méthodes décodés |
| `source_paths.txt` | 102 chemins sources `/Users/paper/Developer/XCode/Paperback/…` extraits des chaînes |
| `objc_dump.txt` | dump ObjC verbeux avec adresses |
| `classes_mangled.txt`, `swift_syms_mangled.txt` | tables de symboles |

L'arborescence réelle du projet est donc connue (`EnvironmentObjects/`,
`Models/DynamicUI/`, `Stores/Local/`, `UIKitViews/`…), ce qui donne la
structure des modules sans deviner.

## Cycle de vie

- `PaperbackAppDelegate` (`AppDelegate.swift`) : `didFinishLaunchingWithOptions`,
  `configurationForConnectingSceneSession`, `handleEventsForBackgroundURLSession`.
- `PaperbackSceneDelegate` (`SceneDelegate.swift`) : `willConnectToSession` installe
  la fenêtre et la racine ; `openURLContexts` gère le scheme `paperback`.
- UI 100 % UIKit programmatique (SnapKit), pas de storyboard : les 71
  `*ViewController` sont instanciées en code.

## Chaîne des notifications (lacune confirmée)

- `UserNotifications.framework` est **lié**, `+[UNUserNotificationCenter currentNotificationCenter]`
  est importé (2 réfs), mais **`UNMutableNotificationContent`, `UNNotificationRequest`
  et `BGTaskScheduler` sont absents** du binaire : aucune notification locale,
  aucun rafraîchissement en tâche de fond.
- L'écran `PaperbackNotificationSettingsViewController`
  (`Views/SettingsView/…`, Eureka) affiche pourtant deux modes —
  « Individual Notifications » / « Grouped Notifications » — avec les
  libellés « When a manga is updated, you will get a single notification for
  each source » (ex. « 23 new updates from MangaLife ») et « … a notification
  for each available title » (ex. « Horimiya Updated / 3 new chapters from
  MangaLife »). Le déclenchement est **entièrement côté serveur** : l'opération
  GraphQL embarquée `UpdatePushToken` (`GraphQLOperations.graphql`) envoie un
  jeton APNs associé à des sources —
  `mutation UpdatePushToken($associatedSources:[String!],$token:String!){ updateSourcesForToken(...) }`
  (hash `4af69c848e7146106000575d9de2714e70aac18c92c285575592e259d5e90d9a`
  dans `operationIDs.json`). Le backend pousse, l'app n'a aucun scheduler local.
### Hooks retenus (implémentés dans `mod\Tweak.xm`)

Point important : les classes Swift sont **enregistrées auprès de l'ObjC sous
leur nom manglé** (`_TtC9Paperback28LibraryUpdaterViewController`, pas
`PaperbackLibraryUpdaterViewController`). Les `%hook` doivent utiliser le nom
manglé, sinon le hook fait silencieusement rien.

| Hook | Nom runtime | Rôle |
|---|---|---|
| `UIApplicationDidFinishLaunchingNotification` | — (pas de hook) | demander l'autorisation de notification |
| `UIApplicationDidEnterBackgroundNotification` / `UIApplicationWillEnterForegroundNotification` | — (pas de hook) | démarrer/arrêter le keep-alive audio (téléchargements en arrière-plan) |
| `viewDidAppear:` | `_TtC9Paperback21MainTabViewController` | atterrir sur l'onglet Library une seule fois |
| `viewDidLoad` | `_TtC9Paperback21LibraryViewController` | mémoriser le VC + `NSTimer` 60 s → `didRefreshCollectionView:` toutes les 30 min |
| `viewDidLoad` / `viewDidDisappear:` | `_TtC9Paperback28LibraryUpdaterViewController` | borne la fenêtre « refresh en cours » |
| `tableView:numberOfRowsInSection:` / `tableView:titleForHeaderInSection:` | `_TtC9Paperback28LibraryUpdaterViewController` | compter les chapitres par source et poster **une** notif fusionnée |
| `didMoveToWindow` | `UIButton` | appliquer `UIGlassEffect` (Liquid Glass) sur les boutons qui ont une surface |
| `viewDidLoad` | `_TtC18ESTabBarController18ESTabBarController` | couleur d'accent de la barre d'onglets |

`PaperbackUpdatesManager` reste hors d'atteinte en `%hook` : aucune de ses
méthodes n'est `@objc` (classe Swift pure, 4 ivars, zéro méthode dans la table
de symboles, aucun symbole `UpdatesManager` dans `decomp\_functions.txt`), donc
il faudrait `MSHookFunction` sur une adresse de vtable. Le déclencheur retenu
est l'updater VC, qui n'apparaît que quand des chapitres sont effectivement
trouvés — même sémantique, zéro adresse en dur.

`shortcut:` les comptes sont lus à l'échelle du tableau entier, mais l'index de
section peut bouger entre deux reloads : les comptes d'une section disparue
restent jusqu'au flush (4 s). Le format de notification reprend celui de l'app
(« 3 new chapters from MangaLife », `Localizable.strings`), fusionné par source.

## UI / thème

- Liquid Glass : le binaire est compilé avec le SDK **iOS 18.4** (aucune chaîne
  `UIGlass`, `UIDesignRequiresCompatibility`), donc il garde le look d'avant.
  `UIDesignRequiresCompatibility=false` dans le plist ne change rien pour un
  binaire de ce SDK (Apple : la clé sert à *revenir* au mode compatibilité) ; le
  glass est donc appliqué au runtime, bouton par bouton, via `UIGlassEffect`
  (`UIVisualEffectView` inséré en sous-vue 0, `tintColor` = ancienne couleur de
  fond, coins = moitié de la hauteur). Style 0 pris pour `regular`, l'autre cas
  étant `clear`.
- `PaperbackThemeManager` (`EnvironmentObjects/ThemeManager.swift`) porte
  `ThemeColors` + `ThemeFonts`, propriétés Swift non `@objc`.
- Écrans de réglage : `PaperbackThemeSettingsViewController`,
  `PaperbackDisplaySettingsViewController`, `PaperbackReaderSettings` +
  `PaperbackChapterReaderSettingsViewController`, `PaperbackReaderSettings.Values`.
- Barre d'onglets : `ESTabBarController` (dépendance tierce embarquée).
- `ChapterReaderViewController` + `ChapterRenderers` (`PagedChapterRenderer`,
  `ScrollBasedChapterRenderer`) : le rendu du lecteur est isolé derrière
  `ChapterRenderer`.

## Téléchargements en arrière-plan

Aucune URLSession de fond (`backgroundSession`=0, `sessionSendsLaunchEvents`=0),
aucun `BGTaskScheduler` : la file vit avec le process, ce qui explique qu'un lot
de 100+ chapitres casse dès que l'app passe en arrière-plan. Correctif retenu :
`UIBackgroundModes += audio` (le plist en avait déjà `fetch`, inutile ici) +
boucle d'un WAV silencieux (`mod\KeepAlive.m`) sur `sceneWillResignActive` /
`sceneDidBecomeActive`. Écarté : `beginBackgroundTask` (~30 s), background
URLSession (delegate Swift non exposé à l'ObjC), hausse de la concurrence
(`requestsPerSecond` et `concurrentChapterDownloads` sont des ivars d'acteur).

## Distribution d'un binaire modifié

Deux voies, le binaire n'étant ni chiffré ni signé App Store :

1. **Build sideload injecté** (voie retenue) — `mod\pack_ipa.py` copie le bundle,
   patche le plist, ajoute le dylib et `LC_LOAD_DYLIB`, puis zippe un IPA que
   Sideloadly/AltStore re-signe. Contrainte : le profil expire (7 jours en
   compte gratuit).
2. **Tweak Theos** sur appareil jailbreaké : `make package` + `dpkg -i`.

Compilation : Theos ne tourne pas nativement sous Windows, mais WSL2 est déjà
installé ici — `_tools\build_dylib.sh` y fait Logos + `clang -c` + `ld64.lld`
arm64 sans `make` (le clang Linux n'émet pas les arguments de link Apple).
Sans Substrate à l'exécution, `mod\SubstrateShim.m` fournit `MSHookMessageEx`
(override de sous-classe via `class_addMethod`, pas de patch de la méthode héritée).


