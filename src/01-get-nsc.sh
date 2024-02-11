#!/bin/bash

################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download pdfs of National Student Clearinghouse data
# Author:   Patrick Lavallee Delgado
# Created:  5 December 2023
#
# Notes:    Link to Fort Fairfield 2019 pdf is wrong on the website.
#
# To do:
#
################################################################################

# Identify inputs and outputs.
URL="https://www.maine.gov/doe/data-reporting/reporting/warehouse/NSC-%d"
RAW="$(pwd)/in/raw/nsc"
PRG="$(pwd)/src/01-get-nsc.py"
OUT="$(pwd)/in/nsc.csv"

# Set year range, e.g. spring of school year.
ymin=2019
ymax=2021

# Consider each year.
for year in $(seq $ymin $ymax)
do

  # Set locations.
  if [[ $year = 2021 ]]
  then
    url=https://www.maine.gov/doe/node/3165
  else
    url=$(printf $URL $year)
  fi
  raw=$RAW/$year

  # Get pdfs listed on website.
  tmp=$(mktemp)
  curl -s $url \
  | grep "<a.*href=\".*\.pdf\"" \
  | sed -E "s/^.*(href=\")(.*\.pdf)(\").*$/\2/" \
  | sed -E "/^https?:\/\/www.maine.gov/! s/^/https:\/\/www.maine.gov/" \
  | sed -E "s/^http:/https:/" \
  > $tmp

  # Download pdfs.
  xargs -n 1 curl -s --output-dir $raw -O < $tmp

done

# Fix error on website where link to Fort Fairfield downloads pdf for Fort Kent.
raw=$(printf $RAW 2019)
fk=$raw/FortKent.pdf
mv $fk.1 $fk
ff=https://www.maine.gov/doe/sites/maine.gov.doe/files/bulk/data/nsc/2018/FortFairfield.pdf
curl -s --output $raw $ff

# Extract tables from pdfs.
find $RAW \
| grep "\.pdf$" \
| python $PRG \
> $OUT
