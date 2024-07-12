/**
 * @file overlay.c
 * @author Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
 * @brief Overlays a 1-component PNG image over a bounding box.
 * @date 2024-07-12
 *
 * @copyright Copyright (c) 2024 Jacopo Maltagliati
 *
 * This file is part of the MUSA micromobility project.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <assert.h>
#include <errno.h>
#include <malloc.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#ifndef DEBUG
#define DEBUG 0
#endif

// https://stackoverflow.com/a/1644898
#define TRACE(fmt, ...)                               \
    do {                                              \
        if (DEBUG) fprintf(stderr, fmt, __VA_ARGS__); \
    } while (0)

typedef unsigned char uchar;

typedef struct overlay {
    int rows, cols, comps;
    uchar* data;
} overlay_t;

typedef struct coords {
    float lat, lon;
} coords_t;

typedef struct bbox {
    coords_t sw, ne;
} bbox_t;

typedef struct vec2 {
    double x, y;
} vec2_t;

typedef struct ivec2 {
    int x, y;
} ivec2_t;

void panic(const char* msg) {
    if (errno) {
        fprintf(stderr, "PANIC: %s: %s\n", msg, strerror(errno));
    } else {
        fprintf(stderr, "PANIC: %s\n", msg);
    }
    exit(EXIT_FAILURE);
}

void load_overlay(const char* const path, overlay_t* const image) {
    // Get size and number of components from image
    if (!stbi_info(path, &(image->rows), &(image->cols), &(image->comps)))
        panic("cannot stat image");
    TRACE("rows: %d, cols: %d\ncomps: %d\n", image->rows, image->cols,
          image->comps);
    if (image->comps != 1) panic("too many components");

    // Load image
    image->data =
        stbi_load(path, &(image->cols), &(image->rows), NULL, image->comps);
    if (image->data == NULL) panic("cannot load image");
}

uchar map(overlay_t image, bbox_t bbox, vec2_t scaling, coords_t point) {
    /* The map is laid down as shown below. In order to get the location of a
       pixel we subtract the BBox's southwestern point's coordinates from the
       point's. Then, we scale the coordinates using the scaling factor we
       calculated previously to obtain an x,y index that references one pixel.
       Caveat: since the geospatial reference zero is in the bottom left corner,
               while the image's zero is in the top left corner we obtain the
               inverse of the desired coordinate on the y axis! Thus the y we
               want is rows-calculated_y.

    0,0                       NE     image-->
        +---+---+---+---+---+          |
        |   |   |   |   |   |          |
        |   |   |   |   |   |         \/
        +---+---+---+---+---+
        |   |   |   |   |   |
        |   |   |   |   |   |
        +---+---+---+---+---+
        |   |   |   |   |   |
        |   |   |   |   |   |
        +---+---+---+---+---+
        |   |   |   |   |   |
        |   |   |   |   |   |
        +---+---+---+---+---+         /\
        |   |   |   |   |   |          |
        |   |   |   |   |   |          |
        +---+---+---+---+---+       geospatial -->
    SW

    */
    int row, col;
    row = image.rows - (int)round((point.lat - bbox.sw.lat) / scaling.y);
    col = (int)round((point.lon - bbox.sw.lon) / scaling.x);
#ifdef DEBUG
    coords_t pz;
    pz.lat = point.lat - bbox.sw.lat;
    pz.lon = point.lon - bbox.sw.lon;
    TRACE("zero ref: %2.4f->%2.4f,%2.4f->%2.4f\n", point.lat, pz.lat, point.lon,
          pz.lon);
    TRACE("get: row: %d, col: %d\n", row, col);
    assert(row >= 0);
    assert(col >= 0);
#endif
    int offset = (row * image.cols) + col;
    return image.data[offset];
}

bool is_inside(bbox_t bbox, coords_t point) {
    return (point.lat >= bbox.sw.lat && point.lat <= bbox.ne.lat &&
            point.lon >= bbox.sw.lon && point.lon <= bbox.ne.lon);
}

overlay_t image;

void free_overlay() { stbi_image_free(image.data); }

int main(int argc, char* argv[]) {
    bbox_t bbox;
    vec2_t scaling;  ///< Scaling factors in degrees per pixel; x->lon, y->lat
    int limit_low, limit_high;
    int id;
    coords_t start, end;
    char* line = NULL;
    size_t len = 0;
    ssize_t nread;
    int stats_rows = 0, stats_missing = 0;

    if (argc < 8) {
        panic(
            "usage: overlay <image file> <sw corner lon> <sw corner lat> <ne "
            "corner lon> <ne corner lat> <lowest value> <highest value>");
    }

    // load overlay image
    load_overlay(argv[1], &image);
    atexit(free_overlay);

    // get bounding box coordinates
    bbox.sw.lon = atof(argv[2]);
    bbox.sw.lat = atof(argv[3]);
    bbox.ne.lon = atof(argv[4]);
    bbox.ne.lat = atof(argv[5]);
    TRACE("bbox:\n  sw: %2.4f,%2.4f\n  ne: %2.4f,%2.4f\n", bbox.sw.lon,
          bbox.sw.lat, bbox.ne.lon, bbox.ne.lat);

    // get limits for output value
    limit_low = atoi(argv[6]);
    limit_high = atoi(argv[7]);
    TRACE("limits:\n low: %d, high: %d\n", limit_low, limit_high);

    // compute scaling factor in deg/row and deg/col
    scaling.x = (bbox.ne.lon - bbox.sw.lon) / (double)image.cols;
    scaling.y = (bbox.ne.lat - bbox.sw.lat) / (double)image.rows;
    TRACE("scaling:\n deg/row: %1.4f, deg/col: %1.4f\n", scaling.y, scaling.x);

    // iterate on stdin (csv)
    // assume we're operating on ways (id,start,end)
    while ((nread = getline(&line, &len, stdin)) != -1) {
        // use canary so integer division by 2 won't risk rounding to zero
        int start_gray = -42, end_gray = -42, mean_gray;

        // input format: id,x1,y1,x2,y2
        sscanf(line, "%d,%f,%f,%f,%f", &id, &(start.lon), &(start.lat),
               &(end.lon), &(end.lat));

        // get grayscale value at starting point
        if (!is_inside(bbox, start)) {
            TRACE("clipping starting point: %2.4f,%2.4f\n", start.lat,
                  start.lon);
            stats_missing++;
        } else {
            start_gray = map(image, bbox, scaling, start);
        }

        // get grayscale value at ending point
        if (!is_inside(bbox, end)) {
            TRACE("clipping ending point: %2.4f,%2.4f\n", end.lat, end.lon);
            stats_missing++;
        } else {
            end_gray = map(image, bbox, scaling, end);
        }

        // check for missing values
        if (start_gray < 0) start_gray = end_gray;
        if (end_gray < 0) end_gray = start_gray;

        mean_gray = (start_gray + end_gray) / 2;
        TRACE("gray: start: %d end: %d mean: %d\ngray%%: %f\n", start_gray,
              end_gray, mean_gray, mean_gray / 255.f);

        // if we're still below zero, it means that both points were outside of
        // the bbox, so we can only clip the value to zero
        if (mean_gray < 0) mean_gray = 0;

        // output format: id,value
        printf("%d,%d\n", id,
               limit_low +
                   (int)round((limit_high - limit_low) * mean_gray / 255.f));
        stats_rows++;
    }
    fprintf(stderr, "Processed %d ways; %d (%.2f%%) data points missing\n",
            stats_rows, stats_missing,
            stats_missing * 100 / (double)stats_rows);
    exit(EXIT_SUCCESS);
}
