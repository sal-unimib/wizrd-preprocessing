#include <assert.h>
#include <errno.h>
#include <malloc.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

/*
 * pollution tool
 * build with -lm; -DDEBUG enables tracing; -DINTERACIVE enables prompt mode
 */

// gcc main.c -o poltool -lm
// cd ..
// tool/./poltool pollution.png 9.202734 45.506527 9.223731 45.527366 <
// coords.csv > pollution.csv

// https://stackoverflow.com/a/1644898
#ifndef DEBUG
#define DEBUG 0
#endif

#define TRACE(fmt, ...)                                                        \
  do {                                                                         \
    if (DEBUG)                                                                 \
      fprintf(stderr, fmt, __VA_ARGS__);                                       \
  } while (0)

struct geom {
  int rows, cols;
};

struct coord {
  float lat, lng;
};

typedef struct geom geom_t;
typedef struct coord coord_t;

typedef unsigned char uchar;

void panic(const char *msg) {
  if (errno) {
    fprintf(stderr, "PANIC: %s: %s\n", msg, strerror(errno));
  } else {
    fprintf(stderr, "PANIC: %s\n", msg);
  }
  exit(EXIT_FAILURE);
}

uchar *load(const char *const path, geom_t *geom) {
  int ok, comp;
  ok = stbi_info(path, &(geom->rows), &(geom->cols), &comp);
  if (!ok)
    panic("cannot stat image");
  TRACE("rows: %d, cols: %d\ncomps: %d\n", geom->rows, geom->cols, comp);
  if (comp != 1)
    panic("too many components");
  uchar *buf = stbi_load(path, &(geom->cols), &(geom->rows), NULL, comp);
  if (buf == NULL)
    panic("cannot load image");
  return buf;
}

uchar map(uchar *poldata, geom_t geom, coord_t bl, double lat_inc,
          double lng_inc, coord_t req) {
#ifdef DEBUG
  coord_t reqz;
  reqz.lat = req.lat - bl.lat;
  reqz.lng = req.lng - bl.lng;
  TRACE("reqz: %2.4f,%2.4f\n", reqz.lat, reqz.lng);
#endif
  int col = (int)round((req.lng - bl.lng) / lng_inc);
  int row = geom.rows - (int)round((req.lat - bl.lat) / lat_inc);
  TRACE("get: row: %d, col: %d\n", row, col);
  int offset = (row * geom.cols) + col;
  return poldata[offset];
}

int main(int argc, char *argv[]) {
  if (argc < 6) {
    puts("usage: poltool <image_name> <bottom_lng> <left_lat> <top_lng> "
         "<right_lat>");
    panic("not enough arguments");
  }

  geom_t geom;
  coord_t bl, tr;
  uchar *poldata = load(argv[1], &geom);
  bl.lat = atof(argv[3]);
  bl.lng = atof(argv[2]);
  tr.lat = atof(argv[5]);
  tr.lng = atof(argv[4]);
  TRACE("bbox:\n  bl: %2.4f,%2.4f\n  tr: %2.4f,%2.4f\n", bl.lng, bl.lat, tr.lng,
        tr.lat);

  double lat_inc = (tr.lat - bl.lat) / (double)geom.rows;
  double lng_inc = (tr.lng - bl.lng) / (double)geom.cols;
  TRACE("lat_inc: %1.4f, lng_inc: %1.4f\n", lat_inc, lng_inc);

#ifdef INTERACTIVE
  coord_t req;
  uchar pol;
  for (;;) {
    printf("lat? ");
    fflush(stdin);
    scanf("%f", &(req.lat));
    printf("lng? ");
    fflush(stdin);
    scanf("%f", &(req.lng));
    if (req.lat < bl.lat || req.lat > tr.lat) {
      fprintf(stderr, "lat out of range\n");
      continue;
    }
    if (req.lng < bl.lng || req.lng > tr.lng) {
      fprintf(stderr, "lng out of range\n");
      continue;
    }
    pol = get_pollution_data(poldata, geom, bl, tr, lat_inc, lng_inc, req);
    printf("pol: %2X\n", pol);
  }
#else
  int id;
  coord_t start, end;
  char *line = NULL;
  size_t len = 0;
  ssize_t nread;
  uchar pol_start, pol_end;
  int valid_nodes, stats_processed = 0, stats_missing = 0;
  while ((nread = getline(&line, &len, stdin)) != -1) {
    valid_nodes = 0;
    // input: id,x1,y1,x2,y2
    sscanf(line, "%d,%f,%f,%f,%f", &id, &(start.lng), &(start.lat), &(end.lng),
           &(end.lat));
    if (start.lat < bl.lat || start.lat > tr.lat || start.lng < bl.lng ||
        start.lng > tr.lng) {
      TRACE("clipping start node %2.4f,%2.4f\n", start.lat, start.lng);
      pol_start = 0;
    } else {
      pol_start = map(poldata, geom, bl, lat_inc, lng_inc, start);
      valid_nodes += 1;
    }

    if (end.lat < bl.lat || end.lat > tr.lat || end.lng < bl.lng ||
        end.lng > tr.lng) {
      TRACE("clipping end node %2.4f,%2.4f\n", end.lat, end.lng);
      pol_end = 0;
    } else {
      pol_end = map(poldata, geom, bl, lat_inc, lng_inc, start);
      valid_nodes += 1;
    }
    if (valid_nodes <= 0) {
      stats_missing++;
      TRACE("%s\n", "neither node is valid. assuming zero");
      printf("%d,%2.4f\n", id, .0f);
    } else
      printf("%d,%2.4f\n", id,
             (pol_start + pol_end) / (double)(valid_nodes * 255));
    stats_processed++;
  }
#endif
  fprintf(stderr, "Processed %d ways; %d (%.2f%%) data points missing\n",
          stats_processed, stats_missing,
          stats_missing * 100 / (double)stats_processed);
  stbi_image_free(poldata);
  exit(EXIT_SUCCESS);
}
