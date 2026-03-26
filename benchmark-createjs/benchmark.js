// CreateJS Zombie Benchmark - WebGL via StageGL
// Uses createjs.StageGL for GPU-accelerated rendering
// HUD is rendered on a separate 2D canvas overlay (StageGL does not support Text)

(function() {
    "use strict";

    // Configuration
    var CANVAS_WIDTH = 800;
    var CANVAS_HEIGHT = 600;
    var ZOMBIE_TYPES = 16;

    // Global state
    var stage;
    var hudCtx;          // 2D context for the HUD overlay canvas
    var spritesheets = [];
    var containers = [];
    var zombieCount = 0;
    var assetsLoaded = false;
    var hudTick = 0;
    var hudText = "Zombies: 0  FPS: 0";
    var hudBold = false;

    // 2-second rolling average FPS (120-slot circular buffer at 60fps target)
    var stopped = false;
    var frameTimes = new Array(120).fill(0);
    var frameTimeIdx = 0;
    var frameTimeCount = 0;
    var rollingFps = 0;

    // Load all assets
    function loadAssets(callback) {
        var promises = [];

        for (var i = 0; i < ZOMBIE_TYPES; i++) {
            promises.push(loadImage('assets/zombi' + i + '.png', i));
            promises.push(loadXML('assets/zombi' + i + '.xml', i));
        }

        Promise.all(promises).then(function(results) {
            callback(results);
        }).catch(function(err) {
            console.error('Error loading assets:', err);
        });
    }

    function loadImage(url, index) {
        return new Promise(function(resolve, reject) {
            var img = new Image();
            img.crossOrigin = "anonymous";
            img.onload = function() {
                resolve({ type: 'image', index: index, data: img });
            };
            img.onerror = function() {
                reject(new Error('Failed to load image: ' + url));
            };
            img.src = url;
        });
    }

    function loadXML(url, index) {
        return new Promise(function(resolve, reject) {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', url);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    resolve({ type: 'xml', index: index, data: xhr.responseText });
                } else {
                    reject(new Error('Failed to load XML: ' + url));
                }
            };
            xhr.onerror = function() {
                reject(new Error('Failed to load XML: ' + url));
            };
            xhr.send();
        });
    }

    // Parse XML and extract frame information
    function parseXML(xmlString) {
        var parser = new DOMParser();
        var doc = parser.parseFromString(xmlString, "text/xml");
        var textures = doc.getElementsByTagName("SubTexture");
        var frames = [];

        for (var i = 0; i < textures.length; i++) {
            var texture = textures[i];
            var x = parseInt(texture.getAttribute("x"), 10);
            var y = parseInt(texture.getAttribute("y"), 10);
            var width = parseInt(texture.getAttribute("width"), 10);
            var height = parseInt(texture.getAttribute("height"), 10);
            var frameX = parseInt(texture.getAttribute("frameX") || "0", 10);
            var frameY = parseInt(texture.getAttribute("frameY") || "0", 10);

            // CreateJS SpriteSheet frames: [x, y, width, height, imageIndex, regX, regY]
            frames.push([x, y, width, height, 0, -frameX, -frameY]);
        }

        return frames;
    }

    // Draw HUD text onto the overlay 2D canvas
    function drawHud() {
        hudCtx.clearRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
        if (hudBold) {
            hudCtx.font = "bold 40px Arial";
        } else {
            hudCtx.font = "20px Arial";
        }
        hudCtx.fillStyle = "#FFFFFF";
        hudCtx.textAlign = "left";
        hudCtx.textBaseline = "top";
        hudCtx.fillText(hudText, 10, 10);
    }

    // Initialize benchmark
    function init() {
        // WebGL-accelerated stage
        stage = new createjs.StageGL("canvas", {
            antialias: false,
            transparent: false,
            preserveDrawingBuffer: false
        });
        console.log("Using StageGL (WebGL)");

        stage.canvas.width = CANVAS_WIDTH;
        stage.canvas.height = CANVAS_HEIGHT;

        // Create 16 containers stacked type 0 (bottom) to type 15 (top)
        for (var t = 0; t < 16; t++) {
            var container = new createjs.Container();
            stage.addChild(container);
            containers.push(container);
        }

        // Set up HUD overlay canvas 2D context
        var hudCanvas = document.getElementById("hud");
        hudCanvas.width = CANVAS_WIDTH;
        hudCanvas.height = CANVAS_HEIGHT;
        hudCtx = hudCanvas.getContext("2d");
        drawHud();

        // RAF timing mode for smooth 60fps animation
        createjs.Ticker.timingMode = createjs.Ticker.RAF;
        createjs.Ticker.addEventListener("tick", onTick);

        loadAssets(onAssetsLoaded);
    }

    // Called when all assets are loaded
    function onAssetsLoaded(results) {
        var images = [];
        var xmls = [];

        for (var i = 0; i < results.length; i++) {
            if (results[i].type === 'image') {
                images[results[i].index] = results[i].data;
            } else if (results[i].type === 'xml') {
                xmls[results[i].index] = results[i].data;
            }
        }

        // Create SpriteSheets for each zombie type — 12fps animation (12/60 = 0.2 speed)
        for (var i = 0; i < ZOMBIE_TYPES; i++) {
            var frames = parseXML(xmls[i]);
            var ss = new createjs.SpriteSheet({
                images: [images[i]],
                frames: frames,
                animations: {
                    walk: { frames: [0, 1, 2, 3, 4, 5, 6, 7], speed: 0.2 }
                }
            });
            spritesheets.push(ss);
        }

        console.log("All assets loaded, " + ZOMBIE_TYPES + " SpriteSheets created");
        assetsLoaded = true;
    }

    // Spawn exactly one zombie of each type (16 total) per call
    function spawnBatch() {
        if (!assetsLoaded) return;
        for (var t = 0; t < 16; t++) {
            var sprite = new createjs.Sprite(spritesheets[t], "walk");
            sprite.x = Math.random() * CANVAS_WIDTH;
            sprite.y = Math.random() * CANVAS_HEIGHT;
            sprite.rotation = Math.random() * 360;
            containers[t].addChild(sprite); // add to type-specific container
            zombieCount++;
        }
    }

    // Ticker handler — main benchmark loop
    function onTick(event) {
        // 2-second rolling average FPS via 120-slot circular buffer
        var delta = event.delta;  // milliseconds since last tick (CreateJS provides this)
        if (delta > 0) {
            frameTimes[frameTimeIdx] = delta;
            frameTimeIdx = (frameTimeIdx + 1) % 120;
            if (frameTimeCount < 120) frameTimeCount++;
        }
        var sum = 0;
        for (var i = 0; i < frameTimeCount; i++) sum += frameTimes[i];
        rollingFps = frameTimeCount > 0 ? 1000 * frameTimeCount / sum : 0;

        // Stop condition: 2-second rolling average FPS < 55
        if (!stopped && frameTimeCount >= 120 && rollingFps < 55) {
            stopped = true;
            hudBold = true;
        }

        // Update HUD every 6 frames to avoid string allocation overhead
        if (++hudTick >= 6) {
            hudTick = 0;
            hudText = "Zombies: " + zombieCount + "  FPS: " + Math.round(rollingFps);
            drawHud();
        }

        // Spawn 16 zombies (one of each type) when not stopped and rolling FPS > 55
        if (!stopped && assetsLoaded && rollingFps > 55) {
            spawnBatch();
        }

        stage.update(event);
    }

    // Initialize on window load
    window.onload = init;

})();
