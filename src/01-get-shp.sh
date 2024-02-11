#!/bin/bash

################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download census tract shapefiles
# Author:   Patrick Lavallee Delgado
# Created:  14 December 2023
#
# Notes:
#
# To do:
#
################################################################################

# Identify inputs and outputs.
URL="https://www2.census.gov/geo/tiger/TIGER%d/TRACT/tl_%d_23_tract.zip"
DTA="$(pwd)/in"
RAW="$DTA/raw/shp"
OUT="$DTA/shapefile"

# Consider each year.
for year in 2019 2020
do

  # Set locations.
  url=$(printf $URL $year $year)
  out=$(basename $url)

  # Get data.
  curl -s --output-dir $RAW -O $url
  unzip $RAW/$out -d $OUT

done
