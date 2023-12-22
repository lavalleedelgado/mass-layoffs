################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download data from Urban Institute's Education Data Explorer
# Author:   Patrick Lavallee Delgado
# Created:  16 December 2023
#
# Notes:
#
# To do:
#
################################################################################

# Impact packages.
import argparse
import sys
import requests
import pandas as pd

# Set API endpoint.
URBAN_API = "https://educationdata.urban.org/api/v1/schools"
PAYLOAD = {"fips": "23"}

# Map categorical levels to variable names.
REPLACE = {
   "sex"  : {
      1:  "sex_male",
      2:  "sex_female",
      9:  "sex_unkn",
      99: "sex_total",
   },
   "race" : {
      1:  "race_white",
      2:  "race_black",
      3:  "race_hisp",
      4:  "race_asian",
      5:  "race_aian",
      6:  "race_nhpi",
      7:  "race_twomore",
      8:  "race_nra",
      9:  "race_unkn",
      20: "race_other",
      99: "race_total",
   }
}


# Request data.
def make_request(url: str) -> pd.DataFrame:
  resp = requests.get(url, params=PAYLOAD).json()
  data = resp["results"]
  while resp["next"]:
      resp = requests.get(resp["next"]).json()
      data.extend(resp["results"])
  return pd.DataFrame(data)


# Download CCD directory and enrollment data.
def get_ccd(year: int) -> pd.DataFrame:

  # Get directory data.
  url = URBAN_API + f"/ccd/directory/{year}"
  ccd = make_request(url)

  # Get enrollment data by gender.
  url = URBAN_API + f"/ccd/enrollment/{year}/grade-12/sex"
  sex = (
    make_request(url)
    .replace(REPLACE)
    .pivot(index="ncessch", columns="sex", values="enrollment")
    .reset_index()
  )

  # Get enrollment data by race.
  url = URBAN_API + f"/ccd/enrollment/{year}/grade-12/race"
  race = (
    make_request(url)
    .replace(REPLACE)
    .pivot(index="ncessch", columns="race", values="enrollment")
    .reset_index()
  )

  # Merge and return the data.
  return (
    ccd
    .merge(sex, how="left", on="ncessch", validate="1:1")
    .merge(race, how="left", on="ncessch", validate="1:1")
  )


# Download EDFacts assessments data.
def get_edfacts(year: int) -> pd.DataFrame:
  url = URBAN_API + f"/edfacts/assessments/{year}/grade-9"
  return make_request(url)


# Hash requests.
get = {"ccd": get_ccd, "edfacts": get_edfacts}


# Run.
if __name__ == "__main__":

  # Parse arguments.
  parser = argparse.ArgumentParser()
  parser.add_argument("data", type=str, choices=list(get))
  parser.add_argument("ymin", type=int)
  parser.add_argument("ymax", type=int)
  parser.add_argument("out", nargs="?", type=argparse.FileType("w"), default=sys.stdout)
  args = parser.parse_args()

  # Handle pandemic year in EDFacts data.
  years = list(range(args.ymin, args.ymax + 1))
  if args.data == "edfacts":
    years.remove(2019)

  # Request and write data.
  (
    pd
    .concat(get[args.data](year) for year in years)
    .to_csv(args.out, index=False)
  )
