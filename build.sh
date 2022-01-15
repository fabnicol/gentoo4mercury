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

if ! service docker start >/dev/null 2>&1
then
    # for those with open-rc
    if ! rc-service docker start
    then
        echo "Could not start Docker."
        exit 15
    fi
fi

if ! awk --version > /dev/null 2>&1
then
  echo "You should install 'awk'"
  exit 1
fi

DOCKERFILE="Dockerfile"
CFLAGS_TEST="$(awk '/^cflags/ {print $2}' .config)"
MERCURY_REV_TEST="$(awk '/^m-rev/ {print $2}' .config)"
ROTD_DATE_TEST="$(awk '/^rotd-date/ {print $2}' .config)"
THREADS_FOUND="$(awk '/^threads/ {print $2}' .config)"
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
BOOTSTRAP_COMPILER_URL="$(awk '/^bootstrap-url/ {print $2}' .config)" 
BOOTSTRAP_COMPILER_NAME="$(awk '/^bootstrap-name/ {print $2}' .config)"
BOOTSTRAP_COMPILER_DATE="$(awk '/^bootstrap-date/ {print $2}' .config)"
GIT_SOURCE_SINCE="$(awk '/^since/ {print $2}' .config)"
MERCURY_GIT_URL="$(awk '/^url/ {print $2}' .config)"
MERCURY_DEFAULT_REV="$(awk '/^default-rev/ {print $2}' .config)"
# Emacs can sometimes crash
# In .config, a reference revision hash is given for a successful build
# If either is left blank, HEAD is used in the Emacs git repository master branch.
EMACS_REV_TEST="$(awk '/^emacs-rev/ {print $2}' .config)"
EMACS_DATE_TEST="$(awk '/^emacs-date/ {print $2}' .config)"

echo "Bootstrap compiler: ${BOOTSTRAP_COMPILER_URL}/${BOOTSTRAP_COMPILER_NAME}"
echo "Dated: ${BOOTSTRAP_COMPILER_DATE}"
echo "Default Mercury revision: ${MERCURY_REV_TEST}"
echo "Fallback Mercury revision: ${MERCURY_DEFAULT_REV}"
echo "Default ROTD date: ${ROTD_DATE_TEST}"
echo "Cloning Mercury git source since: ${GIT_SOURCE_SINCE}"
echo "From URL: ${MERCURY_GIT_URL}"
echo "Emacs revision: ${EMACS_REV_TEST}"
echo "Emacs date: ${EMACS_DATE_TEST}"
echo "------------------------------------------------------------------------"
echo

# ROTDS builds can sometimes crash
# In .config, a reference revision hash is given for a successful build.
# If either is left blank, 06f81f1cf0d339a is used in the Mercury
# git repository master branch and ROTD used is dated 
# $BOOTSTRAP_COMPILER_DATE.
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
        echo "gentoo4mercury build script version $(cat VERSION)"
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
       ROTD_DATE=${BOOTSTRAP_COMPILER_DATE}
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
        ROTD_DATE="${BOOTSTRAP_COMPILER_DATE}"
        MERCURY_REV=${MERCURY_DEFAULT_REV}
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

sed -i "s/CFLAGS/${CFLAGS}/g" ${DOCKERFILE}
sed -i "s/THREADS_FOUND/${THREADS_FOUND}/g" ${DOCKERFILE}
sed -i "s/BOOTSTRAP_COMPILER_NAME/${BOOTSTRAP_COMPILER_NAME}/g" ${DOCKERFILE}
sed -i "s,BOOTSTRAP_COMPILER_URL,${BOOTSTRAP_COMPILER_URL},g" ${DOCKERFILE}
sed -i "s/BOOTSTRAP_COMPILER_DATE/${BOOTSTRAP_COMPILER_DATE}/g" ${DOCKERFILE}
sed -i "s/GIT_SOURCE_SINCE/${GIT_SOURCE_SINCE}/g" ${DOCKERFILE}

# Below replacing HEAD by hash to avoid cache issues with Docker.

if [ "${REVISION}" = "HEAD" ]
then
    REVISION=$(git ls-remote ${MERCURY_GIT_URL} HEAD| cut -f1)
    echo "Replacing non-hash revision with hash: ${REVISION}"
    echo "Note: HEAD^, HEAD~n are unsupported."
fi

if [ -z "${EMACS_REF_TEST}" ] || [ -z "${EMACS_DATE_TEST}" ]
then
    EMACS_DATE=now
    EMACS_REV=HEAD
else
    EMACS_DATE="${EMACS_DATE_TEST}"
    EMACS_REV="${EMACS_REF_TEST}"
fi

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
