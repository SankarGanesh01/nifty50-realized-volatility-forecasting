# Tables - NIFTY 50 Realized Volatility Forecasting

This directory contains structured CSV outputs from the realized volatility forecasting study. These files provide numerical evidence supporting model comparison, feature analysis, and diagnostic testing.

## Files

| File | Description |
|---|---|
| `summary_statistics.csv` | Descriptive statistics for the variables used in the analysis. |
| `stationarity_results.csv` | Results of stationarity tests applied during time-series analysis. |
| `correlation_matrix.csv` | Pairwise Pearson correlations among selected variables. |
| `vif_table.csv` | Variance Inflation Factor (VIF) results for assessing multicollinearity. |
| `model_comparison.csv` | Comparative performance metrics for the forecasting models. |
| `predictions_validation.csv` | Actual and predicted values for the validation period. |
| `predictions_test.csv` | Actual and predicted values for the held-out test period. |
| `arimax_coefficients.csv` | Estimated coefficients from the fitted ARIMAX model. |
| `arimax_residual_diagnostics.csv` | Numerical diagnostic results for ARIMAX residuals. |
| `arimax_improvement_vs_benchmarks.csv` | Model-performance improvements relative to benchmark forecasts. |
| `rf_variable_importance.csv` | Variable-importance results from the Random Forest model. |
| `rf_mtry_tuning.csv` | Results from tuning the Random Forest `mtry` parameter. |
| `variable_types.csv` | Variable names and their recorded data types. |

## Usage

The CSV files can be opened in Excel or loaded into R or Python for further analysis. Consult the corresponding analysis scripts for the definitions of the variables, model specifications, evaluation metrics, and test procedures.

## Reproducibility

These files are derived analytical outputs, not raw market data. Results depend on the input data, preprocessing decisions, feature construction, model settings, and train-validation-test split used in the study.

The reported results should be interpreted using the methodology and limitations documented in the main repository README.
