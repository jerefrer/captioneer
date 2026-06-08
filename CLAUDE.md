# CLAUDE.md — contexte projet

> Ce fichier est lu automatiquement par Claude Code à l'ouverture du dépôt.
> Il résume l'objectif, l'état actuel, les décisions prises et ce qui reste à faire.

## Objectif

**Captioneer** — outil macOS **sans terminal** permettant à un photographe (ou
n'importe quel utilisateur non technique) d'**extraire les légendes (descriptions)
déjà présentes dans les métadonnées de ses images** (TIFF, JPEG, PNG) et de les
rassembler dans un **fichier Excel** (`Extraction.xlsx`).

C'est l'**inverse** d'un outil d'estampillage : on *lit* ce qui est dans les
images, on ne l'y écrit pas. (Le dépôt portait auparavant le nom d'une app
inverse « Imprint » qui écrivait des légendes Excel→TIFF ; tout son code et sa
doc ont été remplacés.)

Cible : Apple Silicon (M1/M2/M3/M4), macOS 14+.

## Comportement attendu

1. L'utilisateur glisse-dépose un **dossier d'images** ou une **sélection de
   fichiers** dans `Captioneer.app` (ou clique pour les choisir ; ou clic droit
   Finder → Action Rapide « Extraire les légendes »).
2. L'app lit les métadonnées de chaque image via ExifTool (`exiftool -j`, en
   **lecture seule** — les images ne sont jamais modifiées).
3. Pour chaque image, la **première valeur non vide** est retenue dans cet ordre :
   `XMP-dc:Description` → `IPTC:Caption-Abstract` → `EXIF:ImageDescription` → `Title`.
4. Un `Extraction.xlsx` est écrit dans le dossier des images, deux colonnes
   `Filename` / `Description`. Texte multiligne et bilingue EN/FR gardé tel quel.
5. Résumé affiché : nombre d'items extraits + liste fichier/légende.

## Architecture

```
Package.swift                  # manifeste SwiftPM (cible macOS 14, dép. Sparkle)
Sources/Captioneer/
  CaptioneerApp.swift          # @main, fenêtre, menu Sparkle, handler Services
  ContentView.swift            # racine, switch sur AppState
  DropZoneView.swift           # zone drag-drop + NSOpenPanel
  ProcessingView.swift         # progression (indéterminée pendant l'extraction)
  SummaryView.swift            # résumé + liste fichier/description
  ErrorView.swift              # état d'erreur
  CaptioneerEngine.swift       # orchestration : installe ExifTool, lit les
                               # métadonnées (-j), construit l'.xlsx
  Models.swift                 # AppState, ProcessingProgress, ProcessSummary,
                               # FileResult, CaptioneerError
  Theme.swift                  # palette crème/sépia tirée de l'icône
  UpdaterController.swift      # wrapper Sparkle (auto-update)
app/Info.plist                 # bundle .app (CFBundleExecutable = Captioneer)
app/make_icns.sh               # génère app/Captioneer.icns depuis la 1re image
                               # de Captioneer.icon/Assets/ (n'importe quel nom)
app/Captioneer.icns            # icône compilée (gitignorée, régénérée au build)
Captioneer.icon/               # source de l'icône (image 1024×1024 + icon.json)
build_app.sh                   # swift build + bundle + sign + DMG + notarise
docs/                          # GitHub Pages : index.html + appcast.xml Sparkle
.github/workflows/release.yml  # CI : build/sign/notarise/appcast sur tag vX.Y.Z
dist/, .build/                 # artéfacts de build (gitignorés)
```

- **UI** : SwiftUI natif (drag-drop, progression, résumé). Le binaire appelle
  `exiftool` (Perl) en child process via `Process`, en **lecture seule** (`-j`,
  sortie JSON). On lit toute la sortie d'un coup (pas de streaming) ; le JSON
  préserve les légendes multilignes là où une sortie tabulée les casserait.
- **Génération de l'`.xlsx`** : `CaptioneerEngine.writeXLSX()` écrit à la main
  les parties XML d'un classeur OOXML (Content_Types, workbook, styles,
  worksheet) dans un dossier temporaire, puis les zippe via `/usr/bin/zip`.
  Style : en-tête gras sur fond sépia, colonne Description en wrap top-aligné,
  ligne d'en-tête gelée. `xml:space="preserve"` garde les sauts de ligne.
- **ExifTool** : non bundlé. `CaptioneerEngine.ensureExifTool()` cherche
  `/usr/local/bin/exiftool`, `/opt/homebrew/bin/exiftool`, puis le PATH,
  puis `~/Library/Application Support/Captioneer/Image-ExifTool-VERSION/`,
  puis télécharge depuis exiftool.org (URLSession + tar).
- **Extensions lues** : tif, tiff, jpg, jpeg, png. Les images sans légende
  apparaissent quand même (statut `.noCaption`, description vide).
- **Concurrence** : `extractMetadata` tourne dans un `Task.detached` ; l'engine
  est `@MainActor`.
- **Sparkle** : auto-update. `SUFeedURL =
  https://jerefrer.github.io/captioneer/appcast.xml`, clé publique EdDSA dans
  l'Info.plist. La CI régénère `docs/appcast.xml` (item signé) à chaque tag.

## Construire & signer

```bash
./build_app.sh --setup-credentials   # 1re fois : stocke le mdp d'app (trousseau)
./build_app.sh                       # build + signe + notarise + agrafe -> DMG
./build_app.sh --no-sign             # dev : bundle + DMG bruts (rapide)
```

Sortie : `dist/Captioneer.dmg` — DMG signé + notarisé + agrafé, avec raccourci
« Applications ». C'est le fichier envoyé à l'utilisateur final.

- Identité : `Developer ID Application: Jeremy Frere (3J4HCZ8V25)`, Team ID
  `3J4HCZ8V25`. Surchargeable via `SIGN_IDENTITY`, `APPLE_ID`, `TEAM_ID`,
  `KEYCHAIN_PROFILE`.
- Profil de notarisation (local) attendu sous le nom `Captioneer-notarize`
  (créé par `--setup-credentials`). La CI en crée un éphémère `captioneer-notarize`.
- `CFBundleIdentifier` : `com.jeremyfrere.Captioneer`.
- Dépôt / Pages : `github.com/jerefrer/captioneer`, `jerefrer.github.io/captioneer`.

## État / ce qui a été vérifié

- ✅ **Migration depuis CaptionExtractor/Imprint → Captioneer (2026-06-08)** :
  module Swift, bundle ID, scripts, CI, site, README, doc renommés ; reliquats
  de l'app inverse (`stamping`/`stamped`/`readingSheet`/`sheetName`,
  parse_sheet.pl, erreurs `noSheetFound`/`multipleSheets`) supprimés.
- ✅ `swift build -c release --arch arm64` : compile, 0 warning, binaire `Captioneer`.
- ✅ `./build_app.sh --no-sign` : bundle + DMG assemblés de bout en bout, icône
  régénérée via le nouveau glob.
- ⚠️ **Pas re-testé** : extraction sur de vrais TIFF depuis cette migration
  (la logique d'extraction n'a pas changé, seulement les noms). Pipeline de
  signature/notarisation **non rejoué** depuis le rename.
- ⚠️ Le dépôt n'a **pas encore de remote git** configuré.

## TODO / pistes d'évolution

- [ ] **Nouvelle icône** : variante « extraction » de l'univers polaroid (traits
      de plume qui sortent de la photo). Déposer le 1024×1024 dans
      `Captioneer.icon/Assets/` (n'importe quel nom .png/.jpg) → régénérée au build.
      Mettre aussi à jour `docs/icon.png` et `docs/screenshot.png`.
- [ ] Créer le dépôt GitHub `jerefrer/captioneer` + activer GitHub Pages (docs/).
- [ ] Re-tester extraction sur de vrais fichiers + rejouer le build signé/notarisé.
- [ ] Universal binary (arm64 + x86_64) pour les Macs Intel.
- [ ] Colonnes optionnelles en sortie (mots-clés, titre, auteur/copyright).

## Notes de contexte

- Le dossier `IGNORE/` (gitignoré) contient des données de test/légendes, pas
  l'app — à ignorer lors des recherches de reliquats.
- Préférences de l'utilisateur (Jeremy) : réponses concises et directes.
