GEARBOX_WIDTH = 32;
GEARBOX_DEPTH = 46;
GEARBOX_HEIGHT = 25.2;

GEARBOX_GAP = 1;

SCREW_HOLE_HEIGHT = 2;
SCREW_HOLE_X_OFFSET = 9;
SCREW_HOLE_Y_OFFSET_TOP = 17;
SCREW_HOLE_Y_OFFSET_BOTTOM = 16;

CASE_WALL_THICKNESS = 2;
GAP_SIZE = 0.3;  // gap between motor and housing

SHAFT_Y_OFFSET = 8;
SHAFT_DIAMETER = 6;
SHAFT_LENGTH = 14;
SHAFT_CLEARANCE = 2;

M3_HOLE_DIAMETER = 3.3;
M3_SCREW_HEAD_DIAMETER = 6;

GRIP_DIAMETER = 41;
GRIP_GUIDE_WALL_THICKNESS = 4;
GRIP_GUIDE_DEPTH = 12;
GRIP_GUIDE_HEIGHT = SHAFT_LENGTH - CASE_WALL_THICKNESS + SHAFT_CLEARANCE;
GRIP_OD = GRIP_DIAMETER + GRIP_GUIDE_WALL_THICKNESS * 2;

COMMAND_STRIP_LENGTH = 46;
COMMAND_STRIP_WIDTH = 16;

module m3_cutout()
{
    cylinder(
        h=CASE_WALL_THICKNESS + 0.001,
        d=M3_HOLE_DIAMETER,
        center=true,
        $fn=36
    );
    translate([0, 0, CASE_WALL_THICKNESS / 2 + GRIP_GUIDE_HEIGHT / 2])
    {
        cylinder(
            h=GRIP_GUIDE_HEIGHT + 0.001,
            d=M3_SCREW_HEAD_DIAMETER,
            center=true,
            $fn=36
        );
    }
}

module feeder()
{
    union()
    {
        difference()
        {
            // ring
            cylinder(
                h=GRIP_GUIDE_HEIGHT,
                d=GRIP_OD,
                $fn=100,
                center=true
            );
            cylinder(h=GRIP_GUIDE_HEIGHT+0.001, d=GRIP_DIAMETER, $fn=100, center=true);

            // half-cylinder
            translate([0, GRIP_OD / 2, 0])
            {
                cube(GRIP_OD, center=true);
            }

        }

        // straight portion
        for (x=[1, -1])
        {
            translate(
                [
                    (GRIP_DIAMETER / 2 + GRIP_GUIDE_WALL_THICKNESS / 2) * x,
                    GRIP_GUIDE_DEPTH / 2,
                    0,
                ]
            )
            {
                cube(
                    [
                        GRIP_GUIDE_WALL_THICKNESS,
                        GRIP_GUIDE_DEPTH,
                        GRIP_GUIDE_HEIGHT
                    ],
                    center=true
                );
            }
        }
    }
}

difference()
{
    base_width = GRIP_DIAMETER + COMMAND_STRIP_WIDTH * 2;

    union()
    {
        cube(
            [
                base_width,
                GEARBOX_DEPTH,
                CASE_WALL_THICKNESS
            ],
            center=true
        );
        translate(
            [
                0,
                SHAFT_Y_OFFSET,
                CASE_WALL_THICKNESS / 2 + GRIP_GUIDE_HEIGHT / 2
            ]
        )
        {
            feeder();
        }

        for (x=[1, -1])
        {
            translate(
                [
                    x * ((GRIP_DIAMETER + COMMAND_STRIP_WIDTH) / 2),
                    0,
                    (CASE_WALL_THICKNESS + GRIP_GUIDE_HEIGHT) / 2,
                ]
            )
            {
                cube(
                    [COMMAND_STRIP_WIDTH, COMMAND_STRIP_LENGTH, GRIP_GUIDE_HEIGHT],
                    center=true
                );
            }
        }
    }
    translate([0, SHAFT_Y_OFFSET, 0])
    {
        cylinder(
            h=CASE_WALL_THICKNESS + 0.001,
            d=SHAFT_DIAMETER + GAP_SIZE * 2,
            center=true,
            $fn=36
        );
    }
    for (x=[1, -1])
    {
        translate([x*SCREW_HOLE_X_OFFSET, SCREW_HOLE_Y_OFFSET_TOP, 0])
        {
            m3_cutout();
        }
        translate([x*SCREW_HOLE_X_OFFSET, -SCREW_HOLE_Y_OFFSET_BOTTOM, 0])
        {
            m3_cutout();
        }
    }
}

