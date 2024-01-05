# nzd is NZWB data
# und is NZ population data distribution

und <- read.csv("data/nz_2021_june_census.csv")
print(und)
nzd <- read.csv("data/nzwb_dob_removed_50_plus.csv.gz")

# Run for one dose only
one_dose_mrn <- unique(nzd$mrn[nzd$dose_number == 1 & nzd$age >= 50]) # List of unique MRNs with dose 1 recorded and age above or equal 50.
length(one_dose_mrn) # 313744

all_dates_copy <- all_dates # Copy all_dates
death_dates_copy <- death_dates # Copy death_dates

all_dates <- all_dates[match(one_dose_mrn, all_dates$mrn),] # Make subset of all_dates

death_dates_1d <- death_dates[match(one_dose_mrn, death_dates$mrn),]
death_dates_1d <- death_dates_1d[!is.na(death_dates_1d$mrn),]
death_dates <- death_dates_1d # Make subset of death_dates
rm(death_dates_1d)

mort_by_date <- rep(0, 933)

for (ct in 1:nrow(all_dates)) {
  start <- as.numeric(as.Date(all_dates$min_date[ct]) - as.Date("2021-01-01") + 1)
  end <- as.numeric(as.Date(all_dates$max_date[ct]) - as.Date("2021-01-01") + 1)
  agcol <- match(ages$grp[all_dates$age[ct] + 1], colnames(mort))
  all_dates$mortality[ct] <- sum(mort[start:end, agcol])
  
  # Add the mortality by date to the mort_by_date vector
  mort_day <- rep(0, 933)
  mort_day[(start - 97):(end - 97)] <- mort[start:end, agcol]
  mort_by_date <- mort_by_date + mort_day
}

temp <- data.frame(mort_by_date, as.Date("2021-04-07") + 1:933, 0)
colnames(temp) <- c("mortality", "date", "week")
temp$week <- as.integer((temp$date - as.Date("2021-04-07")) / 7)

death_dates <- data.frame(death_dates, 0)
colnames(death_dates) <- c("mrn", "date", "week")
death_dates$week <- as.integer(as.numeric(death_dates$date - as.Date("2021-04-07")) / 7)

# Full date range barplot
barplot(aggregate(mortality ~ week, data = temp, FUN = sum)$mortality, main = "Expected vs Actual deaths for the NZWB 50+ with Dose 1 vaccine cohort")

# Restricted date range barplot excluding last 5 weeks
# Set up the graphical parameters to increase font size
par(mar = c(5, 8, 4, 2) + 0.3, cex.main = 1.2, cex.axis = 1.1, cex.lab = 1.1)

# Calculate the mortality sums for the barplot
mortality_sums <- as.integer(aggregate(mortality ~ week, data = temp, FUN = sum)$mortality + 0.5)[1:125]

# Calculate the ylim dynamically to ensure the title and bars do not overlap
max_mortality <- max(mortality_sums)
ylim_upper <- max_mortality * 1.2

# Create the barplot for expected mortality
barplot(mortality_sums,
        main = "Expected vs Actual deaths for the NZWB 50+ with Dose 1 vaccine cohort",
        ylim = c(0, ylim_upper),
        xlab = "Week", # Label for the x-axis
        col = "blue")

# Overlay the actual deaths barplot
actual_deaths <- countby(death_dates$week, death_dates$week)[1:125]
barplot(actual_deaths, col = "#90EE90", add = TRUE)

# Add a legend to the plot
legend("topright", 
       legend = c("Expected Deaths", "Actual Deaths"), 
       fill = c("blue", "#90EE90"), 
       cex = 0.8)

# Reset graphical parameters
par(mar = c(5, 4, 4, 2), cex.main = 1, cex.axis = 1, cex.lab = 1)


