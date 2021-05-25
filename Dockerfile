ARG BASE_IMAGE=databricksruntime/dbfsfuse:latest

FROM $BASE_IMAGE as builder

ARG ECC_INSTALL_PREFIX=/usr/local
ARG CMAKE_VERSION=3.20.2
ARG ECCODES_VERSION=2.22.0

USER root
RUN apt-get update -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing --no-install-recommends \
            software-properties-common build-essential ca-certificates \
            git make wget unzip libtool automake wget openssl libssl-dev

RUN wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh
RUN mkdir /opt/cmake
RUN /bin/sh ./cmake-${CMAKE_VERSION}-linux-x86_64.sh --prefix=/opt/cmake --skip-license
RUN ln -s /opt/cmake/bin/cmake /usr/local/bin/cmake
RUN cmake --version

RUN wget https://confluence.ecmwf.int/download/attachments/45757960/eccodes-${ECCODES_VERSION}-Source.tar.gz && tar -xzf eccodes-${ECCODES_VERSION}-Source.tar.gz

RUN mkdir build
WORKDIR build
RUN cmake -DCMAKE_INSTALL_PREFIX=${ECC_INSTALL_PREFIX} -DENABLE_FORTRAN=OFF ../eccodes-${ECCODES_VERSION}-Source
RUN make
RUN make install
RUN ldconfig
WORKDIR /
ADD requirements.txt .
RUN /databricks/conda/envs/dcs-minimal/bin/pip install -r requirements.txt
RUN /databricks/conda/envs/dcs-minimal/bin/python -m cfgrib selfcheck
 
