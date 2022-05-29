WIDTH = 17;
LENGTH = 60;
HEIGHT = 60;

difference() {
    cylinder(WIDTH, LENGTH, LENGTH, $fn=3, center=false);
    translate([-100, 0, -0.001]) {
        cube([LENGTH * 100, LENGTH * 100, LENGTH * 100]);
    }
}

