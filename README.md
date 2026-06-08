# Captioneer

Une application macOS native qui **extrait les légendes (descriptions) de vos photos**
(TIFF, JPEG, PNG) à partir de leurs métadonnées et les rassemble dans un
**fichier Excel** prêt à ouvrir.

C'est l'inverse d'un outil d'estampillage : ici on *lit* ce qui est déjà dans
les images et on le recopie dans un tableur.

## Utilisation

1. Glissez-déposez un dossier d'images (ou une sélection de fichiers)
   directement dans l'application — ou cliquez pour les choisir.
2. Captioneer lit les métadonnées de chaque image via ExifTool.
3. Un fichier **`Extraction.xlsx`** est généré au même endroit, avec deux
   colonnes : le nom du fichier et sa légende.

Ouvrez-le directement dans Excel, Numbers ou LibreOffice.

### Quelle légende est extraite ?

Pour chaque image, Captioneer prend la **première valeur non vide** dans cet
ordre de préférence :

1. `XMP-dc:Description`
2. `IPTC:Caption-Abstract`
3. `EXIF:ImageDescription`
4. `Title`

Les légendes multi-paragraphes et bilingues (EN/FR) sont conservées telles
quelles, sauts de ligne et accents inclus. Les photos sans aucune légende
apparaissent quand même, avec une description vide.

## Action Rapide (clic droit dans le Finder)

Vous pouvez créer une Action Rapide macOS pour extraire les légendes
directement depuis le Finder :

1. Ouvrez l'application **Raccourcis** (Shortcuts).
2. Créez un nouveau raccourci (**+**).
3. Dans les réglages (icône « i »), cochez **Utiliser comme action rapide** et
   sélectionnez **Finder**.
4. Configurez-le pour recevoir **Fichiers et dossiers**.
5. Ajoutez l'action **Ouvrir un fichier** (Open File).
6. Faites ouvrir le fichier de l'entrée avec l'application **Captioneer**.
7. Enregistrez sous le nom « Extraire les légendes ».

Désormais : clic droit sur un dossier ou une sélection > **Actions rapides** >
**Extraire les légendes**.

## Installation

Téléchargez le dernier `Captioneer.dmg` depuis la
[page des releases](https://github.com/jerefrer/captioneer/releases/latest),
glissez l'app dans **Applications**, lancez. L'app est signée Developer ID +
notarisée : aucun avertissement Gatekeeper.

Cible : Apple Silicon (M1/M2/M3/M4), macOS 14+.
