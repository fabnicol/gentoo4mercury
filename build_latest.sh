#!/bin/bash


if [ $# = 1 ] 
then
    if [ "$1" = "--reuse" ]
    then
        latest_rotd=$(/bin/bash latest_rotd.sh --reuse 2>/dev/null)
    elif [ "$1" = "--help" ]
    then
        echo "USAGE: build_latest.sh [--help/--reuse]"
	echo
	echo 'Launches build.sh $(latest_rotd.sh [--reuse]) HEAD'
	echo
	exit 0
    else
        $0 --help 
        exit 1
    fi
else
    latest_rotd=$(/bin/bash latest_rotd.sh)
    [ $? != 0 ] && exit $?
fi

/bin/bash build.sh ${latest_rotd} HEAD

