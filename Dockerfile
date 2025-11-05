FROM postgres:17-bookworm as wizrd-preprocessing
COPY . .
RUN apt-get update && apt-get install -y \
    cmake build-essential expat libexpat1-dev libboost-dev \
    libboost-program-options-dev libpqxx-dev curl osmctools
RUN ./get_map.sh
RUN test -f bicocca.osm || exit 1
RUN ./patch_osm2pgr.sh
RUN cd osm2pgrouting && \
    cmake -H. -Bbuild && \
    cd build && \
    make -j$(nproc) && \
    cd ../..
RUN cd overlay && \
    make && \
    cd ..
CMD ["/rebuild_db.sh"]
