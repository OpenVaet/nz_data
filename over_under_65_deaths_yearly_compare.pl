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

my %age_groups_srcs       = ();
my %deaths_by_months      = ();
my %deaths                = ();

# Deaths data from https://www.stats.govt.nz/assets/Uploads/Births-and-deaths/Births-and-deaths-Year-ended-September-2023/Download-data/Monthly-death-registrations-by-ethnicity-age-sex-Jan2010-Sep2023.xlsx
my $deaths_by_months_file = 'raw_data/Monthly_death_registrations_by_ethnicity_age_sex_Jan2010_Sep2023.csv';
my $deaths_file           = 'raw_data/VSD349204_20240106_103532_75.csv';

# Load deaths & population.
load_monthly_deaths();
load_deaths();

p%deaths_by_months;
p%deaths;

open my $out, '>:utf8', 'data/over_under_65_deaths_dataset_compare.csv';
say $out "year,age_group,count_monthly,count_yearly";
for my $year (sort{$a <=> $b} keys %deaths_by_months) {
	# next if $year < 2021;
	for my $age_group (sort keys %{$deaths_by_months{$year}}) {
		my $count_monthly = $deaths_by_months{$year}->{$age_group} // die;
		my $count_yearly  = $deaths{$year}->{$age_group} // next;
		if ($age_group == 1) {
			$age_group = 'Under 65'
		} else {
			$age_group = '65+'
		}
		say $out "$year,$age_group,$count_monthly,$count_yearly";
	}
}
close $out;

sub load_monthly_deaths {
	open my $in, '<:utf8', $deaths_by_months_file or die "missing source file : [$deaths_by_months_file]";
	while (<$in>) {
		chomp $_;
		my ($year, $month, $ethnicity, $sex, $age_groups_src, $count) = split ',', $_;
		next if $year eq 'year_reg';
		next unless $ethnicity eq 'Total';
		my $age_group = age_group_from_age_groups_src($age_groups_src);
		$deaths_by_months{$year}->{$age_group} += $count;
	}
	close $in;
}

sub load_deaths {
	my %headers = ();
	open my $in, '<:utf8', $deaths_file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year) = split ',', $_;
		next unless defined $year;
		if ($year eq ' ') {
			my @headers = split ",", $_;
			for my $header_ref (1 .. scalar @headers - 1) {
				my $header = $headers[$header_ref] // die;
				$headers{$header_ref} = $header;
			}
		} else {
			next unless keys %headers;
			next unless looks_like_number($year);
			my %values = ();
			my @values = split ',', $_;
			for my $value_ref (1 .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				$header    = strip_age($header);
				if ($header <= 64) {
					$deaths{$year}->{'1'} += $value;
				} else {
					$deaths{$year}->{'2'} += $value;
				}
			}
		}
	}
	close $in;
}

sub strip_age {
	my $header = shift;
	$header =~ s/Less than 1 year/0/;
	$header =~ s/ years and over//;
	$header =~ s/ years//;
	$header =~ s/ year//;
	$header =~ s/ Years and Over//;
	$header =~ s/ Years//;
	$header =~ s/ Year//;
	return $header;
}

sub age_group_from_age_groups_src {
	my $age_groups_src = shift;
	my $age_group;
	if ($age_groups_src eq '00_00') {
		$age_group = '1';
	} elsif ($age_groups_src eq '01_04') {
		$age_group = '1';
	} elsif ($age_groups_src eq '05_09') {
		$age_group = '1';
	} elsif ($age_groups_src eq '10_14') {
		$age_group = '1';
	} elsif ($age_groups_src eq '15_19') {
		$age_group = '1';
	} elsif ($age_groups_src eq '20_24') {
		$age_group = '1';
	} elsif ($age_groups_src eq '25_29') {
		$age_group = '1';
	} elsif ($age_groups_src eq '30_34') {
		$age_group = '1';
	} elsif ($age_groups_src eq '35_39') {
		$age_group = '1';
	} elsif ($age_groups_src eq '40_44') {
		$age_group = '1';
	} elsif ($age_groups_src eq '45_49') {
		$age_group = '1';
	} elsif ($age_groups_src eq '50_54') {
		$age_group = '1';
	} elsif ($age_groups_src eq '55_59') {
		$age_group = '1';
	} elsif ($age_groups_src eq '60_64') {
		$age_group = '1';
	} elsif ($age_groups_src eq '65_69') {
		$age_group = '2';
	} elsif ($age_groups_src eq '70_74') {
		$age_group = '2';
	} elsif ($age_groups_src eq '75_79') {
		$age_group = '2';
	} elsif ($age_groups_src eq '80_84') {
		$age_group = '2';
	} elsif ($age_groups_src eq '85_89') {
		$age_group = '2';
	} elsif ($age_groups_src eq '90_94' || $age_groups_src eq '95_') {
		$age_group = '2';
	} else {
		die "age_groups_src : $age_groups_src";
	}
	return $age_group;
}