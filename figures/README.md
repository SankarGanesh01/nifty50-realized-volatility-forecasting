# Figures — NIFTY 50 Realized Volatility Forecasting

This directory contains visual outputs from the realized volatility forecasting study of the NIFTY 50 index.

## Figures

| Figure | Description |
|---|---|
| `rv_time_series.png` | Historical time series of the realized volatility target, highlighting periods of volatility spikes. |
| `model_comparison_test.png` | Compares actual realized volatility with forecasts from the historical-mean, naïve, ARIMAX, and Random Forest models over the test period. |
| `correlation_heatmap.png` | Pearson correlation matrix showing relationships among the target, lagged volatility, market activity, and other predictor variables. |
| `rf_variable_importance.png` | Random Forest variable-importance measures using percentage increase in mean squared error and increase in node purity. |
| `arimax_residual_acf.png` | Autocorrelation function (ACF) of ARIMAX residuals, used to assess remaining serial dependence. |
| `arimax_residual_qqplot.png` | Normal Q–Q plot of ARIMAX residuals, used to examine departures from normality. |

## Interpretation

These figures support the evaluation of volatility dynamics, forecast performance, predictor relationships, and model diagnostics. They should be interpreted alongside the numerical results in `tables/` and the analysis code in `notebooks/` or `src/`.

**Note:** Visual diagnostics alone do not establish that a model is statistically adequate or superior. Forecast performance should be assessed using out-of-sample metrics, and residual dependence and distributional assumptions should be evaluated separately.
