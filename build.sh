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

# To avoid compressing the image, set the environment variable
# COMPRESS to 'true'

# Note: there may be spurious sed's. This is to simplify maintenance.

# replace_head_revision
# Replace global variable REVISION with the commit hash
# of git source HEAD. Otherwise no-op.
# First argument is obligatory (unchecked)

replace_head_revision() {
	if [ "$1" = "HEAD" ]
	then
	    REVISION=$(git ls-remote ${MERCURY_GIT_URL} HEAD| cut -f1)
	    echo "Replacing non-hash revision with hash: ${REVISION}"
	    echo "Note: HEAD^, HEAD~n are unsupported."
	fi
}

# sudo required here, even if launched with sudo.

if ! sudo service docker start >/dev/null 2>&1
then
    # for those with open-rc
    if ! sudo rc-service docker start
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

# Download existing DATE and if there is a newer ROTD, adjust.

URL_BC="$(awk '/^bootstrap-url/ {print $2}' .config.in)"

if ! wget ${URL_BC}/DATE -O DATE; then
    echo "No DATE file could be downloaded."
    exit 1
else
    export date_bc=$(cat DATE)
fi

sed "s/DATE_BC/${date_bc}/" .config.in > .config

DOCKERFILE1="Dockerfile1"
DOCKERFILE2="Dockerfile2"

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

# Emacs can sometimes crash
# In .config, a reference revision hash is given for a successful build
# If either is left blank, HEAD is used in the Emacs git repository master branch.

EMACS_REV_TEST="$(awk '/^emacs-rev/ {print $2}' .config)"
EMACS_DATE_TEST="$(awk '/^emacs-date/ {print $2}' .config)"

echo "Bootstrap compiler: ${BOOTSTRAP_COMPILER_URL}/${BOOTSTRAP_COMPILER_NAME}"
echo "Dated: ${BOOTSTRAP_COMPILER_DATE}"
echo "Default Mercury revision: ${MERCURY_REV_TEST}"
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
        echo "          ./build.sh HEAD"
        echo "          ./build.sh"
	echo
        echo "Without arguments, the builds uses"
	echo "ROTD ${ROTD_DATE_TEST} and git source code"
	echo "at hash ${MERCURY_REV_TEST}."
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

    replace_head_revision "$1"

    if [ -z "${ROTD_DATE_TEST}" ]
    then
       ROTD_DATE=${BOOTSTRAP_COMPILER_DATE}
    else
       ROTD_DATE="${ROTD_DATE_TEST}"
    fi

    echo "Using ROTD dated ${ROTD_DATE} and git source revision $1"
    echo "------------------------------------------------------------------------"
    echo
elif [ $# = 2 ]
then
    echo "Using ROTD dated $1 and git source revision $2"
    echo "------------------------------------------------------------------------"
    echo

    replace_head_revision "$2"

    ROTD_DATE="$1"
else
    if [ -z "${ROTD_DATE_TEST}" ]
    then
        ROTD_DATE="${BOOTSTRAP_COMPILER_DATE}"
    else
        ROTD_DATE="${ROTD_DATE_TEST}"
    fi

    replace_head_revision "${MERCURY_REV_TEST}"

    echo "Using ROTD dated ${ROTD_DATE} and source rev. ${REVISION}"
    echo "------------------------------------------------------------------------"
    echo
fi

sed -i "s/REVISION/${REVISION}" Dockerfile
sed "s/REVISION/${REVISION}/g" Dockerfile.in  > "${DOCKERFILE1}"
sed "s/REVISION/${REVISION}/g" Dockerfile2.in > "${DOCKERFILE2}"
sed -i "s/-@/-${ROTD_DATE}/g"  "${DOCKERFILE1}" "${DOCKERFILE2}"

sed -i "s/CFLAGS/${CFLAGS}/g" "${DOCKERFILE1}" "${DOCKERFILE2}"
sed -i "s/THREADS_FOUND/${THREADS_FOUND}/g" "${DOCKERFILE1}" "${DOCKERFILE2}"
sed -i "s/GIT_SOURCE_SINCE/${GIT_SOURCE_SINCE}/g" "${DOCKERFILE1}" "${DOCKERFILE2}"

# Below replacing HEAD by hash to avoid cache issues with Docker.

if [ -z "${EMACS_REF_TEST}" ] || [ -z "${EMACS_DATE_TEST}" ]
then
    EMACS_DATE=now
    EMACS_REV=HEAD
else
    EMACS_DATE="${EMACS_DATE_TEST}"
    EMACS_REV="${EMACS_REF_TEST}"
fi

sed -i "s/EMACS_DATE/${EMACS_DATE}/g" "${DOCKERFILE1}" "${DOCKERFILE2}"
sed -i "s/EMACS_REV/${EMACS_REV}/g" "${DOCKERFILE1}" "${DOCKERFILE2}"

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

if docker build --squash --file ${DOCKERFILE1} --tag gentoo:mercury${REVISION} .
then
    echo "Docker image was built as gentoo:mercury${REVISION}"
else
    echo "Docker image creation failed."
    exit 2
fi

echo "${REVISION}" > GIT_HEAD

if docker save gentoo:mercury${REVISION} -o gentoo4mercury.tar
then
  if [ "${COMPRESS_GZ}" = "true" ] || [ "${COMPRESS_XZ}" = "true" ]
  then
      echo "ROTD DATE: ${ROTD_DATE}" > SUMS
      echo "GIT SOURCE REVISION: ${REVISION}" >> SUMS
      echo "Compressing image..."
      if [ "${COMPRESS_XZ}" = "true" ]
      then
        if  xz -9 -k -f gentoo4mercury.tar
        then
          echo b2sum: $(b2sum gentoo4mercury.tar.xz) >> SUMS
          echo sha512sum: $(sha512sum gentoo4mercury.tar.xz) >> SUMS
	else
	  echo "XZ-compression failed"
	  exit 1
        fi
      fi
      if [ "${COMPRESS_GZ}" = "true" ]
      then
        if gzip -f -k gentoo4mercury.tar
	then
	  echo b2sum: $(b2sum gentoo4mercury.tar.gz) >> SUMS
	  echo sha512sum: $(sha512sum gentoo4mercury.tar.gz) >> SUMS
	else
	  echo "GZ-compression failed"
	  exit 1
        fi
      fi
      echo "Compression performed."
      echo "Files present in current directory $PWD: $(ls -al)"
  else
      echo "No compression was performed."
  fi
else
    echo "Docker could not save the image to tarball."
    exit 4
fi
