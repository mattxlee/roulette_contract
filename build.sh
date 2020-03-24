#!/bin/sh
[ -d build ] && rm -rf build
truffle build
node retrieve-abi.js
