// glo's second pass, after deno fmt: pipe tables the terminal cannot hold
// become one block per row. Glamour lays a table out at the block's full
// width, every column an equal share, headers cut to an ellipsis and cells
// wrapped by character — six columns in 55 cells is unreadable. A block
// keeps each header beside its value instead:
//
//   **Header:** value\
//   **Header:** value
//
// with a blank line between rows. Tables that fit, and everything else,
// pass through untouched. Reads stdin, writes stdout.

let columns = 80; // glow's own fallback when nothing is a terminal
try {
  // stdout is the pipe into glow; Deno also asks stderr, still the pane
  columns = Deno.consoleSize().columns;
} catch { /* piped both ways */ }
const avail = columns - 4; // glow's two-column margins

const text = await new Response(Deno.stdin.readable).text();
const lines = text.split("\n");
const out: string[] = [];

const isDelim = (l: string) =>
  /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(l);
const isRow = (l: string) => l.includes("|") && l.trim() !== "";
// Split on unescaped pipes, dropping the outer ones deno fmt adds
const cells = (l: string): string[] => {
  const parts = l.replace(/\\\|/g, "\0").split("|")
    .map((c) => c.replace(/\0/g, "\\|").trim());
  if (parts[0] === "") parts.shift();
  if (parts.at(-1) === "") parts.pop();
  return parts;
};
// Width as glow shows it: code spans lose their backticks, bold its stars
const shown = (s: string) =>
  s.replace(/`([^`]*)`/g, "$1").replace(/\*\*|__/g, "").length;

let fence = false;
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  if (/^\s*(```|~~~)/.test(l)) fence = !fence;
  if (fence || !isRow(l) || !isDelim(lines[i + 1] ?? "")) {
    out.push(l);
    continue;
  }

  const header = cells(l);
  const rows: string[][] = [];
  let j = i + 2;
  while (j < lines.length && isRow(lines[j])) rows.push(cells(lines[j++]));

  // Natural width: the widest cell per column, a padded separator between
  // columns, a space at each edge.
  const widths = header.map((h, k) =>
    Math.max(shown(h), ...rows.map((r) => shown(r[k] ?? "")))
  );
  const natural = widths.reduce((a, b) => a + b) + 3 * (header.length - 1) +
    2;
  if (natural <= avail) {
    out.push(...lines.slice(i, j));
    i = j - 1;
    continue;
  }

  rows.forEach((r, ri) => {
    const block = header.flatMap((h, k) => {
      const v = r[k] ?? "";
      return v === "" ? [] : [h === "" ? v : `**${h}:** ${v}`];
    });
    out.push(...block.map((b, k) => (k < block.length - 1 ? b + "\\" : b)));
    if (ri < rows.length - 1) out.push("");
  });
  i = j - 1;
}
await new Blob([out.join("\n")]).stream().pipeTo(Deno.stdout.writable);
