# Accessibility

What Idejo promises (AX-01 to AX-04), how it is checked, and what a person still has to check
by hand before a release.

## Checked by the tests

`mix test` (and CI) runs `test/idejo_web/accessibility_test.exs`, which renders every page
(public, signed-in, moderation and admin) and the live topic in its states (composer,
message editor in Write and Preview, moderation forms). It audits the HTML with
`IdejoWeb.Accessibility` (`test/support/accessibility.ex`):

- `<html lang>`, exactly one `<main>`, a `<footer>`, and distinct names for several `<nav>`s;
- a skip link to `<main>` as the first stop of the keyboard;
- exactly one `<h1>`, and no skipped heading level;
- every text field, select and text area labelled; every link, button and summary named;
- every image with an `alt`; no `tabindex` above 0; nothing clickable that is not a link,
  button or form control; no link without `href`;
- unique ids, and every `for`, `aria-labelledby`, `aria-describedby` and `aria-controls`
  naming an element that exists.

It also checks that focus is outlined (`:focus-visible` in `assets/css/app.css`; the
composer's box draws it for its transparent text box), that the editor's Write / Preview
tabs follow the ARIA tabs pattern, and that the focus moves into the message editor and
back to "Edit" when it closes.

Other tests cover the rest: AX-02 and AX-03 (the live region and the text equivalents of
the open state, `test/idejo_web/live/assistive_text_test.exs`) and AX-04 (pages readable
without JavaScript, `test/idejo_web/public_pages_test.exs`).

The tests read HTML only: they cannot see colour contrast, the real focus order on screen,
or what a screen reader says.

## Keyboard audit (2026-10-21)

Done in Firefox with keys only (Tab, Shift+Tab, Enter, the arrows, Escape), on a production
build:

| Page or action | Result |
| --- | --- |
| Tab order on the topic page, as a visitor and as an owner | Logical: skip link, account links, site links, theme, category, then each message (time, @mentions, Moderate, Edit, Report, New topic from this, Reply), the composer, the footer |
| Visible focus on every stop of home, category, topic, new topic, settings, notifications, search, moderation and every admin page | Outlined everywhere |
| Skip link | First stop; Enter moves the focus to the main content |
| Signing in | Keyboard only |
| Composer | Enter sends; Ctrl+Enter inside the window continues the same message |
| Message editor | Opening it moves the focus to its text box (fixed in this audit: it was lost); Cancel or Save returns it to "Edit" (fixed too) |
| Write / Preview tabs | Arrow keys, Home and End switch tabs; Tab goes on to the text box (added in this audit) |
| @mention | Enter opens the user card with the focus on "Close"; Escape closes it and the focus returns to the mention |
| Theme buttons | Now named ("Use the light theme"…); they had no name |

Known limits: the composer takes images only by pasting or dropping (no picker, GM-07;
pasting works from the keyboard). Tab from the user card's only button leaves for the
browser's own controls, as the native modal `<dialog>` does.

## By hand before a release

The MVP definition of done asks for a check of the topic page with a keyboard **and a
screen reader**. The screen-reader part needs a person, with NVDA (Windows) or VoiceOver
(macOS), in a topic where two people talk:

1. The page reads as: heading of the topic, then each message with author, time and text.
2. When someone else starts a message, it is announced once ("Ada started a message.");
   its appends are not announced; when it closes, that is announced once ("Ada’s message is
   complete.") (AX-02).
3. An open message reads "(still being written)" (AX-03).
4. In the composer, the description gives the open state and the time left, and it
   changes when the window ends (AX-03, GM-07).
5. "view earlier version" opens and reads each version with its time (AX-03, GM-11).
6. The @mention card is announced as a dialog with the user's name.
7. The editor's tabs are announced as tabs, with "selected".

Record the result (date, screen reader and browser, findings) under this section.
