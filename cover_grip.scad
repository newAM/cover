HEIGHT = 6;
STRING_RADIUS = 0.6;
SHAFT_RADIUS = 3;
FLAT_RADIUS = 2.4;
BEAD_RADIUS = 2.4;
BEAD_GAP = 0.2;
BEAD_SPACING = 6;
NUM_BEADS = 18;

CIRCUMFERENCE = NUM_BEADS * BEAD_SPACING;
RADIUS = CIRCUMFERENCE / (2 * PI);
ANGLE_SPACING = 360 / NUM_BEADS;

echo(CIRCUMFERENCE=CIRCUMFERENCE);
echo(RADIUS=RADIUS);
echo(ANGLE_SPACING=ANGLE_SPACING);

module bead_holes()
{
    fn = 36;
    hole_size = BEAD_RADIUS + BEAD_GAP;
    cyl_radius = RADIUS + hole_size;

    // repeat bead holes
    for (theta=[0:ANGLE_SPACING:360])
    {
        union()
        {
            // cylindrical to Cartesian coordinate conversion
            translate([RADIUS * cos(theta), RADIUS * sin(theta), 0])
            {
                // bead hole
                sphere(hole_size, $fn=fn);
            }
            translate([cyl_radius * cos(theta), cyl_radius * sin(theta), 0])
            {
                rotate([-theta, 90, 0])
                {
                    cylinder(r=hole_size, h=hole_size, $fn=fn);
                }
            }
        }
    }
}

difference()
{
    // body
    cylinder(h=HEIGHT, r1=RADIUS, r2=RADIUS, center=true, $fn=180);

    bead_holes();

    // string cutout
    difference()
    {
        linear_extrude(height=STRING_RADIUS+BEAD_GAP, center=true)
        {
            difference()
            {
                circle(r=RADIUS+0.001, $fn=180);
                circle(r=RADIUS-STRING_RADIUS+BEAD_GAP, $fn=180);
            }
        }
        bead_holes();
    }

    // shaft
    linear_extrude(height=HEIGHT+1, center=true)
    {
        scale(1.1)
        {
            difference()
            {
                circle(r=SHAFT_RADIUS, $fn=90);

                // "D" shape
                translate([FLAT_RADIUS + SHAFT_RADIUS, 0, 0])
                {
                    square([SHAFT_RADIUS * 2, SHAFT_RADIUS * 2], center=true);
                }
            }
        }
    }
}
