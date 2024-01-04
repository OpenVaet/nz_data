#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use DateTime;
use File::Path qw(make_path);
use Data::Printer;

my $nz_file      = 'raw_data/nz-record-level-data-4M-records.csv';
my $nz_file_out  = 'data/nzwb_dob_removed_50_plus.csv';
my $nz_file_age  = 'nz_analysis/nzwb_age_distribution.csv';
my $nz_file_dose = 'nz_analysis/nzwb_doses_by_days.csv';
my $snap_date    = parse_date('2023-10-27');
my %dates        = ();

make_path('data') unless (-d 'data');
make_path('nz_analysis') unless (-d 'nz_analysis');

load_nz_data();

sub load_nz_data {
	my %stats        = ();
	my %nz_data      = ();
	my %nz_doses     = ();
	my %nz_ages      = ();
	STDOUT->printflush("\rLoading NZWB data ...");
	my ($loaded, $cpt) = (0, 0);
	my $highest_dose_number = 0;
	open my $in, '<:utf8', $nz_file or die "missing source file : [$nz_file]";
	open my $out, '>:utf8', $nz_file_out or die "unable to create output file, make sure that [2013_2022_official_rates.pl] has been executed first.";
	say $out "mrn,batch_id,dose_number,date_time_of_service,date_of_death,age";
	while (<$in>) {
		chomp $_;
		$loaded++;
		$cpt++;
		if ($cpt == 1000) {
			$cpt = 0;
			STDOUT->printflush("\rLoading NZWB data ... [$loaded] rows loaded");
		}
		my ($mrn, $batch_id, $dose_number, $date_time_of_service, $date_of_death, $vaccine_name, $date_of_birth, $age) = split ',', $_;
		next if $mrn eq 'mrn';
		next if $age < 50;
		next unless $dose_number == 1;
		$date_time_of_service = convert_date($date_time_of_service);
		$date_of_birth = convert_date($date_of_birth);
		my $died = 0;
		if ($date_of_death) {
			$date_of_death = convert_date($date_of_death);
			$died = 1;
		}
		if ($died && (exists $nz_data{$mrn}->{'died'} && !$nz_data{$mrn}->{'died'})) {
			die "was here on another row, not dead";
			$nz_data{$mrn}->{'died'} = $died;
		} elsif ($died) {
			$nz_data{$mrn}->{'died'} = $died;
		} else {
			if (!$died && !exists $nz_data{$mrn}->{'died'}) {
				$nz_data{$mrn}->{'died'} = $died;
			}
		}
		if (exists $nz_data{$mrn}->{'date_of_death'}) {
			die unless $nz_data{$mrn}->{'date_of_death'} eq $date_of_death;
		}
		$nz_data{$mrn}->{'date_of_death'} = $date_of_death;
		if (exists $nz_data{$mrn}->{'date_of_birth'}) {
			unless ($nz_data{$mrn}->{'date_of_birth'} eq $date_of_birth) {
				# say "$date_of_birth != " . $nz_data{$mrn}->{'date_of_birth'};
				$stats{'different_DOB'}++;
			}
		}
		if (exists $nz_data{$mrn}->{'age'}) {
			unless ($nz_data{$mrn}->{'age'} eq $age) {
				# say "$age != " . $nz_data{$mrn}->{'age'};
				$stats{'different_age'}++;
			}
		}
		if (!exists $nz_data{$mrn}->{'joined_on'}) {
			$nz_data{$mrn}->{'joined_on'} = 99999999;
		}
		my $compdate_of_service = $date_time_of_service;
		$compdate_of_service =~ s/\D//g;
		$nz_doses{$compdate_of_service}->{'total'}++;
		$nz_data{$mrn}->{'joined_on'} = $compdate_of_service if $compdate_of_service < $nz_data{$mrn}->{'joined_on'};
		$nz_data{$mrn}->{'date_of_birth'} = $date_of_birth;
		$nz_data{$mrn}->{'age'} = $age;
		$nz_data{$mrn}->{'doses'}->{$dose_number} = $date_time_of_service;

		say $out "$mrn,$batch_id,$dose_number,$date_time_of_service,$date_of_death,$age";

		$highest_dose_number = $dose_number if $dose_number > $highest_dose_number;

		# Verifying age.
		$date_of_birth = parse_date($date_of_birth);
		my $years_difference = calculate_years_difference($date_of_birth, $snap_date);
		my $abs_dif = abs($years_difference - $age);
		if ($abs_dif > 2) {
			# say "age offset : [$age vs $years_difference] ($abs_dif)";
			$stats{'offset_between_ages_sup_to_2'}->{$died}++;
		}
	}
	close $in;
	close $out;
	STDOUT->printflush("\rLoading NZWB data ... [$loaded] rows loaded");
	say "";
	say "highest_dose_number : $highest_dose_number";

	# Prints the total of doses administered by days.
	open my $out_doses, '>:utf8', $nz_file_dose;
	say $out_doses "date,total";
	for my $compdate (sort{$a <=> $b} keys %nz_doses) {
		my $total = $nz_doses{$compdate}->{'total'} // die;
		my $date  = convert_compdate_to_date($compdate);
		say $out_doses "$date,$total";
	}
	close $out_doses;

	# Prints the age distribution in the dataset.
	for my $mrn (sort keys %nz_data) {
		my $age = $nz_data{$mrn}->{'age'} // die;

		# Normalizing age if above 90, and incrementing distribution.
		$age = '90' if $age >= 90;
		$nz_ages{$age}++;
	}
	open my $out_ages, '>:utf8', $nz_file_age;
	say $out_ages "age,count";
	for my $age (sort{$a <=> $b} keys %nz_ages) {
		my $count = $nz_ages{$age} // die;
		$age = '90+' if $age eq '90';
		say $out_ages "$age,$count";
	}
	close $out_ages;

	# Visual output of the raw anomalies described.
	# To reproduce the analysis on ages to export date, just adjust the reference line 96.
	p%stats;
}

sub convert_date {
	my $date = shift;
	my ($m, $d, $y) = split '-', $date;
	$dates{"$y$m$d"} = 1;
	return "$y-$m-$d";
}

sub parse_date {
    my ($date_str) = @_;
    my ($year, $month, $day) = split /-/, $date_str;

    return DateTime->new(
        year  => $year,
        month => $month,
        day   => $day,
    );
}

sub calculate_years_difference {
    my ($date1, $date2) = @_;

    # Calculate the difference in years as a floating point number
    my $years = $date1->delta_md($date2)->in_units('years');

    # Return the absolute value of the difference
    return abs($years);
}

sub convert_compdate_to_date {
	my $cp = shift;
	my ($y, $m, $d) = $cp =~ /(....)(..)(..)/;
	return "$y-$m-$d";
}