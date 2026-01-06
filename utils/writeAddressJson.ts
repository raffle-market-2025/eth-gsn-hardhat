import fs from "node:fs";
import path from "node:path";

export default function writeAddressJson(relPath: string, address: string) {
  const abs = path.join(process.cwd(), relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });

  let existing: any = {};
  if (fs.existsSync(abs)) {
    try {
      existing = JSON.parse(fs.readFileSync(abs, "utf8"));
      if (existing == null || typeof existing !== "object") existing = {};
    } catch {
      existing = {};
    }
  }

  const out = { ...existing, address };
  fs.writeFileSync(abs, JSON.stringify(out, null, 2) + "\n", "utf8");
  console.log(`Wrote ${relPath}:`, out);
}