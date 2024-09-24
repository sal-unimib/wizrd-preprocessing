FROM debian:12
WORKDIR build
COPY . .
RUN apt-get update && apt-get install -y \
    cmake build-essentials expat libexpat1-dev libboost-dev \
    libboost-program-options-dev libpqxx-dev
RUN pushd osm2pgrouting &&
    cmake -H. -Bbuild &&
    cd build &&
    make -j$(nproc) &&
    popd
RUN pushd overlay &&
    make &&
    popd
RUN ./rebuild_db.sh
