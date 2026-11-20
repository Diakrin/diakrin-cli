# Diakrin coding-tool workflow

An employee describes an app in their own words; the agent saves it, prepares it and builds it on the company's universal web-app template until there is a working Preview the employee has tried. One core skill, [skills/diakrin/SKILL.md](skills/diakrin/SKILL.md), carries the whole journey:

1. **Save** the idea with `app.draft.create` (or resume with `app.draft.get`/`app.draft.list`). No technical questions, no identifiers asked of the employee.
2. **Ground, then propose**: `platform.context`, `app.draft.list`, `builder.context` and `integration.catalog` before a short product intake with selectable options.
3. **Prepare** with `app.prepare`. The server creates the app, its governed Preview project and blueprint, and returns blockers with who resolves them (`employee`, `it`, `agent`).
4. **Build** on the web-app template after reading `builder.context` and `app.contract`. Edit only `migrations/`, `src/app/`, `public/` and `diakrin.app.json`. Show the employee a running local preview (Diakrin's local engine, `~/.diakrin/bin/diakrin dev start`) and iterate there.
5. **Save** a version when the employee says it is ready (the local engine's `save` with a transfer from `app.code.transfer`, or `app.version.save`). Everything after a save is automatic: Diakrin checks the version, publishes its image to the company cloud and takes it to Preview. The agent reads the version (`app.version.get`; the console app page, Saved versions, shows the same) and reports its `preview` state (`queued`, `checking`, `building`, `deploying`, `ready`, `failed`, `unknown`, `stale`) in product words, opening the URL only when it is `ready`, then verifies the requested behaviour on it before reporting. Installations without automatic Preview keep the explicit `build.start` → `plan.preview` → `deployment.start` → `deployment.preview` path, described once in the skill.
6. **Company data** goes through `integration.catalog`, `integration.request-access` and `integration.request-connection`; approval is IT's and never automatic.
7. **Publish** to Production only on the employee's request, with independent approval.

What the agent starts: connect, create, save, publish. What Diakrin does after a save: check, image, Preview.

The MCP server already sends the builder instructions and the `create-app`, `continue-app`, `improve-app` and `share-app` prompts; the skill never duplicates or contradicts them. Apps run only in Preview and Production. An employee can change only the apps they own (`APP_OWNERSHIP_REQUIRED` otherwise); IT keeps infrastructure, policy and approvals. Builds and business data stay in the company cloud. Every tool the skill names is listed in [references/tool-contract.json](references/tool-contract.json); servers without the draft tools are covered in [references/legacy-tools.md](references/legacy-tools.md).

Diakrin's local engine (the Diakrin CLI 1.0.0 at `~/.diakrin/bin/diakrin`) is installed and kept updated by this plugin; see [references/cli.md](references/cli.md). It never signs in: Diakrin is reached only through the MCP tools, and the engine moves code with one-use transfers from `app.code.transfer`.

## Requirements

A Diakrin company account: your company uses Diakrin (the Diakrin cloud at https://app.diakrin.com, or its own installation). Diakrin is not a demo or a trial; without an account the tools only ask you to sign in.

## Install

- **Claude (claude.ai, Desktop, Cowork, Claude Code):** add Diakrin from the Claude directory, or add `https://api.diakrin.com/mcp` as a custom connector. The first call opens your company sign-in.
- **ChatGPT and Codex:** add Diakrin from the plugin directory. In Codex you can also run `codex mcp add diakrin --url https://api.diakrin.com/mcp`, then `codex mcp login diakrin`.

## What this plugin sends and runs

- **One MCP server:** `https://api.diakrin.com/mcp` (or your company's own Diakrin address). Your assistant sends it what the tools need: the app idea in your words, your answers, the files of a version you save, and the app and company identifiers the tools return. Diakrin never reads chat history, memory or files the assistant does not send to a tool. Sign-in is OAuth with your company account; tokens are short-lived and you can disconnect from the Diakrin console (AI tool connection → Connected assistants).
- **Diakrin's local engine (coding agents with a shell: Claude Code, Codex, Cursor):** at session start the plugin runs its own `engine/install.sh`, which installs the pinned engine (version and SHA-256 per platform in `engine/engine.env`) into `~/.diakrin` in the background, and then lets the engine check a signed update channel at most once a day (`DIAKRIN_NO_AUTO_UPDATE=1` turns it off). The engine runs the app on this computer with its own Node.js, pnpm and in-process database, and sends app code only to your company's Diakrin address with one-use transfers. Network: `github.com/Diakrin/diakrin-cli/releases` (engine and updates), `registry.npmjs.org` or your registry (the app's packages) and your Diakrin address. It stores no credentials.
- **Hooks:** a session-start hook (the installer above, in the background, never failing the session) and, in Claude Code and Cursor, an approval hook that approves exactly the engine's own commands (`pull`, `dev`, `check`, `save`) so the employee is not asked each time. The OpenAI directory package has no hooks; its skill runs the same installer when needed.
- **Nothing else:** no analytics from the plugin.

## Support and security

- Help: support@diakrin.com
- Security reports: security@diakrin.com (see https://diakrin.com/.well-known/security.txt)
- Privacy: https://diakrin.com/privacy · Terms: https://diakrin.com/terms
