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
corner. It has ten tabs.

### Settings

- **Server name**: shown in the header, in page titles and in emails.
- **Who can sign up**: **Anyone**, **Only people with an invite** (see [Invites](#invites)),
  or **Nobody (sign-ups closed)**: the sign-up page says the server is not taking new
  members, the Sign up links disappear, and invite links stop working too. Existing members
  are not affected.
- **Patience timer (active thread) (seconds)**: from 0 to 600, 15 by default: how long after
  a message's first line its author must wait before starting a new one. 0 means no wait
  once someone has written below. It applies to messages started after you change it.
- **Patience timer (unanswered message) (minutes)**: from 1 to 1440 (a day), 10 by default. While nobody
  has written below a message, its author can start a new one (Ctrl+Enter, or Enter three
  times) only once the message is this old; until then it adds a line to the same message,
  so someone writing alone keeps one message. It applies at once, to open messages too.
- **Allow replies even if the timer is still running**: on by default. **Reply** always
  starts a new message; with this on, sending it completes the author's open message at
  once. Off, a reply waits like Ctrl+Enter: until the active-thread patience timer (and,
  while nobody wrote below, the unanswered-message one) has passed.
- **Allow inactive topics**: on by default. A topic nobody follows (no member follows it,
  and it is not followed by everyone) is marked inactive and shown faded in topic lists;
  following it again makes it active. Off, every topic looks the same.
- **Inactive after (days)**: at least 7, 70 by default. A topic with no new message for
  this long is inactive too, even when people follow it; a new message makes it active.
- **Largest image upload (MB)**: from 1 to 20, 3 by default.
- **Performance**: how many messages a topic loads at a time; more load as readers scroll.
  **Normal (recommended)**, the default, loads 10 messages before the one a reader lands on
  and 30 after, 40 more at each scroll, and keeps at most 200 on the page; without
  JavaScript, a topic reads in pages of 50. **Light (for smaller servers)** loads half as
  many, **Heavy (for more powerful servers)** three times as many. It applies to pages
  opened after you change it.
- **Push notifications**: **On** (the default) or **Off**. On, members can turn on
  browser notifications for replies, mentions and topics they follow. Off, they are not
  offered and none are sent.
- **Minutes between followed-topic notifications** (30 by default, 1 to 1440): a member
  gets at most one "There are new messages in N topics you follow" notification in this
  time, and only when one of those topics has something new since the last.
- **Push services**: the only hosts the server sends browser notifications to, one per line.
  The defaults are the services of Chrome and Edge, Firefox, Safari and Windows;
  `*.example.org` allows any name under `example.org`. Add your own, for example a
  UnifiedPush server, if members' browsers use one. Addresses on private networks are always
  refused.
- **GIF provider key**: GIFs in messages (`!gif`, and a GIF button in the graphical
  composer) come from KLIPY. Create an app key in KLIPY's Partner Panel (partner.klipy.com)
  and paste it here; empty, there are no GIFs. Members' browsers then search KLIPY and load
  GIFs from it directly, as KLIPY's terms require, so KLIPY sees the address of everyone who
  searches for or reads a GIF: say so in your **Privacy notice**. Keep ads off for the key in
  the Partner Panel (Idejo shows none), and block words or GIFs there if you need to. A new
  key is in testing mode, limited to 100 searches an hour, until you ask KLIPY for production
  access.
- **GIF content filter**: how strictly KLIPY leaves unsafe GIFs out of searches: **Off**,
  **Low**, **Medium** (the default) or **High**.
- **About** and **Rules** (Markdown): shown to each new member once, in a welcome card with
  the roles they may choose, and at any time under **Rules & Roles** in the sidebar.
- **Privacy notice** (Markdown): shown on the **Privacy** page, linked from the foot of the
  **Help** page (in the sidebar), **Profile and account** and the admin pages, where the
  "Source code" link and the Idejo notice are too. Until you write one, the page says the server has not published a notice yet.
- **Theme**: the website's colours, as `#rrggbb` (or `#rrggbbaa` with transparency), typed
  or chosen with the colour button beside each. **Primary colour** fills buttons, toggles and
  links; **Secondary colour** and **Tertiary colour** appear only where a second colour is
  needed. **Light background** and **Dark background** are the page's in the light and dark
  themes. Text on a colour turns white or near-black, whichever reads better. The page loads
  again when you save a change, to show it. **Stylesheet** can still override them.
- **Logo**: your forum's own logo, shown in the header before the server name in place of
  Idejo's small logo. Choose a JPEG, PNG, GIF or WebP image (up to the image size limit): it
  is saved at once, fitted whole into the header's small square (transparency is kept; only
  the first frame of an animation) and the page loads again to show it. **Use the Idejo
  logo** goes back. The browser tab's icon and the app icon stay Idejo's.

### Info boxes

Your own text shown to everyone on the home page, before the categories and in their grid,
without a card around it: a welcome, links, the next event. **Create info box** takes a
**Title**, an **Icon** and **Colour** (the same choices as a category's), **Show title and
icon** (on by default; off, only the text shows) and a **Text (Markdown)** written in the
message editor, with its **Preview**. **Edit** changes one, the arrows change their
order, **Delete** removes one.

### Automessages

Ready-made messages that the server posts when someone types their command. Every server
starts with three, which you can change or delete like your own: `!tutorial-message` (how
Enter, Ctrl+Enter and `!image` work), `!tutorial-commands` (every `!` command) and `!rules`
(general rules to adapt), each ending with a link to the Help page or Rules & Roles.

Each automessage has a **Command (typed as !command)**: letters, digits, `-` and `_`, not
one of the composer's own commands (`!image`, `!forward`, `!new-topic`, `!poll`, `!schedule`,
`!spoiler`) or another automessage's. Its **Message (Markdown)** is what gets posted.
**Allow everyone to use this command** lets anyone who may post in a topic use it there;
off, only moderators of the topic's category (and you) can. **Wait before it can be used
again (minutes)** holds the command back in a topic once it was posted there, for
everybody (0: no wait; a deleted one does not count). **Sender's username** (`idejo`
unless you change it) and **Sender's picture (optional)** are the account it comes from.
That account belongs to the server: nobody signs in to it, and it is never mentioned,
suggested or notified. Automessages with the same sender's username share the account and
its picture; until you upload one, it shows the Idejo picture. A name a member already has
is refused.

**Post a poll** makes the automessage carry a poll, with the same fields as a poll in a
topic (question, answers with their emoji and colour, several answers, hidden results,
hours). Each use posts a new poll, open for those hours from then. With a poll, the
**Message** may be left empty: the question is then the message.

Those who may use them see the commands after `!` in the composer: choosing `!rules` posts
the `rules` text in the topic as its sender, while what they were writing stays in the
box. Each use is in the moderation log as **Had the server post an automessage**, with the
name of whoever used it. Links in the text are resolved as that person may see them;
`+role` tags notify the role's members whoever sends it, since you wrote the text.
**Edit** changes one, **Delete** removes it (what it posted stays).

### Plugins

Plugins add `!` commands to the composer. Idejo comes with four:

- `!youtube` puts a YouTube video under the message, from its link (`!youtube:link:`, or
  choose `!youtube` and paste it). Videos play from `youtube-nocookie.com`, which sees the
  address of everyone who plays one.
- `!iframe` shows another site's page in a frame under the message: paste the frame's code
  the site gives (`<iframe …>`) or its https address. Only the address is kept, and the
  frame is closed off: it cannot reach the forum, send forms or move the page. While it is
  on, the forum allows frames from any https site.
- `!button` adds a button in the theme's colour that opens a link (`!button:label:`, then
  the link).
- `!card` adds a button that opens a card of text formatted like a message
  (`!card:label:`, then the text).
- `!collapse` folds text: a line `!collapse title`, then lines starting with `:`. Readers
  see the title and unroll the rest with its arrow or by clicking it. Folds are kept as
  written: turning the plugin off or deleting it later does not unfold messages already
  sent.
- `!forum` searches the forums directory at `forums.idejo.org` and puts a small card for the
  chosen forum under the message: its logo, its name and a **Join** button. The logo is
  copied to this server when the card is posted, so readers' browsers never contact the
  other forum. A custom `forum` plugin can name another directory (`"directory"`, an https
  address answering `/api/forums?q=` like Idejo Hub's).

Each plugin is **off** until you tick **Enabled**. Owners and administrators may then use
it; **Add role** opens a list of roles: tick those whose members may use it too, then
**Save**. Members also need the right to post where they use it.

Each plugin is one `.json` file in the plugins folder (`IDEJO_PLUGINS_DIR`, by default
`plugins` in the uploads volume). **Delete a file there to remove its plugin**: its command
leaves the composer and what it added under messages stops showing (it shows again if the
file comes back). A plugin of Idejo's own that you delete is not put back by updates.

**Add custom plugin** uploads a plugin file. A plugin is never code: it names a command and
one of the four blocks above, so it can only do what they do. For example, a Vimeo plugin:

```json
{
  "idejo_plugin": 1,
  "command": "vimeo",
  "name": "Vimeo video",
  "description": "Add a Vimeo video under your message",
  "help": "Type !vimeo:link: with the video's link.",
  "argument": "link",
  "block": "video",
  "video": {
    "match": ["^https://vimeo\\.com/(?<id>\\d+)"],
    "embed": "https://player.vimeo.com/video/{id}"
  }
}
```

`command` takes lower-case letters, digits and `-`, and may not be one of Idejo's commands
or an automessage's. `argument` is `link` (a video's), `text` (a button's or card's label)
or `none`; `block` is `video`, `iframe`, `button`, `card`, `collapse` or `forum`. A video plugin's `match`
patterns (regular expressions) each find the video's `id`, which fills `{id}` in its https
`embed` address. A new plugin is installed off. A file Idejo cannot use is listed with the
reason.

### Email

New members must verify their email address before they can write, and password resets
come by email. **Until email works, nobody new can take part.** Fill in what your email
provider gives you (sender address, SMTP host, port, encryption, username, password), save,
then press **Send test email**: it goes to your own address, and the page shows why if it
fails. If the person who installed the server gave it an SMTP server in its environment,
the page says so above the form, with its host and port: email already works, and saving a
host here replaces that server. [The deployment guide](deploying.md#outgoing-email) has more
detail.

### Idejo ID

Lets members sign in with their **Idejo ID**, one account for every Idejo forum that uses
it; local accounts keep working.

- **Connect to Idejo ID** (login.idejo.org unless your server's host set another): it
  checks that your server answers at its own address, then gives it its sign-in
  credentials. The sign-in and sign-up pages then offer the Idejo ID button.
- **Renew the connection** gets new credentials (after a restore, for example);
  **Disconnect** stops sign-in with Idejo ID here (members keep their accounts).
- **Forums directory:** once connected, tick **List this forum on the forums directory** to
  ask to be listed. The directory's operator approves it; the page shows "Waiting for the
  directory's approval", then "Listed in the directory". Untick it to leave at once. Only
  forums that sign in with Idejo ID can be listed.

When the server's host sets a sign-in provider itself (`IDEJO_OIDC_*`, as Idejo Hub does),
this page only says so.

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
which links are unused, used (and by whom) or expired. While sign-ups are closed, the page
warns that invite links do not work.

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
the stylesheet Idejo came with. It may load nothing from another site and run nothing, so a
stylesheet with `@import`, a `url(…)` to another address (anything but a path on this server,
such as `/uploads/…`, or a `data:` image or font), or something that once ran script in
browsers (`expression(…)`, `behavior:`, `-moz-binding`, `javascript:`) is not saved: the page
says what it found, and your text stays in the box to fix. Upload an image first (in a
message, or as the logo) to use its `/uploads/…` address. The default sets how see-through the menus are (the
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

**Private conversations** are read only by the two people in them: not by moderators, and not
by owners or administrators either. When one of them reports a message, server moderators
(those who moderate every category) see that message in **Moderation**, marked "in a private
conversation", with its full text but no link into the conversation. Resolve or dismiss it
there, or **Delete message** (the note is the log's reason): both people in the conversation
then see "Message deleted by a moderator", and its reports are resolved. To act on the
account, open the author's card (their name) for **User actions**.

**On a topic:** **Moderate this topic** (under the title):

- **Lock** / **Unlock**: a locked topic is read only; open messages in it close.
- **Pin** / **Unpin**: pinned topics stay first in their category.
- **Move to** another category you moderate. Links keep working.
- **Archive topic**: the topic goes to the **Archive**, read only; its open messages close.
  The Archive is hidden from every role until an administrator shows it in
  **Permissions**, so readers (and moderators) no longer see it there.
- **Unarchive to …** (on an archived topic, in place of **Move to**): the topic leaves the
  Archive, open again, back in the category it was archived from (**Unarchived a topic** in
  the log). If that category no longer exists, pick one under **Unarchive to**, then
  **Unarchive**.
- **Permanently delete topic** (under a line, in red): tick **Yes, delete this topic and all
  its messages for good**, then the button. Everything in the topic goes and cannot come
  back; the moderation log keeps its title and category (**Deleted a topic for good**).
  Archive it instead to keep it.

**From a topic list** (owners, administrators and moderators): right-click a topic, press
the menu key or long-press it, in a list or in the sidebar. Under the usual items, for
topics in categories you moderate:

- **N following**: how many members follow the topic. Click it and it turns red as **Mark
  as inactive**; click again to mark the topic inactive (logged as **Marked a topic
  inactive**). It stays faded until someone sends a message there.
- **Archive**, **Move to…** (pick one of the categories you moderate) and **Delete** (click again on **Delete for
  good** to confirm), as in **Moderate this topic**. You stay on the page you were on.
- On an archived topic, **Unarchive to …** in place of Archive and Move: back to the
  category it came from, or **Unarchive to…** and pick one when it has none.

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

**Warnings.** Moderators of a category see **Warn user** on others' messages there. It opens
a card: write the reason (the member reads it), then **Warn**. **View N previous warnings**
lists the earlier warnings of that person you may see (those given in the categories you
moderate; owners and administrators see all), with who gave them and when. The member gets
a notification at once, and a card with the reason over whatever page they are on; when
they are away, the card waits for their next visit, on every page until they choose **I
understand**. With push notifications on, their devices are told too. Warnings are in the
moderation log as **Warned a member**. Owners, administrators, yourself and messages in
private conversations cannot be warned.

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
- With sign-in through an OpenID Connect provider (set by whoever installed the server,
  [deployment guide](deploying.md#sign-in-through-an-openid-connect-provider)), the sign-in
  and sign-up pages show its button. People who sign up with it become members under the
  usual **Who can sign up** rule (an invite link still needed when invite-only); the
  provider never gives a role: roles, bans and moderation stay yours, here. When passwords
  are switched off, owners and administrators can still sign in with a password, from the
  link under the button.
- Changes in the admin panel are recorded in an audit log in the database (who changed
  what, and when).
