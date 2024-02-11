################################################################################
#
# Project:  Mass layoffs
# Purpose:  Locate schools and mass layoff sites
# Author:   Patrick Lavallee Delgado
# Created:  18 December 2023
#
# Notes:
#
# To do:
#
################################################################################

# Import packages.
import os
import re
import requests
import pandas as pd
from geopy.distance import distance
import geopandas as gpd

# Identify inputs and outputs.
MAP = "https://nominatim.openstreetmap.org/search.php"
PWD = os.getcwd()
DTA = os.path.join(PWD, "in")
WRN = os.path.join(DTA, "warn.xlsx")
TMP = os.path.join(PWD, "tmp", "warn-loc.csv")
CCD = os.path.join(DTA, "ccd.csv")
SHP = os.path.join(DTA, "shapefile/tl_{:d}_23_tract.shp")
OUT = os.path.join(DTA, "loc.csv")

# Request coordinates for address.
def get_coord(q: str) -> pd.Series:
  pars = {"q": re.sub("\s", "+", q), "format": "json"}
  data = requests.get(MAP, params=pars).json()
  if data:
    return pd.Series([data[0]["lat"], data[0]["lon"]])
  return pd.Series([pd.NA, pd.NA])

# Load mass layoff sites.
wrn = pd.read_excel(WRN, dtype={"zip": str}).loc[lambda df: df["excl"].ne(1)]
assert wrn.set_index("id").index.is_unique

# Locate mass layoff sites.
wrn["loc"] = wrn[["address", "city", "state", "zip"]].apply(" ".join, axis=1)
wrn[["lat", "lon"]] = wrn["loc"].apply(get_coord)
wrn.to_csv(TMP, index=False)

# Load schools.
ccd = pd.read_csv(CCD).rename(columns={"latitude": "lat", "longitude": "lon"})
assert ccd.set_index(["year", "ncessch"]).index.is_unique

# Calculate distance between two points.
def get_dist(s: pd.Series) -> float:
  a = s["lat_ccd"], s["lon_ccd"]
  b = s["lat_wrn"], s["lon_wrn"]
  return distance(a, b).miles

# Calculate distance from each school to each site.
gdf = ccd.merge(wrn, how="cross", suffixes=("_ccd", "_wrn"))
assert gdf.shape[0] == (ccd.shape[0] * wrn.shape[0])
gdf["dist"] = gdf.apply(get_dist, axis=1)

# Load census tracts.
s19 = gpd.read_file(SHP.format(2019))
s20 = gpd.read_file(SHP.format(2020))
assert s19.crs == s20.crs

# Locate schools within census tracts.
gdf = gpd.GeoDataFrame(gdf, geometry=gpd.points_from_xy(gdf["lon_ccd"], gdf["lat_ccd"]), crs=s19.crs)
d19 = gdf.loc[lambda df: df["year"].le(2019)].sjoin(s19, how="left", predicate="within")
d20 = gdf.loc[lambda df: df["year"].ge(2020)].sjoin(s20, how="left", predicate="within")
gdf = pd.concat([d19, d20])

# Write to disk.
varlist = [
  "id",
  "lat_wrn",
  "lon_wrn",
  "ncessch",
  "year",
  "lat_ccd",
  "lon_ccd",
  "dist",
  "GEOID",
]
gdf[varlist].to_csv(OUT, index=False)
