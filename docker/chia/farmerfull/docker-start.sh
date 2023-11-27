#!/bin/env bash

chia start node farmer-only wallet harvester -r

trap "echo Shutting down ...; chia stop all -d; exit 0" SIGINT SIGTERM
sleep 10

tail -f $CHIA_ROOT/log/debug.log
