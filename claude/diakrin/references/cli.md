# Diakrin's local engine (Diakrin CLI 1.0.0)

The Diakrin plugin installs **Diakrin CLI 1.0.0** as the local engine at `~/.diakrin/bin/diakrin` and keeps it updated
(within its major, from a signed update channel; a new major comes with a new plugin version). By hand (macOS and Linux):

```sh
curl -fsSL https://diakrin.com/cli/install.sh | sh
```

The engine **never signs in**. Diakrin is reached through the plugin's MCP tools; the engine only does what needs this
computer, with one-use, five-minute transfers that the MCP tool `app.code.transfer` hands out.

## Commands

| Step | Command (always the absolute path, always `--json`) | Notes |
|---|---|---|
| Get the code | `app.code.transfer {appId, purpose: "pull"}`, then `~/.diakrin/bin/diakrin pull --transfer <token> --name "<app name>" --json` | Folder `./<name in plain words>` (`data.folder`); in a folder of the same app, Diakrin's changes come in and local ones stay |
| Run it here | `~/.diakrin/bin/diakrin dev start --dir <folder> --open --json` | `data.url`; restart after changes; `dev status`, `dev logs`, `dev stop`. Needs `web-app` 1.1.0+ |
| Check it | `~/.diakrin/bin/diakrin check --dir <folder> --json` | Contract rules, typecheck, tests, render check; `data.findings` |
| Save it | `app.code.transfer {appId, purpose: "save"}`, then `~/.diakrin/bin/diakrin save --transfer <token> --dir <folder> --message "…" --json` | One version; follow it with `app.status` (`data.next`) |
| Is it set up? | `~/.diakrin/bin/diakrin doctor --json` | Offline; `--local --dir <folder>` checks one app folder |

`~/.diakrin/bin/diakrin --json schema [command…]` describes every command. Diakrin itself (create, prepare, status,
Preview, publish, data, approvals) is only MCP tools; there is no CLI command for them.

## Output and failures

`--json` prints one envelope: `{"schemaVersion":"1","ok":true,"data":{…}}` or `{"schemaVersion":"1","ok":false,"error":{"code","message","retryable","nextAction"}}`.
Do what `nextAction` says. A transfer works once: `TRANSFER_INVALID` means get a new one. `TRANSFERS_UNAVAILABLE`,
`ENGINE_NOT_SET_UP`, `ENGINE_UNSUPPORTED` or `LOCAL_PREVIEW_UNAVAILABLE`: use `app.source.read` / `app.version.save` and
Preview in Diakrin. `SOURCE_CONFLICT`: someone saved first; pull again into the same folder, then save. Never put a token in
a file, a message or a chat; the engine never prints one.

Keep app data, source execution and provider secrets customer-side. Save, check, image, Preview, authenticated audience
access and customer acceptance are separate states; never turn a local run into a claim that the app is live.
