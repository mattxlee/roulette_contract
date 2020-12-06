#!/bin/sh
if [ ! -f .mnemonic ]; then
    echo "You need generate the mnemonic and save to file .mnemonic before you start Ganache client."
    exit 1
fi

ganache-cli -b 1 -p 7545 -i 101 -m "`cat .mnemonic`"
