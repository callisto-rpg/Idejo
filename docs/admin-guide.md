<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Admin guide

For the people who run an Idejo community: owners, administrators and moderators. It starts
where [the deployment guide](deploying.md) ends, with the server installed and your owner
account made by the setup wizard. Everything here is done in the browser.

Give your members the [member guide](member-guide.md): one page on how writing in Idejo
works.

## How Idejo is organised

- **Categories** hold **topics**; every topic is a live conversation made of **messages**.
- A message **grows**: each time its author presses Enter, the new text joins the same
  message, live for everyone. For a short while after it starts (the **window**, 45 seconds
  by default) the author cannot start a second one; after that, Ctrl+Enter starts a new
  message. So a topic reads like a forum thread and feels like a chat.
- What people may do depends on their **roles** and on each category's **permissions**.

## Who can do what

Everyone has at least one role:

| Role | Who has it |
| --- | --- |
| **Owner** | You, from the setup wizard. Every right, always; can never be locked out or banned. Only owners give or take away the owner role. |
| **Administrator** | Every right, always, and the admin panel. Cannot be banned. |
| **Moderator** | Moderates every category (reports, lock, pin, move, delete, ban). |
| **Member** | Everyone with a verified email address, on top of their other roles. |
| **Guest** | Visitors who are not signed in, and people who have not verified their email yet. |

You can add your own roles, such as *Team* or *Help desk*, and give several roles to one
person.

There are five **rights**, per category: **View**, **Start topics**, **Post**,
**Moderate** and **Edit tags**. Out of the box, guests view; members view, start topics and
post; moderators also moderate and edit tags.

When someone has several roles, **allow wins**: a right is granted if any of their roles
allows it, even if another of their roles is denied it. Owners and administrators always
have every right, whatever the settings say.

## The admin panel

Owners and administrators find **Admin** in the menu under their name, in the top right
corner. It has seven tabs.

### Settings

- **Server name**: shown in the header, in page titles and in emails.
- **Who can sign up**: **Anyone**, or **Only people with an invite** (see [Invites](#invites)).
- **Growing-message window (seconds)**: from 10 to 600, 45 by default. It applies to messages
  started after you change it.
- **Largest image upload (MB)**: from 1 to 20, 3 by default.

### Email

New members must verify their email address before they can write, and password resets
come by email. **Until email works, nobody new can take part.** Fill in what your email
provider gives you (sender address, SMTP host, port, encryption, username, password), save,
then press **Send test email**: it goes to your own address, and the page shows why if it
fails. [The deployment guide](deploying.md#outgoing-email) has more detail.

### Users

Everyone who has an account, with their roles, newest first. Open a person to:

- **Give a role**: choose it and press **Give role**. Every verified user is a member
  already; the roles you give add to that.
- **Remove** a role. The server always keeps at least one owner, and you cannot remove your
  own administrator role, so nobody locks the server out by mistake.

The highest role that has a colour colours the person's name in topics.

### Categories

- **New category**: a name, an optional description, and optionally its web address
  (`/c/…`). The address is made from the name if you leave it empty and **never changes**,
  so links keep working when you rename the category.
- **Edit** renames a category or changes its description; the arrows change the order.
- **Delete**: a category with topics asks where they go: **Move to** another category, or
  **Archive**. Archived topics become read only and go to the **Archive** category, which is
  hidden from everyone until you show it to some roles in its permissions.

The usual start: *Announcements*, *General*, *Help*.

### Tags

- **New tag**: a name, and **For**: **All categories**, or one category. Names are unique
  across the server. Where a tag belongs never changes.
- When a category has tags (its own or those for all categories), starting a topic there
  takes **at least one**. A category with none takes topics without tags.
- **Rename** keeps the tag on its topics and its links. **Delete** takes it off every topic.
- A topic moved to another category keeps the tags for all categories and loses the old
  category's own; deleting a category deletes its own tags.
- Who may change a topic's tags is the **Edit tags** right in **Permissions**.

### Permissions

The grid of roles and rights.

- **Permissions** (the tab) holds the **server-wide** settings: for each role, a right is
  **Allow** or **Not allowed**. They apply to every category that does not say otherwise.
- **Permissions of a category** (from **Categories**, or **Where the settings apply**) sets
  each right for each role to **Server-wide** (follow the server-wide setting), **Allow** or
  **Deny**.
- Owner and administrator rows show **Always**: they cannot be changed.

Recipes:

| You want | Set in the category's permissions |
| --- | --- |
| A members-only category | Guest · View: **Deny** |
| Announcements only the team writes | Member · Start topics and Post: **Deny**; Team · Start topics and Post: **Allow** |
| A private room for the team | Guest and Member · View: **Deny**; Team · View, Start topics, Post: **Allow** |
| Someone who moderates only *Help* | A role such as *Help desk*, with Moderate: **Allow** in *Help* |

The team room works because **allow wins**: a team member is also a member (denied), but
their Team role allows. Changes apply at once, also to pages people have open.

### Invites

With **Only people with an invite** in [Settings](#settings), press **Create an invite
link** and send the link to one person. Each link works once, for 7 days. The list shows
which links are unused, used (and by whom) or expired.

### Roles

- **New role**: a name and an optional colour (`#rrggbb`).
- The arrows set the order: a higher role ranks higher, for the name colour and the role
  shown above each message. Owner and administrator stay on top, guest at the bottom.
- **Edit** renames a role or changes its colour (built-in roles only change colour);
  **Delete** removes a role you made, and its members lose it.

## Moderation

Moderators (the moderator role, or a role allowed to **Moderate** in a category) see
**Moderation** in the header, with the number of reported messages waiting. Every moderator
action asks for an optional reason and is recorded in the **Moderation log**, which
moderators see for their categories and administrators in full.

**Reports.** Members report a message with **Report** under it and a reason; only moderators
see who reported it. **Moderation** lists reported messages, the longest waiting first:
**Resolve** if you acted, **Dismiss** if not, with a note for the log.

**On a topic:** **Moderate this topic** (under the title):

- **Lock** / **Unlock**: a locked topic is read only; open messages in it close.
- **Pin** / **Unpin**: pinned topics stay first in their category.
- **Move to** another category you moderate. Links keep working.

**Edit tags** (under the title, with the **Edit tags** right): tick the topic's tags, at
least one, and **Save tags**. Logged like the rest, with the tags before and after.

**On a message:** **Moderate** (under the message):

- **Close message**: ends someone's open message, as if they had pressed Ctrl+Enter.
- **Delete message**: readers see "Message deleted by a moderator"; moderators still see the
  text and its history. Its open reports are resolved.
- **Edit**: correct someone's message, for example to remove personal data. Earlier
  versions are kept, and moderators see every version of any edited message.

**Bans.** Server moderators (owners, administrators, and roles allowed to moderate
server-wide) see **User actions** on a person's card: click an @mention of them in a topic,
or open their page, `/u/…`. Choose **Ban…**, then 1 day, 7 days, 30 days, a year or for
good, and a reason. They are signed out at once and cannot sign in until the ban ends or is
lifted with **Lift ban**, in the same menu. Their messages stay. Owners and administrators
cannot be banned.

## Backups and recovery

These need the server's command line, not the admin panel; [the deployment
guide](deploying.md) has the commands.

- **Backups** run every night at 03:00 UTC and keep the last 7. Make one before each update,
  and copy them off the server from time to time ([Backups](deploying.md#backups)).
- **Restore** a backup, also on a new server: [Restore a backup](deploying.md#restore-a-backup).
- **Lost the owner's password**, or email not working for a reset link:
  [Recovery from the command line](deploying.md#recovery-from-the-command-line).
- **Health check** of the server, database and last backup: same section.

## Good to know

- Every message, topic, category and person has a permanent link. Renaming or moving keeps
  old links working.
- Visitors, and search engines, see only what guests may view. A category guests may not
  view does not appear at all, not even its name.
- People delete their own account from **Profile and account**; their messages stay, shown
  as "Deleted user". The last owner cannot delete their account.
- Changes in the admin panel are recorded in an audit log in the database (who changed
  what, and when).
