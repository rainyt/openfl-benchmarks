import openfl.display.BitmapData;
import openfl.Lib;
import openfl.Assets;

import starling.display.Sprite;
import starling.text.BitmapFont;
import starling.text.TextField as StarlingTextField;
import starling.text.TextFormat as StarlingTextFormat;
import starling.textures.Texture;
import starling.textures.TextureAtlas;
import starling.events.Event as StarlingEvent;
import starling.core.Starling;

import massive.display.MassiveDisplay;
import massive.display.ImageLayer;
import massive.data.ImageData;
import massive.data.Frame;
import massive.animation.Animator;
import massive.display.MassiveColorMode;

class ZombieBenchmark extends Sprite {
    private static inline var STAGE_WIDTH:Int = 800;
    private static inline var STAGE_HEIGHT:Int = 600;
    private static inline var SPAWN_THRESHOLD:Int = 55;
    private static inline var TOTAL_ZOMBIE_TYPES:Int = 16;
    private static inline var FRAMES_PER_ZOMBIE:Int = 8;
    private static inline var ANIMATION_FPS:Float = 12.0;
    private static inline var BUFFER_SIZE:Int = 120; // 2-second rolling window at 60fps

    private var mMassiveDisplay:MassiveDisplay;
    // One ImageLayer per zombie type (index 0..15), added in order so type 0
    // is at the bottom of the render stack and type 15 is at the top.
    private var mLayers:Array<ImageLayer<ImageData>> = [];
    private var mZombieCount:Int = 0;
    private var mHudTextField:StarlingTextField;

    // Per-type precomputed frames and timings
    private var mFrames:Array<Array<Frame>> = [];
    private var mTimings:Array<Array<Float>> = [];
    private var mAtlases:Array<TextureAtlas> = [];

    // FPS measurement: 120-slot circular buffer (2s rolling window), no per-frame allocation
    private var mStopped:Bool = false;
    private var mFrameTimes:Array<Float> = [for (_ in 0...BUFFER_SIZE) 0.0];
    private var mFrameTimeIdx:Int = 0;
    private var mFrameTimeCount:Int = 0;
    private var mLastTime:Int = 0;
    private var mFps:Float = 0;
    private var mHudTick:Int = 0;

    public function new() {
        super();

        mLastTime = Lib.getTimer();

        // Must call before creating MassiveDisplay
        MassiveDisplay.init();

        // Load all zombie assets and build per-type frame/timing tables
        loadZombieAssets();

        // Collect all atlas root textures for multi-texturing (one per type)
        var textures:Array<Texture> = [];
        for (i in 0...TOTAL_ZOMBIE_TYPES) {
            textures.push(mAtlases[i].texture);
        }

        // MassiveColorMode.NONE = no color vertex data, renders textures at natural colors.
        // Initial maxQuads set to a modest amount; grows dynamically as zombies are added.
        mMassiveDisplay = new MassiveDisplay(textures, null, MassiveColorMode.NONE, 256);

        // Create 16 ImageLayers — one per zombie type — stacked in order:
        // type 0's layer is at the bottom (added first), type 15's at the top (added last).
        // All same-type zombies are grouped in their dedicated layer, giving the GPU renderer
        // contiguous quads per type in the vertex buffer.
        for (i in 0...TOTAL_ZOMBIE_TYPES) {
            var layer:ImageLayer<ImageData> = new ImageLayer<ImageData>();
            mLayers.push(layer);
            mMassiveDisplay.addLayer(layer);
        }

        addChild(mMassiveDisplay);

        // HUD: Starling TextField using the built-in MINI bitmap font, rendered on top of MassiveDisplay.
        mHudTextField = new StarlingTextField(400, 40, "Zombies: 0",
            new StarlingTextFormat(BitmapFont.MINI, 18, 0xFFFFFF));
        mHudTextField.x = 10;
        mHudTextField.y = 10;
        addChild(mHudTextField);

        addEventListener(StarlingEvent.ENTER_FRAME, onEnterFrame);
    }

    private function loadZombieAssets():Void {
        for (i in 0...TOTAL_ZOMBIE_TYPES) {
            var zombiName = "zombi" + i;
            var pngPath = "assets/" + zombiName + ".png";
            var xmlPath = "assets/" + zombiName + ".xml";

            var bitmapData:BitmapData = Assets.getBitmapData(pngPath);
            var texture:Texture = Texture.fromBitmapData(bitmapData, false);
            bitmapData.dispose();

            var xmlString:String = Assets.getText(xmlPath);
            var atlas:TextureAtlas = new TextureAtlas(texture, xmlString);
            mAtlases[i] = atlas;

            // Get all sub-textures (8 walk frames) in atlas-defined order
            var subTextures = atlas.getTextures();
            var frames:Array<Frame> = [];
            for (t in 0...FRAMES_PER_ZOMBIE) {
                frames.push(Frame.fromTexture(subTextures[t]));
            }
            mFrames[i] = frames;
            // generateTimings(frames, 12) produces cumulative timings at 12fps
            mTimings[i] = Animator.generateTimings(frames, ANIMATION_FPS);
        }
    }

    private function onEnterFrame(event:StarlingEvent):Void {
        var now:Int = Lib.getTimer();
        var delta:Float = now - mLastTime;
        mLastTime = now;

        // FPS via 120-slot circular buffer rolling average (2s window, no allocation)
        mFrameTimes[mFrameTimeIdx] = delta;
        mFrameTimeIdx = (mFrameTimeIdx + 1) % BUFFER_SIZE;
        if (mFrameTimeCount < BUFFER_SIZE) mFrameTimeCount++;
        var totalDelta:Float = 0;
        for (i in 0...mFrameTimeCount) totalDelta += mFrameTimes[i];
        mFps = totalDelta > 0 ? 1000.0 * mFrameTimeCount / totalDelta : 60.0;

        // Stop condition: 2-second rolling average FPS < 55
        if (!mStopped && mFrameTimeCount >= BUFFER_SIZE && mFps < SPAWN_THRESHOLD) {
            mStopped = true;
            // Double the font size — Starling TextFormat is mutable; assignment triggers recomposition
            mHudTextField.format.size = 36;
        }

        // Spawn exactly 16 new zombies (one per type) when not stopped and FPS > 55.
        if (!mStopped && mFps > SPAWN_THRESHOLD) {
            spawnZombies();
        }

        // Update HUD every 6 frames (~10 Hz) to minimise string allocation overhead
        if (++mHudTick >= 6) {
            mHudTick = 0;
            mHudTextField.text = "Zombies: " + mZombieCount + " | FPS: " + Std.int(mFps);
        }
    }

    private function spawnZombies():Void {
        var newTotal:Int = mZombieCount + TOTAL_ZOMBIE_TYPES;

        // Grow the GPU vertex buffer with headroom to avoid frequent reallocations
        if (newTotal > mMassiveDisplay.maxQuads) {
            mMassiveDisplay.maxQuads = newTotal + 512;
        }

        for (zombieType in 0...TOTAL_ZOMBIE_TYPES) {
            var imageData:ImageData = ImageData.fromPool();

            // Set up looping 12fps animation (time-based, handled by Starling juggler via advanceTime)
            imageData.setFrames(mFrames[zombieType], mTimings[zombieType], true, 0, 0, true);

            // Select the texture atlas for this zombie type
            imageData.textureIndex = zombieType;

            // Random position across the stage
            imageData.x = Math.random() * STAGE_WIDTH;
            imageData.y = Math.random() * STAGE_HEIGHT;

            // Random rotation in radians (ImageData.rotation is in radians)
            imageData.rotation = Math.random() * Math.PI * 2;

            // Natural colors: do NOT set red/green/blue — leave at default (1.0)
            // MassiveColorMode.NONE means color fields are ignored anyway

            // Add to the type-specific layer so all same-type zombies are grouped together.
            // Layer index matches zombie type: mLayers[0] holds all type-0 zombies, etc.
            mLayers[zombieType].addImage(imageData);
            mZombieCount++;
        }
    }

    override public function dispose():Void {
        removeEventListener(StarlingEvent.ENTER_FRAME, onEnterFrame);
        super.dispose();
    }
}
