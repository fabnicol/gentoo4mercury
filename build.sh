# Copyright (C) 2022 Fabrice Nicol

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

if ! service docker restart >/dev/null 2>&1
then
    # for those with open-rc
    if ! rc-service docker restart
    then
        echo "Could not start Docker."
        exit 15
    fi
fi

DOCKERFILE="Dockerfile"
MERCURY_REV_TEST="$(grep '^m-rev' .config | cut -f 2 -d\ )"
ROTD_DATE_TEST="$(grep '^rotd-date' .config | cut -f2 -d\ )"
THREADS_FOUND=$(grep threads .config | cut -f2 -d\ )
case "${THREADS_FOUND}" in
    ''|*[!0-9]*)
        echo "ERR: Could not find 'threads' in .config file."
        echo "Building with one job."
        THREADS_FOUND=1
        ;;
    *)
        echo "Building with ${THREADS_FOUND} jobs"
        ;;
esac

# ROTDS builds can sometimes crash
# In .config, a reference revision hash is given for a successful build.
# If either is left blank, 06f81f1cf0d339a is used in the Mercury
# git repository master branch and ROTD used is dated 2022-01-09
# These parameters in .config can be overridden on command line

if [ $# = 1 ]
then
    if [ "$1" = "--help" ]
    then
        echo "USAGE:"
	echo "       ./build.sh"
        echo "       ./build.sh git-revision"
        echo "       ./build.sh YYY-MM-DD git-revision"
	echo
        echo "Examples:"
	echo "          ./build.sh 2022-01-10 4c6636982653"
        echo "          ./build.sh 2022-01-10 HEAD~3"
        echo "          ./build.sh HEAD"
        echo "          ./build.sh"
	echo
        echo "Without arguments, the builds uses"
	echo "ROTD 2022-01-09 and git source code"
	echo "at hash 06f81f1cf0d339a."
        exit 0
    elif [ "$1" = "--version" ]
    then
        echo "ubuntu4mercury build script version $(cat VERSION)"
        echo "Builds a Docker image with compilers"
	echo "for the Mercury language (ROTD and git source)."
        echo "(C) Fabrice Nicol 2022."
	echo "Licensed under the terms of the GPLv3."
        echo "Please read file LICENSE in this directory."
	exit 0
    fi

    echo "Using git source revision $1"
    sed "s/REVISION/$1/g" Dockerfile.in > "${DOCKERFILE}"
    if [ -z "${ROTD_DATE_TEST}" ]
    then
       ROTD_DATE=2022-01-09
    else
       ROTD_DATE="${ROTD_DATE_TEST}"
    fi
    sed -i "s/-@/-${ROTD_DATE}/g" Dockerfile
    REVISION="$1"
    DATE="${ROTD_DATE}"
elif [ $# = 2 ]
then
    echo "Using ROTD dated $1 and git source revision $2"
    sed "s/REVISION/$2/g" Dockerfile.in > "${DOCKERFILE}"
    sed -i "s/-@/-$1/g" "${DOCKERFILE}"
    REVISION="$2"
    DATE="$1"
else
    if [ -z "${MERCURY_REV_TEST}" ] || [ -z "${ROTD_DATE_TEST}" ]
    then
        ROTD_DATE=2022-01-09
        MERCURY_REV=06f81f1cf0d339a
    else
        ROTD_DATE="${ROTD_DATE_TEST}"
        MERCURY_REV="${MERCURY_REV_TEST}"
    fi

    echo "Using ROTD dated ${ROTD_DATE} and source rev. ${MERCURY_REV}"

    sed "s/-@/-${ROTD_DATE}/g" Dockerfile.in > "${DOCKERFILE}"
    sed -i "s/REVISION/${MERCURY_REV}/g" "${DOCKERFILE}"

    REVISION="${MERCURY_REV}"
    DATE="${ROTD_DATE}"
fi

sed -i "s/THREADS_FOUND/${THREADS_FOUND}/g" ${DOCKERFILE}

# Below replacing HEAD by hash to avoid cache issues with Docker.

if [ "${REVISION}" = "HEAD" ]
then
    REVISION=$(git ls-remote https://github.com/Mercury-Language/mercury.git HEAD| cut -f1)
    echo "Replacing non-hash revision with hash: ${REVISION}"
    echo "Note: HEAD^, HEAD~n are unsupported."
fi

# Emacs can sometimes crash
# In .config, a reference revision hash is given for a successful build
# If either is left blank, HEAD is used in the Emacs git repository master branch.

EMACS_REF_TEST="$(grep '^rev' .config | cut -f 2 -d\ )"
EMACS_DATE_TEST="$(grep '^date' .config | cut -f2 -d\ )"

if [ -z "${EMACS_REF_TEST}" ] || [ -z "${EMACS_DATE_TEST}" ]
then
    EMACS_DATE=now
    EMACS_REV=HEAD
else
    EMACS_DATE="${EMACS_DATE_TEST}"
    EMACS_REV="${EMACS_REF_TEST}"
fi

echo "Using Emacs source code at ${EMACS_DATE} and rev. ${EMACS_REV}"

sed -i "s/EMACS_DATE/${EMACS_DATE}/g" ${DOCKERFILE}
sed -i "s/EMACS_REV/${EMACS_REV}/g" ${DOCKERFILE}

client=$(docker version -f '{{.Client.Experimental}}')
server=$(docker version -f '{{.Server.Experimental}}')
echo "Docker experimental client: $client"
echo "Docker experimental server: $server"

if  [ "$client" = "false" ] ||  [ "$server" = "false" ]
then
    echo "Installing experimental Docker."
    echo '{\n  "experimental": true\n}' | sudo tee /etc/docker/daemon.json
    mkdir -p ~/.docker
    echo '{\n  "experimental": "enabled"\n}' | sudo tee ~/.docker/config.json
    if ! service docker restart
    then
        # for those with open-rc
        rc-service docker restart
    fi

    # Test again.

    client=$(docker version -f '{{.Client.Experimental}}')
    server=$(docker version -f '{{.Server.Experimental}}')
    echo "Docker experimental client: $client"
    echo "Docker experimental server: $server"

    # If a failure, balk out and tell what to do.

    if  [ $client = false ] ||  [ $server = false ]
    then
        echo "Could not use experimental version of Docker. Remove --squash from script and run it again."
        echo "(Also remove the present test!)"
        exit 1
    fi
else
    echo "Experimental version checked."
fi

if docker build --squash --file ${DOCKERFILE} --tag gentoo:mercury${REVISION} .
then
    echo "Docker image was built as gentoo:mercury${REVISION}"
else
    echo "Docker image creation failed."
    exit 2
fi

if docker save gentoo:mercury${REVISION} -o gentoo4mercury.tar
then
  if  xz -9 -k -f gentoo4mercury.tar && gzip -v -f gentoo4mercury.tar \
                         && echo "ROTD DATE: ${DATE}" > SUMS \
                         && echo "GIT SOURCE REVISION: ${REVISION}" >> SUMS \
                         && echo b2sum: $(b2sum gentoo4mercury.tar.xz) >> SUMS \
                         && echo b2sum: $(b2sum gentoo4mercury.tar.gz) >> SUMS \
                         && echo sha512sum: $(sha512sum gentoo4mercury.tar.xz) >> SUMS \
                         && echo sha512sum: $(sha512sum gentoo4mercury.tar.gz) >> SUMS
  then
      echo "Compression performed."
  else
      echo "Could not compress the image tarball."
      exit 3
  fi
else
    echo "Docker could not save the image to tarball."
    exit 4
fi
