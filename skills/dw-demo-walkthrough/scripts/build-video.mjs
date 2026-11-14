#!/usr/bin/env node
/**
 * build-video.mjs: WRITES one mp4 and a `clips/` folder beside it. Joins the captioned
 * stills of a screenshot walkthrough into one silent video: each still is held without
 * motion and faded at both ends.
 *
 * Runtime: Node 20+ and ffmpeg. ffmpeg is taken from --ffmpeg, then the FFMPEG
 * environment variable, then `ffmpeg` on PATH. There is no default path.
 *
 * OWNING REFERENCE: dw-demo-walkthrough/SKILL.md, "Screenshot mode", step 5.
 *
 * Traps it encodes:
 *   - `*.clean.png` (the uncaptioned copies for a document) are skipped, so a folder
 *     written by reskin-engine.mjs can be passed as it is.
 *   - no push-in: zoompan moves the crop in whole pixels, so a slow zoom on a screen full
 *     of text reads as a shaking camera, also on a still scaled up first. Stills stay still.
 *   - concat needs identical encodes, so every clip is encoded with the same settings.
 *
 * Parameters:
 *   --shots <dir>     folder with the stills, played in name order (required)
 *   --out <file.mp4>  the video to write (required)
 *   --seconds <n>     seconds per scene, default 10: enough to read a two-line caption
 *   --end-extra <n>   extra seconds for a scene named *-end, default 7 (the closing card)
 *   --ffmpeg <path>   the ffmpeg executable
 *
 * Example:
 *   node scripts/build-video.mjs --shots notes/walkthrough/stills --out deliverables/walkthrough.mp4
 *
 * Exit code 0 when the video was written, 1 on any failure.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; };
const shots = arg('shots'), out = arg('out');
const per = Number(arg('seconds', 10)), endExtra = Number(arg('end-extra', 7));
const ffmpeg = arg('ffmpeg', process.env.FFMPEG || 'ffmpeg');
if (!shots || !out) { console.error('usage: build-video.mjs --shots <dir> --out <file.mp4> [--seconds 10] [--end-extra 7] [--ffmpeg <path>]'); process.exit(1); }

try {
  const stills = fs.readdirSync(shots).filter((f) => f.endsWith('.png') && !f.endsWith('.clean.png')).sort();
  if (!stills.length) throw new Error(`no stills in ${shots}: run the screens spec first`);
  const clips = path.join(path.dirname(out), 'clips');
  fs.rmSync(clips, { recursive: true, force: true }); fs.mkdirSync(clips, { recursive: true });
  const list = [];
  for (const f of stills) {
    const name = path.basename(f, '.png');
    const t = per + (name.endsWith('-end') ? endExtra : 0);
    const vf = `scale=1920:1080:flags=lanczos,fade=t=in:st=0:d=0.4,fade=t=out:st=${t - 0.4}:d=0.4,format=yuv420p`;
    execFileSync(ffmpeg, ['-v', 'error', '-y', '-loop', '1', '-framerate', '30', '-i', path.join(shots, f), '-vf', vf, '-t', String(t), '-an',
      '-c:v', 'libx264', '-preset', 'medium', '-tune', 'stillimage', '-crf', '20', '-g', '60', path.join(clips, name + '.mp4')], { stdio: 'inherit' });
    list.push(`file '${name}.mp4'`); console.log(`${name} ${t}s`);
  }
  fs.writeFileSync(path.join(clips, 'list.txt'), list.join('\n') + '\n');
  execFileSync(ffmpeg, ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', path.join(clips, 'list.txt'), '-c', 'copy', '-movflags', '+faststart', out], { stdio: 'inherit' });
  console.log(`written ${out} (${stills.length} scenes, ${(fs.statSync(out).size / 1e6).toFixed(1)} MB)`);
} catch (e) {
  console.error(`build-video failed: ${e.message}. Check that ffmpeg runs ("${ffmpeg} -version") and that every still is a 16:9 png.`);
  process.exit(1);
}
