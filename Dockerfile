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

# name the portage image
FROM gentoo/portage:latest AS portage

# image is based on stage3-amd64
FROM gentoo/stage3

# copy the entire portage volume in
COPY --from=portage /var/db/repos/gentoo /var/db/repos/gentoo

# USE, ACCEPT_KEYWORDS and LICENSE fixes

RUN echo 'USE="-gtk -gtk2 -gtk3 -sandbox -introspection"' \
            >> /etc/portage/make.conf

# A bit of optimization on Haswell+

RUN sed -i 's/COMMON_FLAGS.*//g' /etc/portage/make.conf \
    && echo 'COMMON_FLAGS="-march=core-avx2 -O2 -pipe"' >> /etc/portage/make.conf
RUN echo '>=media-libs/libsdl-1.2.15-r9 X'  > new.use
RUN echo '>=media-libs/libglvnd-1.3.2-r2 X' >> new.use
RUN echo '>=x11-libs/libxkbcommon-1.0.3 X'  >> new.use
RUN echo '>=dev-libs/libpcre2-10.35 pcre16' >> new.use
RUN echo 'sys-fs/squashfs-tools lzma' >> new.use
RUN echo 'app-emulation/virtualbox -alsa -debug -doc dtrace headless -java libressl -lvm -opengl -opus pam -pax_kernel \
-pulseaudio -python -qt5 -sdk udev -vboxwebsrv -vnc' >> new.use
RUN mv new.use /etc/portage/package.use
RUN echo '>=app-emulation/virtualbox-extpack-oracle-6.1.18.142142 PUEL' \
           >> /etc/portage/package.license
RUN mkdir -p /etc/portage/package.accept_keywords \
&& echo '>=sys-apps/sandbox-2.21 ~amd64' > /etc/portage/package.accept_keywords/sandbox

# Notably dev-python/setuptools and a couple of other python dev tools
# will be obsolete. No other cautious way than unmerge/remerge

RUN emerge --unmerge dev-python/* 2>&1 | tee -a log
RUN emerge -uDN dev-lang/python 2>&1 | tee -a log
RUN emerge -uDN dev-python/setuptools 2>&1 | tee -a log
RUN emerge -u1 portage
RUN emerge gcc-config
RUN gcc-config $(gcc-config -l| wc -l)  && source /etc/profile

# Kernel sources must be available for some package merges

RUN emerge gentoo-sources 2>&1 | tee -a log
RUN eselect kernel set 1
RUN eselect profile set 1

# One needs a config file to modules_prepare the kernel sources,
# which some packages want. Taking that of project 'mkg'.

RUN emerge -u dev-vcs/git 2>&1 | tee -a log
RUN git clone -b gnome --single-branch --depth=1 https://github.com/fabnicol/mkg.git \
    && cd /mkg \
    && cp -vf .config /usr/src/linux  \
    && rm -rf /mkg

RUN cd /usr/src/linux && make syncconfig \
    && make modules_prepare 2>&1 | tee -a log

# Merging first util-linux to facilitate possible debugging operations
# within the container.

RUN USE=caps emerge -u sys-apps/util-linux 2>&1 | tee -a log

# Common maintenance precautions, might be dispensed with

RUN env-update && source /etc/profile
RUN emerge eix && eix-update

# Now, world updates may be considered anfter sync.
# Should it fail, reverting would be easier.
# Prefer webrsync over sync, to alleviate rsync server load

RUN emerge-webrsync 2>&1 | tee -a log
RUN emerge -uDN --with-bdeps=y @world 2>&1 | tee -a log \
    && echo "[MSG] Docker image built! Launching depclean..."
RUN emerge --depclean 2>&1 | tee -a log

# Download auxiliary ROTD build, to bootstrap image building.

RUN wget https://github.com/fabnicol/ubuntu4mercury/releases/download/v1.0.1/rotd.tar.xz
RUN tar xJvf rotd.tar.xz && rm rotd.tar.xz
RUN echo PATH='/usr/local/mercury-rotd-2022-01-12/bin:$PATH' >> /etc/profile

# Download from Github first then if not available from official website.

RUN wget https://github.com/Mercury-Language/mercury-srcdist/archive/refs/tags/rotd-2022-01-12.tar.gz \
   || wget  https://dl.mercurylang.org/rotd/mercury-srcdist-rotd-2022-01-12.tar.gz -O rotd-2022-01-12.tar.gz
RUN tar xzvf rotd-2022-01-12.tar.gz && rm -vf rotd-2022-01-12.tar.gz
RUN echo 'source /etc/profile' >> /root/.bashrc

# Rebuild the same ROTD dated -2022-01-12 within the docker image for security-minded users.
# Using ENV as sourcing /etc/profile will do only when the image is created, not while building it.

ENV PATH=/usr/local/mercury-rotd-2022-01-09/bin:$PATH
ENV THREADS=2
ENV [ ${THREADS} = 0 ] && THREADS=1
RUN echo "Using ${THREADS} for building."
RUN cd mercury-srcdist-rotd-2022-01-12 && /bin/bash configure && make install PARALLEL=-j${THREADS}
RUN rm -rf /mercury-srcdist-rotd-2022-01-12
RUN if [ "-2022-01-12" != "-2022-01-09" ]; then rm -rf /usr/local/mercury-rotd-2022-01-09; fi

# Now with this secured ROTD build the Mercury git source.

RUN git clone --shallow-since=2022-01-08 \
              -b master https://github.com/Mercury-Language/mercury.git \
              && cd /mercury && git reset --hard HEAD

# Now use the fresh ROTD dated -2022-01-12 to build the git source at revision HEAD.
# Synchronize the ROTD and git source dates otherwise it may not build.

ENV PATH=/usr/local/mercury-rotd-2022-01-12/bin:$PATH
RUN cd /mercury \
   && /bin/bash prepare.sh && /bin/bash configure --disable-most-grades \
   && make install PARALLEL=-j${THREADS} && git rev-parse HEAD > HEAD_HASH
RUN echo PATH='$PATH:/usr/local/mercury-DEV/bin' >> /etc/profile
RUN rm -rf /mercury

# First merge Emacs dependencies

RUN emerge --deep --onlydeps  app-editors/emacs

# Clone emacs, with Mercury support for etags (source code tagging).

RUN echo cloning since date="2022-01-09" rev="73b15f45f9369f511985b7b424c1a6cc54b323c2" \
    && git clone --shallow-since="2022-01-09" -b master git://git.sv.gnu.org/emacs.git \
    && cd emacs && git reset --hard "73b15f45f9369f511985b7b424c1a6cc54b323c2"

RUN cd emacs && /bin/bash autogen.sh \
   && /bin/bash configure --prefix=/usr/local/emacs-DEV \
   && make install -j${THREADS}

# Adjust paths.

RUN echo PATH='$PATH:/usr/local/emacs-DEV/bin' >> /etc/profile
RUN echo MANPATH='$MANPATH:/usr/local/mercury-rotd-2022-01-12/man' >> /etc/profile
RUN echo INFOPATH='$INFOPATH:/usr/local/mercury-rotd-2022-01-12/info' >> /etc/profile
RUN echo "(add-to-list 'load-path \n\
\"/usr/local/mercury-rotd-2022-01-12/lib/mercury/elisp\") \n\
(autoload 'mdb \"gud\" \"Invoke the Mercury debugger\" t)" >> /root/.emacs
RUN rm -rf /emacs
RUN echo '#!/bin/bash \n\
PATH0=$PATH \n\
PATH=/usr/local/mercury-DEV/bin:$PATH mmc "$@" \n\
PATH=$PATH0' > /usr/local/bin/mmc-dev && chmod +x /usr/local/bin/mmc-dev
RUN echo '#!/bin/bash \n\
PATH0=$PATH \n\
PATH=/usr/local/mercury-DEV/bin:$PATH mmake "$@" \n\
PATH=$PATH0' > /usr/local/bin/mmake-dev && chmod +x /usr/local/bin/mmake-dev

# Clean up.

RUN emerge --depclean 2>&1 | tee -a log
RUN emerge --unmerge gentoo-sources
RUN revdep-rebuild 2>&1 | tee -a log \
      && echo "[MSG] Docker image ready. Check build log."
RUN env-update
RUN rm -rf /var/cache/distfiles  /var/tmp/* /tmp/* /var/log/* /var/db/repos/gentoo/*
RUN rm -rf /usr/src/linux/*

