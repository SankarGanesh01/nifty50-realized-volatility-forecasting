# nifty50-realized-volatility-forecasting
Quantitative forecasting of NIFTY 50 realized volatility using econometric and machine learning models with cross-sectional market features.
# Forecasting NIFTY 50 Realized Volatility Using Cross-Sectional Market Features

**An econometric and machine-learning comparison of one-day-ahead volatility forecasts**

## Project Overview

Volatility is an important input in derivative pricing, portfolio risk management and financial decision-making. Traditional forecasting approaches often rely heavily on an index's own volatility history. However, changes in market breadth, stock-level dispersion, liquidity and momentum may provide additional information about future market risk.

This project investigates whether cross-sectional information from the Indian equity market improves one-day-ahead forecasts of NIFTY 50 realized volatility.

The study compares an econometric model, **ARIMAX**, and a machine-learning model, **Random Forest**, against two benchmarks: a historical-mean forecast and a naïve random-walk forecast.

## Research Question

Do cross-sectional market signals improve one-day-ahead forecasts of NIFTY 50 realized volatility beyond the information contained in the index's historical volatility?

## Dataset

| Attribute | Details |
|---|---|
| Market | Indian equity market |
| Index | NIFTY 50 |
| Raw data period | 18 October 2007 – 29 July 2026 |
| Data sources | NIFTY 50 OHLCV data and NSE Bhavcopy records |
| Final dataset | 4,630 daily observations |
| Predictors | 26 explanatory variables |
| Target | Next-day Garman–Klass realized volatility |
| Forecast horizon | One trading day ahead |

The dataset combines historical volatility, market returns, cross-sectional stock characteristics, liquidity measures and momentum indicators.

Raw and intermediate datasets are not included in this repository. See [`data/README.md`](data/README.md) for the data coverage, construction pipeline and reproducibility information.

## Methodology

The analysis follows a chronological forecasting framework.

1. **Data preparation:** Clean the source data and apply minimum-history and rolling-liquidity filters.
2. **Feature engineering:** Construct stock-level realized volatility and aggregate cross-sectional market features.
3. **Exploratory analysis:** Examine descriptive statistics, volatility patterns and predictor correlations.
4. **Stationarity testing:** Apply Augmented Dickey–Fuller and KPSS tests to the target and selected predictors.
5. **Model development:** Fit ARIMAX and Random Forest models, alongside historical-mean and naïve benchmarks.
6. **Model selection:** Use the validation period for model selection and hyperparameter tuning.
7. **Out-of-sample evaluation:** Compare forecasts using RMSE, MAE and QLIKE.
8. **Diagnostics:** Examine ARIMAX residual autocorrelation, conditional heteroscedasticity and residual distribution, and assess Random Forest variable importance.

The target is shifted one trading day ahead, and predictors are intended to contain only information available at the forecast origin.

## Forecast Design

| Dataset | Period | Observations |
|---|---|---:|
| Training | 18 October 2007 – 31 December 2022 | 3,751 |
| Validation | 1 January 2023 – 31 December 2024 | 491 |
| Test | 1 January 2025 – 29 July 2026 | 388 |

The final test period is kept separate from model selection to evaluate performance on unseen observations.

## Key Results

According to the project report, ARIMAX achieved the best overall performance on the independent test set.

| Test-set model | RMSE | MAE | QLIKE |
|---|---:|---:|---:|
| **ARIMAX** | **3.537 × 10⁻⁵** | **2.601 × 10⁻⁵** | **0.3209** |
| Naïve (random walk) | 4.459 × 10⁻⁵ | 2.876 × 10⁻⁵ | 0.5222 |
| Random Forest | 5.981 × 10⁻⁵ | 3.600 × 10⁻⁵ | 0.3867 |
| Historical mean | 1.010 × 10⁻⁴ | 9.705 × 10⁻⁵ | 0.8784 |

Lower values indicate better performance for all three reported error metrics.

### Interpretation

- ARIMAX outperformed the three alternatives across RMSE, MAE and QLIKE on the test set.
- Random Forest performed best during validation but did not retain that advantage during the independent test period.
- Market-wide variables, including dispersion, liquidity, breadth and momentum, provided useful predictive information in the fitted models.
- The reported ARIMAX diagnostics included a Ljung–Box p-value of 0.319 and an ARCH-LM p-value of 0.948.

These findings support the study's conclusion that cross-sectional market features can complement historical volatility measures. They do not establish that the same performance will persist in future market conditions.

## Repository Structure

```text
.
├── README.md
├── data/
│   └── README.md
├── figures/
│   ├── realized volatility and correlation plots
│   ├── forecast comparison
│   └── model diagnostics and variable importance
├── notebooks/
│   └── analysis notebooks
├── src/
│   └── data collection and analysis scripts
├── tables/
│   ├── descriptive statistics
│   ├── data validation
│   ├── event and forecast summaries
│   └── statistical test and regression summaries
├── requirements.txt
└── .gitignore
```

The structure above describes the intended organization; individual filenames may differ in the repository. Refer to the folders for the actual files.

## Tools and Technologies

- **R:** Time-series forecasting, econometric analysis and machine learning.
- **Python:** Data collection and supporting data-processing tasks, where applicable.
- **Data analysis:** `data.table`, `zoo`, `forecast`, `tseries` and `randomForest`.
- **Visualisation:** Correlation plots, forecast comparisons, residual diagnostics and variable-importance charts.
- **Statistical methods:** ADF and KPSS stationarity tests, VIF screening, Ljung–Box testing and ARCH-LM testing.

See [`requirements.txt`](requirements.txt) for the Python dependencies. R packages must be installed separately in an R environment.

## Limitations

- The analysis focuses on one-day-ahead forecasts for a single index.
- Only ARIMAX and Random Forest are compared as the principal forecasting models.
- The report does not include a formal Diebold–Mariano test of forecast differences.
- Forecast accuracy can change across market regimes, and extreme volatility spikes remain difficult to predict.
- Reproducing the results requires access to the underlying historical data and consistent implementation of the feature-engineering and evaluation procedures.

## Research Purpose

This project demonstrates a practical workflow for financial time-series forecasting, combining econometric modelling, cross-sectional feature engineering, machine learning, chronological validation and residual diagnostics.

It is intended for academic and research purposes and does not constitute investment advice.
