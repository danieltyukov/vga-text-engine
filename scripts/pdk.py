"""IHP Open PDK SG13G2 paths and corner definitions.

One place for the PDK layout so the synthesis and timing drivers cannot disagree about
which Liberty file a corner name refers to. Override the tree location with the
IHP_PDK_ROOT environment variable.
"""

import os
import pathlib

DEFAULT_ROOT = pathlib.Path.home() / ".local/share/pdk/IHP-Open-PDK/ihp-sg13g2"

ROOT = pathlib.Path(os.environ.get("IHP_PDK_ROOT", DEFAULT_ROOT))

STDCELL = ROOT / "libs.ref/sg13g2_stdcell"
LIB_DIR = STDCELL / "lib"
LEF_DIR = STDCELL / "lef"

TECH_LEF = LEF_DIR / "sg13g2_tech.lef"
CELL_LEF = LEF_DIR / "sg13g2_stdcell.lef"

# corner name -> (liberty file stem, supply, temperature, description)
CORNERS = {
    "slow": ("sg13g2_stdcell_slow_1p08V_125C", "1.08 V", "125 C",
             "slow process, low supply, hot: the setup signoff corner"),
    "typ": ("sg13g2_stdcell_typ_1p20V_25C", "1.20 V", "25 C",
            "typical process, nominal supply, room temperature"),
    "fast": ("sg13g2_stdcell_fast_1p32V_m40C", "1.32 V", "-40 C",
             "fast process, high supply, cold: the hold corner"),
    "slow_1p35": ("sg13g2_stdcell_slow_1p35V_125C", "1.35 V", "125 C",
                  "slow process at the higher supply option"),
    "typ_1p50": ("sg13g2_stdcell_typ_1p20V_25C", "1.20 V", "25 C",
                 "unused placeholder"),
    "fast_1p65": ("sg13g2_stdcell_fast_1p65V_m40C", "1.65 V", "-40 C",
                  "fast process at the higher supply option"),
}

# The three corners reported by default.
DEFAULT_CORNERS = ["slow", "typ", "fast"]

# The corner every signoff number in the documentation is taken at.
SIGNOFF_CORNER = "slow"


def lib(corner):
    stem = CORNERS[corner][0]
    path = LIB_DIR / f"{stem}.lib"
    if not path.exists():
        raise SystemExit(f"missing Liberty file for corner {corner}: {path}\n"
                         f"set IHP_PDK_ROOT if the PDK is elsewhere")
    return path


def check():
    """Raise with a helpful message if the PDK is not where we expect."""
    for p in (TECH_LEF, CELL_LEF):
        if not p.exists():
            raise SystemExit(f"missing PDK file: {p}\n"
                             f"set IHP_PDK_ROOT if the PDK is elsewhere")
    for c in DEFAULT_CORNERS:
        lib(c)
    return True
