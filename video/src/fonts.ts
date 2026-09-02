import { continueRender, delayRender, staticFile } from "remotion";

// The same three faces the site ships, copied from its build output. The
// render is held until they are loaded so no frame is drawn in a fallback.
const FACES: [string, string, number][] = [
  ["Bricolage Grotesque", "fonts/bricolage-700.woff2", 700],
  ["Public Sans", "fonts/public-sans-400.woff2", 400],
  ["JetBrains Mono", "fonts/jetbrains-400.woff2", 400],
];

let started = false;

export function loadFonts(): void {
  if (started || typeof document === "undefined") return;
  started = true;
  const handle = delayRender("fonts");
  Promise.all(
    FACES.map(async ([family, file, weight]) => {
      const face = new FontFace(family, `url(${staticFile(file)})`, {
        weight: String(weight),
      });
      await face.load();
      document.fonts.add(face);
    }),
  )
    .catch((e) => console.error("font load failed", e))
    .finally(() => continueRender(handle));
}
