# Parameters
event_rate <- 3 / 10000  # Expected event rate
power <- 0.9             # Desired power (90%)
alpha <- 0.05            # Significance level (5%)

# Calculate the required sample size
sample_size <- power.prop.test(p1 = event_rate, 
                               p2 = 0, 
                               power = power, 
                               sig.level = alpha, 
                               alternative = "one.sided")$n

# Print the result
cat("The estimated cohort size required to observe the events with desired power and significance level is:", ceiling(sample_size), "\n")