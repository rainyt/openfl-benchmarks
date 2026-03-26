package;

import openfl.Assets;

import starling.core.Starling;
import starling.display.Image;
import starling.display.Sprite;
import starling.events.EnterFrameEvent;
import starling.events.Event;
import starling.text.BitmapFont;
import starling.text.TextField;
import starling.text.TextFormat;
import starling.textures.Texture;
import starling.textures.TextureAtlas;
import starling.utils.Color;

class ZombieBenchmark extends Sprite {
    private static inline var STAGE_WIDTH:Int     = 800;
    private static inline var STAGE_HEIGHT:Int    = 600;
    private static inline var SPAWN_THRESHOLD:Int = 55;
    private static inline var TOTAL_TYPES:Int     = 16;
    private static inline var FRAMES_PER:Int      = 8;
    private static inline var ANIM_SKIP:Int       = 5;   // 60fps / 5 = 12fps animation
    private static inline var HUD_SKIP:Int        = 6;   // update HUD every 6 frames
    private static inline var BUFFER_SIZE:Int     = 120; // 2-second rolling window at 60fps

    // Pre-built texture lookup: _frames[typeIndex][frameIndex]
    private var _frames:Array<Array<Texture>> = [];

    // One Sprite container per zombie type for efficient GPU batching
    private var _containers:Array<Sprite> = [];

    // Parallel arrays — zero allocation in the hot tick loop
    private var _images:Array<Image>   = [];
    private var _typeIdx:Array<Int>    = [];
    private var _frameIdx:Array<Int>   = [];
    private var _frameTick:Array<Int>  = [];

    private var _zombieCount:Int = 0;
    private var _hud:TextField;
    private var _hudTick:Int = 0;

    // FPS tracking via 120-slot circular buffer (2s rolling window)
    private var _mStopped:Bool = false;
    private var _frameTimes:Array<Float>;
    private var _ftIdx:Int   = 0;
    private var _ftCount:Int = 0;
    private var _ftSum:Float = 0.0;
    private var _fps:Float   = 60.0;

    public function new() {
        super();

        _frameTimes = [for (_ in 0...BUFFER_SIZE) 0.0];

        // Load texture atlases for all zombie types
        for (t in 0...TOTAL_TYPES) {
            var bd    = Assets.getBitmapData('assets/zombi$t.png');
            var xml   = Assets.getText('assets/zombi$t.xml');
            var tex   = Texture.fromBitmapData(bd, false);
            bd.dispose();
            var atlas = new TextureAtlas(tex, xml);
            var vec   = atlas.getTextures('character_zombie_walk');
            _frames.push([for (f in 0...Std.int(Math.min(vec.length, FRAMES_PER))) vec[f]]);
        }

        // One container per type for GPU batching
        for (t in 0...TOTAL_TYPES) {
            var c = new Sprite();
            addChild(c);
            _containers.push(c);
        }

        // HUD overlay — added last so it renders on top
        _hud = new TextField(400, 60, 'Zombies: 0  FPS: 60',
            new TextFormat(BitmapFont.MINI, 18, Color.WHITE));
        _hud.x = 10;
        _hud.y = 10;
        addChild(_hud);

        addEventListener(Event.ENTER_FRAME, cast onEnterFrame);
    }

    // Spawn exactly one zombie of each type (16 total)
    private function spawnBatch():Void {
        for (t in 0...TOTAL_TYPES) {
            var img = new Image(_frames[t][0]);
            img.x        = Math.random() * STAGE_WIDTH;
            img.y        = Math.random() * STAGE_HEIGHT;
            img.rotation = Math.random() * Math.PI * 2;
            _containers[t].addChild(img);
            _images.push(img);
            _typeIdx.push(t);
            _frameIdx.push(0);
            _frameTick.push(0);
        }
        _zombieCount += TOTAL_TYPES;
    }

    // Per-frame tick — animate all zombies and manage FPS
    private function onEnterFrame(e:EnterFrameEvent):Void {
        // --- FPS via 120-slot circular-buffer O(1) running sum (2s window) ---
        var dt:Float = e.passedTime;  // seconds since last frame
        _ftSum -= _frameTimes[_ftIdx];
        _ftSum += dt;
        _frameTimes[_ftIdx] = dt;
        _ftIdx = (_ftIdx + 1) % BUFFER_SIZE;
        if (_ftCount < BUFFER_SIZE) _ftCount++;
        _fps = _ftSum > 0 ? _ftCount / _ftSum : 60.0;

        // --- Stop condition: 2-second rolling average FPS < 55 ---
        if (!_mStopped && _ftCount >= BUFFER_SIZE && _fps < SPAWN_THRESHOLD) {
            _mStopped = true;
            _hud.format.size = 36;
            _hud.setRequiresRecomposition();
        }

        // --- HUD update every 6 frames ---
        if (++_hudTick >= HUD_SKIP) {
            _hudTick = 0;
            _hud.text = 'Zombies: $_zombieCount  FPS: ${Math.round(_fps)}';
        }

        // --- Spawn if not stopped and FPS > 55 ---
        if (!_mStopped && _fps > SPAWN_THRESHOLD) spawnBatch();

        // --- Animate all zombies: advance frame every ANIM_SKIP ticks ---
        for (i in 0..._images.length) {
            if (++_frameTick[i] >= ANIM_SKIP) {
                _frameTick[i] = 0;
                var f = (_frameIdx[i] + 1) % FRAMES_PER;
                _frameIdx[i] = f;
                _images[i].texture = _frames[_typeIdx[i]][f];
            }
        }
    }
}
