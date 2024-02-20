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
my %pop_esti              = ();

# Deaths data from https://www.stats.govt.nz/assets/Uploads/Births-and-deaths/Births-and-deaths-Year-ended-September-2023/Download-data/Monthly-death-registrations-by-ethnicity-age-sex-Jan2010-Sep2023.xlsx
my $deaths_by_months_file = 'raw_data/Monthly_death_registrations_by_ethnicity_age_sex_Jan2010_Sep2023.csv';
my $pop_esti_file         = 'raw_data/DPE403905_20240219_032202_8.csv';

# Load deaths & population.
load_pop_esti();
load_deaths();
print_population_normalized();

sub load_deaths {
	say "Loading deaths ...";
	open my $in, '<:utf8', $deaths_by_months_file or die "missing source file : [$deaths_by_months_file]";
	while (<$in>) {
		chomp $_;
		my ($year, $month, $ethnicity, $sex, $age_groups_src, $count) = split ',', $_;
		next if $year eq 'year_reg';
		next unless $ethnicity eq 'Total';
		my $age_group = age_group_from_age_groups_src($age_groups_src);
		$deaths_by_months{$year}->{$month}->{$age_group} += $count;
	}
	close $in;
}

sub load_pop_esti {
	say "Loading population estimates ...";
	my %headers = ();
	open my $in, '<:utf8', $pop_esti_file;
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
				my $age_group = age_group_5_from_age($header);
				$pop_esti{$year}->{$age_group} += $value;
			}
		}
	}
	close $in;
	# p%pop_esti;die;
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
		$age_group = '2';
	} elsif ($age_groups_src eq '05_09') {
		$age_group = '3';
	} elsif ($age_groups_src eq '10_14') {
		$age_group = '4';
	} elsif ($age_groups_src eq '15_19') {
		$age_group = '5';
	} elsif ($age_groups_src eq '20_24') {
		$age_group = '6';
	} elsif ($age_groups_src eq '25_29') {
		$age_group = '7';
	} elsif ($age_groups_src eq '30_34') {
		$age_group = '8';
	} elsif ($age_groups_src eq '35_39') {
		$age_group = '9';
	} elsif ($age_groups_src eq '40_44') {
		$age_group = '10';
	} elsif ($age_groups_src eq '45_49') {
		$age_group = '11';
	} elsif ($age_groups_src eq '50_54') {
		$age_group = '12';
	} elsif ($age_groups_src eq '55_59') {
		$age_group = '13';
	} elsif ($age_groups_src eq '60_64') {
		$age_group = '14';
	} elsif ($age_groups_src eq '65_69') {
		$age_group = '15';
	} elsif ($age_groups_src eq '70_74') {
		$age_group = '16';
	} elsif ($age_groups_src eq '75_79') {
		$age_group = '17';
	} elsif ($age_groups_src eq '80_84') {
		$age_group = '18';
	} elsif ($age_groups_src eq '85_89') {
		$age_group = '19';
	} elsif ($age_groups_src eq '90_94' || $age_groups_src eq '95_') {
		$age_group = '20';
	} else {
		die "age_groups_src : $age_groups_src";
	}
	$age_groups_srcs{$age_group} = $age_groups_src;
	return $age_group;
}

sub age_group_5_from_age {
	my $header = shift;
	my $age_group;
	if ($header >= 0 && $header < 1) {
		$age_group = '1';
	} elsif ($header >= 1 && $header < 5) {
		$age_group = '2';
	} elsif ($header >= 5 && $header < 10) {
		$age_group = '3';
	} elsif ($header >= 10 && $header < 15) {
		$age_group = '4';
	} elsif ($header >= 15 && $header < 20) {
		$age_group = '5';
	} elsif ($header >= 20 && $header < 25) {
		$age_group = '6';
	} elsif ($header >= 25 && $header < 30) {
		$age_group = '7';
	} elsif ($header >= 30 && $header < 35) {
		$age_group = '8';
	} elsif ($header >= 35 && $header < 40) {
		$age_group = '9';
	} elsif ($header >= 40 && $header < 45) {
		$age_group = '10';
	} elsif ($header >= 45 && $header < 50) {
		$age_group = '11';
	} elsif ($header >= 50 && $header < 55) {
		$age_group = '12';
	} elsif ($header >= 55 && $header < 60) {
		$age_group = '13';
	} elsif ($header >= 60 && $header < 65) {
		$age_group = '14';
	} elsif ($header >= 65 && $header < 70) {
		$age_group = '15';
	} elsif ($header >= 70 && $header < 75) {
		$age_group = '16';
	} elsif ($header >= 75 && $header < 80) {
		$age_group = '17';
	} elsif ($header >= 80 && $header < 85) {
		$age_group = '18';
	} elsif ($header >= 85 && $header < 90) {
		$age_group = '19';
	} elsif ($header >= 90) {
		$age_group = '20';
	} else {
		die "header : $header";
	}
	return $age_group;
}

sub print_population_normalized {
	say "Printing normalized data ...";
	open my $out, '>:utf8', 'data/deaths_and_pop_by_months_and_ages.csv';
	say $out "year,month,age_group,age_groups_src,population,deaths";
	for my $year (sort{$a <=> $b} keys %deaths_by_months) {
		next if $year == 2023;
		for my $month (sort{$a <=> $b} keys %{$deaths_by_months{$year}}) {
			for my $age_group (sort{$a <=> $b} keys %{$deaths_by_months{$year}->{$month}}) {
				my $count = $deaths_by_months{$year}->{$month}->{$age_group} // die;
				my $population = $pop_esti{$year}->{$age_group} // die "year : $year - $age_group";
				my $age_groups_src = $age_groups_srcs{$age_group} // die;
				say $out "$year,$month,$age_group,$age_groups_src,$population,$count";
			}
		}
	}
	close $out;
}