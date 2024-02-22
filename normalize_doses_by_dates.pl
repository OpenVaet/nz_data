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

my $archive_doses_file    = 'data/nz_doses_administered_from_archive.csv';
load_archive_doses();
load_git_doses();
my %doses_totals_by_dates = ();
my ($earliest_date, $latest_date);
print_data_by_ages_and_age_groups();
print_day_by_day_totals();

sub load_archive_doses {
	open my $in, '<:utf8', $archive_doses_file;
	while (<$in>) {
		chomp $_;
		my ($archive_url, $archive_date, $age_group, $first_doses, $second_doses) = split ',', $_;
		next if $archive_url eq 'archive_url';
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

sub load_git_doses {
	my $csv_parser = Text::CSV_XS->new ({ binary => 1 });
	for my $date_folder (glob "raw_data/nz-covid-data-main/vaccine-data/*") {
		my ($year, $month, $day) = $date_folder =~ /vaccine-data\/(....)-(..)-(..)$/;
		next unless $year && $month && $day;
		my $date = "$year-$month-$day";
		my $compdate = "$year$month$day";
		next if exists $doses_by_dates{$compdate};
		my $dhb_file = "$date_folder/dhb_residence_uptake.csv";
		die unless -f $dhb_file;
		open my $in, '<:', $dhb_file or die $!;
		# say $dhb_file;
		my %headers = ();
		my $l_num   = 0;
		while (<$in>) {
			chomp $_;
			# say $_;
			$l_num++;
			open my $fh, "<", \$_;
			my $row = $csv_parser->getline ($fh);
			my @row = @$row;
			my %values = ();
			if ($l_num == 1) {
				my $h_num = 0;
				for my $header (@row) {
					$h_num++;
					$headers{$h_num} = $header;
				}
				next;
			} else {
				my $v_num = 0;
				for my $value (@row) {
					$v_num++;
					my $header = $headers{$v_num} // die;
					$values{$header} = $value;
				}
			}
			my $age_group  = $values{'Age group'} // die;
			my $first_doses = $values{'First dose administered'} // $values{'At least partially vaccinated'};
			unless (defined $first_doses) {
				p%values;
				die;
			}
			next if $age_group eq 'Age group';
			$first_doses  =~ s/,//g;
			$doses_by_dates{$compdate}->{'date'} = $date;
			$doses_by_dates{$compdate}->{'year'} = $year;
			$doses_by_dates{$compdate}->{'age_groups'}->{$age_group} += $first_doses;
		}
		close $in;
	}
}

sub print_data_by_ages_and_age_groups {
	open my $out, '>:utf8', 'data/first_doses_by_age_groups_and_dates.csv';
	say $out 'Date,Age Group,First Doses';
	for my $compdate (sort{$a <=> $b} keys %doses_by_dates) {
		$earliest_date = $compdate if !$earliest_date;
		$latest_date   = $compdate;
		my $date = $doses_by_dates{$compdate}->{'date'} // die;
		my $daily_doses_total = 0;
		my ($year, $month) = split '-', $date;
		for my $age_group_name (sort keys %{$doses_by_dates{$compdate}->{'age_groups'}}) {
			next if $age_group_name eq 'Total' || $age_group_name eq 'Various';
			my $first_doses = $doses_by_dates{$compdate}->{'age_groups'}->{$age_group_name} // die;
			say $out "$date,$age_group_name,$first_doses";
			$daily_doses_total += $first_doses;
		}
		$doses_totals_by_dates{$date} = $daily_doses_total;

		# say "date : $date";
	}
	close $out;
}

sub print_day_by_day_totals {
	my $earliest_dt = DateTime->new(
	    year  => substr($earliest_date, 0, 4),
	    month => substr($earliest_date, 4, 2),
	    day   => substr($earliest_date, 6, 2)
	);

	my $latest_dt = DateTime->new(
	    year  => substr($latest_date, 0, 4), 
	    month => substr($latest_date, 4, 2),
	    day   => substr($latest_date, 6, 2)
	);

	my $latest_total;
	open my $out_1, '>:utf8', 'data/total_first_doses_by_dates.csv';
	say $out_1 'Date,First Doses';
	while ($earliest_dt <= $latest_dt) {
		my $date = $earliest_dt->ymd("-");
		if (exists $doses_totals_by_dates{$date}) {
			$latest_total = $doses_totals_by_dates{$date} // die;
		}

		say $out_1 "$date,$latest_total";

	    $earliest_dt->add(days => 1); 
	}
	close $out_1;
}