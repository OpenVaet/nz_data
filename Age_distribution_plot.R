# nzd is SK data
# nzda is SK age data distribution
# und is UN data distribution
# sk_age is SK data age distribution

nzd  <- read.csv("data/nzwb_dob_removed.csv.gz")
und  <- read.csv("UN_NZ_2022.csv")
nzda <- read.csv("SK_NZ_age.csv")

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
  und$Value,
  ylim = c(0, 100000),
  main = "UN data - NZ population by age",
  yaxt = "n",
  xaxt = "n",
  ylab = "Population 000's",
  xlab = "Age"
)
axis(1, at = mp[c(1, 21, 41, 61, 81, 90)], labels = c(1, 21, 41, 61, 81, 90))
axis(2, at = seq(0, 100000, by = 20000), labels = seq(0, 10, by = 2))

nm <- sum(und$Value) / sum(nzda$count)
mp <- barplot(
  und$Value,
  ylim = c(0, 100000),
  main = "NZ population by age (bars, UN data) compared to NZ MOAR data set distribution (red line)",
  yaxt = "n",
  xaxt = "n",
  ylab = "Population 000's",
  xlab = "Age"
)
axis(1, at = mp[c(1, 21, 41, 61, 81, 90)], labels = c(1, 21, 41, 61, 81, 90))
axis(2, at = seq(0, 100000, by = 20000), labels = seq(0, 10, by = 2))
lines(mp, nzda$count * nm, col = "red", lwd = 2)

ks.test(sk_age, und$Value)

# end of age plot