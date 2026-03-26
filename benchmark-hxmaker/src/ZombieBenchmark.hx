package;

import hx.assets.Assets;
import hx.display.MovieClip;
import hx.display.Label;
import hx.display.Stage;
import hx.display.BitmapData;
import hx.display.TextFormat;
import openfl.Lib;

/**
 * HXMaker benchmark using native hx.display.MovieClip (auto-batched, multi-texture)
 * instead of OpenFL Tilemaps.
 *
 * Key differences from the OpenFL Tilemap version:
 *   - hx.display.MovieClip is auto-batched by the HXMaker renderer.
 *   - All 16 zombie textures can be merged into minimal draw calls via
 *     HXMaker's multi-texture rendering path.
 *   - Assets are loaded via hx.assets.Assets.loadAtlas() which produces an
 *     Atlas with per-frame BitmapData sub-regions.
 */
class ZombieBenchmark extends Stage {
    private static inline var STAGE_WIDTH:Int    = 800;
    private static inline var STAGE_HEIGHT:Int   = 600;
    private static inline var SPAWN_THRESHOLD:Int = 55;
    private static inline var TOTAL_ZOMBIE_TYPES:Int = 16;
    private static inline var ANIMATION_FPS:Float    = 12;
    private static inline var BUFFER_SIZE:Int    = 120; // 2-second rolling window at 60fps

    // Per-type ordered frame arrays
    private var mFrames:Array<Array<BitmapData>> = [];

    // Live zombie display objects
    private var mZombies:Array<MovieClip> = [];

    private var mHud:Label;

    private var mReady:Bool = false;
    private var mStopped:Bool = false;
    private var mFrameTimes:Array<Float> = [for (_ in 0...BUFFER_SIZE) 0.0];
    private var mFrameTimeIdx:Int = 0;
    private var mFrameTimeCount:Int = 0;
    private var mLastTime:Int = 0;
    private var mFps:Float = 0;
    private var mHudTick:Int = 0;

    override function onStageInit() {
        super.onStageInit();

        mLastTime = Lib.getTimer();

        // Activate the Stage update loop
        updateEnabled = true;

        // Load all 16 zombie atlases (PNG + XML) via HXMaker's asset system
        var assets = new Assets();
        for (i in 0...TOTAL_ZOMBIE_TYPES) {
            assets.loadAtlas("assets/zombi" + i + ".png", "assets/zombi" + i + ".xml");
        }

        assets.onComplete(function(loaded:Assets) {
            // Extract sorted per-type frame lists from each atlas.
            // All atlases use SubTexture names like "character_zombie_walk0"..."7".
            for (i in 0...TOTAL_ZOMBIE_TYPES) {
                var atlas = loaded.getAtlas("zombi" + i);
                if (atlas != null) {
                    // getBitmapDatasByName returns frames matching the prefix, in insertion order
                    mFrames[i] = atlas.getBitmapDatasByName("character_zombie_walk");
                } else {
                    mFrames[i] = [];
                }
            }

            // HUD label — auto-batched alongside display objects
            mHud = new Label();
            mHud.x = 10;
            mHud.y = 10;
            mHud.width = 500;
            mHud.height = 40;
            mHud.textFormat = new TextFormat("_sans", 16, 0xFFFF00);
            mHud.text = "Zombies: 0";
            mHud.mouseEnabled = false;
            addChild(mHud);

            mReady = true;
        });

        assets.start();
    }

    // Called automatically every frame by the HXMaker engine (dt = seconds since last frame)
    override function onUpdate(dt:Float) {
        super.onUpdate(dt);

        if (!mReady) return;

        var now:Int = Lib.getTimer();
        var delta:Float = now - mLastTime;
        mLastTime = now;

        // Rolling FPS average
        mFrameTimes[mFrameTimeIdx] = delta;
        mFrameTimeIdx = (mFrameTimeIdx + 1) % BUFFER_SIZE;
        if (mFrameTimeCount < BUFFER_SIZE) mFrameTimeCount++;
        var totalDelta:Float = 0;
        for (i in 0...mFrameTimeCount) totalDelta += mFrameTimes[i];
        mFps = totalDelta > 0 ? 1000.0 * mFrameTimeCount / totalDelta : 60.0;

        // Freeze when rolling average drops below threshold
        if (!mStopped && mFrameTimeCount >= BUFFER_SIZE && mFps < SPAWN_THRESHOLD) {
            mStopped = true;
            if (mHud != null) {
                mHud.textFormat = new TextFormat("_sans", 32, 0xFFFF00);
                mHud.height = 60;
            }
        }

        // Spawn 16 new zombies (one per type) each passing frame
        if (!mStopped && mFps > SPAWN_THRESHOLD) {
            spawnZombies();
        }

        // Update HUD every 6 frames (~10 Hz)
        if (++mHudTick >= 6) {
            mHudTick = 0;
            if (mHud != null)
                mHud.text = "Zombies: " + mZombies.length + " | FPS: " + Std.int(mFps);
        }
    }

    private function spawnZombies():Void {
        for (t in 0...TOTAL_ZOMBIE_TYPES) {
            if (mFrames[t] == null || mFrames[t].length == 0) continue;

            // MovieClip auto-sets updateEnabled=true and handles frame animation internally.
            // HXMaker batches all MovieClip/Image instances that share the same texture
            // atlas, dramatically reducing draw calls compared to individual Tilemaps.
            var mc = new MovieClip(mFrames[t], ANIMATION_FPS);
            mc.x = Math.random() * STAGE_WIDTH;
            mc.y = Math.random() * STAGE_HEIGHT;
            mc.rotation = Math.random() * 360;
            mc.play(); // loops infinitely (loop = -1 by default)

            addChild(mc);
            mZombies.push(mc);
        }

        // Keep HUD layer on top of all zombies
        if (mHud != null) setChildIndex(mHud, numChildren - 1);
    }
}
