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

my %oia_deaths  = ();

load_oia_deaths();

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

my $file_2021 = '2021_first_doses_no_dose_by_oia_age_groups_and_dates.csv';
my $file_2022 = '2022_first_doses_no_dose_by_oia_age_groups_and_dates.csv';
my $file_2023 = '2023_first_doses_no_dose_by_oia_age_groups_and_dates.csv';

