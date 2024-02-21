# Loads necessary libraries
library(ggplot2)
library(scales) # For the comma function

# Reads the data from census
census_data <- read.csv("data/2010_2023_dec_census_data.csv")

# Plots the first dataset with a thicker line, point labels, and a title
p1 <- ggplot(census_data, aes(x = year, y = population)) +
  geom_line(size = 1) + # Increase line width
  geom_point(size = 3) + # Increase point size
  geom_text(aes(label = population), vjust = -1, size = 3) + # Add data labels
  scale_y_continuous(labels = comma, limits = c(0, max(census_data$population))) + # Use full number formatting for y-axis and start at 0
  scale_x_continuous(breaks = census_data$year) + # Set x-axis breaks to show integer years
  labs(title = "New Zealand - Population growth per December census data") + # Add chart title
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) # Adjust the angle and justification of x-axis labels

# Prints the plot
print(p1)

# Reads the data from the second CSV file
new_census_data <- read.csv("data/2010_2023_dec_natural_and_immi_vs_census_data.csv")
print(new_census_data)

# Plots the second dataset with two lines
p2 <- ggplot(new_census_data, aes(x = year)) +
  geom_line(aes(y = census.population, colour = "Census Population"), size = 1) +
  geom_line(aes(y = natural.growth.and.immigration.population, colour = "Natural Growth and Immigration Population"), size = 1.1) + 
  geom_text(aes(y = census.population, label = census.population), vjust = -1, size = 3) +
  scale_color_manual(values = c("Census Population" = "blue", "Natural Growth and Immigration Population" = "red"),
                     name = "") +
  scale_x_continuous(breaks = census_data$year) +
  scale_y_continuous(labels = comma, limits = c(0, max(new_census_data$census.population, new_census_data$natural.growth.and.immigration.population))) +
  labs(title = "New Zealand - Comparison of Census Population vs. Natural Growth and Immigration Population") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        legend.position = "bottom")

# Prints the plot
print(p2)

# Plots the yearly offset as a column chart
p3 <- ggplot(new_census_data, aes(x = year, y = offset, fill = year)) +
  geom_col() + # Create the column chart
  geom_text(aes(label = offset), vjust = -0.3, size = 3.5) + # Add data labels above the bars
  scale_x_continuous(breaks = new_census_data$year) + # Set x-axis breaks to show integer years
  scale_y_continuous(labels = comma) + # Use full number formatting for y-axis
  labs(title = "New Zealand - Yearly Offset in 2009 Census Population Data + Natural Growth + Net Immigration", x = "Year", y = "Offset") + # Add labels and title
  theme_minimal() + # Use a minimal theme
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) # Adjust the angle and justification of x-axis labels

# Print the column chart with values
print(p3)


