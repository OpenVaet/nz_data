# Load necessary libraries
library(ggplot2)

# Read the data from the CSV file
data <- read.csv("deaths_and_first_doses_by_weeks_2020_2023.csv", header = TRUE)

# Find the maximum value for doses to scale the secondary y-axis accordingly
max_nz_doses <- max(data$nz_doses_administered)
max_cohort_doses <- max(data$cohort_doses_administered)
max_deaths <- max(c(data$nz_deaths, data$cohort_deaths))
scaling_factor_nz <- max_deaths / max_nz_doses
scaling_factor_cohort <- max_deaths / max_cohort_doses

# Create a sequence of breaks every 20 weeks
breaks <- data$week_num[seq(1, nrow(data), by = 3)]
labels <- data$year_week[seq(1, nrow(data), by = 3)]

# Create the line plot with two y-axes and custom x-axis labels
ggplot(data, aes(x = week_num)) + 
  geom_line(aes(y = nz_doses_administered * scaling_factor_nz, group = 2, colour = "NZ Doses Administered"), size = 1.5) +
  geom_line(aes(y = cohort_doses_administered * scaling_factor_cohort, group = 4, colour = "Cohort Doses Administered"), size = 1.5) +
  scale_y_continuous(
    "Cohort Doses Administered",
    labels = scales::comma
  ) +
  scale_x_continuous(
    "Week Number",
    breaks = breaks,
    labels = labels
  ) +
  labs(title = "Doses Administered in 50+ Sub-cohort & NZ by Week Number") +
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
  ) +
  scale_colour_manual(values = c("NZ Deaths" = "black", "NZ Doses Administered" = "red", "Cohort Deaths" = "blue", "Cohort Doses Administered" = "green")) +
  guides(colour = guide_legend(title = "Legend")) +
  scale_y_continuous(sec.axis = sec_axis(~./scaling_factor_nz, 
                                         name = "NZ Doses Administered",
                                         labels = scales::comma))
