library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(forecast)
library(nlme)

# Load the data
data <- read_csv("data/deaths_and_pop_by_months_and_ages.csv", col_types = cols())
print(data)

# Assuming that 'year' and 'month' columns are numeric
data <- data %>%
  mutate(
    date = as.Date(paste(year, month, "01", sep="-")), # Create a date column
    age_group = as.factor(age_group)
  )

# Convert the data to a ts object with frequency 12 for monthly data
data_ts <- ts(data$deaths, start=c(min(data$year), min(data$month)), frequency=12)

# Update the test_seasonality function to create a ts object for each subset
test_seasonality <- function(subset_data) {
  # Create a time series object for the subset of data
  subset_ts <- ts(subset_data$deaths, frequency=12)
  
  # Fit a linear model with Fourier terms for seasonality
  fit <- lm(deaths ~ population + fourier(subset_ts, K=4) + as.factor(month), data = subset_data)
  
  # Anova to test the significance of the Fourier terms
  anova_result <- anova(fit)
  print(anova_result)
  
  # Return the p-value for the Fourier terms
  p_value <- anova_result["fourier(subset_ts, K = 4)1", "Pr(>F)"]
  return(p_value)
}

# Apply the function to each age_group group and collect results
results <- data %>%
  group_by(age_group) %>%
  do(tibble(p_value = test_seasonality(.))) 

# Determine the age_group at which seasonality starts to have a significant impact
# (using a common significance level of 0.05)
significant_age_groups <- results %>%
  filter(p_value < 0.05) %>%
  arrange(p_value)

# Print the age_groups with significant seasonality
print(significant_age_groups)
