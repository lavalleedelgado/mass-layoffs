################################################################################
#
# Project:  Mass layoffs
# Purpose:  Download pdfs of National Student Clearinghouse data
# Author:   Patrick Lavallee Delgado
# Created:  5 December 2023
#
# Notes:
#
# To do:
#
################################################################################

# Import packages.
import argparse
import sys
import re
import pandas as pd
import tabula
from PyPDF2 import PdfReader

# Set constants to parse pdf contents.
PAGES = [6, 11, 16]
YEAR_PATTERN = re.compile("[\\/]([0-9]{4})[\\/][^\\/]+\.pdf$")
NAME_PATTERN = re.compile("^([^\n]+)")
CEEB_PATTERN = re.compile("(?<=ACT Code: )([0-9]+)")

# Map pdf column headers to variable names.
COLUMNS = {
  "class of"          : "cohort",
  "total in the class": "n_grad",
  "total enrolled"    : "n_coll",
  "total in public"   : "n_coll_public",
  "total in private"  : "n_coll_private",
  "total in 2-year"   : "n_coll_2yr",
  "total in 4-year"   : "n_coll_4yr",
  "total in-state"    : "n_coll_istate",
  "total out-of-state": "n_coll_ostate",
}


# Collect tables from pdf document.
def get_table(
  path: str,
  pages: list[str] = PAGES,
  year_pat: re.Pattern = YEAR_PATTERN,
  name_pat: re.Pattern = NAME_PATTERN,
  ceeb_pat: re.Pattern = CEEB_PATTERN,
  cols: list[str] = COLUMNS,
) -> pd.DataFrame:

  # Get college enrollment counts across three tables.
  dfs = tabula.read_pdf(path, pages=pages)
  for i, df in enumerate(dfs):
    df = df.T.reset_index()
    df.columns = df.iloc[0].str.lower()
    df = df.drop(0).rename(columns=cols).map(destring).assign(lag=i)
    dfs[i] = df

  # Get report year from path.
  year = int(re.search(year_pat, path).group(1))

  # Get school name and CEEB code from cover sheet.
  text = PdfReader(path).pages[0].extract_text()
  try:
    name = re.search(name_pat, text).group(1)
    ceeb = int(re.search(ceeb_pat, text).group(1))
  except:
    name = None
    ceeb = None

  # Stack and return the tables.
  return pd.concat(dfs).assign(nsc=year, school_name=name, ceeb=ceeb)


# Numericize values.
def destring(s: str) -> float:
  if isinstance(s, str):
    return pd.to_numeric(re.sub("[^0-9\.-]", "", s))
  if any(isinstance(s, x) for x in [int, float, complex]):
    return s
  raise TypeError


# Convert calendar year to school year.
def y2sy(year: int, fall: bool = False) -> int:
  y = (year if fall else year - 1) % 100
  return y * 100 + y + 1


if __name__ == "__main__":

  # Parse arguments.
  parser = argparse.ArgumentParser()
  parser.add_argument("pdf", nargs="?", type=argparse.FileType("r"), default=sys.stdin)
  parser.add_argument("out", nargs="?", type=argparse.FileType("w"), default=sys.stdout)
  args = parser.parse_args()

  # Read and write NSC data.
  (
    pd
    .concat(get_table(pdf.rstrip()) for pdf in args.pdf)
    .sort_values("nsc")
    .groupby(["ceeb", "cohort", "lag"], dropna=False)
    .tail(n=1)
    .assign(
      cohort=lambda df: df["cohort"].apply(y2sy),
      lag=lambda df: df["lag"] * 100 + df["lag"],
      sy=lambda df: df["cohort"] + df["lag"],
    )
    .loc[:, ["ceeb", "school_name", "sy", "nsc"] + list(COLUMNS.values())]
    .sort_values(["ceeb", "sy", "cohort"])
    .to_csv(args.out, index=False)
  )
