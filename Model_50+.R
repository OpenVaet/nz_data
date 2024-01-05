# nzd is NZWB data
# und is NZ population data distribution

und  <- read.csv("data/nz_2021_june_census.csv")
print(und)
nzd  <- read.csv("data/nzwb_dob_removed_50_plus.csv.gz")

# nzd is NZWB data
# und is NZ population data distribution

und  <- read.csv("data/nz_2021_june_census.csv")
print(und)
nzd  <- read.csv("data/nzwb_dob_removed_50_plus.csv.gz")

###run for one dose only 
####
####
one_dose_mrn<-(unique(nzd$mrn[nzd$dose_number==1])) ##list of unique mrns with dose 1 recorded
length(one_dose_mrn) ##966989
all_dates_copy<-all_dates ##copy all_dates
death_dates_copy<-death_dates ##copy death_dates
#min_age_copy<-min_age ##copy min_age
#min_dates_copy<-min_dates ##copy min_dates

all_dates<-all_dates[match(one_dose_mrn,all_dates$mrn),] #make subset of all_dates

death_dates_1d<-death_dates[match(one_dose_mrn,death_dates$mrn),]
death_dates_1d<-death_dates_1d[(!is.na(death_dates_1d$mrn)),]
death_dates<-death_dates_1d  #make subset of death_dates
rm(death_dates_1d)

#min_age<-(min_age[match(one_dose_mrn,min_age$mrn),])
#min_dates<-(min_dates[match(one_dose_mrn,min_dates$mrn),])


mort_by_date<-seq_len(933)*0

for (ct in 1:(dim(all_dates)[1])) {
  start<-as.numeric(as.Date(all_dates$min_date[ct])-as.Date("2021-01-01")+1)
  end<-as.numeric(as.Date(all_dates$max_date[ct])-as.Date("2021-01-01")+1)
  agcol<-match(ages$grp[all_dates$age[ct]+1],colnames(mort))
  all_dates$mortality[ct]<-sum(mort[start:end,agcol])
  
  ##add the mortality by date to the mort_by_date vector
  mort_day<-seq_len(933)*0
  mort_day[(start-97):(end-97)]<-mort[start:end,agcol]
  mort_by_date<-mort_by_date+mort_day
}

temp<-data.frame(mort_by_date,as.Date("2021-04-07")+seq(1,933,1),0)
colnames(temp)<-c("mortality","date","week")
temp$week<-as.integer((temp$date-as.Date("2021-04-07"))/7)
barplot(aggregate(mortality~week, data=temp, FUN=sum)$mortality)
death_dates<-data.frame(death_dates,0)
colnames(death_dates)<-c("mrn","date","week")
death_dates$week<-as.integer(as.numeric(death_dates$date-as.Date("2021-04-07"))/7)
##full date range barplot
#barplot(aggregate(mortality~week, data=temp, FUN=sum)$mortality)
#barplot(countby(death_dates$week,death_dates$week),col="red",add=TRUE)

##restricted date range barplot excluding last 5 weeks
barplot(as.integer(aggregate(mortality~week, data=temp, FUN=sum)$mortality+0.5)[1:125],main="Expected vs Actual deaths for the NZ vaccine cohort")
barplot(countby(death_dates$week,death_dates$week)[1:125],col="red",add=TRUE)

all_dates<-all_dates_copy
death_dates<-death_dates_copy
rm(all_dates_copy, death_dates_copy)




