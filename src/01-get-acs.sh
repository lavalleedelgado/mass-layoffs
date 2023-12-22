#!/bin/bash

################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download ACS data and census tract shapefile
# Author:   Patrick Lavallee Delgado
# Created:  14 December 2023
#
# Notes:
#
# To do:
#
################################################################################

# Identify inputs and outputs.
URL="https://api.census.gov/data/%d/acs/acs5/profile?get=%s&for=tract:*&in=state:23&in=county:*"
SHP="https://www2.census.gov/geo/tiger/TIGER2019/TRACT/tl_2019_23_tract.zip"
DTA="$(pwd)/in"
RAW="$DTA/raw/acs"
VAR="$RAW/varlist.csv"
TMP="$RAW/acs-%d.csv"
OUT="$DTA/acs.csv"

# Set year range, e.g. calendar year.
ymin=2010
ymax=2020

# Initialize destination file.
f=$(
  cat $VAR \
  | head -n 1 \
  | tr "," "\n" \
  | grep -nE "varname" \
  | cut -f 1 -d ":"
)
col=$(
  cat $VAR \
  | cut -f $f -d "," \
  | tail -n +2 \
  | tr "\n" "," \
  | sed "s/,$//"
)
echo "year,$col,state,county,tract" > $OUT

# Consider each year.
for year in {$ymin..$ymax}
do

  # Get variable list.
  y=$(($year % 100))
  f=$(
    cat $VAR \
    | head -n 1 \
    | tr "," "\n" \
    | grep -nE "elname" \
    | sed "s/elname//" \
    | awk -v y=$y 'BEGIN { FS = ":" } int($2) <= int(y) { print $1 }' \
    | sort \
    | tail -n 1
  )

  var=$(
    cat $VAR \
    | cut -f $f -d "," \
    | tail -n +2 \
    | tr "\n" "," \
    | sed "s/,$//"
  )

  # Set locations.
  url=$(printf $URL $year $var)
  tmp=$(printf $TMP $year)

  # Get data.
  wget -q -O- $url \
  | sed -E "s/^\[{1,2}//" \
  | sed -E "s/\]{1,2},?$//" \
  | cat - <(echo) \
  > $tmp

  # Stack with final file.
  cat $tmp \
  | tail -n +2 \
  | sed "s/^/$year,/" \
  >> $OUT

done

# Download census tract shapefile.
shp=$(basename $SHP)
wget -P $RAW $SHP
unzip $RAW/$shp -d $DTA/shapefile
