# Améliorations sauvegarde + Module de consultation — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter 4 améliorations de sauvegarde (sécurité avant import, migration, rappel, export CSV) et un module de consultation en wizard 5 étapes (client → prescription → devis → acompte → PDF) dans `la-grande-vision.html`.

**Architecture:** Application mono-fichier HTML/CSS/JS, données en `localStorage`, PDF via jsPDF. Tout le nouveau code reste dans `la-grande-vision.html`. Le wizard est une **page** (`#page-consultation`) qui réutilise l'état global existant (`factureLignes`, `currentPrescState`) et les fonctions de lignes/assurance/PDF, en réemployant les mêmes IDs DOM (`#lignesContainer`, `#totalDisplay`, `#assuranceBreakdown`, `#f_assurance`). Rien n'est persisté avant la finalisation.

**Tech Stack:** HTML, CSS (design system Nocturne existant), JavaScript vanilla, jsPDF (déjà chargé), `localStorage`.

**⚠️ Vérification = navigateur, pas pytest.** Ce projet n'a aucun framework de test ni build. La vérification se fait via **Chrome DevTools MCP** :
- `mcp__chrome__navigate_page` (url/reload), `mcp__chrome__evaluate_script` (assertions sur l'état JS / `localStorage`), `mcp__chrome__take_snapshot` (UI), `mcp__chrome__list_console_messages` (filtre `error`/`warn`).
- URL de l'app : `file:///C:/Users/USER/Documents/GrandeVision/gestion%20la%20grande%20vision/la-grande-vision.html`
- **Avant chaque vérification UI** : recharger avec `ignoreCache: true`.
- **Reset propre des données de démo entre tests** : `evaluate_script` → `['lgv_clients','lgv_prescriptions','lgv_factures','lgv_settings','lgv_last_backup'].forEach(k=>localStorage.removeItem(k)); 'cleared'` puis reload (re-seed automatique).
- **Téléchargements** : on ne teste pas le fichier téléchargé sur disque ; on teste les **fonctions de construction** (`buildBackupPayload`, le contenu CSV) en appelant la logique via `evaluate_script` et en inspectant la valeur renvoyée, et on vérifie l'absence d'erreur console après un appel réel.

**Commits :** dépôt git déjà initialisé. Un commit par tâche. Terminer chaque message par :
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
Sur Windows, git affiche `LF will be replaced by CRLF` — avertissement normal, à ignorer.

---

## Structure des fichiers

| Fichier | Responsabilité | Action |
|---|---|---|
| `la-grande-vision.html` | toute l'app (HTML + `<style>` + `<script>`) | Modifié par chaque tâche |
| `docs/superpowers/specs/2026-06-03-consultation-module-design.md` | spec validée | Référence (lecture seule) |

Tout est dans un seul fichier ; les tâches se repèrent par des **ancres textuelles uniques** (chaînes exactes à passer à l'outil Edit).

---

## Task 1 : Refactor sauvegarde + sécurité avant import + migration

**Files:**
- Modify: `la-grande-vision.html` (bloc `exportData`/`importData`, section `// ========== SAUVEGARDE / RESTAURATION ==========`)

- [ ] **Step 1 : Remplacer `exportData` par les helpers + nouvel `exportData`**

Edit — remplacer **tout** le bloc actuel allant de `function exportData() {` jusqu'à sa fermeture `}` (juste avant `function importData(input) {`). Ancre `old_string` = depuis `    function exportData() {` jusqu'à la ligne `      toast('Sauvegarde exportée');\n    }`. Nouveau contenu :

```js
    function buildBackupPayload() {
      return {
        format: BACKUP_FORMAT,
        version: BACKUP_VERSION,
        exported_at: new Date().toISOString(),
        data: {
          clients: clients,
          prescriptions: prescriptions,
          factures: factures,
          settings: settings
        }
      };
    }

    function downloadBackup(payload, filename) {
      const json = JSON.stringify(payload, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      localStorage.setItem('lgv_last_backup', new Date().toISOString());
    }

    function exportData() {
      const today = new Date().toISOString().split('T')[0];
      downloadBackup(buildBackupPayload(), `sauvegarde-grande-vision-${today}.json`);
      toast('Sauvegarde exportée');
    }

    function migrateBackup(parsed) {
      const s = parsed.data.settings;
      if (s && typeof s === 'object') {
        if (!s.prices) s.prices = JSON.parse(JSON.stringify(DEFAULT_PRICES));
        for (const g in DEFAULT_PRICES) {
          if (!s.prices[g]) s.prices[g] = {};
          for (const k in DEFAULT_PRICES[g]) {
            if (typeof s.prices[g][k] !== 'number') s.prices[g][k] = DEFAULT_PRICES[g][k];
          }
        }
        if (!Array.isArray(s.insurances)) s.insurances = [];
      }
      return parsed;
    }
```

- [ ] **Step 2 : Mettre à jour `importData` (sécurité + migration)**

Edit — dans `importData`, remplacer le bloc qui va de `        const ok = confirm(` jusqu'à la fin du bloc `if (d.settings ...) { ... saveSettings(); }`. Ancre `old_string` = de `        const ok = confirm(` à :
```
        if (d.settings && typeof d.settings === 'object') {
          settings = d.settings;
          if (!settings.prices) settings.prices = JSON.parse(JSON.stringify(DEFAULT_PRICES));
          if (!Array.isArray(settings.insurances)) settings.insurances = [];
          saveSettings();
        }
```
Nouveau contenu :
```js
        const dateLabel2 = parsed.exported_at ? fmtDate(parsed.exported_at) : 'inconnue';
        const ok = confirm(
          `Importer cette sauvegarde du ${dateLabel2} ?\n\n` +
          `• ${d.clients.length} client(s)\n` +
          `• ${d.prescriptions.length} prescription(s)\n` +
          `• ${d.factures.length} facture(s)\n\n` +
          `⚠ Toutes les données actuelles seront définitivement remplacées.\n` +
          `Une sauvegarde de sécurité de vos données actuelles va d'abord être téléchargée.`
        );
        if (!ok) { input.value = ''; return; }

        // Sauvegarde de sécurité AVANT écrasement
        const today2 = new Date().toISOString().split('T')[0];
        downloadBackup(buildBackupPayload(), `securite-avant-import-${today2}.json`);

        // Migration ascendante du fichier importé
        migrateBackup(parsed);

        clients = d.clients;
        prescriptions = d.prescriptions;
        factures = d.factures;
        DB.set('lgv_clients', clients);
        DB.set('lgv_prescriptions', prescriptions);
        DB.set('lgv_factures', factures);

        if (d.settings && typeof d.settings === 'object') {
          settings = d.settings;
          saveSettings();
        }
```
> Note : la ligne d'origine `const dateLabel = ...` reste juste au-dessus mais n'est plus utilisée — la remplacer fait partie de cet `old_string` ? Non : l'ancre commence à `const ok = confirm(`. La variable `dateLabel` précédente devient inutilisée. Pour éviter une variable morte, **inclure aussi** la ligne `        const dateLabel = parsed.exported_at ? fmtDate(parsed.exported_at) : 'inconnue';` dans l'`old_string` (elle est juste avant `const ok`), de sorte qu'elle soit retirée et remplacée par `dateLabel2`.

- [ ] **Step 3 : Vérifier (navigateur) — helpers présents, migration, pas d'erreur**

`mcp__chrome__navigate_page` reload `ignoreCache:true`, puis `evaluate_script` :
```js
() => {
  const r = {};
  r.helpers = ['buildBackupPayload','downloadBackup','exportData','migrateBackup','importData'].every(f => typeof window[f] === 'function');
  const p = buildBackupPayload();
  r.payloadOk = p.format === BACKUP_FORMAT && p.version === BACKUP_VERSION && !!p.data.clients;
  // migration : settings sans un tarif -> doit être recomplété
  const fake = { version: 0, data: { settings: { prices: { type_verre: {} }, insurances: 'pas-un-tableau' } } };
  migrateBackup(fake);
  r.migratedPrice = fake.data.settings.prices.type_verre.unifocaux === DEFAULT_PRICES.type_verre.unifocaux;
  r.migratedInsurances = Array.isArray(fake.data.settings.insurances);
  return r;
}
```
Attendu : `{helpers:true, payloadOk:true, migratedPrice:true, migratedInsurances:true}`.
Puis `list_console_messages` filtre `["error","warn"]` → aucun message.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(backup): helpers buildBackupPayload/downloadBackup, sauvegarde de sécurité avant import et migration de version"
```

---

## Task 2 : Rappel de sauvegarde + « Dernière sauvegarde » dans Paramètres

**Files:**
- Modify: `la-grande-vision.html` (bloc `<style>` ; `<main class="main">` ; `renderSettings` ; section INIT ; section SAUVEGARDE)

- [ ] **Step 1 : CSS du bandeau**

Edit — ancre `old_string` = `    .hidden { display: none !important; }` ; `new_string` = la même ligne suivie de :
```css

    .backup-reminder {
      display: flex; align-items: center; gap: 0.75rem;
      background: rgba(240,182,90,.08);
      border: 1px solid rgba(240,182,90,.45);
      border-radius: var(--r-lg);
      padding: 0.75rem 1rem; margin-bottom: 1.25rem;
      color: var(--lgv-bone); font-size: 13px;
    }
    .backup-reminder i { color: var(--lgv-warning); flex-shrink: 0; }
    .backup-reminder span { flex: 1; }
    .backup-reminder-close {
      background: none; border: none; color: var(--lgv-haze);
      cursor: pointer; padding: 0.25rem; display: inline-flex;
    }
    .backup-reminder-close:hover { color: var(--lgv-bone); }
```

- [ ] **Step 2 : Conteneur du bandeau dans `<main>`**

Edit — ancre `old_string` = `    <main class="main">\n      <section id="page-dashboard" class="page">` ; `new_string` insère le conteneur juste après `<main class="main">` :
```html
    <main class="main">
      <div id="backupReminder" class="hidden"></div>
      <section id="page-dashboard" class="page">
```

- [ ] **Step 3 : Fonctions `checkBackupReminder` / `dismissBackupReminder`**

Edit — ancre `old_string` = `    function migrateBackup(parsed) {` ; insérer **avant** cette ligne le bloc suivant (puis reremettre `function migrateBackup(parsed) {`) :
```js
    let backupReminderDismissed = false;

    function checkBackupReminder() {
      const el = document.getElementById('backupReminder');
      if (!el) return;
      const hasData = clients.length || prescriptions.length || factures.length;
      const last = localStorage.getItem('lgv_last_backup');
      const stale = !last || (Date.now() - new Date(last).getTime()) > 7 * 24 * 60 * 60 * 1000;
      if (backupReminderDismissed || !hasData || !stale) {
        el.classList.add('hidden'); el.innerHTML = ''; return;
      }
      el.classList.remove('hidden');
      el.className = 'backup-reminder';
      el.innerHTML = `
        <i data-lucide="shield-alert"></i>
        <span>Pensez à exporter une sauvegarde de vos données${last ? ' — dernière : ' + fmtDate(last) : ' — aucune sauvegarde enregistrée'}.</span>
        <button class="btn btn-secondary btn-sm" type="button" onclick="exportData(); checkBackupReminder();">Exporter maintenant</button>
        <button class="backup-reminder-close" type="button" title="Fermer" onclick="dismissBackupReminder()"><i data-lucide="x"></i></button>
      `;
      refreshIcons();
    }

    function dismissBackupReminder() {
      backupReminderDismissed = true;
      const el = document.getElementById('backupReminder');
      if (el) { el.classList.add('hidden'); el.innerHTML = ''; }
    }

```

- [ ] **Step 4 : Appeler `checkBackupReminder()` à l'init**

Edit — ancre `old_string` :
```
    // ========== INIT ==========
    updateOnlineStatus();
    renderDashboard();
    refreshIcons();
```
`new_string` :
```
    // ========== INIT ==========
    updateOnlineStatus();
    renderDashboard();
    checkBackupReminder();
    refreshIcons();
```

- [ ] **Step 5 : Ligne « Dernière sauvegarde » dans la carte Paramètres**

Edit — dans `renderSettings`, ancre `old_string` :
```
            <br><span style="color:var(--lgv-haze);">État actuel : ${counts}</span>
          </p>
```
`new_string` :
```
            <br><span style="color:var(--lgv-haze);">État actuel : ${counts}</span>
            <br><span style="color:var(--lgv-haze);">Dernière sauvegarde : ${localStorage.getItem('lgv_last_backup') ? fmtDate(localStorage.getItem('lgv_last_backup')) : 'jamais'}</span>
          </p>
```

- [ ] **Step 6 : Vérifier (navigateur)**

Reset données démo + reload `ignoreCache:true`. Puis `evaluate_script` :
```js
() => {
  const r = {};
  // données de démo présentes + jamais sauvegardé -> bandeau visible
  checkBackupReminder();
  const el = document.getElementById('backupReminder');
  r.shownWhenStale = !el.classList.contains('hidden') && /exporter/i.test(el.textContent);
  // après export simulé (maj last_backup récent) -> masqué
  localStorage.setItem('lgv_last_backup', new Date().toISOString());
  backupReminderDismissed = false;
  checkBackupReminder();
  r.hiddenWhenFresh = el.classList.contains('hidden');
  return r;
}
```
Attendu : `{shownWhenStale:true, hiddenWhenFresh:true}`. Console : aucun error/warn.

- [ ] **Step 7 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(backup): bandeau de rappel de sauvegarde + date de dernière sauvegarde dans Paramètres"
```

---

## Task 3 : Export comptable CSV

**Files:**
- Modify: `la-grande-vision.html` (en-tête `#page-factures` ; nouvelle fonction près de `exportData`)

- [ ] **Step 1 : Bouton CSV dans l'en-tête Factures**

Edit — ancre `old_string` :
```
          <button class="btn btn-primary" onclick="openModal('facture')">
            <i data-lucide="plus"></i>
            Nouvelle facture
          </button>
        </div>
        <div class="glow-rule page-rule"></div>
        <div class="search-bar">
          <input type="text" id="searchFactures" placeholder="Rechercher par numéro ou nom de client..." oninput="renderFactures()">
```
`new_string` :
```
          <div style="display:flex;gap:.5rem;flex-wrap:wrap;">
            <button class="btn btn-tertiary" onclick="exportFacturesCSV()">
              <i data-lucide="table"></i>
              Export comptable (CSV)
            </button>
            <button class="btn btn-primary" onclick="openModal('facture')">
              <i data-lucide="plus"></i>
              Nouvelle facture
            </button>
          </div>
        </div>
        <div class="glow-rule page-rule"></div>
        <div class="search-bar">
          <input type="text" id="searchFactures" placeholder="Rechercher par numéro ou nom de client..." oninput="renderFactures()">
```

- [ ] **Step 2 : Fonctions `csvCell` + `exportFacturesCSV`**

Edit — ancre `old_string` = `    function migrateBackup(parsed) {` ; insérer **avant** ce bloc (et le réécrire ensuite) :
```js
    function csvCell(v) {
      const s = String(v == null ? '' : v);
      return /[";\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    }

    function exportFacturesCSV() {
      if (!factures.length) { toast('Aucune facture à exporter', 'error'); return; }
      const header = ['N°','Date','Client','Total','Assurance','% couvert','Montant couvert','Part patient','Encaissé','Reste','Statut paiement','Livré'];
      const statutLabels = { solde: 'Soldé', partiel: 'Partiel', impaye: 'Impayé' };
      const rows = factures.slice()
        .sort((a, b) => (a.date_facture || '').localeCompare(b.date_facture || ''))
        .map(f => {
          const c = findClient(f.client_id);
          const nom = c ? `${c.nom} ${c.prenom || ''}`.trim() : '';
          return [
            f.numero || '',
            f.date_facture || '',
            nom,
            Number(f.total) || 0,
            f.assurance ? f.assurance.nom : '',
            f.assurance ? f.assurance.couverture_pct : 0,
            factureCouvert(f),
            facturePatientPart(f),
            versementsTotal(f),
            factureReste(f),
            statutLabels[factureStatutPaiement(f)] || '',
            f.livraison && f.livraison.livre ? 'Oui' : 'Non'
          ];
        });
      const csv = [header, ...rows].map(r => r.map(csvCell).join(';')).join('\r\n');
      const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const today = new Date().toISOString().split('T')[0];
      const a = document.createElement('a');
      a.href = url;
      a.download = `factures-grande-vision-${today}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      toast(`${rows.length} facture(s) exportée(s)`);
    }

```

- [ ] **Step 3 : Vérifier (navigateur)**

Reset démo + reload. `evaluate_script` (teste la **construction** du CSV sans télécharger, en répliquant la logique d'en-tête/lignes) :
```js
() => {
  const r = {};
  r.fnExists = typeof exportFacturesCSV === 'function' && typeof csvCell === 'function';
  r.escaping = csvCell('a;b') === '"a;b"' && csvCell('say "hi"') === '"say ""hi"""' && csvCell('plain') === 'plain';
  // construire les lignes comme le fait exportFacturesCSV
  const header = ['N°','Date','Client','Total','Assurance','% couvert','Montant couvert','Part patient','Encaissé','Reste','Statut paiement','Livré'];
  r.headerLen = header.length;
  r.dataRows = factures.length; // 1 en démo
  return r;
}
```
Attendu : `{fnExists:true, escaping:true, headerLen:12, dataRows:1}`.
Puis appel réel pour vérifier l'absence d'erreur : `evaluate_script` → `() => { exportFacturesCSV(); return 'ok'; }`, puis `list_console_messages` `["error","warn"]` → vide.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(factures): export comptable CSV (BOM UTF-8, séparateur ;)"
```

---

## Task 4 : Coquille du wizard (page, nav, stepper, navigation interne)

**Files:**
- Modify: `la-grande-vision.html` (CSS ; sidebar nav ; en-tête dashboard ; section `#page-consultation` ; `navTo` ; nouveau bloc `// ========== MODULE CONSULTATION ==========`)

- [ ] **Step 1 : CSS du wizard**

Edit — ancre `old_string` = `    .backup-reminder-close:hover { color: var(--lgv-bone); }` ; `new_string` = cette ligne suivie de :
```css

    /* ===== Wizard consultation ===== */
    .consult-stepper { display: flex; align-items: center; gap: 0; margin-bottom: 0.5rem; flex-wrap: wrap; }
    .consult-step { display: flex; align-items: center; gap: 0.5rem; opacity: 0.5; }
    .consult-step.active, .consult-step.done { opacity: 1; }
    .consult-step .cs-num {
      width: 26px; height: 26px; border-radius: 999px; display: inline-flex;
      align-items: center; justify-content: center; font-family: var(--lgv-font-mono);
      font-size: 12px; border: 1px solid var(--lgv-veil); color: var(--lgv-mist);
    }
    .consult-step.active .cs-num { background: var(--lgv-grad-blue); color: #fff; border-color: transparent; box-shadow: var(--lgv-glow-blue); }
    .consult-step.done .cs-num { border-color: var(--lgv-blue); color: var(--lgv-blue); }
    .consult-step .cs-label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.1em; }
    .cs-sep { flex: 1; min-width: 16px; height: 1px; background: var(--lgv-veil); margin: 0 0.5rem; }
    .consult-footer { display: flex; justify-content: space-between; align-items: center; margin-top: 1.25rem; gap: 1rem; }
    .consult-toggle { display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-size: 14px; }
    .consult-toggle input { width: auto; }
    .recap-row { display: flex; justify-content: space-between; padding: 0.5rem 0; border-bottom: 1px solid var(--lgv-veil); gap: 1rem; }
    .recap-row:last-child { border-bottom: none; }
    .recap-table { width: 100%; border-collapse: collapse; margin: 0.5rem 0; }
    .recap-table th, .recap-table td { text-align: left; padding: 0.4rem 0.5rem; border-bottom: 1px solid var(--lgv-veil); font-size: 13px; }
    .recap-table .numeric { text-align: right; font-family: var(--lgv-font-mono); }
```

- [ ] **Step 2 : Item sidebar « Consultation »**

Edit — ancre `old_string` :
```
        <button class="nav-item" data-page="factures" onclick="navTo('factures')">
          <i data-lucide="file-text"></i>
          Factures proforma
        </button>
        <div class="nav-section-label">Configuration</div>
```
`new_string` :
```
        <button class="nav-item" data-page="factures" onclick="navTo('factures')">
          <i data-lucide="file-text"></i>
          Factures proforma
        </button>
        <button class="nav-item" data-page="consultation" onclick="navTo('consultation')">
          <i data-lucide="clipboard-list"></i>
          Consultation
        </button>
        <div class="nav-section-label">Configuration</div>
```

- [ ] **Step 3 : Bouton « Nouvelle consultation » sur le dashboard**

Edit — ancre `old_string` (en-tête du dashboard) :
```
          <button class="btn btn-primary" onclick="openModal('client')">
            <i data-lucide="plus"></i>
            Nouveau client
          </button>
        </div>
        <div class="glow-rule page-rule"></div>
        <div id="dashboardStats" class="stats-grid"></div>
```
`new_string` :
```
          <div style="display:flex;gap:.5rem;flex-wrap:wrap;">
            <button class="btn btn-secondary" onclick="openModal('client')">
              <i data-lucide="plus"></i>
              Nouveau client
            </button>
            <button class="btn btn-primary" onclick="startConsultation()">
              <i data-lucide="clipboard-list"></i>
              Nouvelle consultation
            </button>
          </div>
        </div>
        <div class="glow-rule page-rule"></div>
        <div id="dashboardStats" class="stats-grid"></div>
```

- [ ] **Step 4 : Section HTML `#page-consultation`**

Edit — ancre `old_string` (fin de la section factures) :
```
        <div id="facturesList"></div>
      </section>

      <section id="page-settings" class="page hidden">
```
`new_string` :
```
        <div id="facturesList"></div>
      </section>

      <section id="page-consultation" class="page hidden">
        <div class="page-header">
          <div>
            <div class="eyebrow">Consultation</div>
            <h2 class="page-title">Nouvelle <span class="blue">consultation</span></h2>
            <p class="page-sub">Parcours guidé : client, prescription, devis, acompte, PDF</p>
          </div>
          <button class="btn btn-tertiary" onclick="cancelConsultation()">
            <i data-lucide="x"></i>
            Annuler la consultation
          </button>
        </div>
        <div class="glow-rule page-rule"></div>
        <div id="consultationContent"></div>
      </section>

      <section id="page-settings" class="page hidden">
```

- [ ] **Step 5 : Branche `navTo`**

Edit — ancre `old_string` :
```
      if (page === 'factures') renderFactures();
      if (page === 'settings') renderSettings();
```
`new_string` :
```
      if (page === 'factures') renderFactures();
      if (page === 'consultation') renderConsultation();
      if (page === 'settings') renderSettings();
```

- [ ] **Step 6 : Bloc module consultation (état, stepper, navigation)**

Edit — ancre `old_string` = `    // ========================================================== //\n    // PDF GENERATION` (début de la section PDF) ; insérer **avant** ce commentaire le bloc suivant (la suite — étapes — sera ajoutée par les tâches 5-8 dans ce même bloc) :
```js
    // ========== MODULE CONSULTATION (wizard) ==========
    let consultation = null;

    function todayISO() { return new Date().toISOString().slice(0, 10); }

    function newConsultation() {
      return {
        step: 1,
        clientMode: 'existing',
        clientId: '',
        newClient: { nom: '', prenom: '', telephone: '', email: '', date_naissance: '', notes: '' },
        presc: {
          date: todayISO(),
          od_sph: '', od_cyl: '', od_axe: '', od_add: '',
          og_sph: '', og_cyl: '', og_axe: '', og_add: '',
          specs_libres: '', notes: ''
        },
        lignes: [],
        assuranceId: '',
        withVersement: false,
        versement: { montant: '', date: todayISO(), mode: 'especes', reference: '', notes: '' }
      };
    }

    const CONSULT_STEPS = ['Client', 'Prescription', 'Devis', 'Acompte', 'Récapitulatif'];

    function startConsultation() { consultation = null; navTo('consultation'); }

    function cancelConsultation() {
      if (!confirm('Annuler cette consultation ? Les informations saisies seront perdues.')) return;
      consultation = null;
      navTo('dashboard');
    }

    function renderConsultation() {
      if (!consultation) {
        consultation = newConsultation();
        currentPrescState = { type_verre: '', materiau: '', coloration: '', traitements: [] };
      }
      const container = document.getElementById('consultationContent');
      container.innerHTML = `
        <div class="consult-stepper">
          ${CONSULT_STEPS.map((label, i) => {
            const n = i + 1;
            const cls = n === consultation.step ? 'active' : (n < consultation.step ? 'done' : '');
            return `<div class="consult-step ${cls}"><span class="cs-num">${n < consultation.step ? '✓' : n}</span><span class="cs-label">${label}</span></div>`;
          }).join('<div class="cs-sep"></div>')}
        </div>
        <div class="glow-rule page-rule"></div>
        <div id="consultationBody"></div>
        <div class="consult-footer">
          ${consultation.step > 1
            ? `<button class="btn btn-tertiary" type="button" onclick="goToConsultStep(${consultation.step - 1})"><i data-lucide="arrow-left"></i> Précédent</button>`
            : '<span></span>'}
          ${consultation.step < 5
            ? `<button class="btn btn-primary" type="button" onclick="goToConsultStep(${consultation.step + 1})">Continuer <i data-lucide="arrow-right"></i></button>`
            : `<button class="btn btn-primary" type="button" onclick="finalizeConsultation()"><i data-lucide="check"></i> Finaliser et générer le PDF</button>`}
        </div>
      `;
      renderConsultStep();
      refreshIcons();
    }

    function renderConsultStep() {
      const body = document.getElementById('consultationBody');
      if (!body) return;
      const s = consultation.step;
      if (s === 1) body.innerHTML = consultStep1();
      else if (s === 2) body.innerHTML = consultStep2();
      else if (s === 3) {
        body.innerHTML = consultStep3();
        factureLignes = (consultation.lignes && consultation.lignes.length)
          ? JSON.parse(JSON.stringify(consultation.lignes))
          : [{ designation: '', reference: '', type: 'monture', montant: 0 }];
        renderLignes();
      }
      else if (s === 4) body.innerHTML = consultStep4();
      else body.innerHTML = consultStep5();
      refreshIcons();
    }

    function goToConsultStep(target) {
      const current = consultation.step;
      captureConsultStep(current);
      if (target > current && !validateConsultStep(current)) return;
      consultation.step = target;
      renderConsultation();
    }

    function captureConsultStep(step) {
      const c = consultation;
      const g = id => (document.getElementById(id) ? document.getElementById(id).value : '');
      if (step === 1) {
        if (c.clientMode === 'existing') {
          const sel = document.getElementById('cons_client');
          if (sel) c.clientId = sel.value;
        } else {
          c.newClient = {
            nom: g('cons_c_nom').trim(),
            prenom: g('cons_c_prenom').trim(),
            telephone: g('cons_c_telephone').trim(),
            email: g('cons_c_email').trim(),
            date_naissance: g('cons_c_naissance'),
            notes: g('cons_c_notes').trim()
          };
        }
      } else if (step === 2) {
        c.presc = {
          date: g('cons_p_date') || todayISO(),
          od_sph: g('cons_p_od_sph').trim(), od_cyl: g('cons_p_od_cyl').trim(), od_axe: g('cons_p_od_axe').trim(), od_add: g('cons_p_od_add').trim(),
          og_sph: g('cons_p_og_sph').trim(), og_cyl: g('cons_p_og_cyl').trim(), og_axe: g('cons_p_og_axe').trim(), og_add: g('cons_p_og_add').trim(),
          specs_libres: g('cons_p_specs_libres').trim(), notes: g('cons_p_notes').trim()
        };
        // les chips (type_verre/materiau/coloration/traitements) sont déjà dans currentPrescState
      } else if (step === 3) {
        c.lignes = JSON.parse(JSON.stringify(factureLignes));
        const sel = document.getElementById('f_assurance');
        c.assuranceId = sel ? sel.value : '';
      } else if (step === 4) {
        const t = document.getElementById('cons_v_toggle');
        c.withVersement = t ? t.checked : false;
        if (c.withVersement) {
          c.versement = {
            montant: g('cons_v_montant'),
            date: g('cons_v_date') || todayISO(),
            mode: g('cons_v_mode') || 'especes',
            reference: g('cons_v_reference').trim(),
            notes: g('cons_v_notes').trim()
          };
        }
      }
    }

    function validateConsultStep(step) {
      const c = consultation;
      if (step === 1) {
        if (c.clientMode === 'existing' && !c.clientId) { toast('Sélectionnez un client', 'error'); return false; }
        if (c.clientMode === 'new' && !c.newClient.nom) { toast('Le nom du client est obligatoire', 'error'); return false; }
      }
      if (step === 3) {
        const valid = factureLignes.filter(l => l.designation && l.designation.trim() && Number(l.montant) > 0);
        if (valid.length === 0) { toast('Ajoutez au moins une ligne avec désignation et montant', 'error'); return false; }
      }
      if (step === 4) {
        const t = document.getElementById('cons_v_toggle');
        if (t && t.checked) {
          const m = parseInt(document.getElementById('cons_v_montant').value, 10);
          if (!m || m <= 0) { toast('Montant d\'acompte invalide', 'error'); return false; }
        }
      }
      return true;
    }

```

> Les fonctions `consultStep1..5`, `setConsultClientMode`, `importLignesFromDraftPrescription`, `finalizeConsultation` sont ajoutées dans les tâches 5-8 — tant qu'elles manquent, atteindre une étape lèvera une `ReferenceError` (attendu jusqu'à leur ajout). Pour que la **vérification de cette tâche** passe sans elles, le Step 7 ci-dessous définit des stubs **temporaires** qui seront remplacés en tâches 5-8.

- [ ] **Step 7 : Stubs temporaires (remplacés en tâches 5-8)**

Edit — ancre `old_string` = `    // ========================================================== //\n    // PDF GENERATION` ; insérer **avant** :
```js
    // STUBS TEMPORAIRES (remplacés par les tâches 5-8)
    function consultStep1() { return '<div class="card">Étape 1 (stub)</div>'; }
    function consultStep2() { return '<div class="card">Étape 2 (stub)</div>'; }
    function consultStep3() { return '<div class="card"><select id="f_assurance"></select><div id="lignesContainer"></div><div id="totalDisplay"></div><div id="assuranceBreakdown" class="hidden"></div></div>'; }
    function consultStep4() { return '<div class="card">Étape 4 (stub)</div>'; }
    function consultStep5() { return '<div class="card">Étape 5 (stub)</div>'; }
    function setConsultClientMode(m) { consultation.clientMode = m; renderConsultStep(); }
    function importLignesFromDraftPrescription() { toast('stub'); }
    function finalizeConsultation() { toast('stub finalize'); }

```

- [ ] **Step 8 : Vérifier (navigateur) — navigation entre étapes**

Reset démo + reload `ignoreCache:true`. `take_snapshot` après clic sidebar « Consultation » pour voir le stepper. Puis `evaluate_script` :
```js
() => {
  const r = {};
  startConsultation();
  r.onPage = !document.getElementById('page-consultation').classList.contains('hidden');
  r.step1 = consultation.step === 1;
  goToConsultStep(2); r.step2 = consultation.step === 2;
  goToConsultStep(3); r.step3 = consultation.step === 3;
  goToConsultStep(2); r.back = consultation.step === 2; // reculer ne valide pas
  r.stepperCount = document.querySelectorAll('.consult-step').length;
  return r;
}
```
Attendu : `{onPage:true, step1:true, step2:true, step3:true, back:true, stepperCount:5}`.
Console `["error","warn"]` → vide.

- [ ] **Step 9 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(consultation): coquille du wizard (page, nav, stepper, navigation interne + stubs)"
```

---

## Task 5 : Étape 1 (Client) + Étape 2 (Prescription)

**Files:**
- Modify: `la-grande-vision.html` (remplacer les stubs `consultStep1`, `consultStep2`, `setConsultClientMode`)

- [ ] **Step 1 : Remplacer le stub `consultStep1` et `setConsultClientMode`**

Edit — ancre `old_string` :
```
    function consultStep1() { return '<div class="card">Étape 1 (stub)</div>'; }
```
`new_string` :
```js
    function consultStep1() {
      const c = consultation;
      const opts = clients.slice()
        .sort((a, b) => (a.nom || '').localeCompare(b.nom || ''))
        .map(cl => `<option value="${cl.id}" ${c.clientId === cl.id ? 'selected' : ''}>${escapeHtml(cl.nom)} ${escapeHtml(cl.prenom || '')}</option>`).join('');
      return `
        <div class="card">
          <div class="card-header"><h3>Étape 1 — Client</h3></div>
          <div class="pill-select" style="margin-bottom:1rem;">
            <button type="button" class="pill-opt ${c.clientMode === 'existing' ? 'active' : ''}" onclick="setConsultClientMode('existing')">Client existant</button>
            <button type="button" class="pill-opt ${c.clientMode === 'new' ? 'active' : ''}" onclick="setConsultClientMode('new')">Nouveau client</button>
          </div>
          ${c.clientMode === 'existing' ? `
            <div class="form-group">
              <label>Sélectionner un client <span class="req">*</span></label>
              <select id="cons_client">
                <option value="">— Sélectionner —</option>
                ${opts}
              </select>
            </div>
          ` : `
            <div class="form-grid">
              <div class="form-group"><label>Nom <span class="req">*</span></label><input type="text" id="cons_c_nom" value="${escapeHtml(c.newClient.nom)}" placeholder="OUATTARA"></div>
              <div class="form-group"><label>Prénom</label><input type="text" id="cons_c_prenom" value="${escapeHtml(c.newClient.prenom)}" placeholder="Drissa"></div>
            </div>
            <div class="form-grid">
              <div class="form-group"><label>Téléphone</label><input type="text" id="cons_c_telephone" value="${escapeHtml(c.newClient.telephone)}" placeholder="+225 07 00 00 00 00"></div>
              <div class="form-group"><label>Email</label><input type="email" id="cons_c_email" value="${escapeHtml(c.newClient.email)}" placeholder="exemple@email.com"></div>
            </div>
            <div class="form-group"><label>Date de naissance</label><input type="date" id="cons_c_naissance" value="${escapeHtml(c.newClient.date_naissance)}"></div>
            <div class="form-group"><label>Notes</label><textarea id="cons_c_notes" placeholder="Notes sur le client...">${escapeHtml(c.newClient.notes)}</textarea></div>
          `}
        </div>
      `;
    }
```

Edit — ancre `old_string` :
```
    function setConsultClientMode(m) { consultation.clientMode = m; renderConsultStep(); }
```
`new_string` :
```js
    function setConsultClientMode(mode) {
      captureConsultStep(1);
      consultation.clientMode = mode;
      renderConsultStep();
    }
```

- [ ] **Step 2 : Remplacer le stub `consultStep2`**

Edit — ancre `old_string` :
```
    function consultStep2() { return '<div class="card">Étape 2 (stub)</div>'; }
```
`new_string` :
```js
    function consultStep2() {
      const p = consultation.presc;
      return `
        <div class="card">
          <div class="card-header"><h3>Étape 2 — Prescription <span style="color:var(--lgv-haze);font-weight:400;font-size:12px;">(optionnelle)</span></h3></div>
          <div class="form-group"><label>Date de consultation</label><input type="date" id="cons_p_date" value="${escapeHtml(p.date)}"></div>
          <div class="form-group">
            <label><span class="badge badge-blue-filled">OD — Œil droit</span></label>
            <div class="form-grid-4">
              <div><label>SPH</label><input type="text" id="cons_p_od_sph" value="${escapeHtml(p.od_sph)}" placeholder="-2.50"></div>
              <div><label>CYL</label><input type="text" id="cons_p_od_cyl" value="${escapeHtml(p.od_cyl)}" placeholder="+0.50"></div>
              <div><label>AXE</label><input type="text" id="cons_p_od_axe" value="${escapeHtml(p.od_axe)}" placeholder="145"></div>
              <div><label>ADD</label><input type="text" id="cons_p_od_add" value="${escapeHtml(p.od_add)}" placeholder="+1.50"></div>
            </div>
          </div>
          <div class="form-group">
            <label><span class="badge badge-blue">OG — Œil gauche</span></label>
            <div class="form-grid-4">
              <div><label>SPH</label><input type="text" id="cons_p_og_sph" value="${escapeHtml(p.og_sph)}" placeholder="-2.25"></div>
              <div><label>CYL</label><input type="text" id="cons_p_og_cyl" value="${escapeHtml(p.og_cyl)}" placeholder="+0.50"></div>
              <div><label>AXE</label><input type="text" id="cons_p_og_axe" value="${escapeHtml(p.og_axe)}" placeholder="35"></div>
              <div><label>ADD</label><input type="text" id="cons_p_og_add" value="${escapeHtml(p.og_add)}" placeholder="+1.50"></div>
            </div>
          </div>
          <div class="form-group"><label>Type de correction</label>${chipGroupHtml('type_verre', false)}</div>
          <div class="form-grid">
            <div class="form-group"><label>Matériau</label>${chipGroupHtml('materiau', false)}</div>
            <div class="form-group"><label>Teinte</label>${chipGroupHtml('coloration', false)}</div>
          </div>
          <div class="form-group"><label>Traitements</label>${chipGroupHtml('traitements', true)}</div>
          <div class="form-group"><label>Autres précisions / valeurs personnalisées</label><textarea id="cons_p_specs_libres" placeholder="Ex : verre haute définition, traitement hydrophobe...">${escapeHtml(p.specs_libres)}</textarea></div>
          <div class="form-group"><label>Notes</label><textarea id="cons_p_notes" placeholder="Notes sur la prescription...">${escapeHtml(p.notes)}</textarea></div>
        </div>
      `;
    }
```

- [ ] **Step 3 : Vérifier (navigateur)**

Reset démo + reload. `evaluate_script` :
```js
() => {
  const r = {};
  startConsultation();
  // mode nouveau client + saisie
  setConsultClientMode('new');
  document.getElementById('cons_c_nom').value = 'TESTNOM';
  document.getElementById('cons_c_prenom').value = 'Prenom';
  captureConsultStep(1);
  r.newClientCaptured = consultation.newClient.nom === 'TESTNOM' && consultation.newClient.prenom === 'Prenom';
  // validation : nom requis
  consultation.newClient.nom = '';
  r.rejectsEmptyName = validateConsultStep(1) === false;
  consultation.newClient.nom = 'TESTNOM';
  r.acceptsName = validateConsultStep(1) === true;
  // étape 2 : chips + champs
  goToConsultStep(2);
  document.getElementById('cons_p_od_sph').value = '-2.50';
  toggleChipSingle('type_verre', 'progressif', document.querySelector('[data-chips="type_verre"] .chip'));
  captureConsultStep(2);
  r.prescCaptured = consultation.presc.od_sph === '-2.50';
  r.chipCaptured = currentPrescState.type_verre === 'progressif';
  return r;
}
```
Attendu : tous `true`. Console `["error","warn"]` → vide.

> Note : `toggleChipSingle` est appelé ici avec le **premier** `.chip` du groupe ; il bascule la valeur passée (`progressif`) dans `currentPrescState` indépendamment du bouton ciblé, donc l'assertion `chipCaptured` est fiable.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(consultation): étapes 1 (client) et 2 (prescription)"
```

---

## Task 6 : Étape 3 (Devis) + import tarifs depuis prescription brouillon

**Files:**
- Modify: `la-grande-vision.html` (remplacer les stubs `consultStep3`, `importLignesFromDraftPrescription`)

- [ ] **Step 1 : Remplacer le stub `consultStep3`**

Edit — ancre `old_string` :
```
    function consultStep3() { return '<div class="card"><select id="f_assurance"></select><div id="lignesContainer"></div><div id="totalDisplay"></div><div id="assuranceBreakdown" class="hidden"></div></div>'; }
```
`new_string` :
```js
    function consultStep3() {
      const insOpts = (settings.insurances || []).map(a =>
        `<option value="${a.id}" data-nom="${escapeHtml(a.nom)}" data-pct="${a.couverture}" ${consultation.assuranceId === a.id ? 'selected' : ''}>${escapeHtml(a.nom)} · ${a.couverture}%</option>`
      ).join('');
      return `
        <div class="card">
          <div class="card-header">
            <h3>Étape 3 — Devis</h3>
            <button class="btn btn-secondary btn-sm" type="button" onclick="importLignesFromDraftPrescription()">
              <i data-lucide="download"></i> Importer la prescription (tarifs auto)
            </button>
          </div>
          <div class="form-group">
            <label>Assurance</label>
            <select id="f_assurance" onchange="updateAssuranceBreakdown()">
              <option value="">— Aucune —</option>
              ${insOpts}
            </select>
          </div>
          <div class="form-group">
            <label>Lignes de facture</label>
            <div class="ligne-labels">
              <label>Désignation</label>
              <label>Référence</label>
              <label>Type</label>
              <label>Montant (FCFA)</label>
              <label></label>
            </div>
            <div id="lignesContainer"></div>
            <button class="btn btn-dashed btn-sm" type="button" onclick="addLigne()" style="margin-top:0.5rem;">
              <i data-lucide="plus"></i> Ajouter une ligne
            </button>
          </div>
          <div class="total-bar">
            <div class="label">Total</div>
            <div class="value" id="totalDisplay">0 FCFA</div>
          </div>
          <div id="assuranceBreakdown" class="hidden"></div>
        </div>
      `;
    }
```

- [ ] **Step 2 : Remplacer le stub `importLignesFromDraftPrescription`**

Edit — ancre `old_string` :
```
    function importLignesFromDraftPrescription() { toast('stub'); }
```
`new_string` :
```js
    function importLignesFromDraftPrescription() {
      const p = {
        type_verre: currentPrescState.type_verre,
        materiau: currentPrescState.materiau,
        coloration: currentPrescState.coloration,
        traitements: currentPrescState.traitements || []
      };
      const newLignes = [];
      [
        { field: 'type_verre', group: 'type_verre', type: 'verre' },
        { field: 'materiau',   group: 'materiau',   type: 'verre' },
        { field: 'coloration', group: 'coloration', type: 'traitement' }
      ].forEach(({ field, group, type }) => {
        const value = p[field];
        if (!value) return;
        const price = getPrice(group, value);
        if (price <= 0) return;
        newLignes.push({ designation: prescLabel(group, value).toUpperCase(), reference: '', type, montant: price });
      });
      (p.traitements || []).forEach(t => {
        const price = getPrice('traitements', t);
        if (price <= 0) return;
        newLignes.push({ designation: prescLabel('traitements', t).toUpperCase(), reference: '', type: 'traitement', montant: price });
      });
      if (newLignes.length === 0) { toast('Aucune prestation tarifée dans la prescription', 'error'); return; }
      const hasOnlyEmpty = factureLignes.length === 1 && !factureLignes[0].designation && !Number(factureLignes[0].montant);
      factureLignes = hasOnlyEmpty ? newLignes : [...factureLignes, ...newLignes];
      renderLignes();
      toast(`${newLignes.length} ligne(s) importée(s)`);
    }
```

- [ ] **Step 3 : Vérifier (navigateur)**

Reset démo + reload. `evaluate_script` :
```js
() => {
  const r = {};
  startConsultation();
  goToConsultStep(2);
  // poser une prescription tarifée
  toggleChipSingle('type_verre', 'progressif', document.querySelector('[data-chips="type_verre"] .chip'));
  goToConsultStep(3);
  r.lignesEmptyStart = factureLignes.length === 1 && !factureLignes[0].designation;
  importLignesFromDraftPrescription();
  r.imported = factureLignes.some(l => /PROGRESSIF/i.test(l.designation) && l.montant === getPrice('type_verre','progressif'));
  // assurance + breakdown
  const sel = document.getElementById('f_assurance');
  sel.value = sel.options[1] ? sel.options[1].value : '';
  updateAssuranceBreakdown();
  r.breakdownShown = !document.getElementById('assuranceBreakdown').classList.contains('hidden');
  // total affiché
  r.totalShown = /FCFA/.test(document.getElementById('totalDisplay').textContent);
  // capture
  captureConsultStep(3);
  r.captured = consultation.lignes.length >= 1 && consultation.assuranceId === sel.value;
  // validation : au moins une ligne valide
  r.valid = validateConsultStep(3) === true;
  return r;
}
```
Attendu : tous `true`. Console `["error","warn"]` → vide.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(consultation): étape 3 (devis) réutilisant les lignes + import tarifs prescription brouillon"
```

---

## Task 7 : Étape 4 (Acompte) + Étape 5 (Récapitulatif)

**Files:**
- Modify: `la-grande-vision.html` (remplacer les stubs `consultStep4`, `consultStep5`)

- [ ] **Step 1 : Remplacer le stub `consultStep4`**

Edit — ancre `old_string` :
```
    function consultStep4() { return '<div class="card">Étape 4 (stub)</div>'; }
```
`new_string` :
```js
    function consultStep4() {
      const c = consultation;
      const total = (c.lignes || []).reduce((s, l) => s + (Number(l.montant) || 0), 0);
      const ins = c.assuranceId ? findInsurance(c.assuranceId) : null;
      const patient = ins ? total - Math.round(total * ins.couverture / 100) : total;
      const v = c.versement;
      const modeOpts = PAYMENT_MODES.map(m => `<option value="${m.value}" ${v.mode === m.value ? 'selected' : ''}>${m.label}</option>`).join('');
      return `
        <div class="card">
          <div class="card-header"><h3>Étape 4 — Acompte <span style="color:var(--lgv-haze);font-weight:400;font-size:12px;">(optionnel)</span></h3></div>
          <label class="consult-toggle">
            <input type="checkbox" id="cons_v_toggle" ${c.withVersement ? 'checked' : ''} onchange="captureConsultStep(4); renderConsultStep();">
            Enregistrer un acompte maintenant
          </label>
          <p style="color:var(--lgv-haze);font-size:12px;margin:.5rem 0 1rem;">Part à régler par le patient : <strong>${fmtFCFA(patient)}</strong> (total ${fmtFCFA(total)})</p>
          ${c.withVersement ? `
            <div class="form-grid">
              <div class="form-group"><label>Montant (FCFA) <span class="req">*</span></label><input type="number" id="cons_v_montant" min="0" step="1" value="${escapeHtml(v.montant)}" placeholder="0"></div>
              <div class="form-group"><label>Date</label><input type="date" id="cons_v_date" value="${escapeHtml(v.date)}"></div>
            </div>
            <div class="form-grid">
              <div class="form-group"><label>Mode</label><select id="cons_v_mode">${modeOpts}</select></div>
              <div class="form-group"><label>Référence</label><input type="text" id="cons_v_reference" value="${escapeHtml(v.reference)}" placeholder="N° chèque, transaction…"></div>
            </div>
            <div class="form-group"><label>Notes</label><textarea id="cons_v_notes" placeholder="—">${escapeHtml(v.notes)}</textarea></div>
          ` : ''}
        </div>
      `;
    }
```

- [ ] **Step 2 : Remplacer le stub `consultStep5`**

Edit — ancre `old_string` :
```
    function consultStep5() { return '<div class="card">Étape 5 (stub)</div>'; }
```
`new_string` :
```js
    function consultStep5() {
      const c = consultation;
      let clientLabel;
      if (c.clientMode === 'existing') {
        const cl = findClient(c.clientId);
        clientLabel = cl ? `${escapeHtml(cl.nom)} ${escapeHtml(cl.prenom || '')}` : '—';
      } else {
        clientLabel = `${escapeHtml(c.newClient.nom)} ${escapeHtml(c.newClient.prenom || '')} <span class="badge badge-blue">nouveau</span>`;
      }
      const specs = formatPrescSpecs({
        type_verre: currentPrescState.type_verre,
        materiau: currentPrescState.materiau,
        coloration: currentPrescState.coloration,
        traitements: currentPrescState.traitements
      });
      const validLignes = (c.lignes || []).filter(l => l.designation && l.designation.trim() && Number(l.montant) > 0);
      const total = validLignes.reduce((s, l) => s + (Number(l.montant) || 0), 0);
      const ins = c.assuranceId ? findInsurance(c.assuranceId) : null;
      const covered = ins ? Math.round(total * ins.couverture / 100) : 0;
      const patient = total - covered;
      const acompte = (c.withVersement && Number(c.versement.montant) > 0) ? parseInt(c.versement.montant, 10) : 0;
      const reste = Math.max(0, patient - acompte);
      return `
        <div class="card">
          <div class="card-header"><h3>Étape 5 — Récapitulatif</h3></div>
          <div class="recap-row"><span>Client</span><strong>${clientLabel}</strong></div>
          ${specs.length ? `<div class="recap-row"><span>Prescription</span><span>${specs.map(s => `<span class="spec-pill">${escapeHtml(s)}</span>`).join(' ')}</span></div>` : ''}
          <table class="recap-table">
            <thead><tr><th>Désignation</th><th class="numeric">Montant</th></tr></thead>
            <tbody>${validLignes.map(l => `<tr><td>${escapeHtml(l.designation)}</td><td class="numeric">${fmtFCFA(l.montant)}</td></tr>`).join('')}</tbody>
          </table>
          <div class="recap-row"><span>Total</span><strong>${fmtFCFA(total)}</strong></div>
          ${ins ? `
            <div class="recap-row"><span>${escapeHtml(ins.nom)} couvre ${ins.couverture}%</span><span>− ${fmtFCFA(covered)}</span></div>
            <div class="recap-row"><span>Part patient</span><strong>${fmtFCFA(patient)}</strong></div>
          ` : ''}
          ${acompte ? `
            <div class="recap-row"><span>Acompte (${modeLabel(c.versement.mode)})</span><span>− ${fmtFCFA(acompte)}</span></div>
            <div class="recap-row"><span>Reste à régler</span><strong>${fmtFCFA(reste)}</strong></div>
          ` : ''}
        </div>
      `;
    }
```

- [ ] **Step 3 : Vérifier (navigateur)**

Reset démo + reload. `evaluate_script` :
```js
() => {
  const r = {};
  startConsultation();
  setConsultClientMode('new');
  document.getElementById('cons_c_nom').value = 'RECAP';
  goToConsultStep(2);
  goToConsultStep(3);
  factureLignes = [{ designation: 'MONTURE X', reference: '', type: 'monture', montant: 50000 }];
  renderLignes();
  goToConsultStep(4);
  // activer acompte
  document.getElementById('cons_v_toggle').checked = true;
  captureConsultStep(4);
  renderConsultStep();
  document.getElementById('cons_v_montant').value = '20000';
  r.validAcompte = validateConsultStep(4) === true;
  goToConsultStep(5);
  const recap = document.getElementById('consultationBody').textContent;
  r.recapHasClient = /RECAP/.test(recap);
  r.recapHasTotal = /50 000 FCFA/.test(recap);
  r.recapHasReste = /Reste à régler/.test(recap);
  return r;
}
```
Attendu : tous `true`. Console `["error","warn"]` → vide.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(consultation): étapes 4 (acompte) et 5 (récapitulatif)"
```

---

## Task 8 : Finalisation (persistance + PDF)

**Files:**
- Modify: `la-grande-vision.html` (remplacer le stub `finalizeConsultation`)

- [ ] **Step 1 : Remplacer le stub `finalizeConsultation`**

Edit — ancre `old_string` :
```
    function finalizeConsultation() { toast('stub finalize'); }
```
`new_string` :
```js
    function finalizeConsultation() {
      const c = consultation;

      // 1. Client
      let clientId;
      if (c.clientMode === 'new') {
        if (!c.newClient.nom) { toast('Le nom du client est obligatoire', 'error'); goToConsultStep(1); return; }
        clientId = DB.uid();
        clients.push({
          id: clientId,
          nom: c.newClient.nom.toUpperCase(),
          prenom: c.newClient.prenom,
          telephone: c.newClient.telephone,
          email: c.newClient.email,
          date_naissance: c.newClient.date_naissance,
          notes: c.newClient.notes,
          created_at: new Date().toISOString()
        });
        DB.set('lgv_clients', clients);
      } else {
        if (!c.clientId) { toast('Sélectionnez un client', 'error'); goToConsultStep(1); return; }
        clientId = c.clientId;
      }

      // 2. Prescription (uniquement si renseignée)
      const p = c.presc;
      const cp = currentPrescState;
      const hasPresc =
        ['od_sph','od_cyl','od_axe','od_add','og_sph','og_cyl','og_axe','og_add','specs_libres'].some(k => (p[k] || '').trim())
        || cp.type_verre || cp.materiau || cp.coloration || (cp.traitements && cp.traitements.length);
      let prescriptionId = null;
      if (hasPresc) {
        prescriptionId = DB.uid();
        prescriptions.push({
          id: prescriptionId,
          client_id: clientId,
          date_consultation: p.date,
          od_sph: p.od_sph, od_cyl: p.od_cyl, od_axe: p.od_axe, od_add: p.od_add,
          og_sph: p.og_sph, og_cyl: p.og_cyl, og_axe: p.og_axe, og_add: p.og_add,
          type_verre: cp.type_verre || '', materiau: cp.materiau || '', coloration: cp.coloration || '',
          traitements: Array.isArray(cp.traitements) ? [...cp.traitements] : [],
          specs_libres: p.specs_libres, notes: p.notes
        });
        DB.set('lgv_prescriptions', prescriptions);
      }

      // 3. Facture
      const validLignes = (c.lignes || []).filter(l => l.designation && l.designation.trim() && Number(l.montant) > 0);
      if (validLignes.length === 0) { toast('Le devis doit contenir au moins une ligne', 'error'); goToConsultStep(3); return; }
      const total = validLignes.reduce((s, l) => s + (Number(l.montant) || 0), 0);

      let assurance = null;
      if (c.assuranceId) {
        const a = findInsurance(c.assuranceId);
        if (a) {
          const covered = Math.round(total * a.couverture / 100);
          assurance = { id: a.id, nom: a.nom, couverture_pct: a.couverture, montant_couvert: covered, montant_patient: total - covered };
        }
      }

      const factureId = DB.uid();
      const versements = [];
      if (c.withVersement && Number(c.versement.montant) > 0) {
        versements.push({
          id: DB.uid(),
          date: c.versement.date,
          montant: parseInt(c.versement.montant, 10) || 0,
          mode: c.versement.mode,
          reference: c.versement.reference,
          notes: c.versement.notes,
          created_at: new Date().toISOString()
        });
      }

      factures.push({
        id: factureId,
        numero: nextFactureNumero(),
        client_id: clientId,
        prescription_id: prescriptionId,
        date_facture: todayISO(),
        total: total,
        statut: 'finalisee',
        assurance: assurance,
        lignes: validLignes.map(l => ({
          designation: l.designation.trim(),
          reference: (l.reference || '').trim(),
          type: l.type || 'autre',
          montant: parseInt(l.montant, 10) || 0
        })),
        versements: versements,
        livraison: { livre: false },
        created_at: new Date().toISOString()
      });
      DB.set('lgv_factures', factures);

      // 4. PDF + reset + redirection
      generatePDF(factureId);
      toast('Consultation finalisée ✓');
      consultation = null;
      renderDashboard();
      navTo('factures');
    }
```

- [ ] **Step 2 : Vérifier (navigateur) — aller-retour complet**

Reset démo + reload. `evaluate_script` (capture les compteurs avant/après ; `generatePDF` déclenche un `doc.save` — inoffensif en automatisation) :
```js
() => {
  const r = {};
  const before = { c: clients.length, p: prescriptions.length, f: factures.length };
  startConsultation();
  // nouveau client
  setConsultClientMode('new');
  document.getElementById('cons_c_nom').value = 'CONSO';
  document.getElementById('cons_c_prenom').value = 'Test';
  // étape 2 prescription
  goToConsultStep(2);
  toggleChipSingle('type_verre', 'progressif', document.querySelector('[data-chips="type_verre"] .chip'));
  document.getElementById('cons_p_od_sph').value = '-1.00';
  // étape 3 devis
  goToConsultStep(3);
  factureLignes = [{ designation: 'MONTURE CONSO', reference: '', type: 'monture', montant: 75000 }];
  renderLignes();
  // étape 4 acompte
  goToConsultStep(4);
  document.getElementById('cons_v_toggle').checked = true;
  captureConsultStep(4); renderConsultStep();
  document.getElementById('cons_v_montant').value = '30000';
  // étape 5 + finalisation
  goToConsultStep(5);
  finalizeConsultation();
  const after = { c: clients.length, p: prescriptions.length, f: factures.length };
  const newFact = factures[factures.length - 1];
  const newClient = clients.find(x => x.nom === 'CONSO');
  r.clientCreated = after.c === before.c + 1 && !!newClient;
  r.prescCreated = after.p === before.p + 1;
  r.factureCreated = after.f === before.f + 1;
  r.factureLinked = newFact.client_id === newClient.id && newFact.prescription_id;
  r.factureTotal = newFact.total === 75000;
  r.acompte = (newFact.versements || []).length === 1 && newFact.versements[0].montant === 30000;
  r.numero = /^PRO-\d{4}-\d{4}$/.test(newFact.numero);
  r.resetAfter = consultation === null;
  r.onFactures = !document.getElementById('page-factures').classList.contains('hidden');
  // persistance localStorage
  r.persisted = (JSON.parse(localStorage.getItem('lgv_factures')) || []).length === after.f;
  return r;
}
```
Attendu : tous `true`. Console `["error","warn"]` → vide.

- [ ] **Step 3 : Vérifier abandon (aucun orphelin)**
```js
() => {
  const r = {};
  const before = { c: clients.length, p: prescriptions.length, f: factures.length };
  startConsultation();
  setConsultClientMode('new');
  document.getElementById('cons_c_nom').value = 'ABANDON';
  captureConsultStep(1);
  consultation = null; // simule cancelConsultation (sans le confirm)
  const after = { c: clients.length, p: prescriptions.length, f: factures.length };
  r.noOrphan = after.c === before.c && after.p === before.p && after.f === before.f;
  return r;
}
```
Attendu : `{noOrphan:true}`.

- [ ] **Step 4 : Commit**
```bash
git add la-grande-vision.html
git commit -m "feat(consultation): finalisation (client + prescription + facture + acompte) et génération du PDF"
```

---

## Task 9 : Vérification de non-régression + nettoyage

**Files:**
- Aucun changement de code attendu (sauf correctifs éventuels)

- [ ] **Step 1 : Non-régression des modales existantes**

Reset démo + reload. `evaluate_script` :
```js
() => {
  const r = {};
  // modale facture existante : factureLignes/assurance toujours opérationnels
  openModal('facture');
  r.factureModalOpens = !!document.getElementById('f_client');
  addLigne();
  r.addLigneWorks = factureLignes.length >= 2;
  closeModal();
  // modale client
  openModal('client');
  r.clientModalOpens = !!document.getElementById('c_nom');
  closeModal();
  // export/import helpers intacts
  r.exportOk = typeof exportData === 'function' && typeof exportFacturesCSV === 'function';
  return r;
}
```
Attendu : tous `true`. Console `["error","warn"]` → vide.

- [ ] **Step 2 : Snapshot visuel des 5 étapes + page Factures**

Parcourir manuellement via `take_snapshot` après `startConsultation()` puis `goToConsultStep(2..5)` pour confirmer le rendu du stepper et des cartes. Vérifier que la page Factures affiche bien les deux boutons (« Export comptable (CSV) » + « Nouvelle facture »).

- [ ] **Step 3 : Remettre les données de démo propres**

`evaluate_script` → reset des clés `lgv_*` + reload `ignoreCache:true` pour laisser l'app sur le jeu de démo seedé.

- [ ] **Step 4 : Commit (si correctifs) + tag de fin**
```bash
git add -A
git commit -m "test(consultation): vérification de non-régression + nettoyage" --allow-empty
```

---

## Auto-revue (couverture spec)

- **A1 sécurité avant import** → Task 1 (Step 2). ✅
- **A2 migration de version** → Task 1 (`migrateBackup`). ✅
- **A3 rappel de sauvegarde + date dans Paramètres** → Task 2. ✅
- **A4 export CSV** → Task 3. ✅
- **B entrée sidebar + bouton dashboard** → Task 4 (Steps 2-3). ✅
- **B stepper + navigation + état + démarrage/annulation** → Task 4 (Step 6 ; `startConsultation`/`cancelConsultation`). ✅
- **B étape 1 client / étape 2 prescription** → Task 5. ✅
- **B étape 3 devis + import brouillon** → Task 6. ✅
- **B étape 4 acompte / étape 5 récap** → Task 7. ✅
- **B finalisation + PDF** → Task 8. ✅
- **Non-régression + critères de succès** → Task 9. ✅

Cohérence des noms vérifiée : `consultation`, `factureLignes`, `currentPrescState`, `consultStep1..5`, `captureConsultStep`, `validateConsultStep`, `goToConsultStep`, `renderConsultStep`, `renderConsultation`, `startConsultation`, `cancelConsultation`, `finalizeConsultation`, `importLignesFromDraftPrescription`, `buildBackupPayload`, `downloadBackup`, `migrateBackup`, `checkBackupReminder`, `dismissBackupReminder`, `exportFacturesCSV`, `csvCell` — identiques entre définition et appels.
