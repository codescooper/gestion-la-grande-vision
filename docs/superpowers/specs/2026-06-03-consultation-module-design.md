# Spec — Améliorations sauvegarde + Module de consultation

- **Date** : 2026-06-03
- **App** : `la-grande-vision.html` (mono-fichier HTML/CSS/JS, données en `localStorage`, PDF via jsPDF)
- **Statut** : validé, prêt pour plan d'implémentation

## Objectif

1. Renforcer la robustesse des données (sauvegarde/import).
2. Ajouter un **module de consultation** : un parcours guidé en 5 étapes qui enchaîne, en un seul flux, client → prescription → devis → acompte → PDF de facture proforma.

## Contraintes & principes

- **Un seul fichier** : tout le code reste dans `la-grande-vision.html`. Pas de build, pas de dépendance ajoutée.
- **Réutilisation maximale** : on s'appuie sur les fonctions et l'état globaux existants plutôt que de dupliquer.
- **Design system Nocturne** : réutiliser les classes existantes (`card`, `btn`, `glow-rule`, `chip`, `pill-select`, `form-grid`, `badge`, etc.). Pas de nouvelle direction visuelle.
- **Pas de régression** : les modales clients / prescriptions / factures existantes continuent de fonctionner à l'identique.

## État global réutilisé (existant, ne pas dupliquer)

| Élément | Rôle |
|---|---|
| `factureLignes` (var globale) | tableau des lignes du devis courant |
| `renderLignes / addLigne / updateLigne / removeLigne / updateTotal` | gestion des lignes, pilotées par les IDs DOM `#lignesContainer`, `#totalDisplay` |
| `updateAssuranceBreakdown` | lit `#f_assurance`, écrit dans `#assuranceBreakdown` |
| `currentPrescState` + `chipGroupHtml / toggleChipSingle / toggleChipMulti` | chips de prescription (type_verre, materiau, coloration, traitements) |
| `getPrice(group, value)`, `prescLabel(group, value)`, `PRESC_OPTIONS` | tarification & libellés prescription |
| `PAYMENT_MODES`, `modeLabel` | modes de règlement |
| `nextFactureNumero()` | numérotation `PRO-AAAA-NNNN` |
| `generatePDF(id)` | PDF d'une facture **persistée** |
| `findClient / findPrescription / findFacture`, `fmtFCFA / fmtDate / escapeHtml`, `toast`, `refreshIcons` | utilitaires |
| `DB.get/set/uid`, `saveSettings`, `seedData` | persistance |

---

# Partie A — Améliorations sauvegarde

## A1. Sauvegarde de sécurité avant import

**Refactor** : extraire deux helpers depuis l'actuel `exportData()` :

- `buildBackupPayload()` → renvoie l'objet `{ format, version, exported_at, data:{clients, prescriptions, factures, settings} }`.
- `downloadBackup(payload, filename)` → sérialise, crée le Blob, déclenche le téléchargement, `revokeObjectURL`.

`exportData()` devient : `downloadBackup(buildBackupPayload(), 'sauvegarde-grande-vision-<date>.json')` + maj `lgv_last_backup` + toast.

**Dans `importData()`** : après validation et **après** le `confirm()` accepté, **avant** d'écraser les données, appeler
`downloadBackup(buildBackupPayload(), 'securite-avant-import-<date>.json')`.
→ l'utilisateur récupère automatiquement un instantané de l'état qu'il s'apprête à remplacer.

## A2. Migration de version à l'import

Constantes : `BACKUP_VERSION = 1` (déjà présent).

Nouvelle fonction `migrateBackup(parsed)` appelée dans `importData` juste après la validation de forme :

1. Si `parsed.version` absent → considérer `0` (legacy).
2. Sur `parsed.data.settings` : si présent, **fusionner** les tarifs par défaut manquants — pour chaque groupe/clé de `DEFAULT_PRICES`, si `settings.prices[group][key]` n'est pas un nombre, prendre la valeur par défaut. Cela évite qu'une sauvegarde antérieure (faite avant l'ajout d'un nouveau tarif dans le code) n'efface l'option.
3. Garantir `settings.insurances` en tableau (sinon `[]`).
4. Renvoyer le `parsed` migré.

> Le format est volontairement tolérant et ascendant : un fichier `version:0`/`1` reste importable.

## A3. Rappel de sauvegarde

- Clé `localStorage` : `lgv_last_backup` (ISO string), écrite à chaque `exportData()` **et** à chaque `downloadBackup` de sécurité.
- Au chargement de l'app (après `seedData`), `checkBackupReminder()` applique **une seule règle** :
  afficher le rappel **si** au moins un de `clients / prescriptions / factures` contient des données **et** (`lgv_last_backup` absent **ou** ancienneté > 7 jours). Sinon, silencieux.
  - afficher un **bandeau discret** (style carte/`badge`) en haut de la zone principale, refermable (bouton ×), avec un bouton « Exporter maintenant » → `exportData()`. La fermeture ne réarme pas avant la prochaine session (drapeau en mémoire, non persisté).
- Dans la carte « Sauvegarde & restauration » des Paramètres : afficher « Dernière sauvegarde : <date> » (ou « jamais »).

## A4. Export comptable CSV

- Bouton **« Export comptable (CSV) »** dans l'en-tête de la page Factures (à côté de « Nouvelle facture »).
- `exportFacturesCSV()` :
  - colonnes : `N°; Date; Client; Total; Assurance; % couvert; Montant couvert; Part patient; Encaissé; Reste; Statut paiement; Livré`.
  - valeurs calculées via `factureCouvert`, `facturePatientPart`, `versementsTotal`, `factureReste`, `factureStatutPaiement`, `livraisonBadge` (texte).
  - séparateur `;`, **BOM UTF-8** (`﻿`) en tête pour Excel FR, échappement des `"` et des valeurs contenant `;`/retour ligne.
  - montants en nombres bruts (sans « FCFA ») pour exploitation tableur.
  - nom de fichier `factures-grande-vision-<date>.csv`.
  - si aucune facture → toast d'info, pas de téléchargement.

---

# Partie B — Module de consultation (wizard 5 étapes)

## Entrée & navigation

- **Sidebar** : nouvel item entre « Factures proforma » et la section Configuration :
  `<button class="nav-item" data-page="consultation" onclick="navTo('consultation')">` icône `clipboard-list`, libellé « Consultation ».
- **Tableau de bord** : bouton « Nouvelle consultation » (en plus de « Nouveau client »).
- **Démarrage / continuation** (règle retenue, sans perte de données) :
  - Bouton « Nouvelle consultation » (dashboard) → `startConsultation()` : `consultation = null` puis `navTo('consultation')` → **brouillon neuf**.
  - Item « Consultation » (sidebar) → `navTo('consultation')` → `renderConsultation()` **continue** le brouillon en cours s'il existe, sinon en crée un neuf.
  - Le brouillon vit en mémoire : naviguer ailleurs puis revenir ne le détruit pas. Il n'est effacé que par la **finalisation** ou le bouton **« Annuler la consultation »** (confirm) dans l'en-tête du wizard.
- Nouvelle section dans le HTML : `<section id="page-consultation" class="page hidden"> … </section>` avec un conteneur `#consultationContent`.
- `navTo` : ajouter `if (page === 'consultation') renderConsultation();`.

## État (en mémoire uniquement — rien n'est persisté avant la finalisation)

```js
let consultation = null; // null tant que pas démarrée

function newConsultation() {
  return {
    step: 1,                 // 1..5
    clientMode: 'existing',  // 'existing' | 'new'
    clientId: '',            // si existant
    newClient: { nom:'', prenom:'', telephone:'', email:'', date_naissance:'', notes:'' },
    presc: { date:<today>, od_sph:'',od_cyl:'',od_axe:'',od_add:'',
             og_sph:'',og_cyl:'',og_axe:'',og_add:'', specs_libres:'', notes:'' },
    // type_verre/materiau/coloration/traitements vivent dans currentPrescState (réutilisé)
    lignes: [],              // miroir de factureLignes
    assuranceId: '',         // valeur du select assurance
    withVersement: false,
    versement: { montant:'', date:<today>, mode:'especes', reference:'', notes:'' }
  };
}
```

> **Abandon** : le bouton « Annuler la consultation » (confirm) remet `consultation = null` et renvoie au tableau de bord. Rien n'est persisté tant que la finalisation n'a pas eu lieu → aucun enregistrement orphelin.

## Stepper

- Indicateur horizontal 5 étapes (`1 Client · 2 Prescription · 3 Devis · 4 Acompte · 5 Récapitulatif`), étape courante mise en avant (accent bleu), étapes passées marquées « ✓ ». Réutilise `glow-rule`.
- Footer d'actions : **Précédent** (masqué à l'étape 1), **Continuer** (étapes 1-4) / **Finaliser et générer le PDF** (étape 5).
- `goToStep(n)` : avant d'avancer, `captureStep(current)` (lit le DOM → `consultation`) puis `validateStep(current)`. Reculer ne valide pas mais capture.

## Étape 1 — Client

- Bascule « Client existant » / « Nouveau client » (`pill-select` ou deux boutons).
- **Existant** : `<select id="cons_client">` recherchable (liste triée des clients) ; option vide par défaut.
- **Nouveau** : champs identiques à `modalClient` avec IDs préfixés `cons_c_*` (nom*, prénom, téléphone, email, naissance, notes), valeurs liées à `consultation.newClient`.
- **Validation** : mode existant → un client sélectionné ; mode nouveau → `nom` non vide. Sinon toast erreur, on reste.

## Étape 2 — Prescription (optionnelle)

- Champs identiques à `modalPrescription`, IDs préfixés `cons_p_*` (date, OD/OG SPH/CYL/AXE/ADD, specs_libres, notes).
- Chips : réutilise `chipGroupHtml('type_verre',false)` etc. ; `currentPrescState` est (ré)initialisé à l'entrée de l'étape depuis `consultation` (et inversement capturé via les chips, déjà géré par `toggleChip*`).
- Aucune validation bloquante (une consultation peut être un simple devis). `captureStep(2)` recopie les champs texte dans `consultation.presc`.

## Étape 3 — Devis

- **Réutilisation directe** : le HTML rend les mêmes IDs que la modale facture :
  - `<select id="f_assurance" onchange="updateAssuranceBreakdown()">` (mêmes options que `modalFacture`, + valeur `consultation.assuranceId` présélectionnée),
  - `<div id="lignesContainer">`, `<div class="total-bar"><div id="totalDisplay">`, `<div id="assuranceBreakdown" class="hidden">`.
- À l'entrée de l'étape : `factureLignes = consultation.lignes.length ? clone : [ligne vide]` puis `renderLignes()`.
- Bouton **« Importer la prescription (tarifs auto) »** → `importLignesFromDraftPrescription()` :
  - construit les lignes depuis la prescription **brouillon** (`currentPrescState` + `consultation.presc`) avec la même logique que `importLignesFromPrescription` (groupes type_verre→verre, materiau→verre, coloration→traitement, traitements[]→traitement ; `getPrice` > 0 ; libellés `prescLabel(...).toUpperCase()`),
  - même règle de remplacement si lignes vides, puis `renderLignes()` + toast.
- `addLigne / updateLigne / removeLigne / updateTotal / updateAssuranceBreakdown` réutilisés **sans modification**.
- `captureStep(3)` : `consultation.lignes = clone(factureLignes)` ; `consultation.assuranceId = #f_assurance.value`.
- **Validation** : ≥ 1 ligne avec `designation` non vide **et** `montant > 0` (même règle que `saveFacture`).

## Étape 4 — Acompte (optionnel)

- Bascule « Ajouter un acompte maintenant » (`consultation.withVersement`).
- Si activé : champs `cons_v_*` (montant, date=aujourd'hui, mode via `PAYMENT_MODES`, référence, notes) + rappel du total / part patient (calculé depuis `consultation.lignes` et l'assurance choisie).
- Validation : si activé et `montant <= 0` → toast erreur. Si désactivé → rien. Avertissement non bloquant si montant > part patient.

## Étape 5 — Récapitulatif

- Carte lecture seule : identité client, specs prescription (`formatPrescSpecs` sur un objet reconstruit), tableau des lignes + total, breakdown assurance, acompte & reste.
- Boutons : **Précédent** + **Finaliser et générer le PDF**.

## Finalisation — `finalizeConsultation()`

Ordre (avec garde-fous) :

1. **Client** : si `clientMode==='new'` → valider `nom`, `clients.push({id:DB.uid(), ...newClient, nom:UPPER, created_at})`, `DB.set('lgv_clients')`. `clientId` = id résultant. Sinon `clientId = consultation.clientId` (revalider non vide).
2. **Prescription** : si la prescription contient au moins une donnée significative (un champ OD/OG rempli, une chip, ou specs_libres) → `prescriptions.push({id, client_id:clientId, date_consultation, od_*, og_*, type_verre/materiau/coloration/traitements (depuis currentPrescState), specs_libres, notes})`, `DB.set`. Sinon `prescriptionId = null`.
3. **Facture** : filtrer `validLignes` (même règle), `total = somme`, snapshot `assurance` recalculé depuis l'option `#f_assurance`/settings (mêmes champs que `saveFacture` : `id, nom, couverture_pct, montant_couvert, montant_patient`), `numero = nextFactureNumero()`, `statut:'finalisee'`, `versements:[]`, `livraison:{livre:false}`, `created_at`. `factures.push(...)`, `DB.set`.
4. **Acompte** : si `withVersement` et `montant>0` → push `{id, date, montant, mode, reference, notes, created_at}` dans `facture.versements`, `DB.set`.
5. `generatePDF(factureId)`.
6. `toast('Consultation finalisée ✓')`, `consultation = null`, `renderDashboard()`, `navTo('factures')`.

## Validation récap

| Étape | Règle bloquante |
|---|---|
| 1 Client | existant sélectionné **ou** nouveau avec `nom` |
| 2 Prescription | aucune |
| 3 Devis | ≥ 1 ligne valide (désignation + montant>0) |
| 4 Acompte | si activé : montant > 0 |
| 5 Récap | — (finalise) |

## Risque connu & décision

`factureLignes`, `currentPrescState`, `updateAssuranceBreakdown` (lit `#f_assurance`) sont **globaux et basés sur des IDs DOM**. Le wizard réutilise volontairement ces IDs à l'étape 3. La modale facture et le wizard ne sont **jamais ouverts simultanément** (le wizard est une page ; toute navigation ferme les modales). → partage d'état acceptable, pas de duplication de logique.

## Découpage en unités (pour le plan)

1. **A — Refactor sauvegarde** : `buildBackupPayload`, `downloadBackup`, refonte `exportData`/`importData`, `migrateBackup`, `lgv_last_backup`.
2. **A — Rappel** : `checkBackupReminder` + bandeau + ligne « Dernière sauvegarde » dans Paramètres.
3. **A — CSV** : `exportFacturesCSV` + bouton page Factures.
4. **B — Coquille wizard** : section HTML `page-consultation`, item sidebar, bouton dashboard, `renderConsultation`, stepper, `goToStep`, `captureStep`, `validateStep`, état `consultation`.
5. **B — Étapes 1→2** : rendu + capture client & prescription.
6. **B — Étape 3** : rendu devis réutilisant lignes/assurance + `importLignesFromDraftPrescription`.
7. **B — Étapes 4→5** : acompte + récap.
8. **B — Finalisation** : `finalizeConsultation`.
9. **Vérification navigateur** : aller-retour complet d'une consultation → facture + PDF, + non-régression modales existantes.

## Critères de succès

- Une consultation complète (nouveau client + prescription + devis + acompte) produit un client, une prescription liée, une facture `PRO-AAAA-NNNN` avec acompte, et télécharge le PDF — le tout depuis un seul parcours.
- Abandon en cours de wizard → aucune donnée persistée.
- Import déclenche une sauvegarde de sécurité automatique et gère les anciens formats.
- Export CSV ouvrable dans Excel FR avec accents corrects.
- Aucune régression des modales clients/prescriptions/factures.
- Aucune erreur console.
