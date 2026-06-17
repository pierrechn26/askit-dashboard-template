# HANDOFF.md — Passation pour pilotage autonome via Claude Code

Ce document permet de continuer le chantier "template autonome Ask-it" entièrement depuis Claude Code, sans dépendre de Lovable ni d'un assistant externe. À lire en complément de `CLAUDE.md` (contexte projet) et `docs/RUNBOOK_ONBOARDING_CLIENT.md` (v3).

---

## ÉTAT ACTUEL (17 juin 2026)

### FAIT ✅

- **48 migrations passent** sur base Supabase vierge (`npx supabase db push`). Projet de travail : `qrtxsnzhiuzjqdessevg`.
- **20 edge functions déployées** (`npx supabase functions deploy` — testé, fonctionne).
- **5 crons dynamiques** créés via wrapper `call_edge_function()` lisant Vault (testé, request_id retourné). Pas de project_ref en dur.
- **Lot 1 — sync-klaviyo-persona** : TExMiq supprimé → `tenant_config.klaviyo_list_id`, `$first_name` natif, `consented_at` email+SMS, `translateProp` avec `column_labels_mapping`. (commit `e1f5134`)
- **Lot 2 — diagnostic-webhook** : `item_metadata` dans `TOP_LEVEL_KEYS` + priorité explicite sur `c.item_metadata`. Plus de double-emballage. (commit `baac780`)
- **Lot 3 — aski-chat** : `number_of_children` retiré du SELECT. (commit `366d87b`)
- **Migrations corrigées** : `cron.unschedule` conditionnel, crons hardcodés neutralisés, `seed_template` → `manual`. (commit `f2a6332`)
- **Documentation** : CLAUDE.md, HANDOFF.md, Runbook v3 (remplace v2).
- **Infra** : SSH GitHub, Supabase CLI lié, Vercel lié.

### Corrections appliquées pour le db push
- `20260405081128_*.sql` : `cron.unschedule` conditionnel + `cron.schedule` neutralisé
- `20260429053431_*.sql` : `cron.schedule` neutralisé
- `20260415093000_*.sql` : seed P0 `seed_template` → `manual`
- `20260617000000_*.sql` : migration crons dynamique (wrapper Vault + 5 crons)

---

## TODO — par ordre de priorité

### TODO 1 — Nettoyage seeds Ouate (en cours)
- `client_plan` : seed Ouate (`project_id='ouate'`) à retirer (sera inséré par client au provisioning).
- `marketing_sources` : `project_id` DEFAULT 'ouate' + filtre `project_id` dans `monthly-market-intelligence`. À décider : retirer le filtre (sources globales) ou dupliquer par client.

### TODO 2 — mark-stale-sessions-as-abandoned
Logique **inexistante** dans le repo. Aucune edge function, aucun trigger SQL ne marque les sessions `en_cours` comme `abandonne` après un délai. Le marquage d'abandon est uniquement réactif (diagnostic-webhook, quand `abandoned_at_step` est envoyé).
**À implémenter :** edge function ou SQL direct : `UPDATE diagnostic_sessions SET status='abandonne', exit_type='abandon' WHERE status='en_cours' AND updated_at < NOW() - INTERVAL '24 hours'`. Puis ajouter le 6ème cron.

### TODO 3 — Dépendance Vault au provisioning
Chaque nouveau client nécessite 2 secrets Vault pour que les crons fonctionnent :
```sql
SELECT vault.create_secret('https://[REF].supabase.co', 'project_base_url', '...');
SELECT vault.create_secret('[ANON_KEY]', 'project_anon_key', '...');
```
Sans eux, les crons skippent silencieusement (warn dans les logs). Documenté dans le Runbook v3 Phase E.

### TODO 4 — Chantier séparé (LOURD) : moteur persona générique
`persona-priorities/index.ts` lignes ~41-74 : logique de scoring P1-P9 hardcodée Ouate. NE PAS traiter sans cadrage.

### TODO 5 — CI/CD
GitHub Action : sur push `supabase/functions/**` ou `supabase/migrations/**` → `supabase db push` + `supabase functions deploy`. Secrets GitHub nécessaires.

### TODO 6 — Script de provisioning
Scripter la séquence complète nouveau client (voir Runbook v3 Phases A→J).

---

## RÈGLES DE TRAVAIL (rappel)
1. Audit avant toute modif. Montrer le diff, attendre validation, puis appliquer.
2. Jamais de project_ref ou de valeur spécifique-client en dur.
3. Un correctif = un commit clair. Ne rien pousser sans validation.
4. Edge functions : modifier ≠ déployer. `npx supabase functions deploy` séparé.
5. Réparer vers le canonique, jamais patcher.

## NE PAS RÉINTRODUIRE
- Aucun `project_ref` en dur (ni template, ni client).
- Aucun ID de liste Klaviyo en dur.
- Aucune colonne/valeur spécifique-client dans le code générique.

## CONTEXTE
- Le schéma du template est SAIN. `session_code` en `text`, toutes les tables standard présentes.
- ~60% du backlog d'avril déjà appliqué (helpers, hardening). Lots 1-3 maintenant aussi.
- Clients en prod (Baûbo, etc.) restent sur Lovable. Migration séparée, plus tard.

## DÉCISIONS EN ATTENTE
1. Convention matching Shopify (`diag_session_id` vs `_diag_session`+`lim_session_id`).
2. Remplacement génération auto tenant_config (ex-Lovable Gateway/Gemini).
3. `marketing_sources` : retirer le filtre `project_id` dans `monthly-market-intelligence` ou dupliquer par client.
