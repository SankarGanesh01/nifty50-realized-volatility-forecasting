"""
Data Pipeline: NIFTY Volatility Forecasting Project (Python -- data pull only)
Target: NIFTY 50 index | Universe: full NSE bhavcopy, 2007-2026

"""

import os
import time
import zipfile
import io
from pathlib import Path
from datetime import date, timedelta

import requests
import pandas as pd
import yfinance as yf

BASE_DIR = Path(r"C:\Users\sanka\OneDrive\Documents\Advanced Financial Analytics")
RAW_DIR = BASE_DIR / "data" / "raw"
BHAV_DIR = BASE_DIR / "data" / "bhavcopy"
RAW_DIR.mkdir(parents=True, exist_ok=True)
BHAV_DIR.mkdir(parents=True, exist_ok=True)

START_DATE = date(2007, 1, 1)
END_DATE = date(2026, 7, 31)


# ---- 1. NIFTY 50 Index (target variable) ----
def download_nifty50():
    print("Downloading NIFTY 50 index...")
    df = yf.download("^NSEI", start=START_DATE.isoformat(),
                      end=END_DATE.isoformat(), auto_adjust=False)
    df = df.reset_index()
    # Newer yfinance versions return MultiIndex columns (field, ticker)
    # even for a single symbol -- flatten to plain lowercase field names.
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [c[0].lower() if isinstance(c, tuple) else str(c).lower()
                      for c in df.columns]
    else:
        df.columns = [str(c).lower() for c in df.columns]
    df.to_csv(RAW_DIR / "nifty50_index.csv", index=False)
    print(f"NIFTY 50 index saved: {len(df)} rows")
    return df


# ---- 2. India VIX ----
# Same as the R version: script access to NSE's VIX historical page is
# unreliable. Manually download the CSV from
#   https://www.nseindia.com/reports-indices-historical-index-data
# and save as data/raw/india_vix.csv. Optional -- skip if short on time.


# ---- 3. NSE Equity Bhavcopy: full 2007-2026 download ----
HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0 Safari/537.36"),
    "Accept": "*/*",
}

# NSE discontinued the old CM Bhavcopy(csv) format after 2024-07-05 and
# switched to CM-UDiFF Common Bhavcopy Final(zip) from 2024-07-08 onward.
UDIFF_CUTOVER = date(2024, 7, 8)

def old_bhavcopy_url(d: date) -> str:
    yyyy, mon, dd = d.strftime("%Y"), d.strftime("%b").upper(), d.strftime("%d")
    fname = f"cm{dd}{mon}{yyyy}bhav.csv.zip"
    return (f"https://nsearchives.nseindia.com/content/historical/EQUITIES/"
            f"{yyyy}/{mon}/{fname}")

def udiff_bhavcopy_url(d: date) -> str:
    yyyymmdd = d.strftime("%Y%m%d")
    return (f"https://nsearchives.nseindia.com/content/cm/"
            f"BhavCopy_NSE_CM_0_0_0_{yyyymmdd}_F_0000.csv.zip")

def get_bhavcopy(d: date, pause: float = 0.5) -> None:
    yyyy, mon, dd = d.strftime("%Y"), d.strftime("%b").upper(), d.strftime("%d")
    is_udiff = d >= UDIFF_CUTOVER

    # Distinct filename prefixes so old/new format files don't collide
    dest_csv = (BHAV_DIR / f"udiff_{d.strftime('%Y%m%d')}.csv" if is_udiff
                else BHAV_DIR / f"cm{dd}{mon}{yyyy}bhav.csv")

    if dest_csv.exists():
        return  # already have it -- resumable

    url = udiff_bhavcopy_url(d) if is_udiff else old_bhavcopy_url(d)

    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
    except requests.RequestException:
        time.sleep(pause)
        return

    time.sleep(pause)  # be polite -- avoid getting IP-blocked over a long run

    if resp.status_code != 200:
        return  # holiday/weekend -- expected, no bhavcopy that day

    try:
        with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
            names = z.namelist()
            z.extractall(BHAV_DIR)
            if is_udiff:
                # UDiFF zip contains one CSV with a long generated name --
                # rename to our standard, predictable dest_csv name
                extracted = BHAV_DIR / names[0]
                if extracted.exists() and extracted != dest_csv:
                    extracted.rename(dest_csv)
    except zipfile.BadZipFile:
        return  # occasionally NSE returns an HTML error page instead of a zip


def download_all_bhavcopy():
    trading_days = []
    d = START_DATE
    while d <= END_DATE:
        if d.weekday() < 5:  # Mon-Fri
            trading_days.append(d)
        d += timedelta(days=1)

    print(f"Downloading bhavcopy for {len(trading_days)} candidate days.")
    print(f"Old format used before {UDIFF_CUTOVER}, UDiFF format from "
          f"{UDIFF_CUTOVER} onward.")

    for i, d in enumerate(trading_days, 1):
        get_bhavcopy(d)
        if i % 100 == 0:
            print(f"Processed {i}/{len(trading_days)} days")


def combine_bhavcopy() -> pd.DataFrame:
    old_files = list(BHAV_DIR.glob("cm*bhav.csv"))
    udiff_files = list(BHAV_DIR.glob("udiff_*.csv"))
    print(f"Found {len(old_files)} old-format files, {len(udiff_files)} UDiFF files.")

    frames = []

    # --- Old format: SYMBOL, SERIES, OPEN, HIGH, LOW, CLOSE, TOTTRDQTY, TIMESTAMP
    for f in old_files:
        try:
            df = pd.read_csv(f)
        except Exception:
            continue
        if "SERIES" not in df.columns:
            continue
        df = df[df["SERIES"] == "EQ"]
        keep = df[["SYMBOL", "TIMESTAMP", "OPEN", "HIGH", "LOW", "CLOSE",
                   "TOTTRDQTY"]].copy()
        keep.columns = ["symbol", "date", "open", "high", "low", "close", "volume"]
        frames.append(keep)

    # --- UDiFF format: TckrSymb, SctySrs, OpnPric, HghPric, LwPric, ClsPric,
    # TtlTradgVol, TradDt -- mapping confirmed by manual file inspection.
    for f in udiff_files:
        try:
            df = pd.read_csv(f)
        except Exception:
            continue
        if "SctySrs" not in df.columns:
            continue
        df = df[df["SctySrs"] == "EQ"]
        keep = df[["TckrSymb", "TradDt", "OpnPric", "HghPric", "LwPric",
                   "ClsPric", "TtlTradgVol"]].copy()
        keep.columns = ["symbol", "date", "open", "high", "low", "close", "volume"]
        frames.append(keep)

    bhav_all = pd.concat(frames, ignore_index=True)

    # CRITICAL: parse date as an actual datetime, not a string. Old format
    # uses "DD-MON-YYYY", new UDiFF format uses "YYYY-MM-DD" -- format="mixed"
    # lets pandas infer each row's format rather than assuming one pattern.
    # Without proper parsing, sort_values("date") in the adjustment step
    # would sort ALPHABETICALLY, scrambling chronological order per ticker.
    bhav_all["date"] = pd.to_datetime(bhav_all["date"], format="mixed",
                                        errors="coerce")
    n_unparsed = bhav_all["date"].isna().sum()
    if n_unparsed > 0:
        print(f"WARNING: {n_unparsed} rows had an unparseable date -- dropped. "
              f"Inspect a sample of these if the count seems large.")
        bhav_all = bhav_all.dropna(subset=["date"])

    bhav_all.to_csv(RAW_DIR / "bhavcopy_full_2007_2026.csv", index=False)
    print(f"Full bhavcopy panel saved: {len(bhav_all)} rows, "
          f"{bhav_all['symbol'].nunique()} unique tickers, "
          f"{bhav_all['date'].nunique()} trading days")
    return bhav_all


# ---- 4/5. Split/bonus adjustment heuristic ----
def adjust_for_splits(group: pd.DataFrame, threshold: float = 0.40) -> pd.DataFrame:
    group = group.sort_values("date").reset_index(drop=True)
    group["ret"] = group["close"].pct_change()
    group["is_action"] = group["ret"].abs() > threshold

    adj_factor = pd.Series(1.0, index=group.index)
    action_idx = group.index[group["is_action"]].tolist()
    for idx in reversed(action_idx):
        if idx == 0:
            continue
        ratio = group.loc[idx, "close"] / group.loc[idx - 1, "close"]
        adj_factor.loc[: idx - 1] *= ratio

    group["adj_factor"] = adj_factor
    group["adj_close"] = group["close"] * group["adj_factor"]
    return group


def apply_adjustment(bhav_all: pd.DataFrame) -> pd.DataFrame:
    print("Applying split/bonus adjustment heuristic per ticker...")
    print("NOTE: heuristic, not corporate-actions-verified. Spot-check")
    print("known-split tickers before trusting it for the final report.")

    adjusted = bhav_all.groupby("symbol", group_keys=False).apply(adjust_for_splits)
    adjusted.to_csv(RAW_DIR / "bhavcopy_full_2007_2026_adjusted.csv", index=False)

    action_log = adjusted[adjusted["is_action"]][["symbol", "date", "close", "ret"]]
    action_log.to_csv(RAW_DIR / "detected_corporate_actions.csv", index=False)
    print(f"{len(action_log)} candidate split/bonus events detected -- "
          f"review detected_corporate_actions.csv before final use.")
    return adjusted


if __name__ == "__main__":
    download_nifty50()
    download_all_bhavcopy()
    bhav = combine_bhavcopy()
    apply_adjustment(bhav)