// Builds a self-contained review page from Catalog/exercises/*.json.
// Usage: node Catalog/tools/build-review.mjs <output.html>
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const order = ["strength", "bodyweight", "cardio"];
const exercises = fs
  .readdirSync(path.join(root, "exercises"))
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(fs.readFileSync(path.join(root, "exercises", f), "utf8")))
  .sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind) || a.name.localeCompare(b.name));

const html = fs
  .readFileSync(path.join(here, "review-template.html"), "utf8")
  .replace("__RIG__", () => fs.readFileSync(path.join(root, "rig.js"), "utf8"))
  .replace("__DATA__", () => JSON.stringify(exercises))
  .replace("__REFS__", () => fs.readFileSync(path.join(root, "references.json"), "utf8"))
  .replace("__COUNT__", String(exercises.length))
  .replace("__VIEWS__", String(exercises.reduce((n, e) => n + e.animations.length, 0)));

fs.writeFileSync(process.argv[2] || "catalog-review.html", html);
console.log(`wrote ${exercises.length} exercises`);
