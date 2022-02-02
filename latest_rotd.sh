# Copyright (C) 2022  Fabrice Nicol
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

#!/bin/bash

# This program returns the newt ROTD that can be downloaded from
# the official Mercury downloads page, coming after the date
# entered as first argument.
# Returns the date of the next ROTD, if there is one, or NODATE
# if the date entered as first argument is that of the latest
# ROTD available.
# Exits with code 0 on success and 1 on failure.

help() {

    echo "USAGE: $0 [--help/--version/--reuse]"
    echo
    echo "Returns the date of the latest ROTD,"
    echo "or NODATE if there is none."
    echo "With option --reuse, file index.html"
    echo "from a prior download will be parsed"
    echo "in the current directory."
}

if [ $# -gt 2 ]
then
    help
    exit 1
fi

reuse=false

if [ $# = 1 ]
then
    if [ "$1" = "--help" ]
    then
        help
        exit 0
    elif [ "$1" = "--version" ]
    then
        echo "$0 (c) Fabrice Nicol 2022."
        echo "Licensed under the terms of the GPLv3."
        echo "See file LICENSE."
        echo "Version: $(cat VERSION)"
        exit 0
    elif [ "$1" = "--reuse" ]
    then
        # Reusing index.html from prior download.
        reuse=true
    fi
fi

# Download update

if [ "${reuse}" = "false" ]
then
    ROTD=$(git ls-remote --tags --refs https://github.com/Mercury-Language/mercury-srcdist.git | tail -1 | cut -f2 | sed -E 's/.*\/rotd-([0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2})/\1/')
    if [ $? != 0 ] || [ -z "${ROTD}" ]
    then
        echo "ERR: Could not retrieve dates from git remote." >&2
        exit 100
    fi
    echo "${ROTD}" > LATEST_ROTD
else
    if [ -f LATEST_ROTD ]
    then
        ROTD=$(cat LATEST_ROTD)
    else
        echo "NODATE"
        exit 1
    fi
fi

if [ -n "${ROTD}" ]
then
    echo "${ROTD}"
    exit 0
else
    echo "NODATE"
    exit 1
fi
