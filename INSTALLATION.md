# La Grande Vision — Installation sur le poste

Application de gestion optique. Tout fonctionne **en local**, sans Internet (sauf le
chargement des icônes). Les données restent sur **ce poste**, dans le navigateur.

## Pourquoi un petit serveur local ?

L'application peut s'ouvrir de deux façons :

| Méthode | Adresse | Sauvegarde auto vers un dossier |
|---|---|---|
| Double-clic sur le fichier HTML | `file://…` | ⚠️ le navigateur peut redemander l'autorisation du dossier à chaque ouverture |
| **Lanceur (recommandé)** | `http://localhost:8765` | ✅ origine stable → autorisation mémorisée de façon fiable |

Le serveur local n'expose **rien** sur le réseau : il écoute uniquement sur `127.0.0.1`
(cette machine). Aucune installation n'est nécessaire — il utilise PowerShell, déjà
présent dans Windows.

## Démarrer l'application

1. Gardez **tous les fichiers dans le même dossier** (`la-grande-vision.html`, `serve.ps1`,
   `Lancer La Grande Vision.bat`).
2. Double-cliquez sur **`Lancer La Grande Vision.bat`**.
3. Une petite fenêtre « Serveur La Grande Vision » s'ouvre (réduite) **et** le navigateur
   ouvre l'application automatiquement.
4. **Ne fermez pas** la fenêtre du serveur pendant l'utilisation — réduisez-la simplement.
   La fermer arrête le serveur (et donc l'application).

> Si Windows propose plusieurs navigateurs, choisissez **Chrome** ou **Edge**
> (nécessaires pour la sauvegarde automatique vers un dossier).

## Activer la sauvegarde automatique (à faire une fois)

1. Dans l'application : menu **Paramètres** → carte **« Sauvegarde automatique »**.
2. Cliquez sur **« Choisir un dossier de sauvegarde »**.
3. Choisissez de préférence un dossier **synchronisé OneDrive ou Google Drive**
   → la sauvegarde devient automatiquement **cloud** (protégée même en cas de panne du PC).
4. À partir de là, l'application réécrit `sauvegarde-grande-vision-auto.json` dans ce dossier
   **à chaque modification** et à la fermeture de l'onglet.

L'export manuel (bouton « Exporter une sauvegarde ») reste toujours disponible en complément.

## (Optionnel) Lancer automatiquement au démarrage de Windows

1. Faites un clic droit sur `Lancer La Grande Vision.bat` → **Créer un raccourci**.
2. Appuyez sur `Windows + R`, tapez `shell:startup`, validez.
3. Déplacez le raccourci dans le dossier qui s'ouvre.

L'application se lancera à chaque ouverture de session Windows.

## Important — changement d'adresse et données

Les données du navigateur sont **séparées par adresse**. Si vous aviez déjà saisi des
informations en ouvrant le fichier en `file://`, elles **n'apparaîtront pas** sous
`http://localhost:8765` (et inversement).

Pour transférer des données existantes : ouvrez l'ancienne version, **Exporter une
sauvegarde**, puis dans la nouvelle (via le lanceur) **Importer une sauvegarde**.

Pour une nouvelle installation, il n'y a rien à faire : l'application démarre à vide.

## Démonstration

Pour afficher des données de démonstration (formation, présentation) sans toucher à une
vraie base, ouvrez :

```
http://localhost:8765/la-grande-vision.html?demo
```

## En cas de souci

- **« Le port est déjà utilisé »** : une fenêtre serveur est déjà ouverte. Utilisez-la, ou
  fermez-la puis relancez.
- **La sauvegarde auto redemande l'autorisation** : cliquez une fois sur
  « Sauvegarder maintenant » dans Paramètres pour ré-autoriser le dossier.
- **Rien ne s'ouvre** : ouvrez manuellement le navigateur à l'adresse
  `http://localhost:8765/la-grande-vision.html`.
