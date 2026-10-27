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
| **Ctrl+Enter** outside the box | Anywhere on the topic's page (not in another text box): starts a new message, sending what you had not sent yet, and puts the cursor in the box. While you cannot start one yet, it only puts the cursor at the end of your message, to go on writing. |
| **Enter** three times | The same as Ctrl+Enter: press Enter three times in a row, quickly, without typing in between. This is how it works on a phone or tablet, which has no Ctrl. |

The text box below the topic is where you write. Its placeholder repeats the keys, and a
small bubble beside the cursor says **Enter to send**; once you press it, **Sent!**, with
"Message now visible to all!" for two seconds, then "Continue typing to add to your
message" until you type again. These **tutorial bubbles**
(also on the timer line below, and on the sidebar's **×**) are chosen with **Tutorial
bubbles**, in the menu under your name or at the top of **Help**: **All** (the default),
**Simple** (only **Enter to send** and **Sent!**) or **Off**.

## How a message grows

1. You type a line and press Enter. Your message appears for everyone. What you sent **stays
   where you write**, looking like any message, while what you have not sent yet is
   highlighted as temporary. Text you just sent glows for a moment, then settles into the
   message. If your sentence had no punctuation, Idejo adds a full stop (unless you turned
   **Automatic punctuation** off under **Writing** in **Profile and account**).
2. You keep writing and pressing Enter, as in a chat. Each part joins the same message.
   Others can reply meanwhile; their replies appear below your message, which keeps growing.
   What others add to their messages glows the same way. While you type, a bubble over your
   message counts the messages above it that grew ("2 messages above have been appended");
   it fades when you scroll up to read them.
3. For a short while after your message starts (15 seconds, unless your server changed it),
   you can only add to it. Nothing shows this to others; it only means that one quick
   thought stays one message. While nobody has written below it, that lasts longer: until
   your message is 10 minutes old (unless your server changed it), Ctrl+Enter only adds a
   line, so when you write alone your thoughts stay one message. A thin orange line under
   the box fills up meanwhile, a **slow mode** bubble in front of it, and under it "You
   cannot start a new message...", "...but you can continue the one above." and "[Enter] to
   send always works." take turns; when it reaches the
   end it flashes and goes, the bubble moves to the middle and says **Ctrl+Enter to start
   new message**, and Ctrl+Enter starts a new message. If someone writes below you, it jumps to the shorter wait.
4. When you are done, press **Ctrl+Enter**, or **Enter three times**: the message is
   complete, and your next line starts a new message.

Your message also completes when you leave the topic for more than 30 seconds, when the
topic is locked, or when a moderator closes it.

**On a phone or tablet**, press Enter three times in a row instead of Ctrl+Enter.

## Changing what you wrote

- **While your message is open**, change the text right in the box and press Enter. The
  changed part shows as unsent until you do.
- **After it is complete**, use **Edit** under it: the box opens in your message with its
  text, and you change it or add to it as while writing, Enter saving each time. There is no
  timer: **Ctrl+Enter** (or Enter three times) saves and finishes the edit whenever you like.
  The text from before the edit is kept once, as an earlier version, however many times you
  pressed Enter.
- **To delete it**, use **Edit**, remove all the text and press Enter. You are asked "Are you sure
  you want to delete your own message?"; **Yes** deletes it, and others see "Message deleted
  by user" in its place (moderators can still read it). The first message of a topic cannot
  be deleted this way.
- **Your topic's title**: point at the title of a topic you started and click the pencil
  next to it (on a phone it always shows), change the title and **Save**. Its address
  changes with it; the old one still leads there. Locked and archived topics keep theirs.

Once you change text you had already sent, a small **view earlier version** link appears
under the message, so everyone can see what it said before. Adding to the end is not a
change and keeps no history.

## Around a message

A message's actions (**React**, **Edit**, **Reply** and the others) show when you point at
the message. On a phone or tablet, tap the message: they open in a bubble under it, which
goes away when you tap elsewhere or scroll.

- **Reply** under someone's message: "Replying to …" appears above your box (**Cancel
  reply** to undo it), and the box is a new message, shown as a reply to theirs. If your
  own message is still open, sending the reply completes it (when the server allows replies
  while the timer runs, as it does unless an administrator turned it off). Cancel the reply
  and the box stays a new message: Enter then says **You cannot post a new message yet**
  until your open message could be completed with Ctrl+Enter. **Append to my message** puts
  what you typed back after your open message instead.
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
- **Reactions**: click **React** under a message for eight quick choices (a click elsewhere
  closes them), or **+** for
  every emoji (with a search box). Your reactions show under the message, with a count when
  several people chose the same one; click one to add yours or take it back. You may add
  several. The author is told once per message how many reactions it has.
- **Images**: paste or drop a picture (JPEG, PNG, GIF or WebP) into the box, or use
  **!image** (below). In the box it shows as a small "image:" pill with the picture. In the
  editor for a new topic, there is also **Add image**.
- **Commands**: type **!** at the start of a word in the box for a list of commands. Pick one
  with a click, or type its name or use the arrow keys, then **Enter** (or **Tab**):
  - **!image** opens your files; the picture goes at the end of your message.
  - **!new-topic** sends what you wrote, then opens **New topic** with your message as its
    first message: give it a title (and a category, and tags if it has any). When you were
    replying, the new topic continues from the message you replied to. Your message stays
    where it is too, and the message the topic continues from gets a **Continue topic**
    button.
  - **!poll** sends what you wrote, then asks for a question, its answers (**Add an answer**
    for more than two, at most ten), whether **several answers** may be chosen, and in how
    many hours it closes (decimals work; at most 168). The poll goes under your message, one
    per message; with nothing written, the poll is posted on its own, its question as the
    message. Anyone who may post in the topic votes, and may **Change vote** until it
    closes. You see the counts from the start, others once they voted, and everyone once it
    closed; nobody sees who voted for what.
  - **!schedule** posts what you have not sent yet later: enter in how many hours (decimals
    work, such as `0.5` for half an hour; at most 168, a week). Only you see it until then,
    under the box, where **Cancel** takes it back. It is posted as one finished message,
    with a small **scheduled message** label. Text you already sent cannot be scheduled.
  - **!spoiler** sends what you wrote and hides your message (and its poll) behind a blur
    with a **Reveal spoiler** button, until each reader chooses it. Replies quoting it, the
    search results and notifications show *(spoiler)* instead of its words. Choose
    **!spoiler** again, while the message is still yours to continue, to show it plainly.
- **Markdown** works: `**bold**`, `*italics*`, `` `code` ``, code blocks between ```` ``` ````
  lines, `> quotes`, lists and links. Messages have no length limit; a long one shows a
  **Show all** button.
- **New topic from this** turns a side question into its own topic, linked both ways: the
  new topic says where it continues from, and the message gets a **Continue topic** button.
- **Report** sends a message to the moderators, with a reason. Only they see that you
  reported it.
- Each message's time is its **permanent link**.

## Finding your way

- The **home page** shows the categories as cards, with their number of topics and last
  activity, and below them the **active topics**: the most recently active ones everywhere.
- **View** (beside the home page's "Active topics" and at the top right of each category
  page): **Compact**, the usual one-line topics, or **Expanded**, where each topic also shows
  the start of its first message, the pictures posted in the topic at the right (four, then "+N images"), its three
  **latest messages** (two lines each; a picture in them shows as a small "image:" pill),
  and the pictures of who wrote there (five, then "+N more"). Your choice stays for the next
  pages. A topic's tags sit at the right, above its number of messages.
- The **sidebar** on the left lists the categories in the same order and groups as the home
  page, and under each one the topics you follow there, in the order you joined them. The
  small arrow beside a category folds it: then only its topics with new messages show (and
  the one you are reading); your browser remembers. Past four,
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
  the topics that carry all of them. **Operator** switches between **And** (all the ticked
  tags) and **Or** (at least one of them).
- **Rules & Roles** (in the sidebar): what this server is about, its rules, and the roles you
  may give yourself. You see them once when you join; change your roles there at any time.
- **Help** (in the sidebar, under Rules & Roles): the keys that send, the signs (`@`, `+`,
  `#`, `/`, `$`, `!`) and every `!` command, on one page.
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
- **Back in a topic** you opened before, the page opens on the oldest message you have not
  seen, under a red **N unread messages** line that fades after a few seconds. An unread
  message that mentions you (red) or one of your roles (blue) glows in that colour as you
  reach it, and the mention in it pulses.
- **Jump to a message**: once you scroll past a topic's title, a card at the right shows the
  title with **First message**, **First unread**, **Last message** and **My last message**.
  Where there is no room beside the conversation (on a phone), it is a small round button at
  the top right that opens the same list.
- **Follow** / **Unfollow** on a topic. You follow topics you start or write in, until you
  unfollow them, and the topics marked **Followed by everyone**, unless you unfollow them.
- **A topic's menu**: right-click a topic in a list or in the sidebar (on a phone, press and
  hold it) for **Follow** or **Unfollow**, **Unfollow & mute**, **Mark unread** and **Copy
  link**. A muted topic tells you nothing at all, even when someone mentions you
  (`@you` or one of your `+roles`) or replies to you, and stays off **Unread**, until you
  follow it again. **Mark unread** makes its latest message by someone else new again.
- **Search**, the box at the top, finds words in messages and titles.

## Private conversations

Click someone's name to open their card, then **Private Message**: a conversation only the
two of you can read. **Private Conversations**, at the very bottom of the sidebar, lists
yours as cards, with the latest message and how many are new; the number beside it counts
the conversations with something new.

Messages grow as in a topic, but there is no slow mode: **Ctrl+Enter** (or Enter three
times) starts a new message at once. You can still report a message there: moderators then
see that message, never the rest of the conversation. Search, the sidebar's categories and
**Unread** never show private conversations.

Under **Private messages** in **Profile and account**, untick **Members can send me private
messages** to stop new conversations with you, and messages to you in the ones you have.

## Your account

Click your name in the top right corner, then **Profile and account**, to change your
display name, add a picture (and, under **Dark mode picture**, another one for people
using the dark theme), change your password, or delete your account. The same menu
has the **Theme** (follow your system, light or dark) and **Sign out**. Your messages stay after
that, shown as "Deleted user".

**Writing**, on the same page, has **Automatic punctuation** (on at first): a full stop
after a line you send without punctuation at its end, never after code. Turn it off to keep
your messages exactly as typed; a topic page already open follows the change once reloaded.

**Email notifications**, on the same page: when you have not been on the server for 24
hours, you get one email counting what you missed, for what you tick: **@you mentions and
replies to your posts** and **new messages in a thread you created** (both on at first),
**+role mentions**, **new messages in a thread you follow**, **new topics** and **any
activity**. Only finished messages count, never muted topics. With **Don't send me a
second message in the same week if I don't log in** (on at first) you get at most one a
week while you stay away; without it, one a day. Nothing new, no email. Each email has a
link that stops them all in one click.

**Push notifications** show on your computer or phone even when the server is not open.
A bar on category and topic pages says when they are not enabled, once you have posted or
follow a topic: **Enable** asks your browser, **Dismiss** hides it for two weeks. Under **Push
notifications** in **Profile and account** you can:

- see whether this browser has them on, and **Turn on** (if your browser blocked them, it
  says how to allow them again);
- choose what sends one, for all your devices: **Replies to me**, **@you mentions**,
  **+role mentions**, **New messages in topics I follow** (at most one every half hour
  or so, counting the topics) and **Private messages** (who wrote, or with several unread,
  how many: "3 new private messages.");
- see your devices, with **Remove** for any you no longer use;
- **Send test notification** to every device.

You get one notification per message, however much it grows, and none while you have that
topic open. A notification opens the message, or **Unread** when there are several.

**On iPhone or iPad**, notifications come only from the site added to your Home Screen: in
Safari, tap **Share**, then **Add to Home Screen**, then open the server from its icon and
turn them on there.
