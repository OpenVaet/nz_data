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

my %age_groups      = ();
my %nzwb_data       = ();
my $cutoff_compdate = 20230930;
my $nzwb_file       = 'data/nzwb_dob_removed.csv';

# Load NZWB dataset.
load_nzwb_data();
# p%nzwb_data;die;

# Renders total of subjects & sets a few variables.
my $total_recipients = keys %nzwb_data;

sub load_nzwb_data {
	STDOUT->printflush("\rLoading NZWB data ...");
	my ($loaded, $cpt) = (0, 0);
	open my $in, '<:utf8', $nzwb_file or die "missing source file : [$nzwb_file]";
	while (<$in>) {
		chomp $_;
		$loaded++;
		$cpt++;
		if ($cpt == 1000) {
			$cpt = 0;
			STDOUT->printflush("\rLoading NZWB data ... [$loaded] rows loaded");
		}
		my ($mrn, $batch_id, $dose_number, $date_time_of_service, $death_on_dt, $age) = split ',', $_;
		next if $mrn eq 'mrn';
		my $compdate_of_service = $date_time_of_service;
		$compdate_of_service =~ s/\D//g;
		if (!exists $nzwb_data{$mrn}->{'joined_on'}) {
			$nzwb_data{$mrn}->{'joined_on'} = 99999999;
		}
		my $death_on = $death_on_dt;
		if ($death_on) {
			$death_on =~ s/\D//g;
		}
		$nzwb_data{$mrn}->{'joined_on'} = $compdate_of_service if $compdate_of_service < $nzwb_data{$mrn}->{'joined_on'};
		$nzwb_data{$mrn}->{'age'} = $age;
		$nzwb_data{$mrn}->{'doses'}->{$dose_number} = $date_time_of_service;
		$nzwb_data{$mrn}->{'death_on'} = $death_on;
		$nzwb_data{$mrn}->{'death_on_dt'} = $death_on_dt;
	}
	close $in;
	STDOUT->printflush("\rLoading NZWB data ... [$loaded] rows loaded");
	say "";
}

my %by_age_groups    = ();
my %by_days_to_death = ();
my ($died, $missing_dose_1, $missing_dose_1_total_doses_received, $missing_dose_1_died, $dose_1, $dose_1_total_doses_received, $dose_1_died) = (0, 0, 0, 0, 0, 0, 0);
for my $mrn (sort{$a <=> $b} keys %nzwb_data) {
	my $joined_on = $nzwb_data{$mrn}->{'joined_on'} // die;
	my $joined_on_dt = convert_compdate_to_date($joined_on);
	my $age = $nzwb_data{$mrn}->{'age'} // die;
	my ($age_group, $age_group_name) = age_group_5_from_age($age);
	unless (exists $nzwb_data{$mrn}->{'doses'}->{'1'}) {
		$missing_dose_1++;
		if ($nzwb_data{$mrn}->{'death_on_dt'}) {
			$missing_dose_1_died++;
		}
		$missing_dose_1_total_doses_received += keys %{$nzwb_data{$mrn}->{'doses'}};
		# p$nzwb_data{$mrn}->{'doses'};
	} else {
		$dose_1++;
		my ($days_to_death, $days_to_death);
		if ($nzwb_data{$mrn}->{'death_on_dt'}) {
			$dose_1_died++;
			$by_age_groups{$age_group}->{'died'}++;
			$days_to_death = calculate_days_difference($nzwb_data{$mrn}->{'death_on_dt'}, $joined_on_dt);
			$by_days_to_death{$days_to_death}++;
			# say "days_to_death : $days_to_death";
		}
		$by_age_groups{$age_group}->{'total'}++;
		$dose_1_total_doses_received += keys %{$nzwb_data{$mrn}->{'doses'}};
	}
	if ($nzwb_data{$mrn}->{'death_on_dt'}) {
		$died++;
	}
	$nzwb_data{$mrn}->{'age_group'} = $age_group;
	$nzwb_data{$mrn}->{'joined_on_dt'} = $joined_on_dt;
}
my $dose_1_average_dose_received = nearest(0.01, $dose_1_total_doses_received / $dose_1);
my $missing_dose_1_average_dose_received = nearest(0.01, $missing_dose_1_total_doses_received / $missing_dose_1);
say "total_recipients                     : $total_recipients";                     # 2 215 729
say "died                                 : $died";                                 # 37 315

say "dose_1                               : $dose_1";                               # 966 989
say "dose_1_total_doses_received          : $dose_1_total_doses_received";          # 2 331 074
say "dose_1_average_dose_received         : $dose_1_average_dose_received";         # 2.41
say "dose_1_died                          : $dose_1_died";                          # 11 626

say "missing_dose_1                       : $missing_dose_1";                       # 1 248 740
say "missing_dose_1_total_doses_received  : $missing_dose_1_total_doses_received";  # 1 862 317
say "missing_dose_1_average_dose_received : $missing_dose_1_average_dose_received"; # 1.49
say "missing_dose_1_died                  : $missing_dose_1_died";                  # 25 689

p%by_age_groups;
p%by_days_to_death;

my %by_days_to_death_groups = ();
for my $days_to_death (sort{$a <=> $b} keys %by_days_to_death) {
	my ($days_to_death_group,
		$days_to_death_group_name) = group_time_to_death($days_to_death);
	my $total_deaths = $by_days_to_death{$days_to_death} // die;
	$by_days_to_death_groups{$days_to_death_group}->{'days_to_death_group_name'} = $days_to_death_group_name;
	$by_days_to_death_groups{$days_to_death_group}->{'total_deaths'} += $total_deaths;
}
open my $out_1, '>:utf8', 'by_days_to_death.csv';
say $out_1 "days_to_death_group,days_to_death_group_name,total_deaths";
for my $days_to_death_group (sort{$a <=> $b} keys %by_days_to_death_groups) {
	my $days_to_death_group_name = $by_days_to_death_groups{$days_to_death_group}->{'days_to_death_group_name'} // die;
	my $total_deaths = $by_days_to_death_groups{$days_to_death_group}->{'total_deaths'} // die;
	say $out_1 "$days_to_death_group,$days_to_death_group_name,$total_deaths";
}
close $out_1;
open my $out_2, '>:utf8', 'by_age_groups.csv';
say $out_2 "age_group,age_group_name,total_deaths,total_subjects";
for my $age_group (sort{$a <=> $b} keys %by_age_groups) {
	my $age_group_name = $age_groups{$age_group} // die;
	my $total_deaths = $by_age_groups{$age_group}->{'died'} // 0;
	my $total_subjects = $by_age_groups{$age_group}->{'total'} // die;
	say $out_2 "$age_group,$age_group_name,$total_deaths,$total_subjects";
}
close $out_2;

sub convert_compdate_to_date {
	my $cp = shift;
	my ($y, $m, $d) = $cp =~ /(....)(..)(..)/;
	return "$y-$m-$d";
}

sub age_group_5_from_age {
	my $header = shift;
	my ($age_group, $age_group_name);
	if ($header >= 0 && $header < 1) {
		$age_group = '1';
		$age_group_name = 'Under 1 year';
	} elsif ($header >= 1 && $header < 5) {
		$age_group = '2';
		$age_group_name = '1 - 4 years';
	} elsif ($header >= 5 && $header < 10) {
		$age_group = '3';
		$age_group_name = '5 - 9 years';
	} elsif ($header >= 10 && $header < 15) {
		$age_group = '4';
		$age_group_name = '10 - 14 years';
	} elsif ($header >= 15 && $header < 20) {
		$age_group = '5';
		$age_group_name = '15 - 19 years';
	} elsif ($header >= 20 && $header < 25) {
		$age_group = '6';
		$age_group_name = '20 - 24 years';
	} elsif ($header >= 25 && $header < 30) {
		$age_group = '7';
		$age_group_name = '25 - 29 years';
	} elsif ($header >= 30 && $header < 35) {
		$age_group = '8';
		$age_group_name = '30 - 34 years';
	} elsif ($header >= 35 && $header < 40) {
		$age_group = '9';
		$age_group_name = '35 - 39 years';
	} elsif ($header >= 40 && $header < 45) {
		$age_group = '10';
		$age_group_name = '40 - 44 years';
	} elsif ($header >= 45 && $header < 50) {
		$age_group = '11';
		$age_group_name = '45 - 49 years';
	} elsif ($header >= 50 && $header < 55) {
		$age_group = '12';
		$age_group_name = '50 - 54 years';
	} elsif ($header >= 55 && $header < 60) {
		$age_group = '13';
		$age_group_name = '55 - 60 years';
	} elsif ($header >= 60 && $header < 65) {
		$age_group = '14';
		$age_group_name = '60 - 64 years';
	} elsif ($header >= 65 && $header < 70) {
		$age_group = '15';
		$age_group_name = '65 - 69 years';
	} elsif ($header >= 70 && $header < 75) {
		$age_group = '16';
		$age_group_name = '70 - 74 years';
	} elsif ($header >= 75 && $header < 80) {
		$age_group = '17';
		$age_group_name = '75 - 79 years';
	} elsif ($header >= 80 && $header < 85) {
		$age_group = '18';
		$age_group_name = '80 - 84 years';
	} elsif ($header >= 85 && $header < 90) {
		$age_group = '19';
		$age_group_name = '85 - 89 years';
	} elsif ($header >= 90) {
		$age_group = '20';
		$age_group_name = '90+ years old'
	} else {
		die "header : $header";
	}
	$age_groups{$age_group} = $age_group_name;
	return ($age_group, $age_group_name);
}

sub calculate_days_difference {
    my ($date1, $date2) = @_;
    $date1 = parse_date($date1);
    $date2 = parse_date($date2);

    # Calculate the difference as a DateTime::Duration object
    my $duration = $date1->delta_days($date2);

    # Get the difference in days as a number
    my $days = $duration->in_units('days');

    # Return the absolute value of the difference
    return abs($days);
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

sub group_time_to_death {
	my $days_to_death = shift;
	my ($days_to_death_group, $days_to_death_group_name);
	if ($days_to_death >= 0 && $days_to_death < 60) {
		$days_to_death_group = 1;
		$days_to_death_group_name = '0 to 59';
	} elsif ($days_to_death >= 60 && $days_to_death < 120) {
		$days_to_death_group = 2;
		$days_to_death_group_name = '60 to 119';
	} elsif ($days_to_death >= 120 && $days_to_death < 180) {
		$days_to_death_group = 3;
		$days_to_death_group_name = '120 to 179';
	} elsif ($days_to_death >= 180 && $days_to_death < 240) {
		$days_to_death_group = 4;
		$days_to_death_group_name = '180 to 239';
	} elsif ($days_to_death >= 240 && $days_to_death < 300) {
		$days_to_death_group = 5;
		$days_to_death_group_name = '240 to 299';
	} elsif ($days_to_death >= 300 && $days_to_death < 360) {
		$days_to_death_group = 6;
		$days_to_death_group_name = '300 to 359';
	} elsif ($days_to_death >= 360 && $days_to_death < 420) {
		$days_to_death_group = 7;
		$days_to_death_group_name = '360 to 419';
	} elsif ($days_to_death >= 420 && $days_to_death < 480) {
		$days_to_death_group = 8;
		$days_to_death_group_name = '420 to 479';
	} elsif ($days_to_death >= 480 && $days_to_death < 540) {
		$days_to_death_group = 9;
		$days_to_death_group_name = '480 to 539';
	} elsif ($days_to_death >= 540 && $days_to_death < 600) {
		$days_to_death_group = 10;
		$days_to_death_group_name = '540 to 599';
	} elsif ($days_to_death >= 600 && $days_to_death < 660) {
		$days_to_death_group = 11;
		$days_to_death_group_name = '600 to 659';
	} elsif ($days_to_death >= 660 && $days_to_death < 720) {
		$days_to_death_group = 12;
		$days_to_death_group_name = '660 to 719';
	} elsif ($days_to_death >= 720 && $days_to_death < 780) {
		$days_to_death_group = 13;
		$days_to_death_group_name = '720 to 779';
	} elsif ($days_to_death >= 780 && $days_to_death < 840) {
		$days_to_death_group = 14;
		$days_to_death_group_name = '780 to 839';
	} elsif ($days_to_death >= 840 && $days_to_death <= 900) {
		$days_to_death_group = 15;
		$days_to_death_group_name = '840 to 900';
	} else {
		die "days_to_death : $days_to_death";
	}
	return ($days_to_death_group, $days_to_death_group_name);
}

__END__