package;

import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.display.Tile;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.Event;
import openfl.Assets;
import openfl.Lib;
import haxe.xml.Access;

class ZombieBenchmark extends Sprite {
    private static inline var STAGE_WIDTH:Int = 800;
    private static inline var STAGE_HEIGHT:Int = 600;
    private static inline var SPAWN_THRESHOLD:Int = 55;
    private static inline var TOTAL_ZOMBIE_TYPES:Int = 16;
    private static inline var FRAMES_PER_ZOMBIE:Int = 8;
    private static inline var ANIMATION_SKIP:Int = 5; // Advance frame every 5 ticks = 12 fps
    private static inline var BUFFER_SIZE:Int = 120;  // 2-second rolling window at 60fps

    private var mTilemaps:Array<Tilemap> = [];
    private var mTilesets:Array<Tileset> = [];
    // frameIds[zombieType][frameIndex] = tileId (Int)
    private var mFrameIds:Array<Array<Int>> = [];
    private var mZombies:Array<ZombieData> = [];
    private var mZombieCountTextField:TextField;

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

        // Initialize stats display
        initStats();

        // Load all zombie assets
        loadZombieAssets();

        // Add event listener for frame updates
        addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function initStats():Void {
        mZombieCountTextField = new TextField();
        mZombieCountTextField.x = 10;
        mZombieCountTextField.y = 10;
        mZombieCountTextField.width = 400;
        mZombieCountTextField.height = 30;
        mZombieCountTextField.defaultTextFormat = new TextFormat("_sans", 16, 0xFFFF00);
        mZombieCountTextField.text = "Zombies: 0";
        mZombieCountTextField.selectable = false;
        addChild(mZombieCountTextField);
    }

    private function loadZombieAssets():Void {
        for (i in 0...TOTAL_ZOMBIE_TYPES) {
            var zombiName = "zombi" + i;
            var pngPath = "assets/" + zombiName + ".png";
            var xmlPath = "assets/" + zombiName + ".xml";

            // Load bitmap data
            var bitmapData:BitmapData = Assets.getBitmapData(pngPath);

            // Load and parse XML
            var xmlString:String = Assets.getText(xmlPath);
            var xml = Xml.parse(xmlString);
            var access = new Access(xml.firstElement()); // <TextureAtlas>

            // Create tileset
            var tileset:Tileset = new Tileset(bitmapData);

            // Add 8 tiles (one per frame), collecting returned Int tile IDs
            var ids:Array<Int> = [];
            var subTextures = access.nodes.SubTexture;
            var frameIdx = 0;
            for (subNode in subTextures) {
                if (frameIdx >= FRAMES_PER_ZOMBIE) break;
                var x = Std.parseFloat(subNode.att.x);
                var y = Std.parseFloat(subNode.att.y);
                var w = Std.parseFloat(subNode.att.width);
                var h = Std.parseFloat(subNode.att.height);
                var tileId:Int = tileset.addRect(new Rectangle(x, y, w, h));
                ids.push(tileId);
                frameIdx++;
            }

            mTilesets[i] = tileset;
            mFrameIds[i] = ids;

            // Create tilemap for this zombie type
            var tilemap:Tilemap = new Tilemap(STAGE_WIDTH, STAGE_HEIGHT, tileset, true);
            mTilemaps[i] = tilemap;
            addChild(tilemap);
        }

        // Bring HUD text above all tilemaps
        addChild(mZombieCountTextField);
    }

    private function onEnterFrame(event:Event):Void {
        var now:Int = Lib.getTimer();
        var delta:Float = now - mLastTime;
        mLastTime = now;

        // Calculate FPS using 120-slot circular buffer rolling average (2s at 60fps)
        mFrameTimes[mFrameTimeIdx] = delta;
        mFrameTimeIdx = (mFrameTimeIdx + 1) % BUFFER_SIZE;
        if (mFrameTimeCount < BUFFER_SIZE) mFrameTimeCount++;
        var totalDelta:Float = 0;
        for (i in 0...mFrameTimeCount) totalDelta += mFrameTimes[i];
        mFps = totalDelta > 0 ? 1000.0 * mFrameTimeCount / totalDelta : 60.0;

        // Stop condition: 2-second rolling average FPS < 55
        if (!mStopped && mFrameTimeCount >= BUFFER_SIZE && mFps < SPAWN_THRESHOLD) {
            mStopped = true;
            var fmt = mZombieCountTextField.defaultTextFormat.clone();
            fmt.size = 32;
            mZombieCountTextField.defaultTextFormat = fmt;
            mZombieCountTextField.setTextFormat(fmt);
            mZombieCountTextField.height = 60;
        }

        // Spawn new zombies if not stopped and FPS > threshold
        if (!mStopped && mFps > SPAWN_THRESHOLD) {
            spawnZombies();
        }

        // Animate all zombies
        animateZombies();

        // Update HUD every 6 frames (~10 Hz) to minimize string allocation overhead
        if (++mHudTick >= 6) {
            mHudTick = 0;
            mZombieCountTextField.text = "Zombies: " + mZombies.length + " | FPS: " + Std.int(mFps);
        }
    }

    private function spawnZombies():Void {
        // Spawn one of each zombie type (0-15)
        for (zombieType in 0...TOTAL_ZOMBIE_TYPES) {
            var tilemap = mTilemaps[zombieType];
            var ids = mFrameIds[zombieType];

            // Create a new tile for this zombie starting at frame 0
            var x:Float = Math.random() * STAGE_WIDTH;
            var y:Float = Math.random() * STAGE_HEIGHT;
            var tile:Tile = new Tile(ids[0], x, y);

            // Random rotation (0-360 degrees)
            tile.rotation = Math.random() * 360;

            // Add tile to tilemap
            tilemap.addTile(tile);

            // Create zombie data
            var zombie:ZombieData = {
                tile: tile,
                typeIndex: zombieType,
                frameIndex: 0,
                frameTimer: 0
            };

            mZombies.push(zombie);
        }
    }

    private function animateZombies():Void {
        for (zombie in mZombies) {
            // Advance frame timer
            zombie.frameTimer++;

            // Check if we should advance the animation frame
            if (zombie.frameTimer >= ANIMATION_SKIP) {
                zombie.frameTimer = 0;

                // Advance to next frame (looping)
                zombie.frameIndex = (zombie.frameIndex + 1) % FRAMES_PER_ZOMBIE;

                // Update tile ID to show next frame
                zombie.tile.id = mFrameIds[zombie.typeIndex][zombie.frameIndex];
            }
        }
    }
}

private typedef ZombieData = {
    var tile:Tile;
    var typeIndex:Int;
    var frameIndex:Int;
    var frameTimer:Int;
}
