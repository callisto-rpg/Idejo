// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Applies the light/dark theme, the hidden sidebar (sidebar.js) and the tutorial bubbles'
// choice, before first paint. Loaded as a blocking
// <script> in the root layout; kept out of the HTML so the content security
// policy can refuse inline scripts (SP-05).
(() => {
  const systemTheme = () => matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

  const setTheme = (theme) => {
    if (theme === "system") {
      localStorage.removeItem("phx:theme");
      document.documentElement.setAttribute("data-theme", systemTheme());
      document.documentElement.setAttribute("data-theme-source", "system");
    } else {
      localStorage.setItem("phx:theme", theme);
      document.documentElement.setAttribute("data-theme", theme);
      document.documentElement.setAttribute("data-theme-source", "user");
    }
  };
  // Tells the stylesheet that scripts run, so the sidebar button can be shown.
  document.documentElement.dataset.js = ""
  try {
    if (localStorage.getItem("idejo:sidebar") === "hidden") {
      document.documentElement.dataset.sidebar = "hidden"
    }
  } catch (_e) {
    // Storage refused (private window): the sidebar shows.
  }

  // Tutorial bubbles (steward decisions, 2026-10-25, 2026-10-26): all of them unless the
  // account menu or the Help page chose "simple" (the composer's "Enter to send" and "Sent!"
  // only) or "off"; remembered by the browser, like the theme.
  const setBubbles = (choice, remember) => {
    const kept = choice === "off" || choice === "simple"
    if (kept) document.documentElement.dataset.bubbles = choice
    else delete document.documentElement.dataset.bubbles
    try {
      if (remember && kept) localStorage.setItem("idejo:bubbles", choice)
      else if (remember) localStorage.removeItem("idejo:bubbles")
    } catch (_e) {
      // Storage refused (private window): the choice lasts for this page only.
    }
    window.dispatchEvent(new CustomEvent("idejo:bubbles"))
  };
  try {
    const bubbles = localStorage.getItem("idejo:bubbles")
    if (bubbles === "off" || bubbles === "simple") setBubbles(bubbles, false)
  } catch (_e) {
    // Storage refused: bubbles show.
  }
  window.addEventListener("storage", (e) => e.key === "idejo:bubbles" && setBubbles(e.newValue || "on", false));
  window.addEventListener("phx:set-bubbles", (e) => setBubbles(e.target.dataset.choice, true));

  if (!document.documentElement.hasAttribute("data-theme")) {
    setTheme(localStorage.getItem("phx:theme") || "system");
  }
  window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));
  window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    if (document.documentElement.getAttribute("data-theme-source") === "system") {
      document.documentElement.setAttribute("data-theme", systemTheme());
    }
  });
})();
