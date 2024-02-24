# Loads the necessary library for data manipulation
library(dplyr)

# Reads the data from the CSV file into a dataframe
data <- read.csv('data/monthly_death_rates_ever_never_vaccinated.csv')

# Filters data for Age Group 21-40 & 41-60
filtered_data <- data %>%
  filter(Age.Group %in% c("21-40", "41-60"))

compute_miscategorization_rate <- function(df) {
  # We want equal death rates per 10,000 for both groups
  total_deaths <- df$Deaths.ever.vaccinated + df$Deaths.never.vaccinated
  combined_population <- df$Ever.Vaccinated + df$Never.Vaccinated
  target_death_rate <- total_deaths / combined_population * 10000
  
  # Calculates the number of deaths required for the target death rate in each group
  deaths_required_ever_vaccinated <- target_death_rate * df$Ever.Vaccinated / 10000
  deaths_required_never_vaccinated <- target_death_rate * df$Never.Vaccinated / 10000
  
  # Calculates the miscategorization rate as the absolute difference between actual and required deaths, divided by the total deaths
  miscategorized_ever_vaccinated <- abs(deaths_required_ever_vaccinated - df$Deaths.ever.vaccinated)
  miscategorized_never_vaccinated <- abs(deaths_required_never_vaccinated - df$Deaths.never.vaccinated)
  
  miscategorization_rate <- (miscategorized_ever_vaccinated + miscategorized_never_vaccinated) / total_deaths
  return(miscategorization_rate)
}

# Applies the function to each month between 2021-05 and 2022-01 (included)
months_to_analyze <- seq(from = as.Date("2021-05-01"), to = as.Date("2022-01-31"), by = "month")
months_to_analyze <- format(months_to_analyze, "%Y-%m")

# Initializes a vector to store miscategorization rates
miscategorization_rates <- c()

for (month in months_to_analyze) {
  monthly_data <- filtered_data %>%
    filter(`Year.Month` == month)
  monthly_rate <- compute_miscategorization_rate(monthly_data)
  miscategorization_rates <- c(miscategorization_rates, monthly_rate)
}

# Calculates the average, min, max, q1, q2 (which is median) of miscategorization rate
miscategorization_summary <- summary(miscategorization_rates)
list(
  average = mean(miscategorization_rates),
  min = min(miscategorization_rates),
  max = max(miscategorization_rates),
  q1 = miscategorization_summary[2], # First quartile
  q2 = miscategorization_summary[3]  # Median
)