#!/bin/sh
[ -d build ] && rm -rf build/
find . -name "report*json" -exec rm {} \;
