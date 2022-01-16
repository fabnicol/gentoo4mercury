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

    echo "USAGE: $0"
    echo "Returns the date of the latest ROTD,"
    echo "or NODATE if there is none."
}

if [ $# -gt 2 ]
then
    help
    exit 1
fi

if [ $# = 1 ]
then
    if [ "$1" = "--help" ]
    then
        help
        exit 0
    fi
    if [ "$1" = "--version" ]
    then
        echo "$0 (c) Fabrice Nicol 2022."
        echo "Licensed under the terms of the GPLv3."
        echo "See file LICENSE."
        echo "Version: $(cat VERSION)"
        exit 0
    fi
fi

# Download update

[ -f index.html ] && rm index.html
if ! wget http://dl.mercurylang.org/index.html -O index.html
then
    echo "Could not download index from Mercury website."
    exit 1
fi

# Extract ROTD list

if ! grep -m 1 -o -E '"rotd/mercury-srcdist-rotd-(.*).tar.xz"' index.html > list
then
    echo "Could not extract dates from Mercury HTML index."
    exit 1
fi
    bc_date=$(sed -E -n \
        's,.*rotd/mercury-srcdist-rotd-(.*).tar.xz.*,\1,p' list)
    if [ $? != 0 ]
    then
        echo "Could not extract prior ROTD date."
        exit 1
    fi
    rm list
if [ -n "${bc_date}" ]
then
    echo "${bc_date}"
else
    echo "NODATE"
fi
exit 0
