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
use FindBin;
use lib "$FindBin::Bin/../../lib";

my $oia_deaths_file  = 'raw_data/25021_Data_Attachment_1.csv';                      # from https://fyi.org.nz/request/25021-number-of-covid19-vax-deaths-by-age-band-location-and-month#incoming-96520
my $populations_file = 'data/first_doses_no_dose_by_oia_age_groups_and_months.csv'; # from normalize_doses_by_dates.pl

my %oia_deaths  = ();
my %population  = ();

load_population_data();
load_oia_deaths();

sub load_population_data {
	say "Loading OIA compatible population data ...";
	open my $in, '<:utf8', $populations_file or die "missing source file : [$populations_file]";
	while (<$in>) {
		chomp $_;
		my ($year_month, $closest_dose_date, $age_group, $had_first_dose, $had_no_dose) = split ',', $_;
		next if $year_month eq 'year_month';
		my ($year, $month) = split '-', $year_month;
		$population{$year}->{$month}->{$age_group}->{'had_first_dose'} = $had_first_dose;
		$population{$year}->{$month}->{$age_group}->{'had_no_dose'} = $had_no_dose;
	}
	close $in;
	# p%population;die;
}

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
			$count = 3;
		}
		if ($last_dose == 0) {
			$oia_deaths{$year}->{$month}->{$age_group}->{'had_no_dose'} += $count;
		} else {
			$oia_deaths{$year}->{$month}->{$age_group}->{'had_first_dose'} += $count;
		}
	}
	close $in;
}

open my $out, '>:utf8', 'data/death_rates_no_dose_vs_dose.csv';
say $out "year_month,age_group,deaths_per_1000_had_no_dose,deaths_per_1000_had_first_dose";
for my $year (sort{$a <=> $b} keys %population) {
	for my $month (sort{$a <=> $b} keys %{$population{$year}}) {
		for my $age_group (sort keys %{$population{$year}->{$month}}) {
			my $population_had_first_dose      = $population{$year}->{$month}->{$age_group}->{'had_first_dose'} // die;
			my $population_no_first_dose       = $population{$year}->{$month}->{$age_group}->{'had_no_dose'}    // die;
			my $deaths_had_first_dose          = $oia_deaths{$year}->{$month}->{$age_group}->{'had_first_dose'} // 0;
			my $deaths_had_no_dose             = $oia_deaths{$year}->{$month}->{$age_group}->{'had_no_dose'}    // 0;
			my $deaths_per_1000_had_no_dose    = nearest(0.01, $deaths_had_no_dose * 1000 / $population_no_first_dose);
			my $deaths_per_1000_had_first_dose = nearest(0.01, $deaths_had_first_dose * 1000 / $population_had_first_dose);
			say $out "$year-$month,$age_group,$deaths_per_1000_had_no_dose,$deaths_per_1000_had_first_dose";
		}
	}
}
close $out;