// Cyclone 3D — isometric world map
//
// Reads web/data.json (compact archipelago dump produced by
// tools/build_web_data.py from the original tape) and builds a 3D scene
// where every cell of every island becomes a stack of cubes.
//
// Each cell of an island's flight_shape grid maps to one (world_x, world_y)
// position.  The cell's tile index `t` indexes data.stacks[t], whose length
// is the column height — one cube per stack level, each with its own colour
// (Spectrum attribute) and 8x8 glyph on the visible faces.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// ─── Spectrum palette ──────────────────────────────────────────────────────
const PAL_DIM = [
  [  0,   0,   0], [  0,   0, 215], [215,   0,   0], [215,   0, 215],
  [  0, 215,   0], [  0, 215, 215], [215, 215,   0], [215, 215, 215],
];
const PAL_BR = [
  [  0,   0,   0], [  0,   0, 255], [255,   0,   0], [255,   0, 255],
  [  0, 255,   0], [  0, 255, 255], [255, 255,   0], [255, 255, 255],
];
function attrColours(byte) {
  const pal = (byte & 0x40) ? PAL_BR : PAL_DIM;
  return { ink: pal[byte & 7], paper: pal[(byte >> 3) & 7] };
}

// ─── Geometry constants ────────────────────────────────────────────────────
const TILE = 1.0;            // world unit per cell in 3D units
const LEVEL_H = 1.2;         // height of one stack level (exaggerated for 3D)
const SEA_DROP = 0.05;       // sea plane sits just below the stack base
const SEA_TILE = 0;          // tile index 0 is "open sea"

// Default isometric framing.
const ISO_AZIMUTH = Math.PI / 4;       // 45° around Y
const ISO_ELEVATION = Math.atan(1 / Math.SQRT2);  // ~35.264° (true iso)

// ─── State ─────────────────────────────────────────────────────────────────
const state = {
  data: null,
  scene: null, camera: null, renderer: null,
  worldGroup: null, seaGroup: null,
  centre: new THREE.Vector3(),
  // Camera target (point camera looks at) and orbit (azimuth/elev/zoom).
  target: new THREE.Vector3(),
  azimuth: ISO_AZIMUTH,
  elevation: ISO_ELEVATION,
  distance: 200,
  showGlyphs: true,
};

// ─── Bootstrap ─────────────────────────────────────────────────────────────
async function main() {
  const data = await fetch('./data.json').then(r => r.json());
  state.data = data;

  // Centre on the bounding box of the islands themselves — they don't fill
  // the full 768x768 world, so framing on the world centre would leave a
  // lot of blank sea offset from the camera target.
  let xMin = Infinity, xMax = -Infinity, yMin = Infinity, yMax = -Infinity;
  for (const isl of data.islands) {
    const w = isl.tiles[0].length, h = isl.tiles.length;
    xMin = Math.min(xMin, isl.x); xMax = Math.max(xMax, isl.x + w);
    yMin = Math.min(yMin, isl.y); yMax = Math.max(yMax, isl.y + h);
  }
  state.centre.set((xMin + xMax) / 2, 0, (yMin + yMax) / 2);
  state.target.copy(state.centre);
  // Orthographic isometric: screen-vertical -> ground-vertical scale is
  // 1 / sin(elev); pick distance so the larger of the two bbox spans just
  // fits on screen with a little margin.
  const span = Math.max(xMax - xMin, yMax - yMin);
  state.fitDistance = span * Math.sin(ISO_ELEVATION) * 0.55;

  initRenderer();
  initLights();
  buildSea();
  buildIslands();
  buildIslandLegend();
  bindControls();
  resetView();

  document.getElementById('loader').remove();
  animate();

  setStatus(
    `${data.islands.length} islands · ` +
    `${state.totalCubes.toLocaleString()} cubes · ` +
    `world ${data.world_w}×${data.world_h}`,
  );
}

function setStatus(s) { document.getElementById('status').textContent = s; }

// ─── Renderer / camera ─────────────────────────────────────────────────────
function initRenderer() {
  const canvas = document.getElementById('c');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.setClearColor(0x0a0a14);

  // Sea-blue tint matches Cyclone's bright-cyan paper for tile 0 (attr $6F).
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x102030);
  scene.fog = new THREE.Fog(0x0a0a14, 350, 1100);

  // Orthographic camera gives a clean isometric look without
  // perspective foreshortening.
  const aspect = innerWidth / innerHeight;
  const viewSize = 200;
  const camera = new THREE.OrthographicCamera(
    -viewSize * aspect, viewSize * aspect,
    viewSize, -viewSize,
    -2000, 4000,
  );

  state.scene = scene;
  state.camera = camera;
  state.renderer = renderer;

  addEventListener('resize', () => {
    const a = innerWidth / innerHeight;
    const v = state.distance;
    camera.left   = -v * a;
    camera.right  =  v * a;
    camera.top    =  v;
    camera.bottom = -v;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight, false);
  });
}

function initLights() {
  const { scene } = state;
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));
  const sun = new THREE.DirectionalLight(0xfff2c0, 1.0);
  sun.position.set(0.6, 1.0, 0.4).normalize();
  scene.add(sun);
  const fill = new THREE.DirectionalLight(0x6b8cff, 0.35);
  fill.position.set(-0.5, 0.5, -0.6).normalize();
  scene.add(fill);
}

// ─── Glyph atlas ───────────────────────────────────────────────────────────
// One 16×16 grid of 8×8 glyphs = 128×128 atlas.  Each tile is rendered with
// its own ink/paper from data.attrs[i].  Used as a texture atlas; per-cube
// UVs select the right tile.
function buildGlyphAtlas() {
  const { glyphs, attrs } = state.data;
  const ATLAS_TILES = 16;
  const TILE_PX = 8;
  const SIZE = ATLAS_TILES * TILE_PX;
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = SIZE;
  const ctx = canvas.getContext('2d', { willReadFrequently: false });
  ctx.imageSmoothingEnabled = false;

  // Atlas without glyph ink (just paper) — useful for "lights off" debug
  // and cube side faces where the glyph would smear unreadably.
  const flatCanvas = document.createElement('canvas');
  flatCanvas.width = flatCanvas.height = SIZE;
  const fctx = flatCanvas.getContext('2d');

  const rgb = c => `rgb(${c[0]},${c[1]},${c[2]})`;
  for (let i = 0; i < 256; i++) {
    const tx = (i % ATLAS_TILES) * TILE_PX;
    const ty = Math.floor(i / ATLAS_TILES) * TILE_PX;
    const { ink, paper } = attrColours(attrs[i]);
    ctx.fillStyle = rgb(paper);
    ctx.fillRect(tx, ty, TILE_PX, TILE_PX);
    fctx.fillStyle = rgb(paper);
    fctx.fillRect(tx, ty, TILE_PX, TILE_PX);
    ctx.fillStyle = rgb(ink);
    const bytes = glyphs[i];
    for (let y = 0; y < 8; y++) {
      const b = bytes[y];
      for (let x = 0; x < 8; x++) {
        if (b & (0x80 >> x)) ctx.fillRect(tx + x, ty + y, 1, 1);
      }
    }
  }

  const tex = new THREE.CanvasTexture(canvas);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.colorSpace = THREE.SRGBColorSpace;

  const flat = new THREE.CanvasTexture(flatCanvas);
  flat.magFilter = THREE.NearestFilter;
  flat.minFilter = THREE.NearestFilter;
  flat.colorSpace = THREE.SRGBColorSpace;

  return { atlas: tex, flat };
}

// ─── World construction ────────────────────────────────────────────────────
function buildSea() {
  const { data } = state;
  const { paper } = attrColours(data.attrs[SEA_TILE]);
  const seaMat = new THREE.MeshLambertMaterial({
    color: new THREE.Color(`rgb(${paper[0]},${paper[1]},${paper[2]})`),
  });
  // Slightly larger than world bounds so islands are floating in a lagoon.
  const W = data.world_w, H = data.world_h;
  const geom = new THREE.PlaneGeometry(W * 1.15, H * 1.15);
  geom.rotateX(-Math.PI / 2);
  const mesh = new THREE.Mesh(geom, seaMat);
  mesh.position.set(W / 2, -SEA_DROP, H / 2);
  state.scene.add(mesh);
  state.seaGroup = mesh;
}

function buildIslands() {
  const { data } = state;
  const { atlas, flat } = buildGlyphAtlas();

  // For each cell-cube we'll need the UV offset in the atlas.  The atlas
  // is 16×16 of 8×8 tiles, so each tile occupies 1/16 in u and v.
  const ATLAS_N = 16;
  const uvForTile = (idx) => {
    const tx = idx % ATLAS_N;
    const ty = Math.floor(idx / ATLAS_N);
    // Three.js UV origin is bottom-left, but our canvas is top-down — flip ty.
    return {
      u0: tx / ATLAS_N,
      v0: 1 - (ty + 1) / ATLAS_N,
      u1: (tx + 1) / ATLAS_N,
      v1: 1 - ty / ATLAS_N,
    };
  };

  // Walk every island, every cell, every stack level — collect a flat list
  // of cells to render.  Skip tile 0 at level 0 (open sea) — the sea plane
  // already covers it.  Skip "skip" levels.
  //
  // Some non-sea tiles (32 of them) have BRIGHT CYAN paper, the same colour
  // as the sea.  These are coastline-detail tiles: mostly sea, with a few
  // ink pixels of land.  Rendered as a full cube, their side faces show
  // solid cyan and look like blue blocks rising out of the water once the
  // camera rotates off iso.  Render those as flat top-only quads at sea
  // level instead — visually identical from above, invisible from the side.
  const SEA_PAPER_BIT = 0x40 | (5 << 3);   // bright + paper=cyan
  const SEA_PAPER_MASK = 0x40 | (7 << 3);  // bright + paper bits
  const isSeaPaper = (tIdx) =>
    (data.attrs[tIdx] & SEA_PAPER_MASK) === SEA_PAPER_BIT;

  const cubes = [];
  const planes = [];
  for (const isl of data.islands) {
    const grid = isl.tiles;
    for (let r = 0; r < grid.length; r++) {
      for (let c = 0; c < grid[r].length; c++) {
        const raw = grid[r][c];
        if (raw === SEA_TILE) continue;          // bare sea — skip
        const stack = data.stacks[raw];
        for (let lvl = 0; lvl < stack.length; lvl++) {
          const tIdx = stack[lvl];
          if (tIdx === -1) continue;             // skip marker ($FE)
          const wx = isl.x + c;
          const wz = isl.y + r;
          if (isSeaPaper(tIdx)) {
            planes.push([wx, wz, tIdx]);
          } else {
            cubes.push([wx, lvl, wz, tIdx]);
          }
        }
      }
    }
  }
  state.totalCubes = cubes.length + planes.length;

  // Build geometries: one merged BufferGeometry per "group of 5000 cubes"
  // so we don't blow buffer-size limits on weak GPUs.  Per-cube UVs are
  // baked in so we get a single texture, but with each cube showing the
  // right glyph & colour.
  const CHUNK = 5000;
  const material = new THREE.MeshLambertMaterial({
    map: atlas, vertexColors: false,
  });
  state.flatMaterial = new THREE.MeshLambertMaterial({ map: flat });
  state.atlasMaterial = material;

  const group = new THREE.Group();
  for (let i = 0; i < cubes.length; i += CHUNK) {
    const slice = cubes.slice(i, i + CHUNK);
    const geoms = slice.map(([wx, lvl, wz, tIdx]) => makeCellBox(wx, lvl, wz, tIdx, uvForTile));
    const merged = mergeGeometries(geoms, false);
    geoms.forEach(g => g.dispose());
    const mesh = new THREE.Mesh(merged, material);
    group.add(mesh);
  }

  // Sea-decoration quads: one merged double-sided plane mesh per chunk,
  // sitting just above the sea plane to avoid z-fighting.
  if (planes.length) {
    const planeMat = new THREE.MeshLambertMaterial({
      map: atlas, side: THREE.DoubleSide,
    });
    state.planeMaterial = planeMat;
    for (let i = 0; i < planes.length; i += CHUNK) {
      const slice = planes.slice(i, i + CHUNK);
      const geoms = slice.map(([wx, wz, tIdx]) => makeCellPlane(wx, wz, tIdx, uvForTile));
      const merged = mergeGeometries(geoms, false);
      geoms.forEach(g => g.dispose());
      const mesh = new THREE.Mesh(merged, planeMat);
      group.add(mesh);
    }
  }
  state.scene.add(group);
  state.worldGroup = group;
}

// One box geometry for one cube of one stack level.  UVs on every face
// point to the same atlas tile, so the cube's sides "stripe" into the
// surrounding stack — which is fine, since the column is what reads as a
// vertical stripe in the original Cyclone tile renderer.
function makeCellBox(wx, lvl, wz, tIdx, uvForTile) {
  const g = new THREE.BoxGeometry(TILE, LEVEL_H, TILE);
  // Centre the box on (wx + 0.5, lvl*LEVEL_H + LEVEL_H/2, wz + 0.5).
  g.translate(wx + 0.5, lvl * LEVEL_H + LEVEL_H / 2, wz + 0.5);

  // Replace BoxGeometry's default UVs with a single atlas tile.
  // BoxGeometry has 24 vertices, 4 per face, in face order:
  // px, nx, py, ny, pz, nz.  Each face's UVs are (1,1)(0,1)(1,0)(0,0)
  // for some orientation — we just remap to the atlas window.
  const { u0, v0, u1, v1 } = uvForTile(tIdx);
  const uv = g.attributes.uv;
  const uvs = uv.array;
  const u = (t) => u0 + t * (u1 - u0);
  const v = (t) => v0 + t * (v1 - v0);
  for (let face = 0; face < 6; face++) {
    const o = face * 8;
    // Four corners of the face in canonical order:
    //  (0,1) (1,1)
    //  (0,0) (1,0)
    uvs[o + 0] = u(0); uvs[o + 1] = v(1);
    uvs[o + 2] = u(1); uvs[o + 3] = v(1);
    uvs[o + 4] = u(0); uvs[o + 5] = v(0);
    uvs[o + 6] = u(1); uvs[o + 7] = v(0);
  }
  uv.needsUpdate = true;
  return g;
}

// Flat horizontal quad for a "sea-decoration" tile (paper colour matches
// the sea).  Sits a hair above the sea plane so the glyph reads on top
// without z-fighting; from the side it has no thickness so it doesn't
// produce blue blocks when the camera rotates off iso.
function makeCellPlane(wx, wz, tIdx, uvForTile) {
  const g = new THREE.PlaneGeometry(TILE, TILE);
  g.rotateX(-Math.PI / 2);
  g.translate(wx + 0.5, -SEA_DROP + 0.01, wz + 0.5);

  const { u0, v0, u1, v1 } = uvForTile(tIdx);
  const uvs = g.attributes.uv.array;
  // PlaneGeometry has 4 verts in order (TL, TR, BL, BR) in canonical UVs
  // (0,1) (1,1) (0,0) (1,0).  After rotateX the plane points up but vertex
  // order is unchanged, so the same UV mapping works.
  uvs[0] = u0; uvs[1] = v1;
  uvs[2] = u1; uvs[3] = v1;
  uvs[4] = u0; uvs[5] = v0;
  uvs[6] = u1; uvs[7] = v0;
  g.attributes.uv.needsUpdate = true;
  return g;
}

// ─── HUD: island legend ────────────────────────────────────────────────────
function buildIslandLegend() {
  const ol = document.getElementById('island-list');
  state.data.islands.forEach((isl, i) => {
    const li = document.createElement('li');
    const tiles = isl.tiles;
    const w = tiles[0].length, h = tiles.length;
    li.textContent = `${isl.name}`;
    li.title = `${w}×${h} tiles, world (${isl.x},${isl.y})`;
    li.addEventListener('click', () => focusIsland(i));
    ol.appendChild(li);
  });
}

function focusIsland(i) {
  const isl = state.data.islands[i];
  const w = isl.tiles[0].length, h = isl.tiles.length;
  state.target.set(isl.x + w / 2, 4, isl.y + h / 2);
  state.distance = 80;
  applyCamera();
}

// ─── Controls ──────────────────────────────────────────────────────────────
function bindControls() {
  const canvas = state.renderer.domElement;
  const keys = new Set();

  addEventListener('keydown', e => {
    keys.add(e.key.toLowerCase());
    if (e.key === ' ') { resetView(); e.preventDefault(); }
    if (e.key.toLowerCase() === 'g') {
      state.showGlyphs = !state.showGlyphs;
      const mat = state.showGlyphs ? state.atlasMaterial : state.flatMaterial;
      state.worldGroup.traverse(o => { if (o.isMesh) o.material = mat; });
    }
    // Number keys 1-9 / 0 jump to islands 0..9.
    const digit = '1234567890'.indexOf(e.key);
    if (digit >= 0 && digit < state.data.islands.length) focusIsland(digit);
  });
  addEventListener('keyup', e => keys.delete(e.key.toLowerCase()));

  // Continuous WASD / arrow pan.
  state.keys = keys;

  // Mouse: left-drag pans, right-drag rotates.
  let lastX = 0, lastY = 0, dragBtn = -1;
  canvas.addEventListener('mousedown', e => {
    dragBtn = e.button;
    lastX = e.clientX; lastY = e.clientY;
    canvas.classList.add('dragging');
  });
  addEventListener('mouseup', () => {
    dragBtn = -1;
    canvas.classList.remove('dragging');
  });
  addEventListener('mousemove', e => {
    if (dragBtn < 0) return;
    const dx = e.clientX - lastX, dy = e.clientY - lastY;
    lastX = e.clientX; lastY = e.clientY;
    if (dragBtn === 2) {
      state.azimuth -= dx * 0.005;
      state.elevation = clamp(state.elevation + dy * 0.005, 0.15, Math.PI / 2 - 0.05);
    } else {
      panScreen(dx, dy);
    }
    applyCamera();
  });
  canvas.addEventListener('contextmenu', e => e.preventDefault());

  // Touch: one-finger drag = pan, two-finger = rotate/zoom.
  let touchPrev = null;
  canvas.addEventListener('touchstart', e => {
    if (e.touches.length === 1) {
      touchPrev = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    } else if (e.touches.length === 2) {
      touchPrev = pinchInfo(e);
    }
    e.preventDefault();
  }, { passive: false });
  canvas.addEventListener('touchmove', e => {
    if (e.touches.length === 1 && touchPrev) {
      const dx = e.touches[0].clientX - touchPrev.x;
      const dy = e.touches[0].clientY - touchPrev.y;
      touchPrev = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      panScreen(dx, dy);
      applyCamera();
    } else if (e.touches.length === 2 && touchPrev) {
      const cur = pinchInfo(e);
      state.azimuth -= (cur.angle - touchPrev.angle);
      const ratio = touchPrev.dist / cur.dist;
      state.distance = clamp(state.distance * ratio, 20, 800);
      touchPrev = cur;
      applyCamera();
    }
    e.preventDefault();
  }, { passive: false });
  canvas.addEventListener('touchend', () => { touchPrev = null; });

  // Wheel zoom.
  canvas.addEventListener('wheel', e => {
    const factor = Math.exp(e.deltaY * 0.001);
    state.distance = clamp(state.distance * factor, 20, 800);
    applyCamera();
    e.preventDefault();
  }, { passive: false });
}

function pinchInfo(e) {
  const a = e.touches[0], b = e.touches[1];
  const dx = b.clientX - a.clientX, dy = b.clientY - a.clientY;
  return {
    x: (a.clientX + b.clientX) / 2,
    y: (a.clientY + b.clientY) / 2,
    dist: Math.hypot(dx, dy),
    angle: Math.atan2(dy, dx),
  };
}

function panScreen(dx, dy) {
  // Convert screen-space drag to world-space pan along the camera's local
  // X (right) and projected Z (forward-on-ground) axes.
  const speed = state.distance / innerHeight * 2;
  const right = new THREE.Vector3();
  const forward = new THREE.Vector3();
  state.camera.getWorldDirection(forward);
  forward.y = 0; forward.normalize();
  right.crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();
  state.target.addScaledVector(right, -dx * speed);
  state.target.addScaledVector(forward, dy * speed);
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function resetView() {
  state.target.copy(state.centre);
  state.azimuth = ISO_AZIMUTH;
  state.elevation = ISO_ELEVATION;
  state.distance = state.fitDistance || 260;
  applyCamera();
}

function applyCamera() {
  const { camera } = state;
  // Orthographic frustum size scales with `distance` so wheel = zoom.
  const a = innerWidth / innerHeight;
  camera.left   = -state.distance * a;
  camera.right  =  state.distance * a;
  camera.top    =  state.distance;
  camera.bottom = -state.distance;
  camera.updateProjectionMatrix();

  // Position the camera on a sphere around `target`, then look at it.
  const r = 800;
  const x = state.target.x + r * Math.cos(state.elevation) * Math.sin(state.azimuth);
  const y = state.target.y + r * Math.sin(state.elevation);
  const z = state.target.z + r * Math.cos(state.elevation) * Math.cos(state.azimuth);
  camera.position.set(x, y, z);
  camera.lookAt(state.target);
}

// ─── Frame loop ────────────────────────────────────────────────────────────
let lastTime = performance.now();
function animate() {
  requestAnimationFrame(animate);
  const now = performance.now();
  const dt = Math.min(0.05, (now - lastTime) / 1000);
  lastTime = now;
  applyKeyboard(dt);
  state.renderer.render(state.scene, state.camera);
}

function applyKeyboard(dt) {
  const keys = state.keys;
  let dx = 0, dz = 0;
  if (keys.has('w') || keys.has('arrowup'))    dz -= 1;
  if (keys.has('s') || keys.has('arrowdown'))  dz += 1;
  if (keys.has('a') || keys.has('arrowleft'))  dx -= 1;
  if (keys.has('d') || keys.has('arrowright')) dx += 1;
  if (dx || dz) {
    const len = Math.hypot(dx, dz);
    dx /= len; dz /= len;
    const right = new THREE.Vector3();
    const forward = new THREE.Vector3();
    state.camera.getWorldDirection(forward);
    forward.y = 0; forward.normalize();
    right.crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();
    const speed = state.distance * 0.6 * dt;
    state.target.addScaledVector(right, dx * speed);
    state.target.addScaledVector(forward, -dz * speed);
    applyCamera();
  }
  if (keys.has('q')) { state.azimuth += dt * 1.4; applyCamera(); }
  if (keys.has('e')) { state.azimuth -= dt * 1.4; applyCamera(); }
  if (keys.has('r')) {
    state.elevation = clamp(state.elevation + dt * 1.0, 0.15, Math.PI / 2 - 0.05);
    applyCamera();
  }
  if (keys.has('f')) {
    state.elevation = clamp(state.elevation - dt * 1.0, 0.15, Math.PI / 2 - 0.05);
    applyCamera();
  }
}

main().catch(err => {
  console.error(err);
  document.getElementById('loader').textContent = 'failed to load: ' + err.message;
});
