ARG BASE_IMAGE=databricksruntime/dbfsfuse:latest

FROM $BASE_IMAGE as builder


USER root
RUN apt-get update -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing --no-install-recommends \
        software-properties-common build-essential ca-certificates \
        zip curl git make wget unzip libtool automake wget autoconf sqlite3 bash-completion \
	openssl libssl-dev python-dev libjpeg-dev libgeos-dev libexpat-dev libxerces-c-dev \
        libwebp-dev libzstd-dev libpq-dev libopenjp2-7-dev libproj-dev
	    

# Build cmake
ARG CMAKE_VERSION=3.20.2
RUN wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh \
	&& mkdir /opt/cmake \
	&& /bin/sh ./cmake-${CMAKE_VERSION}-linux-x86_64.sh --prefix=/opt/cmake --skip-license \
	&& ln -s /opt/cmake/bin/cmake /usr/local/bin/cmake \
	&& cmake --version

# Build openjpeg
ARG OPENJPEG_VERSION=
RUN if test "${OPENJPEG_VERSION}" != ""; then ( \
    wget -q https://github.com/uclouvain/openjpeg/archive/v${OPENJPEG_VERSION}.tar.gz \
    && tar xzf v${OPENJPEG_VERSION}.tar.gz \
    && rm -f v${OPENJPEG_VERSION}.tar.gz \
    && cd openjpeg-${OPENJPEG_VERSION} \
    && cmake . -DBUILD_SHARED_LIBS=ON  -DBUILD_STATIC_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
    && make -j$(nproc) \
    && make install \
    && mkdir -p /build_thirdparty/usr/lib \
    && cp -P /usr/lib/libopenjp2*.so* /build_thirdparty/usr/lib \
    && for i in /build_thirdparty/usr/lib/*; do strip -s $i 2>/dev/null || /bin/true; done \
    && cd .. \
    && rm -rf openjpeg-${OPENJPEG_VERSION} \
    ); fi

# Build PROJ
ARG PROJ_VERSION=5.1.0
ARG PROJ_INSTALL_PREFIX=/usr/local
RUN \
    mkdir -p /build_projgrids/${PROJ_INSTALL_PREFIX}/share/proj \
    && curl -LOs http://download.osgeo.org/proj/proj-datumgrid-latest.zip \
    && unzip -q -j -u -o proj-datumgrid-latest.zip  -d /build_projgrids/${PROJ_INSTALL_PREFIX}/share/proj \
    && rm -f *.zip

RUN mkdir proj \
    && wget -q https://github.com/OSGeo/PROJ/archive/${PROJ_VERSION}.tar.gz -O - \
        | tar xz -C proj --strip-components=1 \
    && cd proj \
    && ./autogen.sh \
    && CFLAGS='-DPROJ_RENAME_SYMBOLS -O2' CXXFLAGS='-DPROJ_RENAME_SYMBOLS -DPROJ_INTERNAL_CPP_NAMESPACE -O2' \
        ./configure --prefix=${PROJ_INSTALL_PREFIX} --disable-static \
    && make -j$(nproc) \
    && make install DESTDIR="/build" \
    && cd .. \
    && rm -rf proj \
    && PROJ_SO=$(readlink /build${PROJ_INSTALL_PREFIX}/lib/libproj.so | sed "s/libproj\.so\.//") \
    && PROJ_SO_FIRST=$(echo $PROJ_SO | awk 'BEGIN {FS="."} {print $1}') \
    && mv /build${PROJ_INSTALL_PREFIX}/lib/libproj.so.${PROJ_SO} /build${PROJ_INSTALL_PREFIX}/lib/libinternalproj.so.${PROJ_SO} \
    && ln -s libinternalproj.so.${PROJ_SO} /build${PROJ_INSTALL_PREFIX}/lib/libinternalproj.so.${PROJ_SO_FIRST} \
    && ln -s libinternalproj.so.${PROJ_SO} /build${PROJ_INSTALL_PREFIX}/lib/libinternalproj.so \
    && rm /build${PROJ_INSTALL_PREFIX}/lib/libproj.*  \
    && ln -s libinternalproj.so.${PROJ_SO} /build${PROJ_INSTALL_PREFIX}/lib/libproj.so.${PROJ_SO_FIRST} \
    && strip -s /build${PROJ_INSTALL_PREFIX}/lib/libinternalproj.so.${PROJ_SO} \
    && for i in /build${PROJ_INSTALL_PREFIX}/bin/*; do strip -s $i 2>/dev/null || /bin/true; done

# Build GDAL
ARG GDAL_VERSION=2.4.4
ARG GDAL_REPOSITORY=OSGeo/gdal
RUN mkdir gdal \
    && wget -q https://github.com/${GDAL_REPOSITORY}/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz -O - \
        | tar xz -C gdal --strip-components=1 \
    && cd gdal \
    && LDFLAGS="-L/build${PROJ_INSTALL_PREFIX}/lib -linternalproj" ./configure --prefix=/usr --without-libtool \
    --with-hide-internal-symbols \
    --with-jpeg12 \
    --with-python \
    --with-webp --with-proj=/build${PROJ_INSTALL_PREFIX} \
    --with-libtiff=internal --with-rename-internal-libtiff-symbols \
    --with-geotiff=internal --with-rename-internal-libgeotiff-symbols \
    && make -j$(nproc) \
    && make install DESTDIR="/build" \
    && cd ../.. \
    && rm -rf gdal \
    && mkdir -p /build_gdal_python/usr/lib \
    && mkdir -p /build_gdal_python/usr/bin \
    && mkdir -p /build_gdal_version_changing/usr/include \
    && mv /build/usr/lib/python*            /build_gdal_python/usr/lib \
    && mv /build/usr/lib                    /build_gdal_version_changing/usr \
    && mv /build/usr/include/gdal_version.h /build_gdal_version_changing/usr/include \
    && mv /build/usr/bin/*.py               /build_gdal_python/usr/bin \
    && mv /build/usr/bin                    /build_gdal_version_changing/usr \
    && for i in /build_gdal_version_changing/usr/lib/*; do strip -s $i 2>/dev/null || /bin/true; done \
    && for i in /build_gdal_python/usr/lib/python3/dist-packages/osgeo/*.so; do strip -s $i 2>/dev/null || /bin/true; done \
    && for i in /build_gdal_version_changing/usr/bin/*; do strip -s $i 2>/dev/null || /bin/true; done

# Build ecCodes
ARG ECC_INSTALL_PREFIX=/usr/local
ARG ECCODES_VERSION=2.22.0
RUN mkdir -p eccodes/src \
	&& wget -q https://confluence.ecmwf.int/download/attachments/45757960/eccodes-${ECCODES_VERSION}-Source.tar.gz -O - \
	| tar -xz -C eccodes/src --strip-components=1 \
	&& mkdir -p eccodes/build \
	&& cd eccodes/build \
	&& cmake -DCMAKE_INSTALL_PREFIX=${ECC_INSTALL_PREFIX} -DENABLE_FORTRAN=OFF /eccodes/src \
	&& make \
	&& make install \
	&& ldconfig

# Build Magics
ARG MAGICS_INSTALL_PREFIX=/usr/local
ARG MAGICS_VERSION=4.2.3
RUN mkdir -p magics/src \
	&& wget https://confluence.ecmwf.int/download/attachments/3473464/Magics-${MAGICS_VERSION}-Source.tar.gz?api=v2 -O - \
        | tar xz -C /magics/src --strip-components=1
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing --no-install-recommends libboost-all-dev libnetcdf-c++4 libnetcdf-cxx-legacy-dev
RUN /databricks/conda/envs/dcs-minimal/bin/pip install jinja2 netcdf4

RUN mkdir -p /magics/build \
	&& cd /magics/build \
	&& cmake -DCMAKE_INSTALL_PREFIX=${MAGICS_INSTALL_PREFIX} -DENABLE_FORTRAN=OFF -DENABLE_CAIRO=OFF \
		-DPYTHON_EXECUTABLE=/databricks/conda/envs/dcs-minimal/bin/python /magics/src \ 
	&& make \
	&& make install \
	&& ldconfig

WORKDIR /
ADD requirements.txt .
RUN /databricks/conda/envs/dcs-minimal/bin/pip install -r requirements.txt
RUN /databricks/conda/envs/dcs-minimal/bin/python -m cfgrib selfcheck
RUN /databricks/conda/envs/dcs-minimal/bin/python -m Magics selfcheck 
