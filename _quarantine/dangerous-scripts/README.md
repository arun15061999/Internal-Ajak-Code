# ⛔ QUARANTINED — destructive one-off scripts

These scripts were loose in the repository **root**, where a tab-complete or a stray
`psql -f *.sql` could run them against a live database. They are moved here so that running one
has to be a deliberate act.

**Do not execute anything in this directory.** Several cause immediate, hard-to-reverse damage,
and at least one is the confirmed root cause of an open CRITICAL finding.

Quarantined 2026-10-11 as Phase 1 of the remediation of the 2026-10-09 audit
(`qa-handoff/2026-10-09/`). No script was modified — only moved.

## What each one does

| Script | Effect if run | Verdict |
|---|---|---|
| `MANUAL_RLS_FIX.sql` | `ALTER TABLE ... DISABLE ROW LEVEL SECURITY` on `public.users`, `public.gdpr_consent_logs`, `public.gdpr_deletion_requests`, then `DROP POLICY` on several more (lines 11-16) | **Catastrophic.** Strips tenant isolation from the users table and two GDPR audit tables. Never run. |
| `disable-2fa-all-users.sql` | `UPDATE user_two_factor SET totp_secret = NULL` for every row (lines 10-13) | Destructive — never run. **But see the correction below: this loose script is not what ran, and it did not cause a lockout.** |
| `DEPLOY_2FA_FIX.js` | Applies the 2FA "fix" out of band | Superseded. The in-repo migration path is the only sanctioned route. |
| `EXECUTE_2FA_MIGRATION.js` | Same family as above | Superseded. |
| `deploy-2fa-fix.mjs` | Same family as above. **Was tracked in git** | Superseded. |
| `APPLY_MIGRATIONS.sql` | Bulk-applies a migration batch out of band | Dangerous. Production recorded three migrations under different version numbers than local, so re-running is not idempotent. |
| `RUN_ALL_MIGRATIONS.sql` | As above, whole chain | Dangerous, same reason. |
| `fix_migrations.py` | Rewrites migration files/history. **Was tracked in git** | Dangerous. Do not run against `supabase/migrations`. |
| `corrected_indexes.sql` | Creates/alters indexes | Review before any use; may lock tables. |
| `apply_email_logs.sql` | Creates email-log objects out of band | Contributes to the schema drift the audit records — objects created outside the migration chain. |

## Correction — what actually happened with 2FA

An earlier version of this file claimed `disable-2fa-all-users.sql` "already caused an open
CRITICAL" and that "nobody can log in". **Phase 2 triage established both claims are wrong.**
Recording the correction here because this README is where someone will look first.

**It is not this script that ran.** Three near-identical artefacts exist, and only one is in the
migration chain:

| Artefact | Tracked? | Execution evidence |
|---|---|---|
| `disable-2fa-all-users.sql` (this directory) | **No** — `git ls-files` returns only this README | **Zero.** No evidence it was ever run or even tracked |
| `supabase/migrations/20260503000000_disable_2fa_all_users.sql` | **Yes**, in the chain | This is the one that carries the evidence |
| `scripts/disable-2fa-all-users.ts` + `docs/root-docs/2FA_DISABLE_GUIDE.md` | Yes | Prospective authoring ("Files Created", "You should see output like:"), not a run log |

The tracked migration is assessed **EXECUTED (medium confidence)**, inferred from the chain being
applied past that point: `src/__tests__/fixtures/db-schema.json` is a real PostgREST snapshot of
the live project and records `user_two_factor.last_used_totp_step`, a column added only by
`20260927220100`. The snapshot was regenerated 2026-09-29, so the chain was applied through
2026-09-27 — and `20260503000000` sits five months earlier in the same directory. The migration is
data-only, so no DDL artefact can witness it directly; actual row state is
UNVERIFIABLE-WITHOUT-QA-DB.

**There is no lockout.** `src/lib/platform/security-settings.ts:41-51` makes 2FA required for
admin and student only when `hasEnabledFactor` is already true, and
`src/lib/security/two-factor-state.ts:28,35` computes
`enabled = is_enabled && totp_secret` then `setupRequired = required && !enabled`. For those roles
`required === enabled`, so `setupRequired` reduces to `enabled && !enabled` — **always false**.
With `totp_secret` NULL nobody is challenged, redirected or blocked. `KI-001`'s repro step
("observe the redirect to the 2FA challenge") cannot occur. `KI-001` is logged **FALSE-POSITIVE**.

`KI-001`'s second claim — that no enrolment path writes `totp_secret` — is also wrong:
`src/lib/security/two-factor-server.ts:235` does exactly that. The auditor grepped only
`supabase/migrations/` and generalised the result to the application code.

**What is real, and narrower:** admins are stuck re-enrolling. `src/app/api/v1/auth/2fa/setup/route.ts:31,38`
tests the **raw** `is_enabled` column while the state machine tests `is_enabled && totp_secret`, so
an admin row with `is_enabled=true, totp_secret=NULL` gets 409 on setup and 401 on reconfigure.
Teachers and students re-enrol freely. That defect is tracked on its own merits, at HIGH rather
than CRITICAL.

## Why they existed, and the real fix

Each is a symptom of the same underlying problem the audit found: **there is no sanctioned way to
apply a schema change to this project.** There is no `db:push` script, no live-vs-repo diff tooling,
and no apply record, so changes were made by hand and the scripts accumulated.

Quarantining them is containment, not a fix. The fix is a repeatable migration apply path with a
recorded state — tracked as the `schema-drift` theme in
[`qa-handoff/2026-10-09/REMEDIATION_LOG.md`](../../qa-handoff/2026-10-09/REMEDIATION_LOG.md).

## If you genuinely need one

1. Read it in full, including every `ALTER`, `DROP` and `UPDATE`.
2. Run it only against a **disposable, non-production** database. Never against
   `xjiqudbvmjavsywoqqrp`.
3. If it turns out to be needed repeatedly, it does not belong here — convert it into a numbered
   migration under `supabase/migrations/` and delete it from quarantine.
