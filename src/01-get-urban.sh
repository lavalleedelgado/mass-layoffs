#!/bin/bash

################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download CCD data
# Author:   Patrick Lavallee Delgado
# Created:  16 December 2023
#
# Notes:    Collected from Urban Institute's Education Data Explorer.
#
# To do:
#
################################################################################

# Identify inputs and outputs.
PRG="$(pwd)/src/01-get-urban.py"
OUT="$(pwd)/in/%s.csv"

# Set year range, e.g. fall of school year.
ymin=2010
ymax=2020

# Get data.
for data in ccd edfacts
do
  out=$(printf $OUT $data)
  python $PRG $data $ymin $ymax > $out
done
