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

my $stillbirths_file      = 'raw_data/VSB357005_20240222_014547_21.csv';
my $oia_deaths_file       = 'raw_data/25021_Data_Attachment_1.csv';                                          # from https://fyi.org.nz/request/25021-number-of-covid19-vax-deaths-by-age-band-location-and-month#incoming-96520
my $deaths_by_months_file = 'raw_data/Monthly_death_registrations_by_ethnicity_age_sex_Jan2010_Sep2023.csv'; # from https://www.stats.govt.nz/assets/Uploads/Births-and-deaths/Births-and-deaths-Year-ended-September-2023/Download-data/Monthly-death-registrations-by-ethnicity-age-sex-Jan2010-Sep2023.xlsx

my %oia_deaths            = ();
my %deaths_by_months      = ();

my %under_20_deaths       = ();
my %oia_0_20_deaths       = ();

my $default_under_5       = 2;

load_deaths();
load_oia_deaths();
print_compare();
my %yearly_mort_under_20  = ();
print_0_20_oia_to_0_19_ref_compare();
load_stillbirths();
print_2020_2022_stillbirths_included_compare();

sub load_deaths {
	say "Loading deaths ...";
	open my $in, '<:utf8', $deaths_by_months_file or die "missing source file : [$deaths_by_months_file]";
	while (<$in>) {
		chomp $_;
		my ($year, $month, $ethnicity, $sex, $age_group, $count) = split ',', $_;
		next if $year eq 'year_reg';
		next unless $ethnicity eq 'Total';
		$deaths_by_months{$year}->{$month} += $count;
		# say "age_group : $age_group";
		if ($age_group eq '00_00' ||
			$age_group eq '01_04' ||
			$age_group eq '05_09' ||
			$age_group eq '10_14' ||
			$age_group eq '15_19') {
			$under_20_deaths{$year}->{$month} += $count;
		}
	}
	close $in;
}

sub load_oia_deaths {
	say "Loading OIA deaths ...";
	open my $in, '<:utf8', $oia_deaths_file or die "missing source file : [$oia_deaths_file]";
	while (<$in>) {
		chomp $_;
		my ($year_month, $age_group, $last_dose, $days_to_death, $count) = split ',', $_;
		next if $year_month eq 'Month of Death';
		next if $year_month eq 'Total';
		if ($count eq '<5') {
			$count = $default_under_5;
		}
		my ($year, $month) = split '-', $year_month;
		if ($month < 10) {
			$month =~ s/0//;
		}
		if ($age_group eq '0 to 20') {
			$oia_0_20_deaths{$year}->{$month} += $count;
		}
		$oia_deaths{$year}->{$month} += $count;
	}
	close $in;
}

sub print_compare {
	say "Printing deaths compare ...";
	my ($oia_total, $ref_total) = (0, 0);
	open my $out, '>:utf8', 'data/deaths_by_months_raw_compare.csv';
	say $out "Year Month,OIA Deaths,Reference Deaths,OIA Total,Reference Total";
	for my $year (sort{$a <=> $b} keys %oia_deaths) {
		for my $month (sort{$a <=> $b} keys %{$oia_deaths{$year}}) {
			my $oia_deaths = $oia_deaths{$year}->{$month} // die;
			my $ref_deaths = $deaths_by_months{$year}->{$month} // next;
			$oia_total += $oia_deaths;
			$ref_total += $ref_deaths;
			# say "$year - $month - $oia_deaths | $ref_deaths - $oia_total | $ref_total";
			say $out "$year-$month,$oia_deaths,$ref_deaths,$oia_total,$ref_total";
		}
	}
	my $oia_minus_ref = $oia_total - $ref_total;
	close $out;
	say "oia_minus_ref : $oia_minus_ref";
}

sub print_0_20_oia_to_0_19_ref_compare {
	open my $out, '>:utf8', 'data/under_20_deaths_compare.csv';
	say $out "year_month,OIA Total,Ref. Total";
	for my $year (sort{$a <=> $b} keys %oia_0_20_deaths) {
		for my $month (sort{$a <=> $b} keys %{$oia_0_20_deaths{$year}}) {
			my $oia_count = $oia_0_20_deaths{$year}->{$month} // die;
			my $ref_count = $under_20_deaths{$year}->{$month}  // next;
			$yearly_mort_under_20{$year}->{'ref'} += $ref_count;
			$yearly_mort_under_20{$year}->{'oia'} += $oia_count;
			say $out "$year-$month,$oia_count,$ref_count";
		}
	}
	close $out;
}

sub load_stillbirths {
	my %headers = ();
	open my $in, '<:utf8', $stillbirths_file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year, $value) = split ',', $_;
		next unless defined $year && looks_like_number $year;
		$yearly_mort_under_20{$year}->{'ref'} += $value;
	}
	close $in;
}

sub print_2020_2022_stillbirths_included_compare {
	open my $out, '>:utf8', 'data/under_20_deaths_and_stillbirths_compare.csv';
	say $out "Year,OIA Total,Ref. Total";
	for my $year (2020 .. 2022) {
		my $ref_count = $yearly_mort_under_20{$year}->{'ref'} // die;
		my $oia_count = $yearly_mort_under_20{$year}->{'oia'} // die;
		say $out "$year,$oia_count,$ref_count";
	}
	close $out;
}