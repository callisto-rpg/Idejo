<!--
SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Writing in Idejo

Idejo looks like a forum (categories, topics, messages) and every topic is a live chat.
What is different is how you write: **your message grows as you go.**

## The keys

| Key | What it does |
| --- | --- |
| **Enter** | Sends what you wrote. Everyone sees it at once. Keep typing and press Enter again: it joins the **same message**, on the same line. |
| **Shift+Enter** | A line break, as in any text box. Nothing is sent. |
| **Ctrl+Enter** | Sends too, on a **new line** of the same message. Once the window has passed (below), it **closes** your message instead: what you type next starts a new one. |

The text box below the topic is where you write. Its placeholder repeats the keys.

## How a message grows

1. You type a line and press Enter. Your message appears for everyone. What you sent **stays
   where you write**, looking like any message, while what you have not sent yet is
   highlighted as temporary. Text you just sent glows for a moment, then settles into the
   message. If your sentence had no punctuation, Idejo adds a full stop.
2. You keep writing and pressing Enter, as in a chat. Each part joins the same message.
   Others can reply meanwhile; their replies appear below your message, which keeps growing.
3. For a short while after your message starts (45 seconds, unless your server changed it),
   you can only add to it. Nothing shows this to others; it only means that one quick
   thought stays one message.
4. When you are done, press **Ctrl+Enter**: the message is complete, and your next line
   starts a new message.

Your message also completes when you leave the topic for more than 30 seconds, when the
topic is locked, or when a moderator closes it.

**On a phone or tablet** there is no Ctrl+Enter yet: your message keeps growing until you
leave the topic.

## Changing what you wrote

- **While your message is open**, change the text right in the box and press Enter. The
  changed part shows as unsent until you do.
- **After it is complete**, use **Edit** under it.
- **To delete it**, use **Edit**, remove all the text and save. You are asked "Are you sure
  you want to delete your own message?"; **Yes** deletes it, and others see "Message deleted
  by user" in its place (moderators can still read it). The first message of a topic cannot
  be deleted this way.

Once you change text you had already sent, a small **view earlier version** link appears
under the message, so everyone can see what it said before. Adding to the end is not a
change and keeps no history.

## Around a message

- **Reply** under someone's message: "Replying to …" appears above your box (**Cancel
  reply** to undo it). Your next new message is shown as a reply to theirs.
- **Inline links**, highlighted in the message:
  - **@username** mentions someone: they get a notification and follow the topic (unless
    they unfollowed it).
  - **+role** notifies everyone with that role who can read the topic, such as
    **+moderator**, and they follow the topic (unless they unfollowed it). Which roles you may tag is set by the administrators; others stay text.
  - **#topic**, **/category** and **$tag** link to a topic, a category or a tag. Type its
    web address name (`#garden-plans`, `/help`, `$bug`); once sent it reads its name.
  - After typing **@**, **+**, **#**, **/** or **$**, a list suggests the people, roles,
    topics, categories or tags you dealt with lately, narrowing as you type (`@rob` shows
    robert and Robin). Click one, or use the **arrow keys** and **Enter** (or **Tab**);
    **Escape** closes the list.
  - **Click** any of these links to see a small card: a preview, a button to open it, and
    **Follow** for a topic or **New topic** for a category.
- **Emoji**: write `:name:`, such as `:joy:`, `:tada:` or `:+1:`, or type an emoji; it shows
  as a picture. This server also has its own: `:agree:`, `:disagree:`, `:this:`, `:same:`,
  `:yes:`, `:no:`, `:bruh:`, `:nice:`, `:oof:`, `:thank-you:`, `:true:`.
- **Reactions**: point at a message and click **🙂** for eight quick choices, or **+** for
  every emoji (with a search box). Your reactions show under the message, with a count when
  several people chose the same one; click one to add yours or take it back. You may add
  several. The author is told once per message how many reactions it has.
- **Images**: paste or drop a picture (JPEG, PNG, GIF or WebP) into the box. In the editor
  for a new topic or an edit, there is also **Add image**.
- **Markdown** works: `**bold**`, `*italics*`, `` `code` ``, code blocks between ```` ``` ````
  lines, `> quotes`, lists and links. Messages have no length limit; a long one shows a
  **Show all** button.
- **New topic from this** turns a side question into its own topic, linked both ways.
- **Report** sends a message to the moderators, with a reason. Only they see that you
  reported it.
- Each message's time is its **permanent link**.

## Finding your way

- The **home page** shows the categories as cards, with their number of topics and last
  activity, and below them the **active topics**: the most recently active ones everywhere.
- The **sidebar** on the left lists the categories in the same order and groups as the home
  page (click a group's name to fold it away), and under each one the topics you follow there, in the order you joined them. Past four,
  **N more topics** shows the rest. A dot before a topic means something new since you last
  opened it: grey for new messages, blue when one of your `+roles` was mentioned, orange for
  a reply to you, red when you were mentioned (`@you`). The sidebar keeps itself up to date
  while the page is open, and a topic's name glows briefly when a new message arrives in it.
  The **×** next to a topic unfollows it. The topic you are reading is highlighted, and is
  listed even if you do not follow it, with a **+** to follow it. The button at the top left hides the sidebar, and your browser remembers;
  on a phone the same button opens it, and so does a swipe to the right (a swipe to the left
  closes it).
- **New topic**, on a category's page: a title, its **tags** (at least one, when the
  category has any) and a first message, with **Preview**. Nobody sees it before you post it.
- **Tags** show under a topic's title and in topic lists. Clicking one opens
  **Filter by tag** (also in the sidebar): tick one or more tags and **Show topics** lists
  the topics that carry all of them.
- **Rules & Roles** (in the sidebar): what this server is about, its rules, and the roles you
  may give yourself. You see them once when you join; change your roles there at any time.
- **Bubbles** appear at the top right as things happen: a new message in a topic you follow
  (grey), one of your `+roles` mentioned (blue), a reply to you (orange), you mentioned
  (red), a reaction to your message (purple). Each stays ten seconds (pointing at it pauses
  it); click it to go to the message, or × to dismiss it. Nothing bubbles about the topic
  you are reading.
- **Unread** (in the bar at the top) lists topics with messages you have not seen: first,
  under **Following**, every topic you follow, then the other topics. A message counts once,
  however much it grows. The number on it counts the unread messages that reply to you or
  mention you or one of your roles; its colour is that of the strongest, as for the
  sidebar's dots. It updates by itself.
- **Follow** / **Unfollow** on a topic. You follow topics you start or write in, until you
  unfollow them.
- **Search**, the box at the top, finds words in messages and titles.

## Your account

Click your name in the top right corner, then **Profile and account**, to change your
display name, add a picture (and, under **Dark mode picture**, another one for people
using the dark theme), change your password, or delete your account. The same menu
has the **Theme** (follow your system, light or dark) and **Sign out**. Your messages stay after
that, shown as "Deleted user".
