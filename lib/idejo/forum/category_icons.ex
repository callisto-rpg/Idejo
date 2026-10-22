# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.CategoryIcons do
  @moduledoc """
  The icons a category may take (RP-03; steward decision, 2026-10-23): the steward's three
  sets, Topics, Sports and More, drawn on a 32 px grid as a tile in the category's colour with
  the shapes cut out in white or black, whichever reads better on it.

  Each icon's shapes keep three placeholders: `{{bg}}` (the tile's colour), `{{fg}}` (the
  shapes') and `{{rx}}` (the tile's corner). They are parsed into a tree when this module
  compiles, so they are drawn as elements, never as raw HTML; `shapes/2` fills the
  placeholders in.
  """

  @icons [
    {"games", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="4.5" y="10.5" width="23" height="12.5" rx="6.25" fill="{{fg}}"></rect><g fill="{{bg}}"><rect x="8.5" y="15.6" width="6.4" height="2.4" rx="0.8"></rect><rect x="10.5" y="13.6" width="2.4" height="6.4" rx="0.8"></rect><circle cx="20.3" cy="15" r="1.5"></circle><circle cx="23" cy="18.4" r="1.5"></circle></g>|},
    {"sports", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><path d="M5.5 16 L26.5 16 M16 5.5 L16 26.5 M9 8.2 C13 12 13 20 9 23.8 M23 8.2 C19 12 19 20 23 23.8" stroke="{{bg}}" stroke-width="1.8" fill="none"></path>|},
    {"live", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="3.3" fill="{{fg}}"></circle><path d="M11.5 11.5 A6.36 6.36 0 0 0 11.5 20.5 M20.5 11.5 A6.36 6.36 0 0 1 20.5 20.5 M8 8 A11.31 11.31 0 0 0 8 24 M24 8 A11.31 11.31 0 0 1 24 24" stroke="{{fg}}" stroke-width="2.6" stroke-linecap="round" fill="none"></path>|},
    {"cinema", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="5.5" y="7.5" width="21" height="4.5" rx="1.2" fill="{{fg}}"></rect><g fill="{{bg}}"><path d="M10 7.5 L12.6 7.5 L10.4 12 L7.8 12 Z"></path><path d="M16 7.5 L18.6 7.5 L16.4 12 L13.8 12 Z"></path><path d="M22 7.5 L24.6 7.5 L22.4 12 L19.8 12 Z"></path></g><rect x="5.5" y="13.5" width="21" height="12.5" rx="2" fill="{{fg}}"></rect>|},
    {"music", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><ellipse cx="10.6" cy="22.2" rx="3.6" ry="2.9"></ellipse><ellipse cx="21.6" cy="20.2" rx="3.6" ry="2.9"></ellipse><rect x="11.8" y="9" width="2.4" height="13"></rect><rect x="22.8" y="7" width="2.4" height="13"></rect><path d="M11.8 8.8 L25.2 6.3 L25.2 9.9 L11.8 12.4 Z"></path></g>|},
    {"plants", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M7 25 C7 13.5 13.5 7.5 25 7 C24.5 18.5 18.5 25 7 25 Z" fill="{{fg}}"></path><path d="M7.8 24.2 L19.5 12.5" stroke="{{bg}}" stroke-width="1.9" stroke-linecap="round"></path>|},
    {"animals", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><ellipse cx="16" cy="21" rx="5.8" ry="4.8"></ellipse><ellipse cx="8.8" cy="14.6" rx="2.4" ry="2.9"></ellipse><ellipse cx="13.2" cy="9.6" rx="2.5" ry="3"></ellipse><ellipse cx="18.8" cy="9.6" rx="2.5" ry="3"></ellipse><ellipse cx="23.2" cy="14.6" rx="2.4" ry="2.9"></ellipse></g>|},
    {"books", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><path d="M15.2 10.2 C12.5 8.3 9.3 7.6 5.5 8 L5.5 23 C9.3 22.6 12.5 23.3 15.2 25 Z"></path><path d="M16.8 10.2 C19.5 8.3 22.7 7.6 26.5 8 L26.5 23 C22.7 22.6 19.5 23.3 16.8 25 Z"></path></g>|},
    {"food", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M5.5 15.5 L26.5 15.5 C26.5 21.5 21.8 25.5 16 25.5 C10.2 25.5 5.5 21.5 5.5 15.5 Z" fill="{{fg}}"></path><path d="M11.5 6.5 C10.2 8 12.8 9.8 11.5 12 M16 6.5 C14.7 8 17.3 9.8 16 12 M20.5 6.5 C19.2 8 21.8 9.8 20.5 12" stroke="{{fg}}" stroke-width="2" stroke-linecap="round" fill="none"></path>|},
    {"travel", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M5 15 L26.5 6 L20 26.5 L15.3 18.5 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="1" stroke-linejoin="round"></path><path d="M15.3 18.5 L25.5 7" stroke="{{bg}}" stroke-width="1.7" stroke-linecap="round"></path>|},
    {"art", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M16 5.5 C10 5.5 5.5 10.2 5.5 16 C5.5 21.8 10.2 26.5 16 26.5 C18.2 26.5 18.7 24.8 17.9 23.2 C17.1 21.6 18.1 20 20 20 L22.3 20 C24.8 20 26.5 18 26.5 15.4 C26.5 10 21.8 5.5 16 5.5 Z" fill="{{fg}}"></path><g fill="{{bg}}"><circle cx="10.8" cy="13.2" r="1.9"></circle><circle cx="15.4" cy="10.2" r="1.9"></circle><circle cx="20.6" cy="11.3" r="1.9"></circle><circle cx="10.6" cy="18.8" r="1.9"></circle></g>|},
    {"science", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="11.5" y="5.5" width="9" height="2.6" rx="1.3" fill="{{fg}}"></rect><path d="M13.5 7.5 L13.5 13.5 L7.6 23.3 C6.8 24.8 7.8 26.3 9.5 26.3 L22.5 26.3 C24.2 26.3 25.2 24.8 24.4 23.3 L18.5 13.5 L18.5 7.5 Z" fill="{{fg}}"></path><path d="M10.6 19.2 L21.4 19.2" stroke="{{bg}}" stroke-width="1.7"></path>|},
    {"news", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="5.5" y="6.5" width="21" height="19" rx="2" fill="{{fg}}"></rect><g fill="{{bg}}"><rect x="8.5" y="9.5" width="15" height="3.2" rx="0.8"></rect><rect x="8.5" y="15.2" width="6.2" height="7.3" rx="0.8"></rect><rect x="16.8" y="15.2" width="6.7" height="1.9" rx="0.9"></rect><rect x="16.8" y="18.2" width="6.7" height="1.9" rx="0.9"></rect><rect x="16.8" y="21.2" width="4.5" height="1.9" rx="0.9"></rect></g>|},
    {"photo", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="11" y="7" width="10" height="5" rx="1.5" fill="{{fg}}"></rect><rect x="4.5" y="10" width="23" height="15.5" rx="3" fill="{{fg}}"></rect><circle cx="16" cy="17.6" r="5.2" fill="{{bg}}"></circle><circle cx="16" cy="17.6" r="2.9" fill="{{fg}}"></circle>|},
    {"tech", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M11 10 L5.5 16 L11 22 M21 10 L26.5 16 L21 22 M18.2 8.5 L13.8 23.5" stroke="{{fg}}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" fill="none"></path>|},
    {"learning", :topics,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M9.5 15.5 L9.5 21 C12 23.8 20 23.8 22.5 21 L22.5 15.5 Z" fill="{{fg}}"></path><path d="M16 7 L28 13 L16 19 L4 13 Z" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.5" stroke-linejoin="round"></path><path d="M25.5 14.5 L25.5 20" stroke="{{fg}}" stroke-width="1.8" stroke-linecap="round"></path><circle cx="25.5" cy="21.2" r="1.6" fill="{{fg}}"></circle>|},
    {"soccer", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><path d="M16 12.2 L19.61 14.83 L18.23 19.07 L13.77 19.07 L12.39 14.83 Z" fill="{{bg}}"></path><path d="M16 12.2 L16 5.5 M19.61 14.83 L25.99 12.76 M18.23 19.07 L22.17 24.49 M13.77 19.07 L9.83 24.49 M12.39 14.83 L6.01 12.76" stroke="{{bg}}" stroke-width="1.6"></path>|},
    {"football", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g transform="rotate(-35 16 16)"><path d="M3.5 16 C7.5 8.6 24.5 8.6 28.5 16 C24.5 23.4 7.5 23.4 3.5 16 Z" fill="{{fg}}"></path><path d="M11.5 16 L20.5 16 M13 14.2 L13 17.8 M16 14.2 L16 17.8 M19 14.2 L19 17.8" stroke="{{bg}}" stroke-width="1.5" stroke-linecap="round"></path><path d="M8.2 12.6 C7.4 14.8 7.4 17.2 8.2 19.4 M23.8 12.6 C24.6 14.8 24.6 17.2 23.8 19.4" stroke="{{bg}}" stroke-width="1.4" fill="none"></path></g>|},
    {"rugby", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g transform="rotate(35 16 16)"><ellipse cx="16" cy="16" rx="11.2" ry="7.6" fill="{{fg}}"></ellipse><path d="M5.8 13.8 C11 11.2 21 11.2 26.2 13.8 M5.8 18.2 C11 20.8 21 20.8 26.2 18.2" stroke="{{bg}}" stroke-width="1.4" fill="none"></path></g>|},
    {"tennis", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g transform="rotate(45 16 16)"><ellipse cx="16" cy="10.5" rx="6.4" ry="7.4" stroke="{{fg}}" stroke-width="2.4" fill="none"></ellipse><path d="M13 4.8 L13 16.2 M16 3.6 L16 17.4 M19 4.8 L19 16.2 M10.2 7.5 L21.8 7.5 M9.8 10.5 L22.2 10.5 M10.2 13.5 L21.8 13.5" stroke="{{fg}}" stroke-width="1"></path><rect x="14.8" y="17.6" width="2.4" height="10.4" rx="1.2" fill="{{fg}}"></rect></g><circle cx="8.3" cy="8.8" r="2.7" fill="{{fg}}"></circle>|},
    {"basketball", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><path d="M5.5 16 L26.5 16 M16 5.5 L16 26.5 M9 8.2 C13 12 13 20 9 23.8 M23 8.2 C19 12 19 20 23 23.8" stroke="{{bg}}" stroke-width="1.7" fill="none"></path>|},
    {"baseball", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><path d="M9.2 7.2 C12.8 11 12.8 21 9.2 24.8 M22.8 7.2 C19.2 11 19.2 21 22.8 24.8" stroke="{{bg}}" stroke-width="1.6" fill="none"></path><path d="M10.2 10.8 L12.6 10 M11 14.2 L13.4 13.8 M11 17.8 L13.4 18.2 M10.2 21.2 L12.6 22 M21.8 10.8 L19.4 10 M21 14.2 L18.6 13.8 M21 17.8 L18.6 18.2 M21.8 21.2 L19.4 22" stroke="{{bg}}" stroke-width="1.2" stroke-linecap="round"></path>|},
    {"volleyball", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><path d="M16 16 C16 10.5 19 7 22.6 6.4 M16 16 C11.2 18.8 7.2 18.4 5.6 17 M16 16 C20.6 18.8 21.8 23 21 26 M11.2 6.7 C11.2 10.2 13 13.8 16 16" stroke="{{bg}}" stroke-width="1.7" stroke-linecap="round" fill="none"></path>|},
    {"hockey", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M8 5.5 L19 21.5 L24.5 21.5" stroke="{{fg}}" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" fill="none"></path><path d="M24 5.5 L13 21.5" stroke="{{bg}}" stroke-width="5" stroke-linecap="round"></path><path d="M24 5.5 L13 21.5 L7.5 21.5" stroke="{{fg}}" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" fill="none"></path><rect x="12.5" y="24.2" width="7" height="3.2" rx="1.6" fill="{{fg}}"></rect>|},
    {"golf", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M11 6 L11 24.5" stroke="{{fg}}" stroke-width="2.2" stroke-linecap="round"></path><path d="M12 5.5 L23 9.5 L12 13.5 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="1" stroke-linejoin="round"></path><ellipse cx="12.5" cy="25.6" rx="7.5" ry="1.9" fill="{{fg}}"></ellipse><circle cx="23" cy="21.6" r="2.7" fill="{{fg}}"></circle>|},
    {"tabletennis", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M18.6 18.6 L25 25" stroke="{{fg}}" stroke-width="4.2" stroke-linecap="round"></path><circle cx="13.5" cy="13.5" r="8" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.4"></circle><circle cx="24.5" cy="7.8" r="2.6" fill="{{fg}}"></circle>|},
    {"swimming", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="21.8" cy="9.6" r="2.9" fill="{{fg}}"></circle><path d="M7.5 15.8 C10 10.5 15.5 9.5 18.6 13.2" stroke="{{fg}}" stroke-width="2.8" stroke-linecap="round" fill="none"></path><path d="M4.5 20 C7 18.3 9 18.3 11.5 20 C14 21.7 16 21.7 18.5 20 C21 18.3 23 18.3 25.5 20 C26.3 20.5 26.9 20.8 27.5 20.9 M4.5 25.2 C7 23.5 9 23.5 11.5 25.2 C14 26.9 16 26.9 18.5 25.2 C21 23.5 23 23.5 25.5 25.2 C26.3 25.7 26.9 26 27.5 26.1" stroke="{{fg}}" stroke-width="2.3" stroke-linecap="round" fill="none"></path>|},
    {"cycling", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g stroke="{{fg}}" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"><circle cx="8.8" cy="20.5" r="5"></circle><circle cx="23.2" cy="20.5" r="5"></circle><path d="M8.8 20.5 L15.5 20.5 L21.5 12.5 L13 12.5 Z M13 12.5 L12.4 9.8 M10.6 9.8 L14.4 9.8 M21.5 12.5 L23.2 20.5 M21.5 12.5 L20.6 9.4 L23.6 9.4"></path></g>|},
    {"running", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M4.5 20.8 L4.5 15 C4.5 13.5 5.5 12.5 7 12.5 L9 12.5 C10.5 12.5 11.5 13.8 13 13.8 C14 13.8 14.8 13 15.2 11.5 L15.8 9.3 L18.2 10.4 L21.5 15.4 L25 16.7 C26.8 17.3 27.5 18.6 27.5 20 L27.5 20.8 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="0.8" stroke-linejoin="round"></path><path d="M16.6 13.4 L18.6 12.2 M17.8 15.6 L19.8 14.4" stroke="{{bg}}" stroke-width="1.3" stroke-linecap="round"></path><rect x="4.5" y="22" width="23" height="3" rx="1.5" fill="{{fg}}"></rect>|},
    {"skiing", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M12.5 27 L12.5 9.5 C12.5 7 11.2 5.6 9.6 5.4 M19.5 27 L19.5 9.5 C19.5 7 20.8 5.6 22.4 5.4" stroke="{{fg}}" stroke-width="2.9" stroke-linecap="round" fill="none"></path><path d="M7.5 9 L24.5 24.5 M24.5 9 L7.5 24.5" stroke="{{bg}}" stroke-width="3.8" stroke-linecap="round"></path><path d="M7.5 9 L24.5 24.5 M24.5 9 L7.5 24.5" stroke="{{fg}}" stroke-width="1.7" stroke-linecap="round"></path><g fill="{{fg}}"><circle cx="7.5" cy="9" r="1.6"></circle><circle cx="24.5" cy="9" r="1.6"></circle></g>|},
    {"boxing", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M9.5 13 C9.5 8.5 12.5 6 17 6 L18.8 6 C23.2 6 26.2 9.5 26.2 14 L26.2 18.5 C26.2 21 24.7 22.5 22.7 22.5 L12.5 22.5 C10.7 22.5 9.5 21.3 9.5 19.5 Z" fill="{{fg}}"></path><ellipse cx="8.8" cy="17.4" rx="3.3" ry="3.8" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.4"></ellipse><rect x="11.5" y="23.8" width="13" height="3.4" rx="1" fill="{{fg}}"></rect>|},
    {"motorsport", :sports,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M7 5.5 L7 27" stroke="{{fg}}" stroke-width="2.2" stroke-linecap="round"></path><rect x="8.6" y="6.2" width="17" height="12" fill="{{fg}}" stroke="{{fg}}" stroke-width="1.2" stroke-linejoin="round"></rect><g fill="{{bg}}"><rect x="8.6" y="6.2" width="4.25" height="4"></rect><rect x="17.1" y="6.2" width="4.25" height="4"></rect><rect x="12.85" y="10.2" width="4.25" height="4"></rect><rect x="21.35" y="10.2" width="4.25" height="4"></rect><rect x="8.6" y="14.2" width="4.25" height="4"></rect><rect x="17.1" y="14.2" width="4.25" height="4"></rect></g>|},
    {"general", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M6.5 12 L21 12 L21 19.5 C21 22.8 18.5 25.5 15 25.5 L12.5 25.5 C9 25.5 6.5 22.8 6.5 19.5 Z" fill="{{fg}}"></path><path d="M21 14.5 L22.5 14.5 C24.5 14.5 25.6 15.8 25.6 17.3 C25.6 18.8 24.5 20.2 22.5 20.2 L21 20.2" stroke="{{fg}}" stroke-width="2.4" fill="none"></path><path d="M11 5.5 C10 7 12 8.3 11 9.8 M15.5 5.5 C14.5 7 16.5 8.3 15.5 9.8" stroke="{{fg}}" stroke-width="1.9" stroke-linecap="round" fill="none"></path>|},
    {"qa", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="5.5" y="6" width="21" height="15.5" rx="4" fill="{{fg}}"></rect><path d="M10 20.5 L10 26.5 L16.5 20.5 Z" fill="{{fg}}"></path><path d="M13.3 11.4 C13.3 9.8 14.5 8.9 16 8.9 C17.6 8.9 18.8 9.9 18.8 11.3 C18.8 13.2 16 13.5 16 15.4" stroke="{{bg}}" stroke-width="2.3" stroke-linecap="round" fill="none"></path><circle cx="16" cy="18.4" r="1.35" fill="{{bg}}"></circle>|},
    {"announce", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M5.5 12.5 L11 12.5 L22 6.5 L22 25.5 L11 19.5 L5.5 19.5 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="1.2" stroke-linejoin="round"></path><path d="M9 19.5 L11 25.8 L14.3 25.8 L12.8 19.5 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="1" stroke-linejoin="round"></path><path d="M25.8 12.8 L25.8 19.2" stroke="{{fg}}" stroke-width="2.3" stroke-linecap="round"></path>|},
    {"intro", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><rect x="8.5" y="9.5" width="3.2" height="11" rx="1.6"></rect><rect x="12.2" y="6.5" width="3.2" height="13" rx="1.6"></rect><rect x="15.9" y="6" width="3.2" height="13" rx="1.6"></rect><rect x="19.6" y="7.8" width="3.2" height="12" rx="1.6"></rect><path d="M8.5 16 L22.8 16 L22.8 21 C22.8 24.5 20 27 16.5 27 L14.5 27 C11.2 27 8.5 24.5 8.5 21 Z"></path><path d="M9 20 L5.6 15.4 C5 14.5 5.3 13.4 6.2 12.9 C7 12.5 8 12.8 8.5 13.6 L10.8 17 Z"></path></g><path d="M24.8 5.5 C26.2 6.4 27 7.8 27.2 9.4" stroke="{{fg}}" stroke-width="1.8" stroke-linecap="round" fill="none"></path>|},
    {"feedback", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="12.8" r="8.3" fill="{{fg}}"></circle><rect x="12.3" y="18.8" width="7.4" height="3.8" rx="1.2" fill="{{fg}}"></rect><rect x="13.5" y="24" width="5" height="2.6" rx="1.3" fill="{{fg}}"></rect><path d="M12.8 12.5 L14.4 15.4 L16 12.8 L17.6 15.4 L19.2 12.5" stroke="{{bg}}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"></path>|},
    {"events", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="5.5" y="8" width="21" height="18" rx="2.5" fill="{{fg}}"></rect><rect x="5.5" y="13" width="21" height="1.6" fill="{{bg}}"></rect><g fill="{{fg}}" stroke="{{bg}}" stroke-width="1.2"><rect x="9.8" y="5" width="2.8" height="5.5" rx="1.4"></rect><rect x="19.4" y="5" width="2.8" height="5.5" rx="1.4"></rect></g><g fill="{{bg}}"><rect x="9" y="17" width="3" height="3" rx="0.6"></rect><rect x="14.5" y="17" width="3" height="3" rx="0.6"></rect><rect x="20" y="17" width="3" height="3" rx="0.6"></rect><rect x="9" y="21.5" width="3" height="3" rx="0.6"></rect><rect x="14.5" y="21.5" width="3" height="3" rx="0.6"></rect></g>|},
    {"showcase", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M10 6.5 L22 6.5 L22 12 C22 16 19.5 18.5 16 18.5 C12.5 18.5 10 16 10 12 Z" fill="{{fg}}"></path><path d="M10 9 L7.3 9 C7.3 12.5 8.4 14.2 10.6 14.7 M22 9 L24.7 9 C24.7 12.5 23.6 14.2 21.4 14.7" stroke="{{fg}}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" fill="none"></path><rect x="14.6" y="18" width="2.8" height="4.5" fill="{{fg}}"></rect><rect x="10.5" y="22.5" width="11" height="3.6" rx="1.2" fill="{{fg}}"></rect>|},
    {"market", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M6.5 7 L15 7 L25.5 17.5 L17.5 25.5 L7 15 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="2" stroke-linejoin="round"></path><circle cx="11.3" cy="11.3" r="2" fill="{{bg}}"></circle>|},
    {"health", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><rect x="11" y="14.8" width="10" height="2.4"></rect><rect x="4.4" y="12" width="3.2" height="8" rx="1.1"></rect><rect x="8.4" y="9.5" width="3.4" height="13" rx="1.2"></rect><rect x="20.2" y="9.5" width="3.4" height="13" rx="1.2"></rect><rect x="24.4" y="12" width="3.2" height="8" rx="1.1"></rect></g>|},
    {"fashion", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M13.4 9.4 C13.4 7.4 14.6 5.9 16.2 5.9 C17.8 5.9 19 7.1 19 8.6 C19 10.3 16 10.8 16 13.2" stroke="{{fg}}" stroke-width="2.3" stroke-linecap="round" fill="none"></path><path d="M16 13.2 L5.4 21.6 C4.7 22.2 5.1 23.4 6.1 23.4 L25.9 23.4 C26.9 23.4 27.3 22.2 26.6 21.6 Z" stroke="{{fg}}" stroke-width="2.6" stroke-linejoin="round" fill="none"></path>|},
    {"diy", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g transform="rotate(-35 16 16)" fill="{{fg}}"><rect x="7" y="6.5" width="16.5" height="6.5" rx="1.6"></rect><rect x="14.6" y="12" width="3.4" height="15" rx="1.5"></rect></g>|},
    {"parenting", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M6.5 15 A9.5 9.5 0 0 1 16 5.5 L16 15 Z" fill="{{fg}}"></path><path d="M5.5 15.8 L26 15.8 C26 20 22.5 22.5 18.5 22.5 L13 22.5 C9 22.5 5.5 20 5.5 15.8 Z" fill="{{fg}}"></path><path d="M25.6 15.5 L27.4 9.5" stroke="{{fg}}" stroke-width="2.2" stroke-linecap="round"></path><g fill="{{fg}}"><circle cx="10.5" cy="25.6" r="2.3"></circle><circle cx="21.5" cy="25.6" r="2.3"></circle></g>|},
    {"relationships", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M16 25.5 C9 20.5 5.5 16.8 5.5 12.6 C5.5 9.4 8 7 11 7 C13 7 15 8.2 16 10 C17 8.2 19 7 21 7 C24 7 26.5 9.4 26.5 12.6 C26.5 16.8 23 20.5 16 25.5 Z" fill="{{fg}}"></path>|},
    {"cars", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M4.5 20.5 L4.5 16.5 C4.5 15.4 5.3 14.6 6.4 14.4 L9.5 13.8 L12 9.5 C12.5 8.7 13.3 8.2 14.2 8.2 L20.5 8.2 C21.4 8.2 22.2 8.7 22.7 9.5 L25 13.8 L26 14.1 C27 14.4 27.5 15.2 27.5 16.2 L27.5 20.5 C27.5 21.3 26.8 22 26 22 L6 22 C5.2 22 4.5 21.3 4.5 20.5 Z" fill="{{fg}}"></path><g fill="{{bg}}"><path d="M12.6 13.6 L14.6 10.4 L17 10.4 L17 13.6 Z"></path><path d="M18.8 13.6 L18.8 10.4 L20.6 10.4 L22.4 13.6 Z"></path></g><g fill="{{fg}}" stroke="{{bg}}" stroke-width="1.5"><circle cx="10" cy="22" r="3.3"></circle><circle cx="22" cy="22" r="3.3"></circle></g>|},
    {"pets", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="17.5" r="9.5" fill="{{fg}}"></circle><rect x="4" y="3" width="24" height="6.8" fill="{{bg}}"></rect><rect x="10.3" y="8.6" width="11.4" height="2.6" rx="1.3" fill="{{fg}}"></rect><g fill="{{bg}}"><ellipse cx="14.8" cy="18.6" rx="3.8" ry="2.5"></ellipse><path d="M17.8 18.6 L21.6 15.9 L21.6 21.3 Z"></path></g><circle cx="13.6" cy="18" r="0.8" fill="{{fg}}"></circle>|},
    {"finance", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g fill="{{fg}}"><rect x="5" y="13" width="14.5" height="4" rx="2"></rect><rect x="5" y="17.8" width="14.5" height="4" rx="2"></rect><rect x="5" y="22.6" width="14.5" height="4" rx="2"></rect></g><circle cx="21.6" cy="10.6" r="5.6" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.6"></circle><circle cx="21.6" cy="10.6" r="3.1" stroke="{{bg}}" stroke-width="1.3" fill="none"></circle>|},
    {"careers", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M12.5 11 L12.5 8.8 C12.5 7.8 13.3 7 14.3 7 L17.7 7 C18.7 7 19.5 7.8 19.5 8.8 L19.5 11" stroke="{{fg}}" stroke-width="2.3" fill="none"></path><rect x="5" y="11" width="22" height="14.5" rx="2.5" fill="{{fg}}"></rect><rect x="5" y="16.4" width="22" height="1.6" fill="{{bg}}"></rect><rect x="14" y="14.8" width="4" height="4.8" rx="1" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.1"></rect>|},
    {"history", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M10 8 L22 8 C22 12 18.5 14 17.3 16 C18.5 18 22 20 22 24 L10 24 C10 20 13.5 18 14.7 16 C13.5 14 10 12 10 8 Z" fill="{{fg}}"></path><path d="M12.3 10.2 L19.7 10.2 C19.2 11.9 17 13.3 16 14.5 C15 13.3 12.8 11.9 12.3 10.2 Z" fill="{{bg}}"></path><g fill="{{fg}}"><rect x="7.5" y="5.5" width="17" height="2.8" rx="1.2"></rect><rect x="7.5" y="23.7" width="17" height="2.8" rx="1.2"></rect></g>|},
    {"philosophy", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M10.5 26.5 L10.5 21.5 C7.6 19.8 6 16.8 6 13.5 C6 8.8 10 5.5 15 5.5 C20 5.5 23.8 9 23.8 13.3 L23.8 14 L25.8 17.6 C26.1 18.2 25.7 18.8 25 18.8 L23.8 18.8 L23.8 21 C23.8 22.3 22.8 23.3 21.5 23.3 L19.3 23.3 L19.3 26.5 Z" fill="{{fg}}"></path><path d="M12.6 11.6 C12.6 10.1 13.7 9.2 15.1 9.2 C16.5 9.2 17.6 10.1 17.6 11.4 C17.6 13.1 15.1 13.3 15.1 15.2" stroke="{{bg}}" stroke-width="2" stroke-linecap="round" fill="none"></path><circle cx="15.1" cy="17.7" r="1.2" fill="{{bg}}"></circle>|},
    {"languages", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="4.5" y="4.5" width="15" height="11.5" rx="3" fill="{{fg}}"></rect><path d="M8 15 L8 19.5 L12.5 15 Z" fill="{{fg}}"></path><path d="M9 13.4 L12 7.2 L15 13.4 M10.2 11.2 L13.8 11.2" stroke="{{bg}}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" fill="none"></path><rect x="12.5" y="12.5" width="15" height="11.5" rx="3" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.6"></rect><path d="M24 23.2 L24 27.8 L19.5 23.2 Z" fill="{{fg}}"></path><path d="M20 14.8 L20 15.8 M16.5 16.8 L23.5 16.8 M17.6 17.3 C18.6 20 20.5 21.4 23.4 22 M22.4 17.3 C21.4 20 19.5 21.4 16.6 22" stroke="{{bg}}" stroke-width="1.5" stroke-linecap="round" fill="none"></path>|},
    {"politics", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="11.5" y="5.5" width="9" height="11" rx="1" fill="{{fg}}"></rect><path d="M13.8 10.6 L15.5 12.3 L18.3 9" stroke="{{bg}}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"></path><rect x="5.5" y="14" width="21" height="12" rx="2" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.2"></rect><rect x="10.5" y="16.6" width="11" height="1.8" rx="0.9" fill="{{bg}}"></rect>|},
    {"tv", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M16 10 L11.5 5 M16 10 L20.5 5" stroke="{{fg}}" stroke-width="2" stroke-linecap="round"></path><rect x="4.5" y="10" width="23" height="15.5" rx="3" fill="{{fg}}"></rect><rect x="7.5" y="13" width="13" height="9.5" rx="1.5" fill="{{bg}}"></rect><g fill="{{bg}}"><circle cx="24" cy="15.3" r="1.25"></circle><circle cx="24" cy="19.6" r="1.25"></circle></g>|},
    {"comics", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M16.00 4.50 L18.41 8.58 L22.76 6.70 L22.31 11.42 L26.94 12.45 L23.80 16.00 L26.94 19.55 L22.31 20.58 L22.76 25.30 L18.41 23.42 L16.00 27.50 L13.59 23.42 L9.24 25.30 L9.69 20.58 L5.06 19.55 L8.20 16.00 L5.06 12.45 L9.69 11.42 L9.24 6.70 L13.59 8.58 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="0.8" stroke-linejoin="round"></path><rect x="14.8" y="10" width="2.4" height="7.4" rx="1.2" fill="{{bg}}"></rect><circle cx="16" cy="20.6" r="1.45" fill="{{bg}}"></circle>|},
    {"writing", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="11" y="4.8" width="10" height="3.2" rx="1" fill="{{fg}}"></rect><path d="M16 27 L9.5 16.5 L11 9 L21 9 L22.5 16.5 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="0.8" stroke-linejoin="round"></path><path d="M16 25.5 L16 17.5" stroke="{{bg}}" stroke-width="1.4" stroke-linecap="round"></path><circle cx="16" cy="15.8" r="1.8" fill="{{bg}}"></circle>|},
    {"crafts", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M12.8 19.5 L21 5.8 M19.2 19.5 L11 5.8" stroke="{{fg}}" stroke-width="3" stroke-linecap="round"></path><g stroke="{{fg}}" stroke-width="2.6" fill="none"><circle cx="10.6" cy="22.8" r="3.5"></circle><circle cx="21.4" cy="22.8" r="3.5"></circle></g><circle cx="16" cy="14.2" r="0.95" fill="{{bg}}"></circle>|},
    {"boardgames", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="6" y="6" width="20" height="20" rx="4.5" fill="{{fg}}"></rect><g fill="{{bg}}"><circle cx="11" cy="11" r="1.9"></circle><circle cx="21" cy="11" r="1.9"></circle><circle cx="16" cy="16" r="1.9"></circle><circle cx="11" cy="21" r="1.9"></circle><circle cx="21" cy="21" r="1.9"></circle></g>|},
    {"podcasts", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><rect x="12" y="4.5" width="8" height="13.5" rx="4" fill="{{fg}}"></rect><path d="M14.5 8.5 L17.5 8.5 M14.5 11.5 L17.5 11.5" stroke="{{bg}}" stroke-width="1.4" stroke-linecap="round"></path><path d="M8.5 14 C8.5 18.5 11.8 21.5 16 21.5 C20.2 21.5 23.5 18.5 23.5 14 M16 21.5 L16 26 M11.5 26.5 L20.5 26.5" stroke="{{fg}}" stroke-width="2.3" stroke-linecap="round" fill="none"></path>|},
    {"nature", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><path d="M3.5 25 L12.5 10 L17 17.5 L20 13 L28.5 25 Z" fill="{{fg}}" stroke="{{fg}}" stroke-width="1" stroke-linejoin="round"></path><path d="M12.5 10.2 L15.2 14.6 L13.6 13.7 L12.5 15.1 L11.3 13.7 L9.8 14.6 Z" fill="{{bg}}"></path><circle cx="23" cy="8" r="2.8" fill="{{fg}}"></circle>|},
    {"space", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><g transform="rotate(-20 16 16)"><circle cx="16" cy="16" r="7.3" fill="{{fg}}"></circle><ellipse cx="16" cy="16" rx="12.8" ry="4.2" stroke="{{bg}}" stroke-width="4.4" fill="none"></ellipse><ellipse cx="16" cy="16" rx="12.8" ry="4.2" stroke="{{fg}}" stroke-width="2.1" fill="none"></ellipse><path d="M8.7 16 A7.3 7.3 0 0 1 23.3 16 Z" fill="{{fg}}"></path></g>|},
    {"environment", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="16" cy="16" r="10.5" fill="{{fg}}"></circle><g stroke="{{bg}}" stroke-width="1.5" fill="none"><ellipse cx="16" cy="16" rx="4.6" ry="10.5"></ellipse><path d="M5.5 16 L26.5 16 M7.4 10.6 L24.6 10.6 M7.4 21.4 L24.6 21.4"></path></g>|},
    {"weather", :more,
     ~S|<rect width="32" height="32" rx="{{rx}}" fill="{{bg}}"></rect><circle cx="12" cy="12" r="5" fill="{{fg}}"></circle><path d="M12 3.8 L12 5.3 M3.8 12 L5.3 12 M6.2 6.2 L7.3 7.3 M17.8 6.2 L16.7 7.3 M6.2 17.8 L7.3 16.7" stroke="{{fg}}" stroke-width="2" stroke-linecap="round"></path><path d="M10 26 C7.2 26 5.5 24 5.5 21.8 C5.5 19.5 7.3 17.7 9.6 17.7 C10.3 14.6 13 12.5 16.3 12.5 C19.9 12.5 22.8 15 23.3 18.4 C25.4 18.6 27 20.3 27 22.3 C27 24.4 25.3 26 23.2 26 Z" fill="{{fg}}" stroke="{{bg}}" stroke-width="1.6"></path>|}
  ]

  @typedoc "An SVG element: its tag, its attributes and its children."
  @type shape :: {String.t(), [{atom(), String.t()}], [shape()]}

  @shape_tags ~w(rect circle ellipse path g)

  # "<g fill=..><rect .../></g>" into [{"g", [fill: ..], [{"rect", [...], []}]}].
  shape_tags = @shape_tags

  parse = fn markup ->
    # Only the shapes this module draws; any other element is left out.
    tokens =
      ~r{<(/?)(\w+)([^>]*)>}
      |> Regex.scan(markup, capture: :all_but_first)
      |> Enum.filter(fn [_, tag, _] -> tag in shape_tags end)

    {[tree], []} =
      Enum.reduce(tokens, {[[]], []}, fn
        ["", tag, attrs], {stack, open} ->
          attrs =
            for [name, value] <-
                  Regex.scan(~r/([\w-]+)="([^"]*)"/, attrs, capture: :all_but_first),
                do: {String.to_atom(name), value}

          {[[] | stack], [{tag, attrs} | open]}

        ["/", tag, _], {[children, siblings | stack], [{tag, attrs} | open]} ->
          {[[{tag, attrs, Enum.reverse(children)} | siblings] | stack], open}
      end)

    Enum.reverse(tree)
  end

  @parsed Map.new(@icons, fn {id, _group, markup} -> {id, parse.(markup)} end)

  @ids Enum.map(@icons, &elem(&1, 0))
  @groups [:topics, :sports, :more]

  # The eight tints a category without a colour of its own gets from its id.
  @tints ~w(#6567e7 #008ec8 #009690 #0fa05c #ce9200 #dc631e #dd3858 #b740b1)

  @doc "Every icon id, in order."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "The icon ids of each set, in order: `[{:topics, ids}, {:sports, ids}, {:more, ids}]`."
  @spec groups() :: [{atom(), [String.t()]}]
  def groups do
    for group <- @groups, do: {group, for({id, ^group, _} <- @icons, do: id)}
  end

  @doc "Returns true when `id` names an icon."
  @spec icon?(term()) :: boolean()
  def icon?(id), do: id in @ids

  @doc "The tint of a category without a colour of its own, from its id: `#rrggbb`."
  @spec tint(Ecto.UUID.t()) :: String.t()
  def tint(id), do: Enum.at(@tints, :erlang.phash2(id, length(@tints)))

  @doc """
  The colour for shapes drawn on `colour` (`#rrggbb`): white or near-black, whichever has the
  higher WCAG contrast ratio with it.
  """
  @spec contrast(String.t()) :: String.t()
  def contrast("#" <> hex) do
    [r, g, b] =
      for <<pair::binary-size(2) <- hex>> do
        c = String.to_integer(pair, 16) / 255
        if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end

    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # #111111 has a relative luminance of about 0.0056.
    on_white = 1.05 / (luminance + 0.05)
    on_black = (luminance + 0.05) / 0.0556
    if on_black > on_white, do: "#111111", else: "#ffffff"
  end

  @doc """
  The shapes of icon `id` on a tile of `colour` (a checked `#rrggbb`), or nil: elements to draw
  inside an `<svg viewBox="0 0 32 32">`.
  """
  @spec shapes(String.t(), String.t()) :: [shape()] | nil
  def shapes(id, "#" <> _ = colour) do
    case Map.fetch(@parsed, id) do
      {:ok, tree} ->
        fill(tree, %{"{{bg}}" => colour, "{{fg}}" => contrast(colour), "{{rx}}" => "7"})

      :error ->
        nil
    end
  end

  defp fill(tree, values) do
    for {tag, attrs, children} <- tree do
      {tag, for({name, value} <- attrs, do: {name, Map.get(values, value, value)}),
       fill(children, values)}
    end
  end
end
