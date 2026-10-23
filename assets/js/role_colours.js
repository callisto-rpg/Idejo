// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// RoleColours hook (steward decision, 2026-10-23): role names take their role's colour from
// `--role`, which the page's head sets for the colours it was loaded with. On admin pages a
// colour can change without a page load, so each `[data-role-colour]` gets it set here,
// through the DOM: the content security policy refuses style attributes.
export const RoleColours = {
  mounted() { this.paint() },
  updated() { this.paint() },

  paint() {
    this.el.querySelectorAll(".role-name, .name-colour").forEach(el => {
      const colour = el.dataset.roleColour
      if (colour) el.style.setProperty("--role", colour)
      else el.style.removeProperty("--role")
    })
  }
}
