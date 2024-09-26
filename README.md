This repository contains the preprocessing pipeline used to convert an OpenStreetMap dump into a PostgreSQL table containing geometry data properly formatted for running the MUSA navigation webapp.

## Folder Structure

The root of the project contains a number of files which are directly responsible for the various phases of the set-up.

### Folders

- `functions/` - Contains functions used in the database.
- `osm2pgrouting/` - Git submodule containing the source code for osm2pgrouting. Remember to clone with `git clone --recurse-submodules` or pull with `git pull --recurse-submodules` at least once (hint: `-f` can be used when pulling if the submodule somehow breaks).
- `overlay/` - Contains the sources for and other files related to the overlay tool used to simulate traffic and air pollution data.
- `patch/` - Contains patches for osm2pgrouting that enable exporting custom columns.

### Scripts

- `dump_functions.sh` - Creates a file for each custom function present in the database; it can be useful if you modifified a function and want to update its definition.
- `get_map.sh` - Downloads an OSM dump of the area inside the bounding box; must be called at least once before `rebuild_db.sh` to download the geometry from OSM.
- `globals.sh` - Contains all shared variables, including IP addresses, bounding box limits, file names, etc. **This script is not executable.**
- `patch_osm2pgr.sh` - Computes a patch by comparing the sources downloaded from the git submodule containing osm2pgrouting and the patched sources provided in the `patch/` folder; run at least once or you won't have the proper columns in the table when you recreate the DB.
- `rebuild_db.sh` - The actual preprocessing pipeline.

### Other files

- `mapconfig.xml` - This file is used by osm2pgrouting to extract features from the OSM dump and label them appropriately. The pipeline then uses the tags for a number of purposes, mainly determining green areas. Modify this only if you know what you're doing.

## Workflow

### Automated Process (Docker)

> If you're using Podman, either `/s/docker/podman/` or `alias docker=podman`

To rebuild the container image you should do the following:

```console
$ rm -rf osm2pgrouting/
$ mkdir -p osm2pgrouting 
$ git pull --recurse-submodules 
$ docker build -t mapserver-rebuilder .
```

...which can be condensed into the following one-liner:

`rm -rf osm2pgrouting/; mkdir -p osm2pgrouting; git pull --recurse-submodules; docker build -t mapserver-rebuilder .`

The image only needs to be rebuilt if you change an overlay image or the bounding box, or when you change the variables in `globals.sh` (or any other script for that matter). Once you've rebuilt the image, you can run the container as follows:

`docker run --name=mapserver-rebuilder --network=musa-network mapserver-rebuilder`

This will have the same effect as running `./rebuild_db.sh`, but will not require you to forward the DB's port to the host.

### Manual Process

> ***CAVEAT***\
> You most likely need to change some of the variables defined in `globals.sh` (the database's IP address at the very least).

1. Clone this repository locally with `git clone --recurse-submodules` and make sure that the `osm2pgrouting/` folder is populated.
2. Patch osm2pgrouting by running `./patch_osm2pgr.sh` then build it. Refer to the osm2pgrouting README file for dependencies etc. You can build osm2pgr as follows:
   ```shell
   pushd osm2pgrouting
   cmake -H. -Bbuild
   cd build
   make -j$(nproc)
   popd
   ```
3. Build the overlay tool as follows:
   ```shell
   pushd overlay
   make
   popd
   ```
4. Download the OSM dump by running `./get_map.sh`. You should now have a `bicocca.osm` file in the repo's root folder, unless you changed its name in `globals.sh`.
5. Run `./rebuild_db.sh`.

Steps 1-4 only need to be executed the first time you clone the repo: from then on, if you only want to rebuild the database you can run `./rebuild_db.sh` directly.

### Modifying the Database

#### Bounding box

The bounding box is currently defined as the smaller rectangular area that contains the polygon that roughly covers metro stations Bignami M5 and Bicocca M5 (west), the Vivaio Bicocca (south-east), via Breda on the other side of the railway (east) and the U14 and U24 buildings (north-east).

![bicocca](https://github.com/user-attachments/assets/cb76c5ae-a200-4a53-a0b3-e57185168d11)

The bounding box is expressed as the coordinates of its southwestern and northeastern corners, which are specified in the `BB_[SW,NE]_[LAT,LON]` variables in `globals.sh`.

#### Functions and Procedures

In PostgreSQL, functions and procedures are user-defined routines that can be executed in the database and can be used for extending and customizing a query or automating some steps. 

- Functions can be called from within SQL queries, they can accept parameters and return a value;
- Procedures are similar to functions but they don't return anything and are used to execute a series of SQL statements.

In the MUSA micromobility application, functions are used to compute the cost of a route.

Function definitions can be downloaded automatically from the database with the `dump_functions.sh` script. If you defined a new function you want to include in the dump, you need to add its name to the `FUNCTION_NAMES` array in the script.

##### `calculate_cost_advanced_new.sql` - Function

Computes the cost of a route given some parameters; this function is the core of the application and can be modified to influence how routing decisions are taken.

<!-- TODO Some more info? -->

##### `calculate_heuristic_estimate.sql` - Function

> This is currently unused

Used by A* routing to provide an estimate cost for route optimization.

<!-- TODO Some more info? -->

##### `make_green_areas.sql` - Procedure

Used by the pipeline to create polygons enclosing green areas, then calculating which routes intercept said polygons and marking them as `green:=true`. The areas are identified using the `tag_id` that osm2pgrouting gave them according to `mapconfig.xml`. Currently, Green Areas are tagged with an ID number lower than `3000`.

#### Overlays

To simulate traffic and pollution data, a tool that can use images as density maps to express the value of a certain (user-defined) attribute is provided.

To use the tool, the user needs to specify:
- A single-channel (monochrome, no alpha channel) PNG image which is laid over the bounding box and used to determine the density of a certain attribute in a specific set of coordinates.
- The coordinates of the bounding box
- The lower and upper limits of the output value. e.g. the European Air Quality Index ranges from 0 (best) to 500 (worst).

The tool then reads lines of the form `id,x1,y1,x2,y2` from the standard input. This mechanism can be used to pipe in via redirection a CSV file containing rows expressing a stretch of road as follows: _Unique ID,Start Longitude,Start Latitude,End Longitude,End Latitude_.

For each input line, the tool prints on the standard output lines of the form `id,value` that can be used to construct a CSV file that expresses the value of a certain attribute for each stretch of road.

For more information refer to [`overlay/README.md`](https://raw.githubusercontent.com/iralabdisco/MUSA-preprocessing/main/overlay/README.md).

If you want to add or change an overlay in the processing pipeline, you need to modify step 6 and its variables. The code currently creates CSV files for each overlay, merges them, then uploads them to a new table in the database. The table is then joined with `ways` on `id` and the source tables are dropped. This process will likely change in the future when more data points are present.

##### Examples

You can call the overlay tool as follows: `overlay/./overlay overlay/blob.png 9.202734 45.506527 9.223731 45.527366 0 499 < ways.csv > pollution.csv`

The following picture shows an image file that can be used as an overlay. The image was created with GIMP by drawing over a screenshot of the bounding box (see the files in `overlay/map/`). The black areas express the lowest percentages, while the white areas the highest. The image has been flattened, downsampled, converted to grayscale (1 channel), the alpha channel was removed, and it was exported as PNG.

![blob](https://github.com/user-attachments/assets/ebbef933-6077-4411-aa81-7ff3db51446d)
