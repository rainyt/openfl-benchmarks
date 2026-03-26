package;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.geom.Rectangle;
import openfl.geom.Point;
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
    private static inline var TOTAL_TYPES:Int = 16;
    private static inline var FRAMES_PER:Int = 8;
    private static inline var ANIM_SKIP:Int = 5;   // advance frame every 5 ticks ≈ 12 fps
    private static inline var HUD_SKIP:Int = 6;    // update HUD every 6 ticks ≈ 10 Hz
    private static inline var BUFFER_SIZE:Int = 120; // 2-second rolling window at 60 fps

    // Per-type Sprite containers (type 0 = bottom layer, type 15 = top layer)
    private var _containers:Array<Sprite> = [];

    // Pre-extracted BitmapData frames: _frames[typeIndex][frameIndex]
    private var _frames:Array<Array<BitmapData>> = [];

    // Parallel arrays for all live zombies
    private var _bitmaps:Array<Bitmap>  = [];
    private var _typeIdx:Array<Int>     = [];
    private var _frameIdx:Array<Int>    = [];
    private var _frameTick:Array<Int>   = [];

    private var _hud:TextField;

    private var _mStopped:Bool = false;
    private var _frameTimes:Array<Float> = [for (_ in 0...BUFFER_SIZE) 0.0];
    private var _frameTimeIdx:Int = 0;
    private var _frameTimeCount:Int = 0;
    private var _lastTime:Int = 0;
    private var _fps:Float = 0;
    private var _hudTick:Int = 0;

    public function new() {
        super();

        _lastTime = Lib.getTimer();

        loadAssets();
        initHud();

        addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    // -------------------------------------------------------------------------
    // Asset loading — extract individual BitmapData frames from each atlas
    // -------------------------------------------------------------------------
    private function loadAssets():Void {
        var ZERO = new Point(0, 0);

        for (t in 0...TOTAL_TYPES) {
            var name = "zombi" + t;
            var pngPath = "assets/" + name + ".png";
            var xmlPath = "assets/" + name + ".xml";

            // Load source atlas
            var sourceBD:BitmapData = Assets.getBitmapData(pngPath);

            // Parse XML
            var xmlStr:String = Assets.getText(xmlPath);
            var xml = Xml.parse(xmlStr);
            var access = new Access(xml.firstElement()); // <TextureAtlas>

            // Extract frames
            var typeFrames:Array<BitmapData> = [];
            var frameIdx = 0;
            for (subNode in access.nodes.SubTexture) {
                if (frameIdx >= FRAMES_PER) break;
                var x = Std.parseFloat(subNode.att.x);
                var y = Std.parseFloat(subNode.att.y);
                var w = Std.parseFloat(subNode.att.width);
                var h = Std.parseFloat(subNode.att.height);

                var frame = new BitmapData(Std.int(w), Std.int(h), true, 0);
                frame.copyPixels(sourceBD, new Rectangle(x, y, w, h), ZERO);
                typeFrames.push(frame);
                frameIdx++;
            }

            _frames[t] = typeFrames;

            // Create a per-type Sprite container and add to stage
            var container = new Sprite();
            _containers[t] = container;
            addChild(container);

            // Dispose the atlas — we have everything we need
            sourceBD.dispose();
        }
    }

    // -------------------------------------------------------------------------
    // HUD — added last so it sits on top of all containers
    // -------------------------------------------------------------------------
    private function initHud():Void {
        _hud = new TextField();
        _hud.x = 10;
        _hud.y = 10;
        _hud.width = 400;
        _hud.height = 30;
        _hud.defaultTextFormat = new TextFormat("_sans", 16, 0xFFFF00);
        _hud.text = "Zombies: 0";
        _hud.selectable = false;
        _hud.autoSize = openfl.text.TextFieldAutoSize.LEFT;
        addChild(_hud);
    }

    // -------------------------------------------------------------------------
    // Main loop
    // -------------------------------------------------------------------------
    private function onEnterFrame(event:Event):Void {
        var now:Int = Lib.getTimer();
        var delta:Float = now - _lastTime;
        _lastTime = now;

        // Rolling 2-second FPS average (120-slot circular buffer)
        _frameTimes[_frameTimeIdx] = delta;
        _frameTimeIdx = (_frameTimeIdx + 1) % BUFFER_SIZE;
        if (_frameTimeCount < BUFFER_SIZE) _frameTimeCount++;
        var totalDelta:Float = 0;
        for (i in 0..._frameTimeCount) totalDelta += _frameTimes[i];
        _fps = totalDelta > 0 ? 1000.0 * _frameTimeCount / totalDelta : 60.0;

        // Stop condition: buffer full and FPS < threshold
        if (!_mStopped && _frameTimeCount >= BUFFER_SIZE && _fps < SPAWN_THRESHOLD) {
            _mStopped = true;
            var fmt = _hud.defaultTextFormat.clone();
            fmt.size = 32;
            _hud.defaultTextFormat = fmt;
            _hud.setTextFormat(fmt);
            _hud.height = 60;
        }

        // Spawn a new batch if benchmark is still running
        if (!_mStopped && _fps > SPAWN_THRESHOLD) {
            spawnBatch();
        }

        // Animate every live zombie
        animateZombies();

        // Update HUD at ~10 Hz
        if (++_hudTick >= HUD_SKIP) {
            _hudTick = 0;
            _hud.text = "Zombies: " + _bitmaps.length + " | FPS: " + Std.int(_fps);
        }
    }

    // -------------------------------------------------------------------------
    // Spawn one zombie per type (16 total) at random position + rotation
    // -------------------------------------------------------------------------
    private function spawnBatch():Void {
        for (t in 0...TOTAL_TYPES) {
            var bmp = new Bitmap(_frames[t][0]);

            // Centre the bitmap on its registration point so rotation looks right
            bmp.x = Math.random() * STAGE_WIDTH;
            bmp.y = Math.random() * STAGE_HEIGHT;
            bmp.rotation = Math.random() * 360;

            _containers[t].addChild(bmp);

            _bitmaps.push(bmp);
            _typeIdx.push(t);
            _frameIdx.push(0);
            _frameTick.push(0);
        }
    }

    // -------------------------------------------------------------------------
    // Advance animation frames for every zombie
    // -------------------------------------------------------------------------
    private function animateZombies():Void {
        var n = _bitmaps.length;
        for (i in 0...n) {
            _frameTick[i]++;
            if (_frameTick[i] >= ANIM_SKIP) {
                _frameTick[i] = 0;
                _frameIdx[i] = (_frameIdx[i] + 1) % FRAMES_PER;
                _bitmaps[i].bitmapData = _frames[_typeIdx[i]][_frameIdx[i]];
            }
        }
    }
}
