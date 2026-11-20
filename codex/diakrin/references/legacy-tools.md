# Legacy tools (older servers only)

Use this reference **only** when the draft tools (`app.draft.create`, `app.draft.get`,
`app.draft.list`, `app.draft.update`, `app.prepare`) are not discovered on the connected server,
or when the employee explicitly selected an older shared project. Current servers hide most of
these tools from builders; the core [diakrin skill](../skills/diakrin/SKILL.md) and the server
instructions are the only path there. Nothing here changes the employee-facing rules: no
technical questions, no identifiers asked of the employee, no self-approval, Preview and
Production only.

## Intake and resume

- `app.start` is the older business intake: organization id, a concise business name and
  description, a retained UUID idempotency key and an optional explicitly selected project id.
  It returns `resume: {organizationId, projectId, startId}`; keep that tuple in credential-free
  local notes. A start id is not an app id, an operation id or a deployment handle.
- `app.get` with the saved resume re-reads the intake after a restart. It rechecks membership
  and project grants and reports observations without changing state or notifying owners. Never
  start a replacement intake because a read failed, and never change projects automatically.
- `app.update` persists enumerated business answers only: the unchanged resume, the returned
  policy revision, the latest session revision as `expectedRevision`, the answers and a retained
  UUID key for that exact write. Unknown fields are rejected; answers are not approvals.
- If the initial intake failed before its session committed, an explicitly requested retry of
  the identical `app.start` payload and key recovers the committed session rather than replacing
  it. Retry it after an owner blocker only when the owner's action resolved the gate, with the
  original key.
- `app.request-owner` on this path uses the complete resume plus a key, or the organization
  alone plus a key when setup blocked creation before a handle existed.

## Template-pinned intent sessions

- `intent.start`, `intent.get` and `intent.answer` are the older catalog-defined clarification
  flow. Every call pins the template id, version and per-template canonical digest. Start uses
  explicit organization, project and environment ids, the current policy revision,
  `expectedRevision: 0` and a retained UUID key. Resume with `intent.get` and the saved session,
  scope and pins after a reconnect; historical unpinned sessions stay unpinned.
- Relay at most three unresolved questions, in business words, with the approved choices and
  recommended defaults. A recommended default is a suggestion, not consent. A ready intent
  grants neither access nor approval.

## Established apps without a draft

- `app.list`, `app.read`, `app.create` and `app.edit` manage app identity and metadata. Retain
  the exact app id and the server-supplied operational scope. `app.edit` updates metadata with
  its revision and a UUID key; a normal edit cannot move an app across policy boundaries
  (`GROUP_POLICY_REVIEW_REQUIRED` means a separately reviewed migration, never a silent widening).
- `app.blueprint.save` stores reviewed requirements for an existing app: full scoped mutation
  context, current project and policy revisions, approved template id and version, name,
  summary, audience, business tasks, acceptance criteria, exact capability ids, retention days
  and an optional intent session id. The server pins the template digest. Fetch `app.contract`
  again after saving. Do not select every allowed capability.
- `project.list` and `project.get` read IT-managed shared project metadata only; they are not
  the app picker. `project.update` saves project requirements metadata (summary, audience, data
  classification) and preserves omitted environment and capability selections; it is not an app
  blueprint, not an approval, and never the way to change one app.
- `capability.list` explains which company capabilities are approved and available. It grants
  nothing: a selected capability, skill or template is never an authorization.
- `diagnostics.read` reports backend, MCP, identity and runtime connection diagnostics; use it to
  explain missing setup, never to infer that an app is healthy.

## Delivery on established apps

The order is the same as on current servers, with identifiers from `builder.context` after
reading the explicitly selected project: `app.contract` → `build.start` / `build.get` →
`plan.preview` / `plan.get` → `deployment.start` / `deployment.get` → `deployment.preview`.
`build.start` binds the current scoped mutation context, the latest contract digest and the
customer-selected repository source (repository id, exact 40-hex commit, manifest, lockfile,
template and toolchain digests). Never submit a moving branch or tag, switch repositories
silently, upload credentials or data, or invent a digest. A queued build or a local success is
not hosted acceptance.

## Connections and tokens

App-restricted connections limit which apps and operations are allowed; they grant no access of
their own. A bounded create connection uses `app.create` for one standalone app and becomes bound
to that app in the same transaction; do not assume it supports intake or a second app.
Organization tokens are broad, not app-restricted, and expire after one hour. OAuth is scoped
only when trusted identity supplies enforced restrictions.

## Hard stops

`SPECIFICATION_CHANGED` and `TEMPLATE_CHANGED` are review stops on every path. Keep the original
session, scope, answers, revisions and template pins; blocked intent inspection returns empty
questions and next actions. Explain that a review is needed and stop: no automatic answer,
rebase, revision rewrite, replacement session, code edit, build, plan or deployment.

Customer cloud management is agentless and owned by the Diakrin-hosted controller. Permanent
management-worker requests are retired; historical records do not authorize new installations.
Never fall back to shell commands, direct cloud APIs or another account. The dense boundary
notes behind these rules are kept in [builder-boundary.md](builder-boundary.md).
