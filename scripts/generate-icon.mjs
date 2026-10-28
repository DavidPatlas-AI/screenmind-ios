import sharp from "sharp";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const svg='<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><rect width="1024" height="1024" fill="#295f48"/><rect x="220" y="209" width="455" height="555" rx="73" fill="#a5bc8f" transform="rotate(-12 447 486)"/><rect x="314" y="235" width="455" height="555" rx="73" fill="#d8e2c6" transform="rotate(9 541 512)"/><rect x="279" y="279" width="448" height="544" rx="73" fill="#f8faef"/><rect x="345" y="354" width="112" height="112" rx="34" fill="#32694e"/><path d="M375 410l19 19 36-43" stroke="#f7fae9" stroke-width="13" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M350 547h299M350 602h244M350 657h269M350 712h166" stroke="#a8b99a" stroke-width="17" stroke-linecap="round"/></svg>';
await sharp(Buffer.from(svg)).removeAlpha().png().toFile(path.join(root,"ScreenMind/Assets.xcassets/AppIcon.appiconset/AppIcon.png"));
console.log("Generated opaque 1024px iOS app icon.");
