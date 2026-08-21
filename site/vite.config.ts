import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// The static landing page for TimeBuddy. Builds to dist/ for any static host.
export default defineConfig({
  // Relative base so the bundle resolves its own assets under the GitHub Pages
  // project sub-path (/timebuddy/) without knowing that path at build time.
  // The Flutter app is published one level down, at /timebuddy/app/, and is a
  // separate bundle built with `--base-href /timebuddy/app/`.
  base: "./",
  plugins: [tailwindcss()],
  build: { outDir: "dist", emptyOutDir: true },
});
