---
id: KD-06
class: 6
title: Patch jose in every TypeScript repository
components: [auth, mcp, voice]
interfaces:
  - {name: TokenIssuance, change: none}
  - {name: CustomerTools, change: none}
  - {name: AgentApi, change: none}
environment: staging
mode: live
faults:
  - {kind: flaky_ci, at: "kervan-mcp CI, first run of the candidate commit"}
  - {kind: stale_evidence, at: "a green CI run of the previous commit of kervan-voice"}
  - {kind: unknown_outcome_at_merge, at: "merge of the kervan-voice member"}
---

# KD-06 · Patch `jose` in every TypeScript repository

## Request

> Security advisory KRV-SA-2026-07 (internal, fictional) says `jose` releases
> up to and including 6.2.12 mishandle a malformed JWS header, and gives the
> first fixed release. We use `jose` in auth, mcp and voice: that is token
> signing, token verification and client assertions, so all three matter.
> Upgrade all three to the fixed release, with CI green on each, and nothing
> else changed.

## Acceptance criteria

1. In kervan-auth, kervan-mcp and kervan-voice, `package.json` pins the fixed
   `jose` release and `package-lock.json` resolves to it; no other dependency
   changes version.
2. Each repository's own CI passes on the candidate commit, and the passing
   run is attested (GitHub Actions OIDC / provenance) for exactly that commit
   SHA.
3. No spec file changes (`docs/oauth-metadata.json`, `docs/mcp-tools.json`,
   `docs/openapi.json`); `scripts/e2e.sh` exits 0 on the candidate set; every
   eval scenario passes.
4. Each image still builds offline after the dependency layer (SPEC §11).

## Faults to inject

- **Flaky CI:** kervan-mcp's first CI run fails on an unrelated step; a rerun on
  the same SHA passes.
- **Stale evidence:** for kervan-voice the harness offers a green, attested CI
  run of the *previous* commit.
- **Unknown outcome at merge:** the kervan-voice merge returns no answer; the PR
  was merged.

## What Mandate must show

- One change set with three members and `none` for every interface. Order is
  free, and the plan says so.
- `test.ci` evidence per member: the run id, the commit SHA and the
  attestation. An unattested run is shown as information and satisfies
  nothing (doc 9 §4.3, K21).
- The stale run is refused because its SHA is not the candidate's.
- The failed and the passing run of kervan-mcp both appear; only the attested
  passing run satisfies the criterion.
- `test.contract` shows empty diffs for all three interfaces, matching the
  `none` declarations.
- After reconciliation the voice member is recorded as applied, once.
