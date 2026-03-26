import openfl.display.Sprite;
import openfl.Lib;

class Main extends Sprite {
    public function new() {
        super();
        addChild(new ZombieBenchmark());
    }
}
