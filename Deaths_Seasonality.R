library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(forecast)
library(nlme)

# Loads the data
data <- read_csv("data/deaths_and_pop_by_months_and_ages.csv", col_types = cols())
print(data)

# Converts the data to a ts object with frequency 12 for monthly data
data <- data %>%
  mutate(
    date = as.Date(paste(year, month, "01", sep="-")),
    age_group = as.factor(age_group)
  )
data_ts <- ts(data$deaths, start=c(min(data$year), min(data$month)), frequency=12)

test_seasonality <- function(subset_data) {
  # Creates a time series object for the subset of data
  subset_ts <- ts(subset_data$deaths, frequency=12)
  
  # Fits a linear model with Fourier terms for seasonality
  fit <- lm(deaths ~ population + fourier(subset_ts, K=4) + as.factor(month), data = subset_data)
  
  # Anova to test the significance of the Fourier terms
  anova_result <- anova(fit)
  print(anova_result)
  
  # Returns the p-value for the Fourier terms
  p_value <- anova_result["fourier(subset_ts, K = 4)1", "Pr(>F)"]
  return(p_value)
}

# Applies the function to each age_group group and collects results
results <- data %>%
  group_by(age_group) %>%
  do(tibble(p_value = test_seasonality(.))) 

# Determines the age_group at which seasonality starts to have a significant impact
# (using a significance level of 0.05)
significant_age_groups <- results %>%
  filter(p_value < 0.05) %>%
  arrange(p_value)

# Prints the age_groups with significant seasonality
print(significant_age_groups)
