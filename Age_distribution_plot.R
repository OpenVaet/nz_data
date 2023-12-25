# nzd is SK data
# nzda is SK age data distribution
# und is UN data distribution
# sk_age is SK data age distribution

nzd  <- read.csv("data/nzwb_dob_removed.csv.gz")
und  <- read.csv("data/nz_2021_june_census.csv")
nzda <- read.csv("nz_analysis/nzwb_age_distribution.csv")

countby <- function(x, levelsvector) {
  tapply(x, as.factor(levelsvector), length)
}

sk_age <- as.vector(
  c(
    countby(nzd$age, nzd$age)[1:89],
    sum(countby(nzd$age, nzd$age)[90:110])
  )
)

par(mfrow = c(1, 2))
mp <- barplot(
  sk_age,
  ylim = c(0, 100000),
  main = "SK data - vaccine dose by age",
  yaxt = "n",
  xaxt = "n",
  ylab = "Vaccine doses 000's",
  xlab = "Age"
)
axis(1, at = mp[c(1, 21, 41, 61, 81, 90)], labels = c(1, 21, 41, 61, 81, 90))
axis(2, at = seq(0, 100000, by = 20000), labels = seq(0, 10, by = 2))

mp <- barplot(
  und$count,
  ylim = c(0, 100000),
  main = "NZ data - NZ population by age",
  yaxt = "n",
  xaxt = "n",
  ylab = "Population 000's",
  xlab = "Age"
)
axis(1, at = mp[c(1, 21, 41, 61, 81, 90)], labels = c(1, 21, 41, 61, 81, 90))
axis(2, at = seq(0, 100000, by = 20000), labels = seq(0, 10, by = 2))

nm <- sum(und$count) / sum(nzda$count)
mp <- barplot(
  und$count,
  ylim = c(0, 100000),
  main = "NZ population by age (bars, NZ data) compared to NZWB data set distribution (red line)",
  yaxt = "n",
  xaxt = "n",
  ylab = "Population 000's",
  xlab = "Age"
)
axis(1, at = mp[c(1, 21, 41, 61, 81, 90)], labels = c(1, 21, 41, 61, 81, 90))
axis(2, at = seq(0, 100000, by = 20000), labels = seq(0, 10, by = 2))
lines(mp, nzda$count * nm, col = "red", lwd = 2)

ks.test(sk_age, und$count)

# end of age plot