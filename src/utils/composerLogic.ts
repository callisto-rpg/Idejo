// SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Text that already ends a sentence (closing quotes or brackets allowed).
const ENDS_WITH_PUNCTUATION = /[.!?…:;,]["'”’)\]»]*$/;

export function finishSentence(text: string): string {
  const body = text.replace(/\s+$/, "");
  if (body === "" || ENDS_WITH_PUNCTUATION.test(body)) return body;
  return body + ".";
}

// Splits `value` into runs of sent and unsent text. Characters kept from the
// sent text (a longest common subsequence) count as sent; everything typed or
// changed since counts as unsent, wherever the caret was.
export function sentRuns(sent: string, value: string): Array<[string, boolean]> {
  let start = 0;
  const max = Math.min(sent.length, value.length);
  while (start < max && sent[start] === value[start]) start++;

  let end = 0;
  while (end < max - start && sent[sent.length - 1 - end] === value[value.length - 1 - end]) end++;

  const a = sent.slice(start, sent.length - end);
  const b = value.slice(start, value.length - end);
  const marks = new Array(b.length).fill(false);

  // Very large middles skip the table and count as unsent.
  if (a.length > 0 && b.length > 0 && a.length * b.length <= 4_000_000) {
    const w = b.length + 1;
    const table = new Uint32Array((a.length + 1) * w);
    for (let i = a.length - 1; i >= 0; i--) {
      for (let j = b.length - 1; j >= 0; j--) {
        table[i * w + j] = a[i] === b[j]
          ? table[(i + 1) * w + j + 1] + 1
          : Math.max(table[(i + 1) * w + j], table[i * w + j + 1]);
      }
    }
    for (let i = 0, j = 0; i < a.length && j < b.length;) {
      if (a[i] === b[j]) { marks[j] = true; i++; j++; }
      else if (table[(i + 1) * w + j] >= table[i * w + j + 1]) i++;
      else j++;
    }
  }

  const runs: Array<[string, boolean]> = [[value.slice(0, start), true]];
  for (let j = 0; j < b.length; j++) {
    const last = runs[runs.length - 1];
    if (last[1] === marks[j]) last[0] += b[j];
    else runs.push([b[j], marks[j]]);
  }
  runs.push([value.slice(value.length - end), true]);
  return runs.filter(([text]) => text.length > 0);
}
