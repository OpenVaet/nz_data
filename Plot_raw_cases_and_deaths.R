# Load necessary libraries
library(ggplot2)

# Read the data from the CSV file
data <- read.csv("deaths_and_cases_by_weeks_2020_2023.csv", header = TRUE)

# Find the maximum value for cases to scale the secondary y-axis accordingly
max_cases <- max(data$cases_administered)
max_deaths <- max(data$deaths)
scaling_factor <- max_deaths / max_cases

# Create a sequence of breaks every 20 weeks
breaks <- data$week_num[seq(1, nrow(data), by = 3)]
labels <- data$year_week[seq(1, nrow(data), by = 3)]

# Create the line plot with two y-axes and custom x-axis labels
ggplot(data, aes(x = week_num)) + 
  geom_line(aes(y = deaths, group = 1), colour = "black") +
  geom_line(aes(y = cases_administered * scaling_factor, group = 2), colour = "red") +
  scale_y_continuous(
    "Deaths",
    sec.axis = sec_axis(~./scaling_factor, name = "Covid Cases")
  ) +
  scale_x_continuous(
    "Week Number",
    breaks = breaks,
    labels = labels
  ) +
  labs(title = "Covid-19 Cases and Deaths by Week Number") +
  theme_minimal() +
  theme(axis.title.y.right = element_text(color = "red"),
        axis.text.y.right = element_text(color = "red"),
        axis.title.y.left = element_text(color = "black"),
        axis.text.y.left = element_text(color = "black"),
        axis.text.x = element_text(angle = 90, hjust = 1)) # Rotate x labels for better readability
