# HANDOFF.md — Passation pour pilotage autonome via Claude Code

Ce document permet de continuer le chantier "template autonome Ask-it" entièrement depuis Claude Code, sans dépendre de Lovable ni d'un assistant externe. À lire en complément de `CLAUDE.md` (contexte projet) et `docs/RUNBOOK_ONBOARDING_CLIENT.md`.

---

## ÉTAT ACTUEL (jalon atteint)

✅ **Le template se recrée intégralement depuis ce repo.** Les 47 migrations passent sur une base Supabase vierge (`npx supabase db push --linked`). Projet Supabase de travail créé sous le compte Pierre (ref : `qrtxsnzhiuzjqdessevg`), CLI Supabase installé et lié, repo sur GitHub (`pierrechn26/askit-dashboard-template`).

**Corrections déjà appliquées pour faire passer le db push :**
- `20260405081128_*.sql` : `cron.unschedule` rendu conditionnel (DO $$ EXCEPTION) + `cron.schedule` hardcodé neutralisé (commenté)
- `20260429053431_*.sql` : `cron.schedule` hardcodé neutralisé (commenté)
- `20260415093000_*.sql` : seed persona P0 `seed_template` → `manual` (contrainte CHECK)

**Objectif global :** sortir complètement de Lovable. Le repo + Supabase CLI + GitHub + Vercel deviennent la chaîne complète. Chaque nouveau client = recréation du template sur un nouveau projet Supabase (le "remix" version autonome).

---

## RÈGLES DE TRAVAIL (rappel)
1. Audit avant toute modif. Montrer le diff, attendre validation, puis appliquer.
2. Jamais de project_ref ou de valeur spécifique-client en dur dans le template. Tout doit être générique/dynamique.
3. Un correctif = un commit clair. Montrer le diff avant commit. Ne rien pousser sans validation.
4. Edge functions Supabase : modifier le code ≠ déployer. Déploiement via `npx supabase functions deploy` (séparé de Vercel qui ne fait que le frontend).
5. Réparer vers le canonique, jamais patcher pour coller à un bug.

---

## FEUILLE DE ROUTE — par ordre de priorité

### ÉTAPE 1 — Migration crons propre (infra)
**Problème :** 2 crons étaient hardcodés (neutralisés), 4 crons manquent totalement du repo (`detect-persona-clusters`, `mark-stale-sessions-as-abandoned`, `aski-daily-learn`, `monthly-market-intelligence`). `detect-persona-clusters` est critique (fait émerger les personas — sans lui les clients restent bloqués sur P0).

**À faire :** créer UNE migration dédiée idempotente qui crée les 6 crons via un wrapper `call_edge_function(fn_name)` à URL **dynamique** (jamais de project_ref en dur).

**Question technique à résoudre d'abord** (laissée en suspens) : comment résoudre dynamiquement l'URL du projet + la clé anon dans le wrapper, puisque `supabase_url()` et `current_setting('app.settings.*')` retournent NULL en SQL direct sur ce projet. Pistes à tester :
- `SELECT name FROM vault.decrypted_secrets LIMIT 5;` → si Vault dispo, y stocker l'URL + anon key au provisioning.
- sinon : colonne dans `tenant_config` (déjà `client_supabase_url` existe) + un GUC custom défini au provisioning (`ALTER DATABASE ... SET app.base_url = ...`).
- Fréquences cibles (à confirmer, déduites de l'audit) : `detect-persona-clusters` quotidien 3h UTC, `mark-stale-sessions-as-abandoned` quotidien, `aski-daily-learn` quotidien, `monthly-market-intelligence` 1er du mois 8h UTC, `weekly-intelligence-refresh` lundi 7h, `scrape-commercial-facts-weekly` lundi 8h.

### ÉTAPE 2 — Nettoyer les seeds Ouate-specific (infra)
- `client_plan` est seedé avec données Ouate (`project_id='ouate'`, plan scale 50000). Le retirer du seed (à insérer par client au provisioning) OU le rendre générique.
- `marketing_sources` : 213 lignes avec `project_id='ouate'` par défaut. Neutraliser ce défaut (ces sources sont génériques, pas Ouate-specific — soit project_id NULL, soit une valeur neutre).

### ÉTAPE 3 — LOT 1 : sync-klaviyo-persona (corrections code, le plus rentable)
Fichier : `supabase/functions/sync-klaviyo-persona/index.ts`. 4 corrections (toutes confirmées présentes par audit) :
- **1.1 (CRITIQUE)** ligne ~359 : `id: "TExMiq"` hardcodé → lire depuis `tenant_config.klaviyo_list_id`. Si null : warn explicite + skip subscription proprement (profile-import reste fait). Vérifier aucun autre ID de liste en dur ailleurs.
- **1.2** ligne ~213 : prénom en `user_name` custom → envoyer en attribut natif `attributes.first_name`. Idem email → `attributes.email`, téléphone → `attributes.phone_number` (E.164). Retirer le prénom des props custom (plus de doublon).
- **1.3** ligne ~339 : pas de `consented_at` sur SMS → ajouter `consented_at` (ISO now) au bloc sms.marketing (et email.marketing pour cohérence). Garder condition optin_sms && téléphone E.164.
- **1.4** : `translateProp` / `column_labels_mapping` absent → lire `tenant_config.column_labels_mapping`. Implémenter `translateProp(key, value)` : remplace la CLÉ par `mapping[key].label` si présent, la VALEUR par `mapping[key].value_mapping[value]` si présent (gérer arrays et CSV "a,b,c"). Si clé absente du mapping, envoyer tel quel. Filtrer valeurs vides ("", null, arrays vides).

### ÉTAPE 4 — LOT 2 : diagnostic-webhook (double-emballage item_metadata)
Fichier : `supabase/functions/diagnostic-webhook/index.ts` lignes ~637-643. `"item_metadata"` absent de `TOP_LEVEL_KEYS` → un item au format `{item_label, item_metadata:{...}}` est ré-emballé en `{item_metadata:{item_metadata:{...}}}`. Casse silencieusement tableau + Klaviyo.
**Fix :** ajouter `"item_metadata"` à `TOP_LEVEL_KEYS`, ET priorité stricte : `item_metadata = (c.item_metadata est objet non vide non-array) ? c.item_metadata : metadata`. Pas de merge.

### ÉTAPE 5 — LOT 3 : aski-chat colonnes legacy
Fichier : `supabase/functions/aski-chat/index.ts` ligne ~307. Le `.select()` liste `trust_triggers_ordered` (cause "Aski temporairement indisponible" si colonne absente) et `number_of_children` (Ouate-specific). Retirer ces colonnes legacy du select / de l'usage (ligne ~143).

### ÉTAPE 6 — Chantier séparé (LOURD, à cadrer avant) : moteur persona générique
`persona-priorities/index.ts` lignes ~41-74 : toute la logique de scoring P1-P9 est hardcodée Ouate (`skin_concern`, `age_range`, `has_routine`). Le scoring n'est pas générique → clients non-skincare restent sur P0. NE PAS traiter sans cadrage explicite : c'est un repensé d'architecture (scoring piloté par config par client), pas un correctif simple.

### ÉTAPE 7 — Déploiement & CI
- Installer/configurer le déploiement des edge functions : `npx supabase functions deploy` (toutes) ou par fonction.
- Créer `.github/workflows/deploy.yml` (GitHub Action : sur push touchant `supabase/functions/**` ou `supabase/migrations/**` → `supabase db push` + `supabase functions deploy`). Nécessite secrets GitHub : `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`.
- Brancher Vercel sur le repo pour le frontend (build `dist/`, env `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY`, rewrite SPA vers index.html).

### ÉTAPE 8 — Script de provisioning nouveau client (le "remix" autonome)
Documenter/scripter la séquence complète pour onboarder un client sans Lovable :
1. nouveau projet Supabase (`supabase projects create` ou via UI)
2. `supabase link` + `supabase db push` (47 migrations)
3. appliquer les 4 `pending_migrations/` (manuellement : `psql ... -f`)
4. `supabase secrets set` pour chaque clé (cf. RUNBOOK Phase C)
5. `supabase functions deploy` (toutes)
6. créer les crons (migration Étape 1) + résoudre l'URL dynamique
7. INSERT `tenant_config` (Phase D) + `client_plan` du client
8. frontend : Vercel auto-deploy avec env du nouveau projet

### ÉTAPE 9 — Mettre à jour la doc d'onboarding
Réviser `docs/RUNBOOK_ONBOARDING_CLIENT.md` pour le nouveau workflow (Claude Code + Supabase CLI au lieu de Lovable) + intégrer les apprentissages Baûbo :
- audit diagnostic EN AMONT (avant migrations), pas en Phase G
- consented_at SMS + dépendance "canal SMS activé côté compte Klaviyo"
- $first_name natif
- cache tenant_config (hard refresh nécessaire après changement de mapping — à corriger côté frontend : revalidation)
- captation indicatif pays E.164 à la source dans le diagnostic + normalizePhoneE164 idempotente côté dashboard

---

## DÉCISIONS EN ATTENTE (à trancher au fil de l'eau)
1. **Convention de matching Shopify** : `diag_session_id` (utilisé sur Baûbo) vs `_diag_session` + `lim_session_id` (doc template). Choisir UNE convention standard pour tous les futurs clients.
2. **Résolution URL dynamique crons** : Vault vs GUC custom vs tenant_config (cf. Étape 1).
3. **LOVABLE_API_KEY** : utilisé par l'AI Gateway (génération tenant_config via Gemini en Phase D). En sortant de Lovable, à remplacer par un appel direct Gemini/OpenAI/Anthropic. Concerne le portail admin, pas le dashboard.

## NE PAS RÉINTRODUIRE (pièges confirmés)
- Aucun `project_ref` en dur (ni celui du template, ni celui d'un client).
- Aucun ID de liste Klaviyo en dur.
- Aucune colonne/valeur spécifique-client dans le code générique.
- Ne pas auditer/importer depuis un projet client existant pour "comprendre la structure" : le repo est la source de vérité du template générique.

## CONTEXTE IMPORTANT
- Le schéma du template est SAIN (pas de "régression 5 juin" — c'était un artefact du remix Baûbo, pas du template). `session_code` est en `text`, toutes les tables standard présentes.
- ~60% du backlog d'avril (`docs/TEMPLATE_CORRECTIONS_BACKLOG.md`) est déjà appliqué (helpers de robustesse, hardening). Ce backlog est un PLAN daté d'avant Baûbo, pas un historique — ne pas s'y fier comme état réel.
- Les clients en prod (Baûbo, Demain Beauty, etc.) sont chacun sur leur propre projet Supabase Lovable. Sortir le template de Lovable ne les sort pas. Migration client par client, plus tard.
