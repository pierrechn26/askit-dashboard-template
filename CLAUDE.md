# CLAUDE.md — Contexte projet : Template Dashboard Ask-it V2

## Ce qu'est ce projet
Template de dashboard SaaS multi-tenant (Ask-it). Il est **remixé par client** : chaque client (Ouate, Demain Beauty, Cottan, Baûbo, etc.) obtient une copie de ce template, branchée sur son propre projet Supabase et son propre diagnostic. Le template doit donc rester **100% générique / brand-agnostic** : aucune valeur, colonne, ou logique spécifique à un client ne doit y vivre.

Stack : React + Vite + Tailwind (frontend) ; Supabase Postgres + Edge Functions (Deno) (backend). Intégrations : Shopify, Klaviyo, Anthropic API, Perplexity.

## Règles de travail IMPÉRATIVES
1. **Audit avant toute modification.** Ne jamais modifier un fichier sans l'avoir lu et sans avoir confirmé le diagnostic. Montrer le constat, attendre validation, puis corriger.
2. **Ne jamais inventer.** Si une information manque (schéma DB, valeur attendue), le dire et demander, ne pas supposer.
3. **Réparer vers le canonique, jamais patcher pour coller à un bug.** Si un schéma ou un contrat est cassé, le réparer vers l'état standard attendu, pas contourner.
4. **Un correctif = un commit clair**, avec un message explicite. Montrer le diff avant de commit. Ne pas grouper des correctifs non liés dans un même commit.
5. **Ne rien pousser sans validation explicite de l'utilisateur (Pierre).**
6. **Edge functions Supabase** : modifier le code ne suffit pas à le déployer. Le déploiement Supabase est séparé de Vercel (qui ne déploie que le frontend). Toujours préciser quand un correctif nécessite un redéploiement Supabase.

## Pièges connus — code hardcodé d'anciens clients (Ouate / LIM)
Le template traîne des résidus d'anciens clients, figés en dur dans le code générique. Ce sont les principaux problèmes à corriger. Découverts pendant l'onboarding Baûbo :

### 1. ID de liste Klaviyo hardcodé (CRITIQUE — fuite inter-clients)
`supabase/functions/sync-klaviyo-persona/index.ts` (~ligne 359) contient `id: "TExMiq"` en dur (liste d'un ancien client). Conséquence : tous les profils d'un nouveau client partent dans la liste Klaviyo d'un autre client. Doit être lu depuis `tenant_config.klaviyo_list_id`. Vérifier qu'AUCUNE autre fonction ne contient d'ID de liste en dur.

### 2. Colonnes legacy Ouate dans les .select() des edge functions
- `aski-chat/index.ts` (~ligne 307) : `.select()` liste `number_of_children`, `trust_triggers_ordered` (colonnes spécifiques Ouate, peuvent ne pas exister sur un tenant neuf → erreur 42703).
- `persona-priorities/index.ts` (~lignes 41-74) : `.select()` + **toute la logique de scoring P1-P9 est hardcodée Ouate** (`skin_concern`, `age_range`, `has_routine`, `is_existing_client`). Le moteur de scoring persona n'est donc pas générique. (= chantier lourd séparé, à ne pas traiter sans cadrage.)

### 3. diagnostic-webhook double-emballe item_metadata (silencieux)
`diagnostic-webhook/index.ts` (~lignes 637-643) : `"item_metadata"` est absent de `TOP_LEVEL_KEYS`. Donc un item entrant au format `{ item_label, item_metadata: {...} }` voit sa clé `item_metadata` ré-aspirée → double enveloppe `{ item_metadata: { item_metadata: {...} } }` en base. Casse silencieusement le tableau de réponses et l'enrichissement Klaviyo. Fix : ajouter `"item_metadata"` à `TOP_LEVEL_KEYS` + priorité stricte à `c.item_metadata` s'il existe (objet non vide), sinon `metadata` reconstruit.

### 4. Klaviyo (sync-klaviyo-persona) — plusieurs défauts
- Le prénom part en propriété custom (`user_name`) au lieu de l'attribut natif Klaviyo `$first_name`. Idem email → `$email`, téléphone → `$phone_number` natifs.
- Pas de `consented_at` sur le consentement SMS (Klaviyo refuse l'opt-in SMS sans timestamp).
- `column_labels_mapping` / `translateProp` pas lu côté Klaviyo → les valeurs partent en clés techniques (illisibles pour les filtres).

### 5. Dette mineure
- Coexistence `email_optin`/`sms_optin` (legacy) et `optin_email`/`optin_sms` (canonique) dans `types.ts` et certains hooks.
- Crons (`cron.job`) peuvent contenir un `project_ref` figé du template lors d'un remix → à re-scheduler post-remix.

## Référence de correction qui marche
Le projet **Baûbo** (séparé, déjà remixé) a déjà reçu toutes ces corrections, testées et validées en production (Klaviyo : first_name natif, consented_at, translateProp lisant column_labels_mapping, lecture tenant_config.klaviyo_list_id ; diagnostic-webhook : item_metadata dans TOP_LEVEL_KEYS). **Le code Baûbo est la référence de ce qui doit être porté sur le template.** Quand un correctif a une version Baûbo validée, s'en inspirer plutôt que réécrire.

## Ce qui N'EST PAS un problème (vérifié)
- Pas de régression schéma "5 juin" dans le template : `diagnostic_sessions` n'est jamais recréée from scratch, `session_code` est en `text` (pas varchar(7)), toutes les tables standard sont présentes (`api_usage_logs` pluriel, `recommendation_usage`, `tenant_commercial_facts`, `persona_detection_log`, `client_orders`, `client_products`). Ne pas "corriger" le schéma du template : il est sain. Les colonnes manquantes vues sur Baûbo venaient du remix/des pending_migrations, pas du template.

## Ordre de traitement prévu
- Lot 1 — Klaviyo (sync-klaviyo-persona) : hardcode TExMiq, $first_name natif, consented_at SMS, translateProp/column_labels_mapping. (le plus rentable, circonscrit à une fonction)
- Lot 2 — diagnostic-webhook : double-emballage item_metadata.
- Lot 3 — colonnes legacy Ouate dans aski-chat .select().
- Lot 4 — dette (nomenclature optin, crons).
- Chantier séparé (lourd, à cadrer) — rendre le scoring persona générique (persona-priorities).
