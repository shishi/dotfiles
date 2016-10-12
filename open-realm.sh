#!/bin/sh
UUID=$(ls -t1 ~/Library/Developer/CoreSimulator/Devices/ | head -1)
open $(find ~/Library/Developer/CoreSimulator/Devices/$UUID/data/Containers/Data/Application/ -name \*.realm)
