# Zombie Sprite Rendering Benchmarks

A collection of benchmarks that measure how many animated sprites can be rendered at 60fps across different Haxe and JavaScript rendering frameworks.

Each benchmark contuously spawns batches of 16 zombies (one per type). It stops spawning when FPS drops below a 2 second average of 55fps, then presents the final count.

---

## Frameworks

- [OpenFL](https://openfl.org/) - An AIR/Flash SDK like API for cross platform development
- [Starling for OpenFL](https://github.com/openfl/starling) - Cross platform game engine
- [Massive](https://github.com/MatseFR/massive-starling) - A high performance library for Starling
- [CreateJS](https://createjs.com/) — Similar JavaScript framework included out of interest

---

## Benchmarks

| Directory | Framework | Renderer |
|-----------|-----------|----------|
| `benchmark-openfl/` | OpenFL | `Tilemap` / `Tileset` (GPU batched) |
| `benchmark-openfl-trad/` | OpenFL | Traditional `Bitmap` / `BitmapData` / `Sprite` |
| `benchmark-starling/` | Starling (Stage3D) | `Image` per sprite, per-type containers |
| `benchmark-massive/` | Massive | `MassiveDisplay` + `ImageLayer` (ultra-batched) |
| `benchmark-createjs/` | CreateJS | `StageGL` (WebGL) + 2D canvas HUD overlay |

---

## Running the Benchmarks

### Haxe benchmarks (openfl, openfl-trad, starling, massive-starling)

Install any required frameworks via `haxelib install`.

For example:
```bash
haxelib install starling
```
Or from Git using:
```bash
haxelib git starling https://github.com/openfl/starling.git
```

To run the tests (except CreateJS):

```bash
cd benchmark-openfl          # or any other benchmark directory except createjs
openfl test hl -final        # HashLink (desktop, fast JIT)
openfl test cpp -final       # Native C++
openfl test html5 -final     # HTML5 / WebGL in browser
```

### CreateJS benchmark

```bash
cd benchmark-createjs
python3 -m http.server 8080
# Then open http://localhost:8080 in your browser
```

---

## Requirements

- [Haxe](https://haxe.org/) (4.x)
- [OpenFL](https://openfl.org/)
- [HashLink](https://hashlink.haxe.org/) — for `openfl test hl`
- [Python](https://www.python.org/) — for testing CreateJS via `python3 -m http.server 8080`
- Assets are in `assets/` and are shared across all Haxe benchmarks
- CreateJS assets are self-contained in `benchmark-createjs/assets/`
