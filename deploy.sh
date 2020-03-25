#!/bin/sh
if [ $# -ne 1 ]; then
    echo "./deploy.sh [network name]; for example: ./deploy.sh development"
    exit 0
fi

truffle deploy --network $1
node retrieve-addr.js
