<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Contributing to Idejo

Thank you for helping. Idejo is licensed AGPL-3.0-only (see `LICENSE` and `NOTICE`).

## 1. Sign the CLA once

Before your first pull request can be merged, you sign the Contributor Licence Agreement
(LI-05). A bot comments on your PR with a link; reply with the sentence it gives you.
You keep your copyright and grant the project steward a perpetual, worldwide, royalty-free
copyright and patent licence, including the right to relicense. A DCO sign-off alone is not
enough. Contributing for an employer? Ask them to sign the corporate version first.

## 2. One requirement per pull request

Each PR implements one requirement ID from the specs, or fixes one bug (DV-05).

- Put the ID in the title: `GM-03: appends never extend the window`.
- Add or update tests named and tagged with the ID (DV-02):
  ```elixir
  @tag req: "GM-03"
  test "GM-03 appends never extend the window" do
  ```
- If a change needs behaviour the specs don't describe, open an issue first.

## 3. Every file gets an SPDX header

```elixir
# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only
```

Use the comment syntax of the file type. `reuse lint` must pass.

## 4. AI-assisted changes

AI tools are welcome, but a person selects, reviews and edits every change (LI-08).
Mark AI-assisted commits with a trailer on the last line of the message:

```
Assisted-by: Claude Code
```

Changes to authentication, permissions, uploads or security plugs
(`lib/idejo/accounts/`, `lib/idejo/access/`, `lib/idejo/uploads/`, `lib/idejo_web/plugs/`)
get a line-by-line human review (DV-06). Say so in the PR description.

## 5. Before you open the PR

```sh
mix precommit     # format, credo, compile warnings, tests
mix dialyzer
reuse lint
```

CI runs the same checks plus the security and dependency audits. New dependencies must use
a licence compatible with both AGPL-3.0 and a future proprietary licence (MIT, BSD,
Apache-2.0 and similar) (LI-06).

## 6. Development setup

See `docs/getting-started.md` and `CLAUDE.md`.
