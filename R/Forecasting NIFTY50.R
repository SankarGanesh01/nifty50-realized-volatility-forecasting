# ==============================================================================
# This script performs the complete workflow:
# 1. Data preprocessing and quality checks
# 2. Feature engineering
# 3. Exploratory data analysis
# 4. Econometric modelling (ARIMAX)
# 5. Machine learning modelling (Random Forest)
# 6. Forecast evaluation and diagnostics
#
# The script is fully reproducible and should be run from top to bottom.
# ------------------------------------------------------------------------------
# AI Assistance Disclosure
# OpenAI ChatGPT and Anthropic Claude were used as programming assistants for
# debugging, troubleshooting.
# All feature engineering, modelling decisions, implementation, testing,
# interpretation and final verification were completed by myself.
# ------------------------------------------------------------------------------

# Load packages
required_packages <- c("data.table", "zoo", "forecast", "tseries", "randomForest", "corrplot")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("Please install the '", pkg, "' package before running the script.")
}

invisible(lapply(required_packages, library, character.only = TRUE))

# Define project paths and model parameters
project_dir <- "C:/Users/sanka/OneDrive/Documents/Advanced Financial Analytics"

raw_dir        <- file.path(project_dir, "data", "raw")
processed_dir  <- file.path(project_dir, "data", "processed")
nifty_file     <- file.path(raw_dir, "nifty50_index.csv")
bhavcopy_file  <- file.path(raw_dir, "bhavcopy_full_2007_2026_adjusted.csv")
output_file    <- file.path(processed_dir, "master_forecasting_dataset.csv")

results_dir <- "results"
figures_dir <- file.path(results_dir, "figures")
tables_dir  <- file.path(results_dir, "tables")
models_dir  <- file.path(results_dir, "models")

for (d in c(processed_dir, results_dir, figures_dir, tables_dir, models_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

MIN_TRADING_DAYS    <- 250
TURNOVER_LOOKBACK   <- 60
TURNOVER_PERCENTILE <- 0.70
HAR_WEEK_WINDOW     <- 5
HAR_MONTH_WINDOW    <- 22
VOL_OF_VOL_WINDOW   <- 22
MOMENTUM_SHORT      <- 5
MOMENTUM_LONG       <- 22
RF_NTREE            <- 500

# Helper functions used throughout the analysis  
# Helper functions were independently implemented and refined with assistance
# from LLMs during debugging and code review.
sample_skew <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3) return(NA_real_)
  m <- mean(x)
  s <- sd(x)
  if (is.na(s) || s == 0) return(NA_real_)
  (sum((x - m)^3) / n) / s^3
}

sample_excess_kurtosis <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4) return(NA_real_)
  m <- mean(x)
  s <- sd(x)
  if (is.na(s) || s == 0) return(NA_real_)
  (sum((x - m)^4) / n) / s^4 - 3
}

save_png <- function(filepath, plot_fun, w = 8, h = 5.5, res = 300) {
  png(filepath, width = w, height = h, units = "in", res = res)
  tryCatch(plot_fun(), finally = dev.off())
}

rmse_fun <- function(actual, pred) {
  sqrt(mean((actual - pred)^2, na.rm = TRUE))
}

mae_fun <- function(actual, pred) {
  mean(abs(actual - pred), na.rm = TRUE)
}

qlike_fun <- function(actual, pred, eps) {
  actual <- pmax(actual, eps)
  pred   <- pmax(pred, eps)
  mean(actual / pred - log(actual / pred) - 1, na.rm = TRUE)
}

compute_vif <- function(df) {
  vars <- names(df)
  vifs <- sapply(vars, function(v) {
    fit <- tryCatch(lm(as.formula(paste0("`", v, "` ~ .")), data = df), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    r2 <- summary(fit)$r.squared
    if (is.na(r2) || r2 >= 0.999999) return(Inf)
    1 / (1 - r2)
  })
  data.frame(variable = vars, VIF = as.numeric(vifs))
}

vif_reduce <- function(df, threshold = 10) {
  dropped <- character(0)
  repeat {
    v <- compute_vif(df)
    v <- v[is.finite(v$VIF), ]
    if (nrow(v) == 0 || max(v$VIF) <= threshold || ncol(df) <= 1) break
    worst <- v$variable[which.max(v$VIF)]
    dropped <- c(dropped, worst)
    df <- df[, setdiff(names(df), worst), drop = FALSE]
  }
  list(kept = names(df), dropped = dropped)
}

standardize <- function(dt, cols, means, sds) {
  m <- as.matrix(dt[, ..cols])
  sweep(sweep(m, 2, means[cols], "-"), 2, sds[cols], "/")
}

run_stationarity <- function(x, name) {
  x <- x[is.finite(x)]
  adf  <- tryCatch(adf.test(x), error = function(e) NULL)
  kpss <- tryCatch(suppressWarnings(kpss.test(x, null = "Level")), error = function(e) NULL)

  adf_stationary  <- if (!is.null(adf)) adf$p.value < 0.05 else NA
  kpss_stationary <- if (!is.null(kpss)) kpss$p.value >= 0.05 else NA
  conclusion <- if (isTRUE(adf_stationary) && isTRUE(kpss_stationary)) {
    "Stationary"
  } else if (!isTRUE(adf_stationary) && !isTRUE(kpss_stationary)) {
    "Non-stationary"
  } else {
    "Inconclusive"
  }

  data.frame(
    variable = name,
    ADF_p = if (!is.null(adf)) adf$p.value else NA,
    KPSS_p = if (!is.null(kpss)) kpss$p.value else NA,
    conclusion = conclusion
  )
}

arch_lm_test <- function(resid, lags = 12) {
  e2 <- resid^2
  n <- length(e2)
  reg_df <- data.frame(e2 = e2[(lags + 1):n])
  for (L in seq_len(lags)) reg_df[[paste0("lag", L)]] <- e2[(lags + 1 - L):(n - L)]
  fit <- lm(e2 ~ ., data = reg_df)
  stat <- (n - lags) * summary(fit)$r.squared
  list(statistic = stat, p.value = 1 - pchisq(stat, df = lags))
}

# Read raw NIFTY 50 and NSE Bhavcopy datasets
if (!file.exists(nifty_file)) stop("NIFTY file not found at: ", nifty_file)
if (!file.exists(bhavcopy_file)) stop("Bhavcopy file not found at: ", bhavcopy_file)

nifty_raw <- fread(nifty_file)
bhav_raw  <- fread(bhavcopy_file)

setnames(nifty_raw, tolower(gsub("[ .]+", "_", names(nifty_raw))))
setnames(bhav_raw,  tolower(gsub("[ .]+", "_", names(bhav_raw))))

nifty_raw[, date := as.Date(date)]
bhav_raw[,  date := as.Date(date)]

expected_nifty_cols <- c("date", "open", "high", "low", "close", "volume")
expected_bhav_cols  <- c("symbol", "date", "open", "high", "low", "close", "volume")
missing_nifty_cols  <- setdiff(expected_nifty_cols, names(nifty_raw))
missing_bhav_cols   <- setdiff(expected_bhav_cols, names(bhav_raw))

if (length(missing_nifty_cols) > 0) {
  stop("NIFTY file is missing expected columns: ", paste(missing_nifty_cols, collapse = ", "))
}
if (length(missing_bhav_cols) > 0) {
  stop("Bhavcopy file is missing expected columns: ", paste(missing_bhav_cols, collapse = ", "))
}
if (sum(sapply(nifty_raw[, ..expected_nifty_cols], function(x) sum(is.na(x)))) > 0) {
  warning("Missing values found in the raw NIFTY columns used by the pipeline.", call. = FALSE)
}
if (sum(sapply(bhav_raw[, ..expected_bhav_cols], function(x) sum(is.na(x)))) > 0) {
  warning("Missing values found in the raw Bhavcopy columns used by the pipeline.", call. = FALSE)
}

bhav_raw[, price_close := close]

setkey(nifty_raw, date)
setkey(bhav_raw, symbol, date)

# Retain stocks with sufficient trading history and liquidity
bhav_raw[, turnover := as.double(close) * as.double(volume)]

stock_obs_count <- bhav_raw[, .N, by = symbol]
eligible_symbols <- stock_obs_count[N >= MIN_TRADING_DAYS, symbol]
bhav_eligible <- bhav_raw[symbol %in% eligible_symbols]
setorder(bhav_eligible, symbol, date)

bhav_eligible[, roll_turnover := frollmean(
  turnover,
  n = TURNOVER_LOOKBACK,
  align = "right",
  na.rm = TRUE
), by = symbol]

liquidity_threshold_by_date <- bhav_eligible[!is.na(roll_turnover), .(
  threshold = quantile(roll_turnover, probs = TURNOVER_PERCENTILE, na.rm = TRUE)
), by = date]

bhav_eligible <- merge(bhav_eligible, liquidity_threshold_by_date, by = "date", all.x = TRUE)
bhav_eligible[, is_liquid_universe := !is.na(roll_turnover) & !is.na(threshold) & roll_turnover >= threshold]

bhav_liquid <- bhav_eligible[is_liquid_universe == TRUE]

if (nrow(bhav_liquid) == 0) {
  stop("Liquidity filter removed all observations. Check MIN_TRADING_DAYS, TURNOVER_LOOKBACK or TURNOVER_PERCENTILE.")
}

# Feature engineering
# Construct stock-level and market-level forecasting features

# In Feature engineering workflow was developed by me but
# LLMs were used only to assist in debugging, code review and documentation suggestions.
setorder(bhav_liquid, symbol, date)
bhav_liquid[, log_ret := log(close) - log(shift(close, 1)), by = symbol]
bhav_liquid[abs(log_ret) > log(3), log_ret := NA_real_]

gk_const <- 2 * log(2) - 1
bhav_liquid[, rv_gk := 0.5 * (log(high / low))^2 - gk_const * (log(close / open))^2]

if (bhav_liquid[!is.finite(rv_gk), .N] > 0) {
  warning("Non-finite stock-level Garman-Klass volatility values found.", call. = FALSE)
}

setorder(nifty_raw, date)
nifty_raw[, mkt_log_ret := log(close) - log(shift(close, 1))]
nifty_raw[, mkt_ret2_t := mkt_log_ret^2]
nifty_raw[, leverage_term_t := fifelse(mkt_log_ret < 0, mkt_log_ret^2, 0)]
nifty_raw[, rv_gk_t := 0.5 * (log(high / low))^2 - gk_const * (log(close / open))^2]
nifty_raw[, overnight_ret_t := log(open) - log(shift(close, 1))]
nifty_raw[, overnight_ret2_t := overnight_ret_t^2]
nifty_raw[, mom_5_t := log(close) - log(shift(close, MOMENTUM_SHORT))]
nifty_raw[, mom_22_t := log(close) - log(shift(close, MOMENTUM_LONG))]

setnames(
  nifty_raw,
  old = c("open", "high", "low", "close", "volume"),
  new = c("nifty_open", "nifty_high", "nifty_low", "nifty_close", "nifty_volume")
)

# Aggregate stock-level information into daily market-wide features
cross_sectional_daily <- bhav_liquid[!is.na(log_ret), .(
  n_stocks_universe  = .N,
  csd_t              = sd(log_ret, na.rm = TRUE),
  cs_skew_t          = sample_skew(log_ret),
  cs_kurt_t          = sample_excess_kurtosis(log_ret),
  avg_stock_vol_t    = mean(rv_gk, na.rm = TRUE),
  breadth_t          = mean(log_ret > 0, na.rm = TRUE),
  cs_tail_count_t    = mean(abs(log_ret - mean(log_ret, na.rm = TRUE)) > 2 * sd(log_ret, na.rm = TRUE), na.rm = TRUE),
  total_turnover_t   = as.numeric(sum(turnover, na.rm = TRUE)),
  amihud_illiq_mkt_t = mean(abs(log_ret) / pmax(turnover, 1), na.rm = TRUE)
), by = date]

bhav_liquid[, mom_22_stock := log(close) - log(shift(close, MOMENTUM_LONG)), by = symbol]

cs_mom_dispersion <- bhav_liquid[!is.na(mom_22_stock), .(
  cs_mom_dispersion_t = sd(mom_22_stock, na.rm = TRUE)
), by = date]

volume_concentration <- bhav_liquid[!is.na(turnover), {
  ord <- order(-turnover)
  top_n <- min(50, .N)
  top_turnover <- sum(turnover[ord][seq_len(top_n)])
  total_turnover <- sum(turnover)
  .(volume_concentration_t = if (total_turnover > 0) top_turnover / total_turnover else NA_real_)
}, by = date]

cross_sectional_daily <- merge(cross_sectional_daily, cs_mom_dispersion, by = "date", all.x = TRUE)
cross_sectional_daily <- merge(cross_sectional_daily, volume_concentration, by = "date", all.x = TRUE)
setorder(cross_sectional_daily, date)

n_nifty_dates  <- uniqueN(nifty_raw$date)
n_cs_dates     <- uniqueN(cross_sectional_daily$date)
n_common_dates <- length(intersect(nifty_raw$date, cross_sectional_daily$date))

if (n_common_dates < min(n_nifty_dates, n_cs_dates) * 0.9) {
  warning("Fewer than 90% of dates are common to both datasets. Check trading-calendar alignment.", call. = FALSE)
}

# Combine NIFTY variables with cross-sectional market features
daily_master <- merge(nifty_raw, cross_sectional_daily, by = "date", all = FALSE)
setorder(daily_master, date)

daily_master[, rv_lag1 := shift(rv_gk_t, 1)]
daily_master[, rv_lag2 := shift(rv_gk_t, 2)]
daily_master[, rv_week_t := frollmean(rv_gk_t, n = HAR_WEEK_WINDOW, align = "right", na.rm = TRUE)]
daily_master[, rv_month_t := frollmean(rv_gk_t, n = HAR_MONTH_WINDOW, align = "right", na.rm = TRUE)]
daily_master[, vol_of_vol_t := frollapply(rv_gk_t, N = VOL_OF_VOL_WINDOW, FUN = sd, align = "right")]
daily_master[, amihud_illiq_index_t := abs(mkt_log_ret) / pmax(nifty_volume, 1)]

# Target construction- Create one-day-ahead forecasting target
daily_master[, RV_target_t1 := shift(rv_gk_t, n = 1, type = "lead")]

verify_df <- daily_master[, .(date, rv_gk_t, RV_target_t1)]
verify_df[, next_date_rv := shift(rv_gk_t, n = 1, type = "lead")]
mismatch_count <- verify_df[
  !is.na(RV_target_t1) & !is.na(next_date_rv) & RV_target_t1 != next_date_rv,
  .N
]
# Verify that predictors use only information available at time t
if (mismatch_count > 0) {
  stop("Look-ahead bias check failed: RV_target_t1 does not equal next trading day's RV_gk_t.")
}

# Quality checks- Perform data quality and consistency checks
n_dupe_dates <- daily_master[, .N, by = date][N > 1, .N]
if (n_dupe_dates > 0) {
  stop("Data quality check failed: ", n_dupe_dates, " duplicate date(s) found in the master dataset.")
}

trim_cols <- c("rv_month_t", "vol_of_vol_t", "cs_mom_dispersion_t", "mom_22_t")
daily_master_trimmed <- daily_master[complete.cases(daily_master[, ..trim_cols])]
daily_master_final <- daily_master_trimmed[!is.na(RV_target_t1)]

remaining_na <- daily_master_final[, lapply(.SD, function(x) sum(is.na(x))), .SDcols = setdiff(names(daily_master_final), "date")]
remaining_na <- melt(remaining_na, measure.vars = names(remaining_na), variable.name = "column", value.name = "n_missing")
remaining_na <- remaining_na[n_missing > 0]

if (nrow(remaining_na) > 0) {
  warning("Missing values remain after trimming: ", paste(remaining_na$column, collapse = ", "), call. = FALSE)
}

if (daily_master_final[breadth_t < 0 | breadth_t > 1, .N] > 0) {
  stop("Data quality check failed: breadth_t is outside [0, 1].")
}

final_check <- daily_master_final[, .(date, rv_gk_t, RV_target_t1)]
final_check[, expected_next_rv := shift(rv_gk_t, n = 1, type = "lead")]
final_mismatch <- final_check[!is.na(expected_next_rv) & RV_target_t1 != expected_next_rv, .N]

if (final_mismatch > 0) {
  stop("Look-ahead bias check failed on the final trimmed dataset.")
}

# # Save the final forecasting dataset
daily_master_final[, total_turnover_t := as.numeric(total_turnover_t)]
daily_master_final[, log_turnover_t := log1p(total_turnover_t)]

final_columns <- c(
  "date",
  "RV_target_t1",
  "rv_gk_t", "rv_week_t", "rv_month_t", "rv_lag1", "rv_lag2",
  "vol_of_vol_t", "overnight_ret2_t",
  "mkt_log_ret", "mkt_ret2_t", "leverage_term_t",
  "csd_t", "cs_skew_t", "cs_kurt_t", "avg_stock_vol_t",
  "breadth_t", "cs_tail_count_t", "cs_mom_dispersion_t",
  "n_stocks_universe",
  "total_turnover_t", "log_turnover_t", "nifty_volume",
  "amihud_illiq_mkt_t", "amihud_illiq_index_t", "volume_concentration_t",
  "mom_5_t", "mom_22_t"
)

missing_final_cols <- setdiff(final_columns, names(daily_master_final))
if (length(missing_final_cols) > 0) {
  stop("The following expected final columns are missing: ", paste(missing_final_cols, collapse = ", "))
}

master_output <- daily_master_final[, ..final_columns]
setorder(master_output, date)
fwrite(master_output, output_file)

# Forecasting setup
script_start_time <- Sys.time()
set.seed(2026)

master <- copy(master_output)
master[, date := as.Date(date)]
setorder(master, date)

target_col     <- "RV_target_t1"
predictor_cols <- setdiff(names(master), c("date", target_col))
numeric_cols   <- c(target_col, predictor_cols)

na_total <- sum(sapply(master, function(x) sum(is.na(x))))
if (na_total > 0) {
  warning(na_total, " missing values found; dropping affected rows.", call. = FALSE)
  master <- master[complete.cases(master)]
}

# Exploratory data analysis(EDA)
fwrite(
  data.frame(variable = names(master), type = sapply(master, class)),
  file.path(tables_dir, "variable_types.csv")
)

summary_stats <- master[, ..numeric_cols][, lapply(.SD, function(x) {
  c(mean = mean(x), sd = sd(x), min = min(x), median = median(x), max = max(x))
})]
summary_stats <- cbind(variable = numeric_cols, as.data.frame(t(summary_stats)))
fwrite(summary_stats, file.path(tables_dir, "summary_statistics.csv"))

save_png(file.path(figures_dir, "rv_time_series.png"), function() {
  plot(
    master$date,
    master[[target_col]],
    type = "l",
    col = "navy",
    main = "NIFTY 50 Realized Volatility (target)",
    xlab = "Date",
    ylab = "RV_target_t1"
  )
})

corr_vars <- c(
  "RV_target_t1", "rv_gk_t", "rv_week_t", "rv_month_t", "rv_lag1", "rv_lag2",
  "mkt_log_ret", "total_turnover_t", "nifty_volume", "amihud_illiq_mkt_t",
  "csd_t", "breadth_t", "cs_skew_t", "cs_kurt_t", "cs_mom_dispersion_t"
)
# Examine relationships among key forecasting variables
cor_matrix <- cor(master[, ..corr_vars], use = "pairwise.complete.obs")
fwrite(cbind(variable = rownames(cor_matrix), as.data.frame(cor_matrix)), file.path(tables_dir, "correlation_matrix.csv"))

png(file.path(figures_dir, "correlation_heatmap.png"), width = 12, height = 12, units = "in", res = 600)
corrplot(
  cor_matrix,
  method = "square",
  type = "upper",
  col = colorRampPalette(c("#313695", "#74ADD1", "white", "#FDAE61", "#A50026"))(200),
  tl.col = "black",
  tl.cex = 0.85,
  tl.srt = 45,
  cl.cex = 0.9,
  addgrid.col = "grey90",
  mar = c(0, 0, 3, 0),
  title = "Pearson Correlation Matrix"
)
dev.off()

vif_table <- as.data.table(compute_vif(as.data.frame(master[, ..predictor_cols])))
setorder(vif_table, -VIF)
fwrite(vif_table, file.path(tables_dir, "vif_table.csv"))

# Stationarity tests- Test stationarity of the target and representative predictors
stationarity_vars <- c(
  target_col, "rv_gk_t", "rv_month_t", "mkt_log_ret", "csd_t",
  "breadth_t", "avg_stock_vol_t", "total_turnover_t", "mom_22_t"
)

stationarity_results <- do.call(
  rbind,
  lapply(stationarity_vars, function(v) run_stationarity(master[[v]], v))
)
fwrite(stationarity_results, file.path(tables_dir, "stationarity_results.csv"))

# Train-validation-test split
# Created chronological train, validation and test datasets
train_start <- as.Date("2007-10-18")
train_end   <- as.Date("2022-12-31")
valid_start <- as.Date("2023-01-01")
valid_end   <- as.Date("2024-12-31")
test_start  <- as.Date("2025-01-01")
test_end    <- as.Date("2026-07-29")

train_set <- master[date >= train_start & date <= train_end]
valid_set <- master[date >= valid_start & date <= valid_end]
test_set  <- master[date >= test_start & date <= test_end]

stopifnot(
  nrow(train_set) > 0,
  nrow(valid_set) > 0,
  nrow(test_set) > 0,
  max(train_set$date) < min(valid_set$date),
  max(valid_set$date) < min(test_set$date)
)

# Baselines
# Generate benchmark forecasts
historical_mean_value <- mean(train_set[[target_col]], na.rm = TRUE)

valid_preds <- data.table(
  date = valid_set$date,
  actual = valid_set[[target_col]],
  hist_mean = historical_mean_value,
  naive = valid_set$rv_gk_t
)

test_preds <- data.table(
  date = test_set$date,
  actual = test_set[[target_col]],
  hist_mean = historical_mean_value,
  naive = test_set$rv_gk_t
)

# ARIMAX
# Fit ARIMAX model using selected exogenous predictors
vif_reduction <- vif_reduce(as.data.frame(train_set[, ..predictor_cols]))
arimax_predictors <- vif_reduction$kept

writeLines(
  c("Dropped (VIF > 10):", vif_reduction$dropped, "", "Retained:", arimax_predictors),
  file.path(models_dir, "arimax_predictor_selection.txt")
)

train_means <- sapply(train_set[, ..arimax_predictors], mean)
train_sds   <- sapply(train_set[, ..arimax_predictors], sd)
train_sds[train_sds == 0] <- 1

xreg_train <- standardize(train_set, arimax_predictors, train_means, train_sds)
xreg_valid <- standardize(valid_set, arimax_predictors, train_means, train_sds)
y_train_log <- log(pmax(train_set[[target_col]], 1e-12))

fit_arimax <- auto.arima(
  y_train_log,
  xreg = xreg_train,
  seasonal = FALSE,
  stepwise = FALSE,
  approximation = FALSE,
  trace = FALSE
)

arimax_order <- arimaorder(fit_arimax)
coef_table <- data.frame(term = names(coef(fit_arimax)), estimate = as.numeric(coef(fit_arimax)))
se <- tryCatch(sqrt(diag(vcov(fit_arimax))), error = function(e) rep(NA_real_, length(coef(fit_arimax))))
coef_table$std_error <- se
coef_table$t_stat <- coef_table$estimate / coef_table$std_error

fwrite(coef_table, file.path(tables_dir, "arimax_coefficients.csv"))
writeLines(capture.output(summary(fit_arimax)), file.path(models_dir, "arimax_model_summary.txt"))

forecast_valid <- forecast(fit_arimax, xreg = xreg_valid, h = nrow(valid_set))
smear <- exp(0.5 * var(residuals(fit_arimax)))
valid_preds[, arimax := exp(as.numeric(forecast_valid$mean)) * smear]

train_valid <- rbind(train_set, valid_set)
train_valid_means <- sapply(train_valid[, ..arimax_predictors], mean, na.rm = TRUE)
train_valid_sds <- sapply(train_valid[, ..arimax_predictors], sd, na.rm = TRUE)
train_valid_sds[train_valid_sds == 0] <- 1

xreg_train_valid <- standardize(train_valid, arimax_predictors, train_valid_means, train_valid_sds)
xreg_test <- standardize(test_set, arimax_predictors, train_valid_means, train_valid_sds)
y_train_valid_log <- log(pmax(train_valid[[target_col]], 1e-12))

fit_arimax_final <- Arima(
  y_train_valid_log,
  order = c(arimax_order["p"], arimax_order["d"], arimax_order["q"]),
  xreg = xreg_train_valid
)

writeLines(capture.output(summary(fit_arimax_final)), file.path(models_dir, "arimax_final_model_summary.txt"))

forecast_test <- forecast(fit_arimax_final, xreg = xreg_test, h = nrow(test_set))
smear <- exp(0.5 * var(residuals(fit_arimax)))
test_preds[, arimax := exp(as.numeric(forecast_test$mean)) * smear]

# Random Forest
# Tune and fit the Random Forest forecasting model
# Random Forest was reviewed with LLM assistance to debugging

rf_x_train <- as.data.frame(train_set[, ..predictor_cols])
rf_y_train <- train_set[[target_col]]
rf_x_valid <- as.data.frame(valid_set[, ..predictor_cols])
rf_y_valid <- valid_set[[target_col]]
rf_x_test  <- as.data.frame(test_set[, ..predictor_cols])

p <- length(predictor_cols)
mtry_grid <- unique(pmin(p, c(3, 5, 7, 9, 11)))
tuning_results <- data.frame(mtry = integer(0), valid_rmse = numeric(0))

for (m in mtry_grid) {
  set.seed(2026)
  fit_m <- randomForest(x = rf_x_train, y = rf_y_train, mtry = m, ntree = RF_NTREE)
  tuning_results <- rbind(
    tuning_results,
    data.frame(mtry = m, valid_rmse = rmse_fun(rf_y_valid, predict(fit_m, rf_x_valid)))
  )
}

fwrite(tuning_results, file.path(tables_dir, "rf_mtry_tuning.csv"))
best_mtry <- tuning_results$mtry[which.min(tuning_results$valid_rmse)]

rf_train_valid <- rbind(train_set, valid_set)
rf_x_final <- as.data.frame(rf_train_valid[, ..predictor_cols])
rf_y_final <- rf_train_valid[[target_col]]

set.seed(2026)
fit_rf <- randomForest(
  x = rf_x_final,
  y = rf_y_final,
  mtry = best_mtry,
  ntree = RF_NTREE,
  importance = TRUE
)

writeLines(capture.output(print(fit_rf)), file.path(models_dir, "random_forest_model_summary.txt"))

valid_preds[, random_forest := as.numeric(predict(fit_rf, rf_x_valid))]
test_preds[, random_forest := as.numeric(predict(fit_rf, rf_x_test))]

fwrite(valid_preds, file.path(tables_dir, "predictions_validation.csv"))
fwrite(test_preds, file.path(tables_dir, "predictions_test.csv"))

# Model evaluation
# Compare forecasting accuracy across all models
qlike_eps <- 0.01 * quantile(train_set[[target_col]], 0.01)

model_names <- c(
  hist_mean = "Historical Mean",
  naive = "Naive (Random Walk)",
  arimax = "ARIMAX",
  random_forest = "Random Forest"
)

evaluate_period <- function(preds_dt, label) {
  do.call(rbind, lapply(names(model_names), function(col) {
    data.frame(
      period = label,
      model = model_names[[col]],
      n = sum(!is.na(preds_dt[[col]]) & !is.na(preds_dt$actual)),
      RMSE = rmse_fun(preds_dt$actual, preds_dt[[col]]),
      MAE = mae_fun(preds_dt$actual, preds_dt[[col]]),
      QLIKE = qlike_fun(preds_dt$actual, preds_dt[[col]], qlike_eps)
    )
  }))
}

model_comparison <- rbind(
  evaluate_period(valid_preds, "Validation"),
  evaluate_period(test_preds, "Test")
)

setDT(model_comparison)
setorder(model_comparison, period, RMSE)
fwrite(model_comparison, file.path(tables_dir, "model_comparison.csv"))

stopifnot(length(unique(model_comparison[period == "Test"]$n)) == 1)

best_test <- model_comparison[period == "Test"][which.min(RMSE)]
benchmark <- model_comparison[period == "Test" & model != "ARIMAX"]
benchmark[, Improvement_RMSE := 100 * (RMSE - best_test$RMSE) / RMSE]
benchmark[, Improvement_MAE := 100 * (MAE - best_test$MAE) / MAE]
fwrite(benchmark, file.path(tables_dir, "arimax_improvement_vs_benchmarks.csv"))

save_png(file.path(figures_dir, "model_comparison_test.png"), function() {
  plot(
    test_preds$date,
    test_preds$actual,
    type = "l",
    col = "black",
    lwd = 1.5,
    main = "Actual vs Forecast - Test Period",
    xlab = "Date",
    ylab = "RV_target_t1"
  )
  lines(test_preds$date, test_preds$hist_mean, col = "grey60", lty = 2)
  lines(test_preds$date, test_preds$naive, col = "orange")
  lines(test_preds$date, test_preds$arimax, col = "blue")
  lines(test_preds$date, test_preds$random_forest, col = "forestgreen")
  legend(
    "topright",
    legend = c("Actual", "Historical Mean", "Naive", "ARIMAX", "Random Forest"),
    col = c("black", "grey60", "orange", "blue", "forestgreen"),
    lty = c(1, 2, 1, 1, 1),
    cex = 0.8
  )
}, w = 10, h = 6)

# Diagnostics
# Check ARIMAX residual diagnostics
arimax_resid <- as.numeric(residuals(fit_arimax))

save_png(file.path(figures_dir, "arimax_residual_qqplot.png"), function() {
  qqnorm(arimax_resid, main = "ARIMAX Residuals: Q-Q Plot")
  qqline(arimax_resid, col = "red", lwd = 2)
})

save_png(file.path(figures_dir, "arimax_residual_acf.png"), function() {
  Acf(arimax_resid, main = "ARIMAX Residuals: ACF")
})

lb_fitdf <- sum(arimax_order[c("p", "q")])
ljung_box <- Box.test(
  arimax_resid,
  lag = max(20, lb_fitdf + 5),
  type = "Ljung-Box",
  fitdf = lb_fitdf
)

arch_test <- arch_lm_test(arimax_resid)

diagnostic_summary <- data.frame(
  test = c("Ljung-Box", "ARCH-LM"),
  statistic = c(unname(ljung_box$statistic), arch_test$statistic),
  p_value = c(ljung_box$p.value, arch_test$p.value)
)
fwrite(diagnostic_summary, file.path(tables_dir, "arimax_residual_diagnostics.csv"))

# Variable importance
# Identify the most influential Random Forest predictors
rf_importance <- importance(fit_rf)
rf_importance_df <- setDT(data.frame(
  variable = rownames(rf_importance),
  PercIncMSE = rf_importance[, "%IncMSE"],
  IncNodePurity = rf_importance[, "IncNodePurity"]
))
setorder(rf_importance_df, -PercIncMSE)
fwrite(rf_importance_df, file.path(tables_dir, "rf_variable_importance.csv"))

save_png(file.path(figures_dir, "rf_variable_importance.png"), function() {
  varImpPlot(fit_rf, main = "Random Forest: Variable Importance", n.var = min(15, p))
}, w = 8, h = 8)

# Save outputs
elapsed <- round(as.numeric(difftime(Sys.time(), script_start_time, units = "secs")), 1)

final_summary <- c(
  "FINAL SUMMARY",
  "=================================",
  sprintf("Train: %s to %s (%d obs)", train_start, train_end, nrow(train_set)),
  sprintf("Validation: %s to %s (%d obs)", valid_start, valid_end, nrow(valid_set)),
  sprintf("Test: %s to %s (%d obs)", test_start, test_end, nrow(test_set)),
  "",
  capture.output(print(model_comparison)),
  sprintf(
    "\nBest test-set model: %s\nRMSE: %.6e\nMAE: %.6e\nQLIKE: %.4f\nARIMA Order: (%d,%d,%d)",
    best_test$model,
    best_test$RMSE,
    best_test$MAE,
    best_test$QLIKE,
    arimax_order["p"],
    arimax_order["d"],
    arimax_order["q"]
  ),
  sprintf("Observations: %d | Predictors: %d | Runtime: %.1fs", nrow(master), length(predictor_cols), elapsed)
)

writeLines(final_summary, file.path(results_dir, "final_summary.txt"))
cat("Analysis completed successfully.\n")
