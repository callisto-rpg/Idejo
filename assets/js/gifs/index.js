// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// GIF providers' adapters, by the id their Idejo.Gifs.Provider module gives (steward
// decision, 2026-11-03). Each has:
//   page({key, filter, query, page}) -> Promise<{items, more}>, items being
//     {id, slug, title, preview: {url, width, height}, full: {url, width, height}};
//   shared({key, gif, query}) -> nothing, told when a GIF is chosen.
// To add a provider: its adapter here, and its module on the server (Idejo.Gifs.Provider).
import {klipy} from "./klipy"

export const providers = {klipy}
