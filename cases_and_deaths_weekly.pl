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
use Time::Piece;
use FindBin;
use lib "$FindBin::Bin/../../lib";

my $deaths_file = 'raw_data/covid_19_data_portal - deaths - data.csv';
my $cases_file  = 'raw_data/covid_19_data_portal - cases - data.csv';

my %deaths      = ();
my %cases       = ();

load_deaths();
load_cases();

my $week_num = 0;
open my $out_1, '>:utf8', 'deaths_and_cases_by_weeks.csv';
say $out_1 "year_week,week_num,cases_administered,deaths";
for my $year (sort{$a <=> $b} keys %deaths) {
	for my $week_number (sort{$a <=> $b} keys %{$deaths{$year}}) {
		$week_num++;
		my $cases_administered = $cases{$year}->{$week_number} // 0;
		my $deaths = $deaths{$year}->{$week_number} // die;
		say $out_1 "$year-$week_number,$week_num,$cases_administered,$deaths";
	}
}
close $out_1;

$week_num = 0;
open my $out_2, '>:utf8', 'deaths_and_cases_by_weeks_2020_2023.csv';
say $out_2 "year_week,week_num,cases_administered,deaths";
for my $year (sort{$a <=> $b} keys %deaths) {
	next if $year < 2020;
	for my $week_number (sort{$a <=> $b} keys %{$deaths{$year}}) {
		$week_num++;
		my $cases_administered = $cases{$year}->{$week_number} // 0;
		my $deaths = $deaths{$year}->{$week_number} // die;
		say $out_2 "$year-$week_number,$week_num,$cases_administered,$deaths";
	}
}
close $out_2;

sub load_deaths {
	open my $in, '<:utf8', $deaths_file;
	while (<$in>) {
		chomp $_;
		my ($resource_id, $geo, $period, $label_1, $label_2, $label_3, $value, $unit, $measure, $multiplier) = split ',', $_;
		next if $resource_id eq 'ResourceID';
		next unless $label_1 eq 'Total';
		my $date = Time::Piece->strptime($period, '%Y-%m-%d');
		my $week_number = $date->strftime('%U');
		my ($year) = split '-', $period;
		# say "period      : $period";
		# say "year        : $year";
		# say "week_number : $week_number";
		# say "value       : $value";
		# say $_;
		$deaths{$year}->{$week_number} += $value;
	}
	close $in;
}

sub load_cases {
	open my $in, '<:utf8', $cases_file;
	while (<$in>) {
		chomp $_;
		my ($resource_id, $geo, $period, $label_1, $label_2, $label_3, $value, $unit, $measure, $multiplier) = split ',', $_;
		next if $resource_id eq 'ResourceID';
		my $date = Time::Piece->strptime($period, '%Y-%m-%d');
		my $week_number = $date->strftime('%U');
		my ($year) = split '-', $period;
		# say "period      : $period";
		# say "label_1     : $label_1";
		# say "year        : $year";
		# say "week_number : $week_number";
		# say "value       : $value";
		$cases{$year}->{$week_number} += $value;
	}
	close $in;
}