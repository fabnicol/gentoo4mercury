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
    echo "USAGE: $0 rotd-date [number of rotds after it] [--reuse] [--keep]"
    echo
    echo "OPTIONS:"
    echo "--reuse: Optional argument. Reuse index.html already downloaded."
    echo "--keep:  Optional argument. Do not remove temporary files."
    echo "         These two options should come at the end in this order,"
    echo "         after a numeric second argument."
    echo "NOTE:"
    echo "If the second argument is absent, it is taken to be equal to 1."
    echo
    echo "Examples: $0 2022-01-09 4 --reuse"
    echo "          $0 2022-01-09 1 --reuse --keep"
    echo "          $0 2022-01-09"
}

balk_out() {
    echo "You entered a third and/or fourth argument that is not licit."
    echo
    help
    exit 1
}

if [ $# -gt 4 ] || [ $# = 0 ]
then
    echo "Enter the date of the latest ROTD as 1st argument"
    echo "and optionally the minimum number of ROTD after it."
    help
    exit 1
fi

reuse=false
keep=false

if [ $# = 1 ]
then
    if [ "$1" = "--help" ]
    then
        help
        exit 0
    fi
    if [ "$1" = "--version" ]
    then
        echo "new-rotd (c) Fabrice Nicol 2022."
        echo "Licensed under the terms of the GPLv3."
        echo "See file LICENSE."
        echo "Version: $(cat VERSION)"
        exit 0
    fi
else
    increment=$2
    case "${increment}" in
        ''|*[!0-9]*)
            echo "ERR: Second argument is not licit."
            echo "Enter an integer second argument (>1)"
            help
            exit 1
            ;;
        *)
            echo "Looking for ${increment} ROTD after $1." >/dev/stderr
            ;;
    esac
    if [ $# -gt 2 ]
    then
        if [ "$3" = "--reuse" ]
        then
            reuse=true
        else
            balk_out
        fi
        if [ $# = 4 ]
        then
            if [ "$4" = "--keep" ]
            then
                keep=true
            else
                balk_out
            fi
        fi
   fi
fi

# Download update

if [ "${reuse}" = false ]
then
    [ -f index.html ] && rm index.html
    if ! wget http://dl.mercurylang.org/index.html -O index.html
    then
        echo "Could not download index from Mercury website."
        exit 1
    fi
fi

# Extract ROTD list

if ! grep -o -E '"rotd/mercury-srcdist-rotd-(.*).tar.xz"' index.html > list
then
    echo "Could not extract dates from Mercury HTML index."
    exit 1
fi

# Now count lines and remove quotes:

if ! grep -n -o "rotd/.*xz" list > list2
then
    echo "Could not count lines in list of ROTDs."
    exit 1
fi

# Compute line of bootstrapping compiler 2022-01-09

line_bc=$(($(grep $1 list2 | cut -f1 -d\:) - ${increment}))
if [ $? != 0 ]
then
    echo "Could not compute prior line in list."
    exit 1
fi

if [ "${line_bc}" -gt "0" ]
then
    new_bc_date=$(cut -f2 -d\: <<< `sed -E -n \
        "${line_bc}s,rotd/mercury-srcdist-rotd-(.*).tar.xz,\1,p" list2`)
    if [ $? != 0 ]
    then
        echo "Could not extract prior ROTD date."
        exit 1
    fi
    echo ${new_bc_date}
    [ "${keep}" = false ] && rm list list2 index.html
else
    echo "NODATE"
fi
exit 0
