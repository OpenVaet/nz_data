# Load necessary libraries
library(ggplot2)
library(scales) # Ensure this library is loaded for the scales::comma function

# Read the data from the CSV file
data <- read.csv("deaths_and_first_doses_by_weeks_2020_2023.csv", header = TRUE)

# Find the maximum value for cohort_doses_administered to scale the secondary y-axis accordingly
max_cohort_doses_administered <- max(data$cohort_doses_administered)
max_deaths <- max(data$cohort_deaths)
scaling_factor <- max_deaths / max_cohort_doses_administered

# Create a sequence of breaks every 20 weeks
breaks <- data$week_num[seq(1, nrow(data), by = 3)]
labels <- data$year_week[seq(1, nrow(data), by = 3)]

# Create the line plot with two y-axes and custom x-axis labels
ggplot(data, aes(x = week_num)) + 
  geom_line(aes(y = cohort_deaths, group = 1), colour = "black", size = 1.5) +
  geom_line(aes(y = cohort_doses_administered * scaling_factor, group = 2), colour = "red", size = 1.5) +
  scale_y_continuous(
    "Cohort Deaths",
    labels = scales::comma,
    sec.axis = sec_axis(~./scaling_factor, name = "Cohort Doses Administered", labels = scales::comma)
  ) +
  scale_x_continuous(
    "Week Number",
    breaks = breaks,
    labels = labels
  ) +
  labs(title = "Deaths & Doses 1 in NZWB 50+ Dose 1 by Week Number") +
  theme_minimal() +
  theme(
    axis.title.y.right = element_text(color = "red", size = 12),
    axis.text.y.right = element_text(color = "red", size = 10),
    axis.title.y.left = element_text(color = "black", size = 12),
    axis.text.y.left = element_text(color = "black", size = 10),
    axis.title.x = element_text(size = 12),
    axis.text.x = element_text(angle = 90, hjust = 1, size = 10),
    legend.text = element_text(size = 10),
    legend.title = element_text(size = 12)
  )

