# Diakrin

Diakrin lets any employee describe a business app in plain words and have Claude build it, under the company's IT and security rules, in the company's own cloud.

This plugin connects Claude to Diakrin and teaches Claude the Diakrin workflow:

1. Save the employee's idea as a draft, in their own words.
2. Propose a short first version and ask only the questions Diakrin needs.
3. Prepare the app, build it on Diakrin's approved web-app template, and save a version.
4. Diakrin checks every saved version and takes it to Preview; Claude shares the Preview link once it is ready.
5. Publishing happens only when the employee asks, with the company's real groups and approvals.

## What you need

A Diakrin company account: your company uses Diakrin (the Diakrin cloud at https://app.diakrin.com). Without an account, the Diakrin tools only ask you to sign in.

## What it contains

- **The Diakrin connector** (`https://api.diakrin.com/mcp`). You sign in once with your company account; Claude then acts only as you, on the apps you own or manage.
- **The Diakrin skill**, which tells Claude how to save, prepare, build, check and share an app with Diakrin.

It contains no hooks, scripts or programs. In claude.ai chat and Cowork, Claude saves and prepares the app and works on its code through the connector. To also run apps on your own computer in Claude Code, see the Diakrin docs: https://diakrin.com/docs/connect-claude

## Privacy and terms

- Privacy policy: https://diakrin.com/privacy
- Terms: https://diakrin.com/terms
- Docs: https://diakrin.com/docs
