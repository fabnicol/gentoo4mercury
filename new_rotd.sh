#!/bin/bash

# This program returns the newt ROTD that can be downloaded from
# the official Mercury downloads page, coming after the date
# entered as first argument.
# Returns the date of the next ROTD, if there is one, or NODATE
# if the date entered as first argument is that of the latest
# ROTD available.
# Exits with code 0 on success and 1 on failure.

if [ $# != 1 ]
then
    echo "Enter the date of the latest ROTD as 1st argument."
    echo "Exiting."
    exit 1
fi

# Download update

[ -f index.html ] && rm index.html
if ! wget http://dl.mercurylang.org/index.html -O index.html
then
    echo "Could not download index from Mercury website."
    exit 1
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

line_bc=$(($(grep $1 list2 | cut -f1 -d\:) - 1))
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
    rm list list2
else
    echo "NODATE"
fi
exit 0
