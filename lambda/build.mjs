import { build } from "esbuild";

const targets = [
  { entry: "src/authorizer.ts", outfile: "dist/authorizer/index.js" },
  { entry: "src/register.ts", outfile: "dist/register/index.js" },
];

for (const t of targets) {
  await build({
    entryPoints: [t.entry],
    outfile: t.outfile,
    bundle: true,
    platform: "node",
    target: "node22",
    format: "cjs",
    sourcemap: false,
    minify: false,
  });
  console.log(`built ${t.outfile}`);
}
