# matlab-starbook
Control an Avalon mount with StarGo from Matlab

![Image of StarGo](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/stargo.jpg)

Purpose
-------

STARGO: this is a Matlab class to control the Avalon StarGo for telescope mounts.

- Controller: StarGo
- Mounts: M-zero, M-uno, Linear mounts.
   
This way you can fully control, and plan the sky observations from your sofa, while it's freezing outside.

Setup of the scope
------------------

**Balancing**

Make sure the scope on the mount is well balanced. Firt balance the DEC axis, then the RA axis. You may need counter-weights to balance the RA axis. Also make sure the scope is roughly aligned with the Pole scope.

**Polar alignment**

First perform a Polar alignment. For this, use ![Stellarium](https://stellarium.org/) and display the North Pole. Display the Equatorial coordinate grid, and locate Polaris wrt the North Pole, using clock graduations. The view in the Polar scope will be inverted (the Polar scope is a refractor). For instance, if Polaris is a 9 o-clock, then it must be positioned at 3 o-clock in the Polar scope. Position Polaris on its circle (at 40 arcmins from Pole), at the given clock quadrant (inverted wrt Stellarium). For the South Pole, a similar procedure 5using Stellarium) can be used.

**Initial set-up and star alignment**

- Switch the StarGo ON, the coordinates are set to zero on both RA and DEC axes. 
- Start the StarGo Matlab application using e.g. `addpath('/path/to/stargo'); sg=stargo('/dev/ptyUSB0'); plot(sg);`. The proper serial port is something like `COM1` under Windows, `/dev/tty.KeySerial1` under MacOSX, and `/dev/ttyUSB0` under Linux.
- Make sure the site location is properly set (longitude, latitude), as well as the UTC offset (time-zone and day-light saving). Use the __Navigate/Settings__ menu for that.
- Point the North Pole with the scope, the DEC axis pointing down (scope on the top). 
- Then set/sync the HOME position. The RA coordinate now shows the meridian, and DEC remains at 90.
- Select a reference star and use GOTO to slew the mount there.
- With the KeyPad or directional arrows on the interface, center that star in the scope view. The DEC axis usually requires a minimal adjustment, whereas the RA axis may be larger.
- Then SYNC/align it. This indicates that the target star is there. The mount coordinates will then be set to that of the star.
- You may enter more reference stars, up to 24, in order to refine the alignment.

Usage
-----


