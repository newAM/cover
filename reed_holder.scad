// a rectangular prism to hold the reed switches closer to the window

STRIP_X = 27;
STRIP_Y = 16;

REED_X = 23;
REED_Y = 13.9;
REED_Z = 5.9;

FRAME_TO_COVER = 33;

MAGNET_Z = 3;

Z = FRAME_TO_COVER - MAGNET_Z - REED_Z;

cube([STRIP_X, STRIP_Y, Z]);
