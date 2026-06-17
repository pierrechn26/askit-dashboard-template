# RUNBOOK ONBOARDING CLIENT — Ask-it (v3, workflow autonome)

Procédure pour onboarder un nouveau client **sans Lovable**, via Claude Code + Supabase CLI + GitHub + Vercel. Remplace la v2 (qui dépendait de Lovable). Intègre les correctifs et apprentissages issus de l'onboarding Baûbo.

**Principe :** chaque client = un nouveau projet Supabase recréé depuis le repo template + un frontend déployé sur Vercel + un diagnostic branché. Le template est la source de vérité unique, générique, sans aucune valeur spécifique-client en dur.

---

## ⚠️ CHANGEMENT MAJEUR vs v2
- **Plus de Lovable.** Le provisioning se fait via `supabase` CLI (db push, functions deploy, secrets set).
- **L'audit du diagnostic se fait EN AMONT** (nouvelle Phase A-bis), avant les migrations — car le schéma de réponses du diagnostic détermine le `column_labels_mapping` et tout le tableau dashboard. (Apprentissage Baûbo : le faire en Phase G était trop tard.)
- **Crons créés via migration dédiée à URL dynamique** (plus de project_ref hardcodé).
- **Klaviyo** : first_name natif, consented_at SMS, translateProp lisant column_labels_mapping (corrections template appliquées).

---

## PRÉ-REQUIS
- Compte Supabase (propriétaire) + Supabase CLI installé et authentifié (`npx supabase login`).
- Repo template cloné, Claude Code opérationnel.
- Accès GitHub (push) + Vercel (déploiement frontend).
- Côté client : accès Shopify (collaborator via Shopify Partners), accès Klaviyo (Private API Key + **canal SMS activé sur le compte** si opt-in SMS voulu), URL du diagnostic, URL du site marchand, nom du propriétaire du store Shopify.
- Clés API : Anthropic, Perplexity.

---

## PHASE A — Setup projet (15 min)

### A.1 — Créer le projet Supabase client
- supabase.com → New project → nommer `dashboard-[client]` → région Europe West → définir et NOTER le mot de passe DB.
- Noter le **project ref** (Settings → General → Reference ID).

### A.2 — Cloner le template pour ce client
```
git clone [repo-template] dashboard-[client]
cd dashboard-[client]
rm -rf .git && git init && git remote add origin [nouveau-repo-client]
```
(ou fork du template selon ta convention de gestion des repos clients)

### A.3 — Lier et recréer la base
```
npx supabase link --project-ref [PROJECT_REF_CLIENT]
npx supabase db push                      # 48 migrations
# appliquer les 4 pending_migrations :
psql "[SUPABASE_DB_URL]" -f supabase/pending_migrations/01_drop_diagnostic_responses.sql
psql "[SUPABASE_DB_URL]" -f supabase/pending_migrations/02_add_utm_columns.sql
psql "[SUPABASE_DB_URL]" -f supabase/pending_migrations/03_add_tone_label.sql
psql "[SUPABASE_DB_URL]" -f supabase/pending_migrations/04_add_column_labels_mapping.sql
```
✓ Vérifier : 22 tables, personas = 1 ligne (P0), marketing_sources = 213 lignes.

---

## PHASE A-bis — AUDIT DU DIAGNOSTIC (NOUVEAU — à faire AVANT toute config) (20 min)

⚠️ **Apprentissage Baûbo : à faire ici, pas en Phase G.** Le schéma de réponses du diagnostic conditionne le `column_labels_mapping`, le `persona_dimension_mapping` et tout le tableau dashboard.

Auditer le diagnostic client (markdown) :
1. **Schéma** : colonnes de la table sessions du diagnostic, tables liées, clé de session (`session_id` vs `session_code` ?).
2. **Flow complet** : toutes les étapes, tous les parcours conditionnels, pour chaque question : clé technique stockée + valeurs possibles + libellé affiché.
3. **Persona calculé ?** (généralement non — le dashboard fait le clustering via `detect-persona-clusters`).
4. **Données contextuelles** : UTM, gclid, fbclid, device, locale, opt-in email/SMS, téléphone (format E.164 ?).
5. **Intégrations existantes** (Klaviyo, Shopify, webhook).
6. **Moments de persistance**.
7. **Clé de matching Shopify** dans le panier (note_attributes / line_item properties).

→ Cet audit produit la **liste exhaustive clé → valeurs → libellé FR** qui servira en Phase I.

---

## PHASE B — Secrets (10 min)
```
npx supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
npx supabase secrets set PERPLEXITY_API_KEY=pplx-...
npx supabase secrets set DASHBOARD_WEBHOOK_SECRET=[openssl rand -hex 32 — NOTER, réutilisé Phase G]
npx supabase secrets set USAGE_STATS_API_KEY=askit-usage-stats-2026
npx supabase secrets set ORGANIZATION_ID=[UUID portail]
npx supabase secrets set MONITORING_API_KEY=mk_...
npx supabase secrets set PORTAL_URL=https://srzbcuhwrpkfhubbbeuw.supabase.co
```
✓ `npx supabase secrets list` pour vérifier.
Note : `SUPABASE_*` sont auto-injectés. Plus de `LOVABLE_API_KEY` → la génération auto de tenant_config (ex-Gemini via Lovable Gateway) doit être remplacée par un appel direct (à cadrer).

---

## PHASE C — Déployer les edge functions (5 min)
```
npx supabase functions deploy        # toutes d'un coup
```
✓ Smoke test : appeler aski-chat, vérifier réponse + ligne dans api_usage_logs.

---

## PHASE D — tenant_config (15 min)
- INSERT du tenant_config (project_id, brand_name, brand_tone, industry, target_audience, integrations_enabled, shopify_store_domain, klaviyo_list_id, client_supabase_url).
- ⚠️ `client_supabase_url` doit finir par `/functions/v1/get-usage-stats`.
- ⚠️ `integrations_enabled.klaviyo = true` si Klaviyo.
- ⚠️ `klaviyo_list_id` = ID court de la liste (ex: RsS5V8). **Le code le lit ici, plus de hardcode.**
✓ Vérifier remontée des coûts IA au portail.

---

## PHASE E — Crons (5 min)

La migration `20260617000000_create_crons_dynamic.sql` crée automatiquement les 5 crons via un wrapper `call_edge_function()` à URL dynamique (lecture Vault).

**⚠️ DÉPENDANCE VAULT — obligatoire avant que les crons fonctionnent :**
```sql
SELECT vault.create_secret(
  'https://[PROJECT_REF_CLIENT].supabase.co',
  'project_base_url',
  'Base URL of this Supabase project for cron edge function calls'
);

SELECT vault.create_secret(
  '[ANON_KEY_CLIENT]',
  'project_anon_key',
  'Anon key of this Supabase project for cron edge function calls'
);
```
L'anon key se trouve dans Settings → API → `anon` `public`.

Sans ces 2 secrets Vault, les crons **skippent silencieusement** (warn dans les logs, pas de crash).

✓ `SELECT jobname, schedule FROM cron.job ORDER BY jobname;` — vérifier 5 crons présents.
✓ `SELECT public.call_edge_function('detect-persona-clusters');` — test réel du wrapper.

---

## PHASE F — Shopify (15-30 min)
- Webhook `orders/paid` (HMAC via SHOPIFY_WEBHOOK_SECRET hex 64 sans préfixe).
- ⚠️ PAS de Dev Dashboard / Custom App / client_credentials (shop_not_permitted hors Partner Org).
- F.1 récupérer l'URL de `shopify-order-webhook` → créer le webhook dans Shopify Admin.
- F.2 récupérer la clé de signature (hex 64) → `npx supabase secrets set SHOPIFY_WEBHOOK_SECRET=...`
- F.3 test : notification de test → vérifier 200 + HMAC validé + upsert client_orders.
- ⚠️ `client_orders.tenant_id` est NOT NULL → le webhook l'écrit automatiquement depuis `tenant_config.project_id`.

---

## PHASE G — Brancher le diagnostic (30-45 min)
- DASHBOARD_WEBHOOK_SECRET **identique** des 2 côtés.
- Côté diagnostic : helper `forwardToDashboard` qui POST vers `/functions/v1/diagnostic-webhook` (header `x-webhook-secret`), aux 2 régimes : ping `en_cours` à chaque étape + `termine` à la complétion.
- ⚠️ Mapping schéma diagnostic → contrat dashboard (clé session, opt-ins, answers → items[0].item_metadata À PLAT).
- ⚠️ `status` doit valoir exactement `"termine"` (déclenche scoring + Klaviyo).
- ⚠️ Convention de matching Shopify : [À FIGER — `diag_session_id` ou `_diag_session`+`lim_session_id`].
- ⚠️ Téléphone capté en E.164 à la source (react-phone-number-input, défaut FR).
- ⚠️ Push `?r=<session_id>` dans l'URL résultats (replaceState) pour la restauration à l'actualisation.
- ⚠️ `duration_seconds` : timestamp de départ partagé (sessionStorage) entre instances du hook.
- Test E2E : parcours complet → session `termine` en base, item_metadata à plat, profil Klaviyo créé+abonné.

---

## PHASE H — Scrape commercial facts (5 min)
- Déclencher `scrape-commercial-facts` pour le tenant. ✓ ≥ 20 facts (sinon vérifier website_url accessible).

---

## PHASE I — Mappings & personas (45 min)
### I.1 — column_labels_mapping (à partir de l'audit Phase A-bis)
- Construire le dictionnaire `{ clé: { label, category, value_mapping } }` couvrant toutes les clés du diagnostic.
- Ne traduire (value_mapping) que les valeurs techniques (tirets bas) ; les valeurs déjà en phrases restent telles quelles.
- INSERT dans `tenant_config.column_labels_mapping`.
- ⚠️ Dès que non-vide, le fallback `persona_dimension_mapping.need` est ignoré → lister TOUTES les clés dynamiques voulues.
- ⚠️ Ce mapping sert le tableau dashboard ET les propriétés Klaviyo (clé→label, valeur→value_mapping).
- ⚠️ **Cache frontend** : après un changement de mapping, hard refresh (Cmd+Shift+R) nécessaire tant que la revalidation tenant_config n'est pas corrigée côté frontend.

### I.2 — persona_dimension_mapping
- Aligner sur les VRAIES clés du diagnostic (identity / need / behavior).

### I.3 — Détection personas + recos
- Lancer `detect-persona-clusters` (normal si tout reste en P0 sous ~30 sessions).
- Lancer `generate-marketing-recommendations`. ✓ ton conforme au brand_tone, pas de référence à un autre client.

### I.4 — Test Aski
- Question test → réponse cohérente, tracking api_usage_logs, pas de fuite inter-clients.

---

## PHASE J — Frontend + mise en prod (15 min + DNS)
- Brancher Vercel sur le repo client (build `dist/`, env `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY`, rewrite SPA → index.html).
- Domaine custom `[client].ask-it.ai` (CNAME).
- Activer l'iframe diagnostic sur le site client.
- Envoyer l'invitation client_admin.
- Programmer revue J+15.

---

## KLAVIYO — POINTS DE VIGILANCE (apprentissages Baûbo)
- Opt-in : email saisi → optin_email ; téléphone saisi → optin_sms (consentement assumé).
- Prénom → `$first_name` natif (pas propriété custom). Email → `$email`, téléphone → `$phone_number` E.164.
- `consented_at` (ISO) requis sur le consentement SMS, sinon Klaviyo refuse.
- ⚠️ **Le canal SMS doit être activé sur le COMPTE Klaviyo** (Settings → SMS : numéro d'envoi + France autorisée). Sans ça, l'opt-in SMS reste "jamais abonné" quel que soit le code. Le consentement est préservé (optin_sms en base + propriété Klaviyo) pour backfill ultérieur.
- Propriétés lisibles via column_labels_mapping (filtres clairs).
- Filtrer les valeurs vides avant envoi.

---

## CHECKLIST FINALE
- [ ] 48 migrations + 4 pending appliquées
- [ ] 7 secrets configurés, DASHBOARD_WEBHOOK_SECRET identique des 2 côtés
- [ ] 2 secrets Vault configurés (project_base_url + project_anon_key)
- [ ] edge functions déployées (smoke test aski-chat OK)
- [ ] tenant_config rempli (klaviyo_list_id, client_supabase_url correct)
- [ ] 5 crons présents et pointant vers le bon projet (dont detect-persona-clusters)
- [ ] Shopify webhook orders/paid + HMAC OK + tenant_id écrit
- [ ] Diagnostic branché : status "termine", item_metadata à plat, E.164, ?r= dans l'URL
- [ ] Klaviyo : first_name natif, consented_at, propriétés lisibles, profil abonné (SMS si canal actif)
- [ ] column_labels_mapping complet, persona_dimension_mapping aligné
- [ ] Frontend Vercel + domaine custom + iframe
- [ ] Test E2E final : 1 diagnostic → tableau + Klaviyo + (commande test conversion)
- [ ] Invitation client envoyée, revue J+15 programmée

---

## DÉCISIONS À FIGER (cf. HANDOFF.md)
- Convention matching Shopify (`diag_session_id` vs `_diag_session`+`lim_session_id`).
- Remplacement de la génération auto tenant_config (ex-Lovable Gateway/Gemini).
