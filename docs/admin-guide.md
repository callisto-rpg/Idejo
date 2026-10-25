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
  message, live for everyone. For a short while after it starts (the **window**, 15 seconds
  by default) the author cannot start a second one; after that, Ctrl+Enter (or Enter three
  times in a row) starts a new message. So a topic reads like a forum thread and feels like
  a chat.
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
- **Growing-message window (seconds)**: from 2 to 600, 15 by default. It applies to messages
  started after you change it.
- **Unanswered message time (minutes)**: from 1 to 1440 (a day), 10 by default. While nobody
  has written below a message, its author can start a new one (Ctrl+Enter, or Enter three
  times) only once the message is this old; until then it adds a line to the same message,
  so someone writing alone keeps one message. It applies at once, to open messages too.
- **Largest image upload (MB)**: from 1 to 20, 3 by default.
- **Push notifications**: **On** (the default) or **Off**. On, members can turn on
  browser notifications for replies, mentions and topics they follow. Off, they are not
  offered and none are sent.
- **About** and **Rules** (Markdown): shown to each new member once, in a welcome card with
  the roles they may choose, and at any time under **Rules & Roles** in the sidebar.
- **Privacy notice** (Markdown): shown on the **Privacy** page, linked from the foot of every
  page. Until you write one, the page says the server has not published a notice yet.

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

The highest role that has a colour colours the person's name in these lists.

### Categories

- **Groups** put categories under headings, on the home page and in the sidebar: create,
  rename, reorder (the arrows) or delete them (their categories stay, in no group). Choose a
  category's **Group** when you create or edit it. Categories in no group come last, under
  **Other**; with a single section, the heading stays **Categories**.

- **New category**: a name, an optional description, and optionally its web address
  (`/c/…`). The address is made from the name if you leave it empty and **never changes**,
  so links keep working when you rename the category.
- **Icon** and **Colour**: pick one of the icons (Topics, Sports, More) or **No icon**, and
  a colour as a hex code (`#3366ff`) or with the colour picker next to it; a preview shows
  the result. Without a colour, the category keeps a tint of its own; without an icon, it
  shows its initial.
- **Edit** renames a category or changes its description, icon or colour; the arrows change
  the order.
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

- **New role**: a name and an optional colour (`#rrggbb`). A role's name is written in its
  colour everywhere it appears, or in grey without one.
- The arrows set the order: a higher role ranks higher, for the name colour and the role
  shown next to each author's name. Owner and administrator stay on top, guest at the bottom.
- **Visible next to name** (on at first): turned off, the role still gives its rights, but
  conversations show the member's next role that is visible instead (often Member). Turn it
  off for Member to show only roles that stand out.
- **Edit** renames a role or changes its colour and **Visible next to name** (built-in roles
  keep their name);
  **Delete** removes a role you made, and its members lose it.
- **Can be tagged by everyone**: anyone may notify the role's members by writing
  **+role** (the role's name as shown in the list, such as `+help-desk`). Out of the box:
  owner, administrator and moderator.
- **Can tag roles beneath**: the role's members may notify any role ranked below it, even one
  not tagged by everyone. Out of the box: owner, administrator and moderator. Member and
  guest can never be tagged.
- Each role has a page at `/r/…` listing its members, which a **+role** links to.
- **Members can choose it** (custom roles only): members give themselves this role, or drop
  it, in the welcome card and under **Rules & Roles**. Whoever picks it gets every right the
  role has in **Permissions**, so give such roles no moderation rights.

### Stylesheet

CSS that every page loads after Idejo's own styles, so its rules win: change colours,
spacing, or anything else. **Save** applies it as pages load; **Reset to default** brings back
the stylesheet Idejo came with. The default sets how see-through the menus are (the
account menu, a topic's menu and the dropdowns: `--menu-opacity`, `--menu-blur`: 70% and
4px; any element with the `popup-menu` class), the cards and dialogs over a page, which
follow the menus (`--card-opacity`, `--card-blur`: give them values of their own to set
them apart), the welcome card (`--overlay-opacity`, `--overlay-blur`: 80% and 6px),
and the cover over a **!spoiler** message
(`--spoiler-opacity`, `--spoiler-blur`: 50% and 4px) with its **Reveal spoiler** button
(`--spoiler-button-opacity`, `--spoiler-button-blur`: 80% and 6px). A stylesheet saved before
these existed keeps working: menus and the cover then use those values anyway, and cards
keep the values it saved (**Reset to default** brings the menus' look to them). Each change is in the
audit log.

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
- **Archive topic**: the topic goes to the **Archive**, read only; its open messages close.
  The Archive is hidden from every role until an administrator shows it in
  **Permissions**, so readers (and moderators) no longer see it there.
- **Permanently delete topic** (under a line, in red): tick **Yes, delete this topic and all
  its messages for good**, then the button. Everything in the topic goes and cannot come
  back; the moderation log keeps its title and category (**Deleted a topic for good**).
  Archive it instead to keep it.

**Change the title:** point at the title and click the pencil next to it, then **Save**.
Starters change their own topic's title too, while it is open; moderators may also in
locked topics, and nobody in archived ones. A moderator's change to someone else's topic is
logged (**Renamed a topic**, with the titles before and after).

**Make everyone follow it** (owners and administrators, under the topic's moderation
form): everyone who may read the topic follows it, including members who join later, and
visitors see it in their sidebar. It shows a **Followed by everyone** badge. People can
still unfollow it, and each of them is notified of its new messages as with any topic they
follow. **Stop making everyone follow it** undoes it for those who never chose themselves.

**Edit tags** (under the title, with the **Edit tags** right): tick the topic's tags, at
least one, and **Save tags**. Logged like the rest, with the tags before and after.

**On a message:** **Moderate** (under the message) opens a card:

- **Close message**: ends someone's open message, as if they had pressed Ctrl+Enter.
- **Delete message**: readers see "Message deleted by a moderator"; moderators still see the
  text and its history. Its open reports are resolved.
- **Select multiple messages for deletion**: every message you may delete gets a checkbox
  (not your own, nor ones already deleted), and a banner at the top reads **Delete all
  selected messages**. Give a reason if you like and press **Delete selected**; each message
  is deleted as above and logged on its own.
- **Edit**: correct someone's message, for example to remove personal data. Earlier
  versions are kept, and moderators see every version of any edited message.
- **Select to be moved**: every message of the thread gets a checkbox (except its first
  message, which stays), and a banner at the top reads **Move all selected messages to**:
  - **New thread**: give it a title and a category; the earliest selected message opens it.
  - **Existing thread**: find it by title, or paste its link.
  Messages still being written are closed first. Moved messages keep their time, so in an
  existing thread they sit where their time puts them. Replies keep their links, and old
  links to the messages lead to their new thread. Logged, with the reason you give.

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
