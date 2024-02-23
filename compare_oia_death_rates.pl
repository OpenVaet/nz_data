#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use Data::Printer;
use Data::Dumper;
use JSON;
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use Text::CSV qw( csv );
use Statistics::Descriptive;
use Statistics::LineFit;
use DateTime;
use DateTime::Format::ISO8601;
use FindBin;
use lib "$FindBin::Bin/../../lib";

my $oia_deaths_file   = 'raw_data/25021_Data_Attachment_1.csv'; # from https://fyi.org.nz/request/25021-number-of-covid19-vax-deaths-by-age-band-location-and-month#incoming-96520
my %oia_deaths        = ();
my %oia_yearly_deaths = ();
my %oia_age_groups    = ();

load_oia_deaths();

my %doses_by_dates = ();
load_doses_by_dates();

# For each year & month covered, 
# Calculating mortality rates.
my %monthly_death_rates = ();
calculate_monthly_rates();

open my $out, '>:utf8', 'data/monthly_death_rates_ever_never_vaccinated.csv';
say $out "Year,Month,Year Month,Age Group,Reference Doses Date,Ever Vaccinated,Never Vaccinated,Deaths ever vaccinated,Deaths never vaccinated,Deaths per 10000 ever vaccinated,Deaths per 10000 never vaccinated";
for my $year (sort{$a <=> $b} keys %monthly_death_rates) {
	for my $month (sort{$a <=> $b} keys %{$monthly_death_rates{$year}}) {
		for my $age_group (sort keys %{$monthly_death_rates{$year}->{$month}}) {
			my $reference_doses_date               = $monthly_death_rates{$year}->{$month}->{$age_group}->{'reference_doses_date'}               // die;
			my $ever_vaccinated                    = $monthly_death_rates{$year}->{$month}->{$age_group}->{'ever_vaccinated'}                    // die;
			my $never_vaccinated                   = $monthly_death_rates{$year}->{$month}->{$age_group}->{'never_vaccinated'}                   // die;
			my $deaths_ever_vaccinated             = $monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_ever_vaccinated'}             // die;
			my $deaths_never_vaccinated            = $monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_never_vaccinated'}            // die;
			my $deaths_per_10000_ever_vaccinated  = $monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_per_10000_ever_vaccinated'}  // die;
			my $deaths_per_10000_never_vaccinated = $monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_per_10000_never_vaccinated'} // die;
			say $out "$year,$month,$year-$month,$age_group,$reference_doses_date,$ever_vaccinated,$never_vaccinated,$deaths_ever_vaccinated,$deaths_never_vaccinated,$deaths_per_10000_ever_vaccinated,$deaths_per_10000_never_vaccinated";
		}
	}
}
close $out;

sub load_oia_deaths {
	say "Loading OIA deaths ...";
	open my $in, '<:utf8', $oia_deaths_file or die "missing source file : [$oia_deaths_file]";
	while (<$in>) {
		chomp $_;
		my ($year_month, $age_group, $last_dose, $days_to_death, $count) = split ',', $_;
		next if $year_month eq 'Month of Death';
		next if $year_month eq 'Total';
		$age_group =~ s/ to /-/;
		if ($age_group eq '81-100' || $age_group eq '100+') {
			$age_group = '81+';
		}
		my ($year, $month) = split '-', $year_month;
		if ($count eq '<5') {
			$count = 2;
		}
		if ($last_dose == 0) {
			$oia_deaths{$year}->{$month}->{$age_group}->{'deaths_had_no_dose'} += $count;
			$oia_yearly_deaths{$year}->{$age_group}->{'deaths_had_no_dose'} += $count;
		} else {
			$oia_deaths{$year}->{$month}->{$age_group}->{'deaths_had_first_dose'} += $count;
			$oia_yearly_deaths{$year}->{$age_group}->{'deaths_had_first_dose'} += $count;
		}
		$oia_age_groups{$age_group} = 1;
	}
	close $in;
}

sub load_doses_by_dates {
	my $file_2021      = 'data/2021_first_doses_no_dose_by_age_and_dates.csv';
	my $file_2022      = 'data/2022_first_doses_no_dose_by_age_and_dates.csv';
	my $file_2023      = 'data/2023_first_doses_no_dose_by_age_and_dates.csv';
	my @files          = ($file_2021, $file_2022, $file_2023);
	for my $file (@files) {
		open my $in, '<:utf8', $file;
		while (<$in>) {
			chomp $_;
			my ($date, $age, $had_first_dose, $had_no_dose) = split ',', $_;
			next if $date eq 'Date';
			my ($year, $month, $day) = split '-', $date;
			my $compdate = $date;
			$compdate =~ s/\D//g;
			$doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_first_dose'} = $had_first_dose;
			$doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_no_dose'} = $had_no_dose;
			$doses_by_dates{$year}->{$month}->{$day}->{$age}->{'dose_sum'} = $had_no_dose + $had_first_dose;
		}
		close $in;
	}
}

sub calculate_monthly_rates {
	my $from_date = '2021-04-01';
	my $to_date   = '2023-11-30';
	my $dt_from   = DateTime::Format::ISO8601->parse_datetime($from_date);
	my $dt_to     = DateTime::Format::ISO8601->parse_datetime($to_date);
	my %dates     = ();
	while ($dt_from <= $dt_to) {
	    my $year  = $dt_from->year;
	    my $month = $dt_from->month;
		$month    = "0$month" if $month < 10;
	    $dates{$year}->{$month} = 1;
	    $dt_from->add(days => 1);
	}
	for my $year (sort{$a <=> $b} keys %dates) {

		my %deaths_in_year = (); # Keeps track of the deaths to current month processed.
		for my $age_group (sort keys %oia_age_groups) {
			$deaths_in_year{$age_group}->{'deaths_ever_vaccinated'} = 0;
			$deaths_in_year{$age_group}->{'deaths_never_vaccinated'} = 0;
		}

		for my $month (sort{$a <=> $b} keys %{$dates{$year}}) {
			my %by_offsets = ();
			for my $day (sort{$a <=> $b} keys %{$doses_by_dates{$year}->{$month}}) {
				my $offset_to_15 = abs(15 - $day);
				$by_offsets{$offset_to_15} = $day;
			}
			my $closest_day;
			my $reference_month = $month;
			for my $offset_to_15 (sort{$a <=> $b} keys %by_offsets) {
				$closest_day = $by_offsets{$offset_to_15};
				last;
			}
			unless ($closest_day) {
				$reference_month = '05';
				$closest_day     = '03';
			}

			# Fetches the yearly death, which we want to add to the December census of this year to calculate our mortality rates.
			my %deaths = %{$oia_yearly_deaths{$year}};

			# Fetches the population (no dose, first dose) on the closest reference day.
			for my $age_group (sort keys %oia_age_groups) {

				# Population as per December 31 census
				my ($ever_vaccinated, $never_vaccinated) = generate_population_by_age_group($year, $reference_month, $closest_day, $age_group);

				# Adds the deaths during the year in each age group to the pool
				$ever_vaccinated  += $oia_yearly_deaths{$year}->{$age_group}->{'deaths_had_first_dose'};
				$never_vaccinated += $oia_yearly_deaths{$year}->{$age_group}->{'deaths_had_no_dose'};

				# Substracts the people who already died this year.
				$ever_vaccinated  -= $deaths_in_year{$age_group}->{'deaths_ever_vaccinated'};
				$never_vaccinated -= $deaths_in_year{$age_group}->{'deaths_never_vaccinated'};

				# Calculates death rates.
				my $deaths_ever_vaccinated  = $oia_deaths{$year}->{$month}->{$age_group}->{'deaths_had_first_dose'} // 0;
				my $deaths_never_vaccinated = $oia_deaths{$year}->{$month}->{$age_group}->{'deaths_had_no_dose'}    // 0;
				my $deaths_per_10000_ever_vaccinated  = nearest(0.01, $deaths_ever_vaccinated * 10000 / $ever_vaccinated);
				my $deaths_per_10000_never_vaccinated = nearest(0.01, $deaths_never_vaccinated * 10000 / $never_vaccinated);

				# Integrates the population, deaths & death rates for the year / month.
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'reference_doses_date'}               = "$year-$month-$closest_day";
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'ever_vaccinated'}                    = $ever_vaccinated;
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'never_vaccinated'}                   = $never_vaccinated;
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_ever_vaccinated'}             = $deaths_ever_vaccinated;
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_never_vaccinated'}            = $deaths_never_vaccinated;
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_per_10000_ever_vaccinated'}  = $deaths_per_10000_ever_vaccinated;
				$monthly_death_rates{$year}->{$month}->{$age_group}->{'deaths_per_10000_never_vaccinated'} = $deaths_per_10000_never_vaccinated;

				$deaths_in_year{$age_group}->{'deaths_ever_vaccinated'}  += $deaths_ever_vaccinated;
				$deaths_in_year{$age_group}->{'deaths_never_vaccinated'} += $deaths_never_vaccinated;
			}
		}
	}
}

sub generate_population_by_age_group {
	my ($year, $month, $day, $age_group) = @_;
	my ($from_age, $to_age) = split '-', $age_group;
	my ($ever_vaccinated, $never_vaccinated) = (0, 0);
	if (defined $from_age && $to_age) {
		for my $age (sort{$a <=> $b} keys %{$doses_by_dates{$year}->{$month}->{$day}}) {
			next unless $from_age <= $age && $age <=$to_age;
			$ever_vaccinated  += $doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_first_dose'};
			$never_vaccinated += $doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_no_dose'};
		}
	} else {
		die unless $from_age;
		if (
			$from_age eq '81+'
		) {
			$from_age =~ s/\+//;
			for my $age (sort{$a <=> $b} keys %{$doses_by_dates{$year}->{$month}->{$day}}) {
				next unless $from_age <= $age;
				$ever_vaccinated  += $doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_first_dose'};
				$never_vaccinated += $doses_by_dates{$year}->{$month}->{$day}->{$age}->{'had_no_dose'};
			}
		} else {
			die "from_age : $from_age";
		}
	}
	return ($ever_vaccinated, $never_vaccinated);
}