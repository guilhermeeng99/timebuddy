import "./styles.css";
import { mountLiveGrid } from "./live-grid";

/**
 * The landing page's whole runtime: an old-bookmark redirect, the live grid,
 * and the footer year.
 */

/**
 * Sends a deep link meant for the app to the app.
 *
 * Until this page existed the Flutter build was served from the Pages root, so
 * every bookmark and every link the app produced looks like
 * `…/timebuddy/#/settings` — go_router's hash strategy. Those URLs now land
 * here. Forwarding them costs three lines and is the difference between a
 * bookmark that still works and one that silently opens a marketing page.
 *
 * The test is `#/`, with the slash: the page's own anchors are `#features`,
 * `#time`, `#start`, which can never match.
 */
function forwardAppDeepLink(): boolean {
  const hash = window.location.hash;
  if (!hash.startsWith("#/")) return false;
  window.location.replace(`./app/${hash}`);
  return true;
}

if (!forwardAppDeepLink()) {
  mountLiveGrid();

  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
}
