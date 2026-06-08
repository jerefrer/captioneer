# CaptionExtractor

Une application macOS native qui permet d'extraire les légendes (descriptions) de photos (TIF, JPG, PNG) et de générer un fichier CSV compatible Excel.

## Utilisation

1. Glissez-déposez un dossier contenant vos images ou une sélection d'images directement dans l'application.
2. L'application lira les métadonnées de vos images via ExifTool.
3. Un fichier `Extraction.csv` sera généré au même endroit avec deux colonnes : le nom du fichier et sa légende.

Vous pouvez ouvrir ce fichier directement dans Excel.

## Action Rapide (Clic droit)

Vous pouvez créer une Action Rapide dans macOS pour extraire les légendes directement depuis le Finder :

1. Ouvrez l'application **Raccourcis** (Shortcuts) sur votre Mac.
2. Cliquez sur le bouton **+** pour créer un nouveau raccourci.
3. Dans les réglages du raccourci (icône "i" à droite), cochez **Utiliser comme action rapide** et sélectionnez **Finder**.
4. Configurez-le pour recevoir **Fichiers et dossiers** (Files and Folders).
5. Ajoutez l'action **Ouvrir un fichier** (Open File).
6. Configurez l'action pour ouvrir le fichier de l'entrée du raccourci avec l'application **CaptionExtractor**.
7. Enregistrez le raccourci sous le nom "Extraire les légendes" (Extract Captions).

Désormais, vous pouvez faire un clic droit sur un dossier ou une sélection de fichiers dans le Finder > **Actions rapides** > **Extraire les légendes**.
