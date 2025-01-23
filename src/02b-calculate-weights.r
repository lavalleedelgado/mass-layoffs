################################################################################
#
# Project:  Mass layoffs
# Purpose:  Calculate workforce and distance weights
# Author:   Patrick Lavallee Delgado
# Created:  16 November 2024
#
# Notes:
#
# To do:
#
################################################################################

# Import packages.
library(dplyr)
library(tidyr)
library(sf)

# Identify inputs and outputs.
PWD <- getwd()
DTA <- file.path(PWD, "in")
SHP <- file.path(DTA, "shapefile", "tl_%4.0f_23_tract.shp")
ACS <- file.path(DTA, "acs.csv")
CCD <- file.path(DTA, "ccd.csv")
OUT <- file.path(DTA, "wgt.csv")

# Write a function to check uniqueness of identifiers.
isid <- function(.data, ...) {
  if(any(duplicated(dplyr::select(.data, ...)))) {
    stop("indexers do not uniquely identify the observations")
  }
  return(.data)
}

# Load tracts in Maine by census year.
shp <- list()
for (year in c(2019, 2020)) {
  lab <- sprintf("%4.0f", year)
  shp[[lab]] <- st_read(sprintf(SHP, year)) |>
    rename_with(~ tolower(.x)) |>
    isid(geoid)
}

# Load tract characteristics.
acs <- read.csv(ACS) |>
  mutate(
    cyear = if_else(year <= 2019, "2019", "2020"),
    geoid = sprintf("%02.0f%03.0f%06.0f", state, county, tract)
  ) |>
  isid(geoid, year)

# Load schools.
ccd <- read.csv(CCD) |>
  rename(lon = longitude, lat = latitude) |>
  st_as_sf(coords = c("lon", "lat"), crs = st_crs(shp[["2019"]])) |>
  isid(ncessch, year) |>
  mutate(cyear = if_else(year <= 2019, "2019", "2020")) |>
  st_join(
    shp |>
      bind_rows(.id = "cyear") |>
      st_as_sf(),
    join = st_within
  ) |>
  filter(cyear.x == cyear.y) |>
  select(-c(cyear.x, cyear.y)) |>
  isid(ncessch, year)

# Calculate total workforce in tracts within commuting distance of each school.
dta <- shp |>
  # Calculate distances between all tracts in each census year.
  lapply(\(x) {
    st_distance(x) |>
      units::set_units("mi") |>
      as_tibble() |>
      rlang::set_names(x$geoid) |>
      bind_cols(geoid = x$geoid) |>
      pivot_longer(
        cols = -c("geoid"),
        names_to = "geoid2",
        values_to = "dist"
      )
  }) |>
  bind_rows(.id = "cyear") |>
  isid(geoid, geoid2, cyear) |>
  # Filter to pairs within commuting distance in each calendar year.
  left_join(
    select(acs, geoid, year, cyear, avg_commute),
    by = c("geoid", "cyear"),
    relationship = "many-to-many"
  ) |>
  isid(geoid, geoid2, year) |>
  mutate(avg_commute = units::as_units(avg_commute, "mi")) |>
  filter(dist <= avg_commute) |>
  # Sum workforce in nearby tracts.
  left_join(
    select(acs, geoid2 = geoid, year, den_emp),
    by = c("geoid2", "year"),
    relationship = "many-to-one"
  ) |>
  group_by(geoid, year, cyear, avg_commute) |>
  summarize(tot_emp = sum(den_emp)) |>
  isid(geoid, year) |>
  # Recover geometries.
  left_join(
    bind_rows(shp, .id = "cyear"),
    by = c("geoid", "cyear"),
    relationship = "many-to-one"
  ) |>
  st_as_sf() |>
  # Merge onto schools.
  st_join(
    select(ccd, ncessch, year),
    join = st_contains,
    left = FALSE
  ) |>
  filter(year.x == year.y) |>
  select(ncessch, year = year.x, geoid, avg_commute, tot_emp) |>
  isid(ncessch, year)

# Ensure all schools exist with nonmissing data.
stopifnot(nrow(dta) == nrow(ccd))
stopifnot(all(!is.na(dta$tot_emp)))

# Write to disk.
dta |>
  st_drop_geometry() |>
  write.csv(OUT, row.names = FALSE)
