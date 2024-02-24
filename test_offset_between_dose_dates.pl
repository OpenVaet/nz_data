#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV qw( csv );
use Data::Printer;
use Data::Dumper;
use DateTime;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);

my %doses_by_dates        = ();

my $archive_doses_file    = 'data/first_doses_by_age_groups_and_dates.csv';
load_archive_doses();

# p%doses_by_dates;die;

sub load_archive_doses {
	open my $in, '<:utf8', $archive_doses_file;
	while (<$in>) {
		chomp $_;
		my ($archive_date, $age_group, $first_doses) = split ',', $_;
		next if $archive_date eq 'Date';
		my $compdate = $archive_date;
		$compdate =~ s/\D//g;
		my ($year) = split '-', $archive_date;
		$age_group = reformat_age_group($age_group);
		$doses_by_dates{$compdate}->{'date'} = $archive_date;
		$doses_by_dates{$compdate}->{'year'} = $year;
		$doses_by_dates{$compdate}->{'age_groups'}->{$age_group} += $first_doses;
	}
	close $in;
}

sub reformat_age_group {
	my $age_group = shift;
	$age_group =~ s/ and over/\+/;
	$age_group =~ s/ years//;
	$age_group =~ s/ //g;
	$age_group =~ s/\/Unknown//;
	return $age_group;
}

my $date_1 = '20220803';
my $date_2 = '20220810';

my $sum_date_1 = 0;

for my $age_group ('5-11', '12-17', '18-24', '25-29') {
	say $age_group;
	say $doses_by_dates{$date_1}->{'age_groups'}->{$age_group};
	$sum_date_1 += $doses_by_dates{$date_1}->{'age_groups'}->{$age_group};
}

my $sum_date_2 = 0;
for my $age_group ('5-11', '12-17', '18-24', '25-29') {
	say $age_group;
	say $doses_by_dates{$date_2}->{'age_groups'}->{$age_group};
	$sum_date_2 += $doses_by_dates{$date_2}->{'age_groups'}->{$age_group};
}

my $offset = $sum_date_2 - $sum_date_1;

say "sum_date_1 : $sum_date_1";
say "sum_date_2 : $sum_date_2";
say "offset     : $offset";