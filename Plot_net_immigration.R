# Load necessary libraries
library(ggplot2)

# Read the CSV file into a dataframe
immigration_data <- read.csv("data/2019_2023_immi_by_oia_age_groups_data.csv")

# Cast the Year column to a factor for better plotting
immigration_data$Year <- as.factor(immigration_data$Year)

# Plot the data using ggplot
ggplot(data = immigration_data, aes(x = Year, y = Net.Immigration, group = `Age.Group`, color = `Age.Group`)) +
  geom_line(size = 1.3) + 
  geom_point() +
  geom_text(aes(label = Net.Immigration), vjust = -0.5, size = 3) +
  labs(title = "New Zealand - Net Immigration by Age Group (2019-2023)",
       x = "Year",
       y = "Net Immigration",
       color = "Age Group") +
  theme_minimal() +
  theme(legend.position = "bottom")