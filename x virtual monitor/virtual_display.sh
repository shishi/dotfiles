#! /bin/bash

/usr/bin/xrandr -d :0 --output VIRTUAL1 --primary --auto
/usr/bin/xrandr --newmode "3840x2160_60.00"  712.75  3840 4160 4576 5312  2160 2163 2168 2237 -hsync +vsync
/usr/bin/xrandr --addmode VIRTUAL1 "3840x2160_60.00"

#/usr/bin/xrandr -d :0 --output VIRTUAL2 --primary --auto
#/usr/bin/xrandr --addmode VIRTUAL2 "3840x2160_60.00"

/usr/bin/xrandr

