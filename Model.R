# nzd is NZWB data
# und is NZ population data distribution

und  <- read.csv("data/nz_2021_june_census.csv")
print(und)
nzd  <- read.csv("data/nzwb_dob_removed.csv.gz")

##==========================================

### Start of modelling of cohort's daily death rate

# Earliest registered date for each person
min_dates <- aggregate(as.Date(nzd$date_time_of_service, "%Y-%m-%d") ~ mrn, data = nzd, FUN = min)

# Earliest registered date of death for any person with a date of death
death_dates <- aggregate(as.Date(nzd$date_of_death, "%Y-%m-%d") ~ mrn, data = nzd, FUN = min)

# Minimum age for each person
min_age <- aggregate(age ~ mrn, data = nzd, FUN = min)

# Defines 'right' function
right = function (string, char) {
  substr(string,nchar(string)-(char-1),nchar(string))
}

monthly_deaths <- read.csv("data/nz_2021_2023_deaths.csv")
mort <- data.frame(matrix(ncol = 21, nrow = length(seq(as.Date("2021-01-01"), as.Date("2023-09-30"), by = "day"))))
colnames(mort) <- c("Date", sort(unique(monthly_deaths$age_group)))
mort$Date <- seq(as.Date("2021-01-01"), as.Date("2023-09-30"), by = "day")
dm <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

### Build a file from first day of series to 30th Oct 2023 containing the daily death rate for each age group
for (yr in unique(monthly_deaths$year)) {
  for (mt in unique(monthly_deaths$month)) {
    for (ag in unique(monthly_deaths$age_group)) {
      if (length(monthly_deaths[monthly_deaths$year == yr & monthly_deaths$month == mt & monthly_deaths$age_group == ag, 1]) > 0) {
        mort[substr(mort$Date,1,7)==paste0(yr,"-",right(paste0("0",mt),2)),match(ag,colnames(mort))] <-
          monthly_deaths[monthly_deaths$year==yr & monthly_deaths$month==mt & monthly_deaths$age_group==ag,4]/dm[mt]
      }
    }
  }
}


mort[is.na(mort)] <- 0
colnames(mort)[21] <- "90+"
print(mort)

## Create all_dates matrix for each participant containing start and end date
all_dates <- cbind(min_dates, min_age[, 2], as.Date("2023-09-30"))
colnames(all_dates) <- c("mrn", "min_date", "age", "max_date")
all_dates$max_date[death_dates$mrn + 1] <- death_dates[, 2]
all_dates <- cbind(all_dates, all_dates$max_date - all_dates$min_date, 0)
colnames(all_dates)[5:6] <- c("exp_days", "mortality")
# Convert ages above 90 to 90
all_dates$age <- ifelse(all_dates$age > 90, 90, all_dates$age)

print(all_dates)

## Create ages matrix to match age to age group
a <- colnames(mort)[2:21]
ages <- data.frame(matrix(ncol = 2, nrow = 91))
colnames(ages) <- c("age", "grp")
ages$age <- 0:90 
ages$grp[1] <- a[1]
ages$grp[2:5] <- a[2]
ages$grp[6:90] <- a[as.integer((0:84) / 5) + 3] 
ages$grp[91] <- "90+" 
ages$age[91] <- "90+"
print(ages)

## Make data frame for the NZ population data by age group and calculate the totals
undg <- data.frame(und$age, und$count, ages$grp[match(und$age, ages$age)])
colnames(undg) <- c("Age", "Count", "Group")
print(undg)
und_totals <- aggregate(Count ~ Group, data = undg, FUN = sum)$Count
print(und_totals)

## Nullify 00_00 column from mort
mort[, 2] <- 0
print(mort)

## Divide the total daily mortality for all groups by their group population totals
for (ct in 1:19) {
  mort[, ct + 2] <- mort[, ct + 2] / und_totals[ct]
}
print(mort)

###start the iteration
###for each row of the 2.2m unique participant rows
###find the start date and end date of the study for that participant
###check the age group
###add the daily mortality risks for all days in the study for that participant
###for that age group

###make a mortality counter by date
#mort_by_date<-matrix(0,nrow=903,ncol=1)
mort_by_date<-seq_len(903)*0


cpt <- 0
current <- 0
for (ct in 1:(dim(all_dates)[1])) {
  cpt <- cpt + 1
  current <- current + 1
  if (cpt == 100) {
    cpt <- 0
    print(paste('Processing ', current, '/', nrow(all_dates)))
  }
  start<-as.numeric(as.Date(all_dates$min_date[ct])-as.Date("2021-01-01")+1)
  end<-as.numeric(as.Date(all_dates$max_date[ct])-as.Date("2021-01-01")+1)
  agcol<-match(ages$grp[all_dates$age[ct]+1],colnames(mort))
  all_dates$mortality[ct]<-sum(mort[start:end,agcol])

  ##add the mortality by date to the mort_by_date vector
  mort_day<-seq_len(903)*0
  mort_day[(start-97):(end-97)]<-mort[start:end,agcol]
  mort_by_date<-mort_by_date+mort_day
}

write.csv(mort_by_date,"mort_by_date.csv")

temp<-data.frame(mort_by_date,as.Date("2021-04-07")+seq(1,933,1),0)
colnames(temp)<-c("mortality","date","week")
temp$week<-as.integer((temp$date-as.Date("2021-04-07"))/7)
barplot(aggregate(mortality~week, data=temp, FUN=sum)$mortality)
death_dates<-data.frame(death_dates,0)
colnames(death_dates)<-c("mrn","date","week")
death_dates$week<-as.integer(as.numeric(death_dates$date-as.Date("2021-04-07"))/7)
barplot(aggregate(mortality~week, data=temp, FUN=sum)$mortality)
barplot(countby(death_dates$week,death_dates$week),col="red",add=TRUE)

sum(as.integer(aggregate(mortality~week, data=temp, FUN=sum)$mortality+0.5)[1:125])
sum(countby(death_dates$week,death_dates$week)[1:125])
