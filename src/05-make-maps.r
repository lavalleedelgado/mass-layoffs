################################################################################
#
# Project:  Mass layoffs
# Purpose:  Draw map for APPAM 2024 poster presentation
# Author:   Patrick Lavallee Delgado
# Created:  13 November 2024
#
# Notes:
#
# To do:
#
################################################################################

# Import packages.
library(dplyr)
library(tidyr)
library(lubridate)
library(sf)
library(tigris)
library(haven)
library(readxl)
library(ggplot2)
library(ggnewscale)
library(ggspatial)

# Identify inputs and outputs.
PWD <- getwd()
DTA <- file.path(PWD, "in")
WRN <- file.path(DTA, "warn.xlsx")
SCH <- file.path(PWD, "out", "analysis.dta")
SHP <- file.path(DTA, "shapefile", "tl_2019_us_county.shp")
LOC <- file.path(DTA, "loc.csv")
WGT <- file.path(DTA, "wgt.csv")
ACS <- file.path(DTA, "acs.csv")
OUT <- file.path(PWD, "out")

# Write a function to check uniqueness of identifiers.
isid <- function(.data, ...) {
  if(any(duplicated(dplyr::select(.data, ...)))) {
    stop("indexers do not uniquely identify the observations")
  }
  return(.data)
}

# Specify Penn colors.
pennred <- "#990000"
pennblue <- "#002856"

################################################################################
# Summarize mass layoffs.
################################################################################

# Draw mass layoffs over time.
read_excel(WRN) |>
  mutate(year = year(date)) |>
  ggplot(aes(x = year, y = layoffs)) +
  geom_bar(stat = "identity", fill = pennblue) +
  scale_x_continuous(breaks = seq(2012, 2023, by = 2)) +
  scale_y_continuous(labels = scales::comma) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 32)
ggsave(file.path(OUT, "layoffs.png"), height = 6, width = 12, units = "in")

################################################################################
# Summarize student outcomes.
################################################################################

# Load schools.
sch <- read_stata(SCH)

# Set cohort value labels.
cohort_vlab <- c()
for (year in sort(unique(sch$cohort))) {
  lab <- sprintf("SY 20%2.0f-%2.0f", floor(year / 100), year %% 100)
  cohort_vlab[lab] <- year
}

# Set mill town value labels.
mill_vlab <- c("Mill towns" = 1, "All others" = 0)

# Set outcome value labels.
variable_vlab <- c(
  "High school graduation"        = "pct_grad_3mo",
  "College enrollment"            = "pct_coll_3mo",
  "Two-year college enrollment"   = "pct_coll_2yr_3mo",
  "Four-year college enrollment"  = "pct_coll_4yr_3mo"
)

# Draw college enrollment over time by mill town status.
sch |>
  select(cohort, mill, enrl, matches("^pct_.*_3mo$")) |>
  pivot_longer(
    cols = -c(cohort, mill, enrl),
    names_to = "variable",
    values_to = "value"
  ) |>
  mutate(variable = factor(
    variable,
    levels = unname(variable_vlab),
    labels = names(variable_vlab)
  )) |>
  group_by(mill, variable) |>
  mutate(
    bl = if_else(cohort == min(cohort), value, NA),
    bl = weighted.mean(bl, enrl, na.rm = TRUE)
  ) |>
  group_by(cohort, mill, variable) |>
  summarize(
    mu = weighted.mean(value, enrl, na.rm = TRUE) - bl,
    sd = sd(value, na.rm = TRUE),
    n = sum(!is.na(value))
  ) |>
  mutate(
    se = sd / sqrt(n),
    lb = mu - se,
    ub = mu + se,
    sy = if_else(!mill, cohort - 5, cohort + 5)
  ) |>
  ggplot(aes(x = sy, y = mu, ymin = lb, ymax = ub, linetype = factor(mill))) +
  geom_hline(yintercept = 0, linewidth = 0.5) +
  geom_line(color = pennblue, linewidth = 0.5) +
  geom_point(color = pennblue) +
  geom_errorbar(color = pennblue, linewidth = 0.5, width = 8) +
  facet_wrap(~ variable, ncol = 1) +
  scale_x_continuous(
    breaks = unname(cohort_vlab),
    labels = names(cohort_vlab)
  ) +
  scale_linetype_manual(
    values = c("0" = 2, "1" = 1),
    breaks = unname(mill_vlab),
    labels = names(mill_vlab),
  ) +
  labs(x = NULL, y = NULL, linetype = NULL) +
  theme_minimal(base_size = 32) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1),
    legend.position = "bottom"
  )
ggsave(file.path(OUT, "outcomes.png"), height = 19, width = 12, units = "in")

################################################################################
# Draw exposure to mass layoffs for the class of 2015.
################################################################################

# Set focal cohort and signal interval.
YEAR <- 2014
grad <- ymd(sprintf("%d-07-01", YEAR + 1))
interval <- interval(grad %m-% months(9), grad %m+% months(3))

# Load counties in Maine.
shp <- st_read(SHP) |>
  filter(STATEFP == 23) |>
  erase_water(area_threshold = 0.997) |>
  rename_with(~ tolower(.x)) |>
  isid(geoid)
stopifnot(nrow(shp) == 16)

# Load school-site pairs.
loc <- read.csv(LOC) |>
  rename_with(~ tolower(.x)) |>
  mutate(geoid = sprintf("%011.0f", geoid)) |>
  filter(year == YEAR) |>
  isid(id, ncessch)

# Load schools.
sch <- read_stata(SCH) |>
  mutate(
    year = cohort %% 100 + 2000,
    mill = as.factor(mill)
  ) |>
  filter(year == YEAR) |>
  isid(ncessch)

# Load workforce weights.
wgt <- read.csv(WGT) |>
  filter(year == YEAR) |>
  isid(ncessch)

# Load mass layoff events.
wrn <- read_excel(WRN) |>
  filter(excl != 1) |>
  mutate(date = as_date(date)) |>
  filter(date %within% interval) |>
  inner_join(
    loc |>
      select(id, lon_wrn, lat_wrn) |>
      unique(),
    by = "id",
    relationship = "one-to-one"
  ) |>
  isid(id)

# Load tract characteristics.
acs <- read.csv(ACS) |>
  filter(year == YEAR) |>
  mutate(geoid = sprintf("%02.0f%03.0f%06.0f", state, county, tract)) |>
  isid(geoid)

# Recalculate mass layoff signal.
dta <- loc |>
  left_join(wgt, by = "ncessch", relationship = "many-to-one") |>
  inner_join(wrn, by = "id", relationship = "many-to-one") |>
  isid(id, ncessch) |>
  mutate(
    diff = interval(grad, floor_date(date, unit = "month")) %/% months(1),
    dosage = layoffs / (tot_emp / 1000) / ceiling(dist / avg_commute),
    d = -(diff - 3) / 12 - 1,
    d = if_else(ceiling(d) == 0, 1, d)
  ) |>
  filter(ceiling(d) >= 0) |>
  group_by(ncessch, lon_ccd, lat_ccd) |>
  summarize(signal = sum(dosage ^ d)) |>
  ungroup() |>
  isid(ncessch) |>
  inner_join(
    select(sch, ncessch, mill),
    by = "ncessch",
    relationship = "one-to-one"
  )

# Customize annotations for each event.
e1 <- c(500, -68.65, 44.48)
e2 <- c(395, -69.50, 44.88)
e3 <- c(200, -70.20, 43.96)
e4 <- c(200, -68.40, 45.28)
lab <- as.data.frame(rbind(e1, e2, e3, e4))
colnames(lab) <- c("layoffs", "lon", "lat")
stopifnot(all(wrn$layoffs == lab$layoffs))

# Draw exposure.
acs |>
  mutate(countyfp = sprintf("%03.0f", county)) |>
  group_by(countyfp) |>
  summarize(tot_emp = sum(den_emp)) |>
  left_join(shp, by = "countyfp", relationship = "one-to-one") |>
  st_as_sf() |>
  st_make_valid() |>
  ggplot() +
  geom_sf(mapping = aes(fill = tot_emp), color = "grey80") +
  scale_fill_steps(
    low = "white",
    high = "grey60",
    labels = scales::label_number(suffix = " K", scale = 1e-3)
  ) +
  annotation_scale(location = "br", unit_category = "imperial") +
  # annotation_north_arrow(
  #   which_north = "true",
  #   style = north_arrow_fancy_orienteering,
  #   location = "br",
  #   pad_x = unit(0.875, "in"), pad_y = unit(0.35, "in")
  # ) +
  geom_point(
    mapping = aes(x = lon_wrn, y = lat_wrn, size = layoffs),
    data = wrn,
    shape = 24,
    color = "black",
    fill = "white"
  ) +
  scale_size_area(max_size = 20, guide = "none") +
  geom_text(
    data = wrn,
    mapping = aes(x = lon_wrn, y = lat_wrn, label = layoffs)
  ) +
  new_scale("color") +
  new_scale("size") +
  geom_point(
    mapping = aes(x = lon_ccd, y = lat_ccd, size = signal, color = mill),
    data = dta
  ) +
  scale_size_area(max_size = 10, guide = "none") +
  scale_color_manual(
    values = c("0" = pennblue, "1" = pennred),
    breaks = c(1, 0),
    labels = c("Yes", "No")
  ) +
  labs(
    x = NULL, y = NULL,
    color = "Mill town",
    size = "Signal",
    fill = "Population"
  ) +
  guides(
    color = guide_legend(order = 1),
    size = guide_legend(order = 2)
  ) +
  theme_minimal(base_size = 28) +
  theme(
    legend.position = c(0.7, 0.1),
    legend.box = "horizontal",
    legend.title = element_text(hjust = 0.5),
    legend.text = element_text(size = 20),
    legend.text.position = "left"
  )
ggsave(file.path(OUT, "signal.png"), height = 18, width = 14, units = "in")
