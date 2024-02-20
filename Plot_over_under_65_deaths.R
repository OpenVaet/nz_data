library(ggplot2)
library(dplyr)
data <- read.csv("data/over_under_65_deaths.csv")
data$age_group <- factor(data$age_group, levels = c("65+", "Under 65"))
data <- data %>%
  arrange(year, month, age_group) %>%
  group_by(year, month) %>%
  mutate(cum_count = cumsum(count))
data$year_month <- with(data, paste(year, sprintf("%02d", month), sep = "-"))
breaks <- data$year_month[seq(1, length(data$year_month), by = 12)]
ggplot(data, aes(x = year_month, y = count, fill = age_group)) +
  geom_col(position = "dodge") +
  scale_x_discrete(breaks = breaks) +
  scale_fill_manual(values = c("65+" = "red", "Under 65" = "blue")) +
  labs(
    title = "New-Zealand - Deaths under age 65 & 65+",
    x = "Year-Month",
    y = "Total Count",
    fill = "Age Group"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1, vjust = 1),
    plot.title = element_text(hjust = 0.5)
  ) +
  guides(fill = guide_legend(reverse = FALSE))
ggsave("total_column_chart_with_title.png", width = 12, height = 8)
