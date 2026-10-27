# Data Sources, Coverage and Preparation

## 1. Overview

This project investigates whether cross-sectional market information improves one-day-ahead forecasts of NIFTY 50 realized volatility. The dataset combines index-level market data with stock-level observations from the National Stock Exchange of India (NSE).

Raw market data and large intermediate datasets are not included in this public repository. This document describes the data coverage, construction process and variables used in the study.

## 2. Data Sources and Study Period

| Item | Description |
|---|---|
| Market | Indian equity market |
| Index | NIFTY 50 |
| Primary data sources | NIFTY 50 OHLCV data and NSE Bhavcopy records |
| Raw data coverage | 18 October 2007 – 29 July 2026 |
| Initial Bhavcopy dataset | Approximately 7.3 million observations across more than 4,000 listed securities |
| Final modelling dataset | 4,630 daily observations |
| Final dataset structure | 28 columns: date, target variable and 26 predictors |
| Forecasting horizon | One trading day ahead |

*Source: Project report, Data Description and Methodology sections.*

The raw data coverage represents the period described in the report. The effective observation period for individual variables may differ because of data availability, preprocessing, liquidity filters and the construction of lagged or rolling features.

## 3. Data Preparation Pipeline

The dataset was prepared through the following stages:

1. **Data collection:** Obtain historical NIFTY 50 OHLCV data and NSE Bhavcopy records.
2. **Data quality and preprocessing:** Clean the source data, handle missing or invalid observations, and apply minimum-history and rolling-liquidity filters to the stock universe.
3. **Feature construction:** Calculate daily stock returns and Garman–Klass realized volatility.
4. **Cross-sectional aggregation:** Construct daily market-wide measures of dispersion, breadth, skewness, kurtosis, tail events, stock volatility and momentum dispersion.
5. **Index-level features:** Incorporate market returns, trading volume, turnover and Amihud illiquidity measures.
6. **Lagged and rolling variables:** Construct historical volatility, weekly and monthly realized-volatility measures, and momentum predictors.
7. **Forecast target:** Define `RV_target_t1` as the next-day realized-volatility target.
8. **Chronological modelling:** Split observations into training, validation and test periods without randomly shuffling the time series.

Predictors are intended to use information available by the close of day *t*, while the target represents day *t + 1*.

## 4. Forecasting Periods

| Dataset | Period | Observations |
|---|---|---:|
| Training | 18 October 2007 – 31 December 2022 | 3,751 |
| Validation | 1 January 2023 – 31 December 2024 | 491 |
| Test | 1 January 2025 – 29 July 2026 | 388 |
| **Total** | **18 October 2007 – 29 July 2026** | **4,630** |

The training set is used for model estimation, the validation set for model selection and tuning, and the test set for final out-of-sample evaluation.

## 5. Main Variables

The modelling dataset includes:

- **Target:** `RV_target_t1`
- **Historical volatility:** Current, lagged and rolling realized-volatility measures.
- **Market returns and leverage:** Market return measures and a leverage-effect variable.
- **Cross-sectional characteristics:** Dispersion, skewness, kurtosis, average stock volatility, market breadth and tail counts.
- **Liquidity and trading activity:** Turnover, volume, Amihud illiquidity and volume concentration.
- **Momentum:** Short-term and medium-term momentum indicators.
- **Market universe:** Number of liquid stocks included in daily calculations.

The complete variable descriptions are provided in the project's report appendix.

## 6. Data Availability and Reproducibility

The raw and intermediate datasets are excluded from this public repository because of their size and to keep the repository manageable.

To reproduce the analysis:

1. Obtain the necessary historical data from the original source, subject to applicable access conditions and terms.
2. Run the project's data collection and preparation scripts.
3. Recreate the feature-engineered dataset.
4. Apply the documented chronological split.
5. Fit the forecasting models and compare their out-of-sample performance.

The figures and summary tables published in the repository provide supporting analytical outputs; they are not substitutes for the underlying raw data.

## 7. Limitations and Disclaimer

The reported results depend on the selected study period, data filters, feature definitions, forecasting models and evaluation procedure. Reproduction requires consistent data coverage and implementation choices.

This repository is intended for academic and research purposes only. It does not constitute investment advice.
