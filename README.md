# matlab-stargo
Control an Avalon mount with StarGo from Matlab. 
Version: 19.08. Download at https://github.com/farhi/matlab-stargo.

![Image of StarGo](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/stargo.jpg)

Purpose
=======

STARGO: this is a Matlab class to control the Avalon StarGo for telescope mounts.
- Controller: Avalon StarGo
- Mounts: M-zero, M-uno, Linear mounts.
   
This way you can fully control, and plan the sky observations from your sofa, while it's freezing outside.

Table of Contents
- [Initial set-up of the StarGo board](#stargo-init)
- [Connecting the StarGo board to the compute](#connecting)
- [Description of the StarGo main interface](#interface)
- [Setup of the scope](#mount-init) (balancing, polar alignment, star alignment)
- [Methods](#methods)
- [Installation](#installation)
- [Credits](#credits)

Initial set-up of the StarGo board <a id=stargo-init></a>
==================================

For the initial set-up (only once), it is safer to follow the instructions from Avalon, and used their StarGo software. This way, all internal settings (torque, gear ratio, other hidden stuff) will be transferred to the board from the MCF pre-configured files. You will thus need a Windows system, and the ASCOM platform. Once done, you do not need any more the ASCOM drivers (except if you wish to control other equipment), nor Windows (any other system will do). Make sure you also set the correct location (longitude, latitude) for your observation site. This can be changed later from the matlab-stargo application.

In case you do not have access to a Windows system, you can still use the matlab-stargo, but some functionalities may be incomplete.

Connecting the StarGo board to the computer <a id=connecting></a>
===========================================

Switch ON the StarGo controller (plug its power supply). You may then connect the StarGo board to the computer either using a USB cable, or via Bluetooth/wifi. Follow the procedure indicated in the StarGo manual. In the end, you will get a serial port reference such as (this depends on your system):
- Windows: 'COM1' on Windows
- Linux: '/dev/ttyUSB0' (when connected with a cable)
- Linux: '/dev/rfcomm0' (when connected via Bluetooth)
- Mac OSX: '/dev/tty.KeySerial1'
- simulation mode: 'sim'

In case the device is not found, or you wish to test the application without connecting the real board, you can specify the 'sim' devive for the simulation mode.

Then start the Matlab StarGo application using the following commands (from Matlab):
```matlab
addpath /path/to/matlab-stargo
sg = stargo;  % should detect the serial port
plot(sg);
```

In case the wrong serial port is used, or is not detected, you may use, following the above mentioned port (here for a USB cable under Linux). The window can be rescaled to match your screen resolution.
```matlab
sg = stargo('/dev/ttyUSB0');
```
Last, when not found the simulation mode 'sim' is used.

After a few seconds, the main StarGo interface will show up. The window can be rescaled to match your screen resolution. The UTC offset (time-zone and daylight saving) will be determined automatically from the computer clock, as well as the date and time. The RA and DEC coordinates are shown as 0 after switching the board ON.

![StarGo Main GUI](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/StarGo_main_interface.png)

You should then open the settings Dialogue with the main interface 'StarGo/Settings' menu item, or with command:
```matlab
settings(sg); 
```

![StarGo Settings Dialogue](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/StarGo_settings.png)

Check the main settings, e.g. the latitude and longitude for your observation site, as well as the Polar scope LED level. If the attached scope does not collide with the mount when passing the meridian, you can leave the meridian flip mode to 'off', else set it to 'auto'. We do not recommend to change the other setings, except the RA/DEC reverse mode in case the mount does not go in the right direction when pressing the arrow keys. In case you need to change the mount mode (equatorial / alt-azimutal), you may need to restart the board. Then restart Matlab and re-connect to your StarGo board.

Description of the StarGo main interface <a id=interface></a>
========================================

The interface displays the RA and DEC coordinates reported by the board (the mount) on the left side. Red LEDs on the left are switched on when motors are active (tracking or moving). The slew speed for manual moves can be changed with the slider below (4 levels, it may be slow to respond - be patient). Arrow keys allow the move the RA and DEC motors using the above slew speed. Pressing the arrows starts the move. To stop it, press the STOP button in the centre. The mount status is shown on the bottom left, e.g. as TRACKING or MOVING.

The right side shows a SkyChart view. It displays stars and other objects from catalogues, as well as the current mount position (as a red cross/circle), and potential targets (see below). You can use the ToolBar icons to e.g. select the zoom tool (+) and (-). Then, it is possible to drag a rectangle around areas you wish to focus at. Double click the chart to rest the view, or use the 'SkyChart/Reset Plot' menu item.

Menus allow more more commands, e.g.:
- The File menu is standard (save, print, ...).
- The StarGo menu contains commands to control the mount.
- The Help menu shows help about the StarGo (this help).
- The SkyChart menu relates to commands for the sky view.
- The Planning menu allow to define a set of targets, and then run through an observation list with exposure times.

Experiment the interface a little to discover its functionalities.

Setup of the scope<a id=mount-init></a>
==================

Balancing
---------

Install the Tripod and level it, using its incorporated bubble level. Make sure the scope on the mount is well balanced. First balance the DEC axis, then the RA axis. You may need counter-weights to balance the RA axis. Point roughly the Pole, the DEC axis pointing down (scope on the top). 

Polar alignment
---------------

The Polar alignment is an essential step. It is defined as the HOME position, pointing towards the Pole. Install the Polar Scope provided by Avalon with your mount. By construction, it does not require any alignment, as the mechanics is finely adjusted. Connect the LED to the StarGo and switch it ON from the StarGo settings Dialogue. Then, you need to position correctly the Polaris star wrt the Pole (in Northern Hemisphere), in the Polar Scope. 

The Sky Chart displayed on the main interface assumes you are facing South. This means that the area around Polaris on this map is already reverted, as seen in a refractor. You can then zoom on Polaris (use the (+) icon on the ToolBar, select a rectangle region around). The North Pole is also displayed. Rotate the Polar Scope (unscrew slightly its two small knobs) to match the Chart, so that the Polaris circle is at the same o-clock position in the Polar Scope. Then block it.

![StarGo zoom on Polaris (Matlab)](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/StarGo_Polaris.png)
![StarGo zoom on Polaris (Stellarium)](https://github.com/farhi/matlab-stargo/blob/master/@stargo/doc/StarGo_Polaris_Stellarium.png)

Now, position Polaris on its circle in the Polar Scope corresponding to the Sky Chart by adjusting the altitude (elevation, vertical screw), and the azimuthal position (with two horizontal screw). As said before, as the image is reversed, movements will be opposite i in the Polar Scope. Once done, block it all. Make sure you will not bump into the tripod, mount or scope afterwards (be cautious).

You may also use Stellarium https://stellarium.org/ and display the North Pole. Display the Equatorial coordinate grid, and locate Polaris wrt the North Pole, using clock graduations. The view in the Polar scope will be inverted (the Polar scope is a refractor). For instance, if Polaris is a 9 o-clock, then it must be positioned at 3 o-clock in the Polar scope. Position Polaris on its circle (at 40 arcmins from Pole), at the given clock quadrant (inverted wrt Stellarium). 

For the South Pole, a similar procedure (using the StarGo SkyChart or Stellarium) can be used, but the image on the Sky Chart is not reversed.

If you are in a hurry, you may align on Polaris only. This is not as good, but will do if you use short exposures (e.g. 30 s max). On longer exposures, stars would be seen as circling slowly.

Once the mount is aligned on the Pole, you can synchronise the StarGo encoders on that position by selecting the 'StarGo/Home/Set HOME position' menu item. 
You may alternatively enter the command:
```matlab
home(sg, 'set');
```

The DEC coordinate is then set to e.g. 90 deg, and the RA coordinate cooresponds with the current West. Once done, as the mount knows the Pole location (HOME), the site GPS and the time, it can be requested to point any object. However, without a reference few star alignments, the accuracy may not be perfect.

Star alignment
--------------

- Select a reference star (e.g. Regulus, Vega, Sirius, Betelgeuse) and use GOTO to slew the mount there.
- With the KeyPad or directional arrows on the interface, center that star in the scope view. The DEC axis usually requires a minimal adjustment, whereas the RA axis may be larger.
- Then SYNC/align it. This indicates that the target star is there. The mount coordinates will then be set to that of the star.
- You may enter more reference stars, up to 24, in order to refine the alignment.




Methods <a id=methods></a>
=======

Installation <a id=installation></a>
============

There is no ned for any ASCOM, nor INDI plateform. Only Matlab (no other toolbox), 
as well as gphoto if you plan to use a camera.

**Matlab files**
   
First navigate to the matlab-stargo directory or type:
 
```matlab
  addpath /path/to/matlab-stargo
```
 
Credits <a id=credits></a>
=======

- Local Time to UTC from https://fr.mathworks.com/matlabcentral/fileexchange/22295-local-time-to-utc
- Parse JSON from https://fr.mathworks.com/matlabcentral/fileexchange/23393--another--json-parser
- Amazing work from Eran O. Ofek (MAAT). URL : http://weizmann.ac.il/home/eofek/matlab/
- Stars (~100000) data base from http://astrosci.scimuze.com/stellar_data.htm
- deep sky objects (~200000) from http://klima-luft.de/steinicke/ngcic/ngcic_e.htm
 
(c) E. Farhi, 2019. GPL2.


