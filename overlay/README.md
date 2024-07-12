# Overlay Tool

This tool is used in the pipeline to overlay an image over the map's bounding box. When invoking the overlay tool, the user needs to specify a grayscale PNG image, making sure it has only one component and no alpha channel, and the bounding box's coordinates expressed as the longitude and latitude of the South-Western corner and the longitude and latitude of the North-Eastern one. The user also specifies a maximum and minimum value for the output.

The tool reads tuples of the form `id,x1,y1,x2,y2` from standard input and outputs tuples of the form `id,value` to the standard output. The `value` is computed as the mean of the values read from pixels located under the coordinates of the starting point (`x1`,`y1`) and the ending point (`x2`, `y2`). If a point lies outside of the bounding box, the tool uses the other point's value. If both points lie outside of the bounding box, the tool assumes zero.

This value is then scaled according to the minimum and maximum values specified by the user before being output.

## Building

A Makefile is provided for convenience. Typing the following in this folder:

- `make` - builds the tool normally;
- `make DEBUG=1` - builds the tool with assertions and tracing enabled;
- `make clean` - removes all build files.

## Caveats

The tool works but input validation is not robust. You should only use this tool in well-formed scripts and perform input validation prior to invoking it.