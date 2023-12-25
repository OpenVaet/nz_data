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

my %stats                 = ();
my %pop                   = ();
my %dates                 = ();
my %age_groups            = ();
my %age_groups_srcs       = ();
my %nzwb_data             = ();
my %nzwb_population       = ();
my %doses_administered    = ();
my %deaths_by_months      = ();
my %daily_odds_of_dying   = ();
my %recruitment_by_day    = ();
my %doses_by_day          = ();
my %nz_deaths_stats       = ();
my %nzwb_deaths_stats     = ();
my %kdeaths_stats_by_days = ();
my $cutoff_compdate       = 20230930;

# Deaths data from https://www.stats.govt.nz/assets/Uploads/Births-and-deaths/Births-and-deaths-Year-ended-September-2023/Download-data/Monthly-death-registrations-by-ethnicity-age-sex-Jan2010-Sep2023.xlsx
my $deaths_by_months_file = 'raw_data/Monthly_death_registrations_by_ethnicity_age_sex_Jan2021_Sep2023.csv';
my $nzwb_file             = 'data/nzwb_dob_removed.csv';
my $nzwb_file_gz          = 'data/nzwb_dob_removed.csv.gz';
my $nz_pop_file           = 'raw_data/DPE403903_20231206_032556_74.csv';

# Load deaths & population.
load_deaths();
load_pop();

# Load NZWB dataset.
load_nzwb_data();

# Renders total of subjects & sets a few variables.
my $total_recipients = keys %nzwb_data;
say "total_recipients : $total_recipients"; # 2 215 729

# Computes the likelyhood to die by month & by day, given deaths / pop.
calc_expected_mortality_rates();

# Builds NZWB dataset stats (how many died, by age groups, during the observed period)
calc_nzwb_dataset_stats();

# p%stats;
# p%nzwb_deaths_stats;


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
	open my $out, '>:utf8', 'data/nz_2021_2023_deaths.csv';
	say $out "year,month,age_group,count";
	for my $year (sort{$a <=> $b} keys %deaths_by_months) {
		next if $year < 2021;
		for my $month (sort{$a <=> $b} keys %{$deaths_by_months{$year}}) {
			for my $age_group (sort keys %{$deaths_by_months{$year}->{$month}}) {
				my $age_groups_src = $age_groups_srcs{$age_group} // die;
				my $count = $deaths_by_months{$year}->{$month}->{$age_group} // die;
				say $out "$year,$month,$age_groups_src,$count";
			}
		}
	}
	close $out;
}

sub load_pop {
	say "Loading population ...";
	my %headers = ();
	open my $in, '<:utf8', $nz_pop_file or die "missing source file : [$nz_pop_file]";
	my %population_2021_by_age = ();
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year) = split ',', $_;
		next unless defined $year;
		if ($year eq ' ') {
			my @headers = split ",", $_;
			my $scope   = (scalar @headers - 2) / 3;
			my $from    = scalar @headers - $scope;
			for my $header_ref ($from .. scalar @headers - 1) {
				my $header = $headers[$header_ref] // die;
				$headers{$header_ref} = $header;
			}
		} else {
			next unless keys %headers;
			next unless looks_like_number($year);
			my @values = split ',', $_;
			my $scope   = (scalar @values - 2) / 3;
			my $from    = scalar @values - $scope;
			for my $value_ref ($from .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				my $age    = age_from_header($header);
				next unless looks_like_number $value;
				my ($age_group, $age_group_name) = age_group_5_from_age($age);
				$pop{$year}->{$age_group} += $value;
				if ($year eq 2021) {
					$age = '90' if $age >= 90;
					$population_2021_by_age{$age} += $value;
				}
			}
		}
	}
	close $in;

	# Prints 2021 reference population to be used by R.
	open my $out, '>:utf8', 'data/nz_2021_june_census.csv';
	say $out 'age,count';
	for my $age (sort{$a <=> $b} keys %population_2021_by_age) {
		next if $age == 0;
		my $count = $population_2021_by_age{$age} // die;
		$age = '90+' if $age eq '90';
		say $out "$age,$count";
	}
	close $out;
}

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
		my ($mrn, $batch_id, $dose_number, $date_time_of_service, $date_of_death, $age) = split ',', $_;
		next if $mrn eq 'mrn';
		my $died = 0;
		if ($date_of_death) {
			$died = 1;
		}
		if ($died && (exists $nzwb_data{$mrn}->{'died'} && !$nzwb_data{$mrn}->{'died'})) {
			die "was here on another row, not dead";
			$nzwb_data{$mrn}->{'died'} = $died;
		} elsif ($died) {
			$nzwb_data{$mrn}->{'died'} = $died;
		} else {
			if (!$died && !exists $nzwb_data{$mrn}->{'died'}) {
				$nzwb_data{$mrn}->{'died'} = $died;
			}
		}
		my $compdate_of_service = $date_time_of_service;
		$compdate_of_service =~ s/\D//g;
		if (!exists $nzwb_data{$mrn}->{'joined_on'}) {
			$nzwb_data{$mrn}->{'joined_on'} = 99999999;
		}
		$nzwb_data{$mrn}->{'joined_on'} = $compdate_of_service if $compdate_of_service < $nzwb_data{$mrn}->{'joined_on'};
		$nzwb_data{$mrn}->{'age'} = $age;
		$nzwb_data{$mrn}->{'doses'}->{$dose_number} = $date_time_of_service;
		$nzwb_data{$mrn}->{'date_of_death'} = $date_of_death;
	}
	close $in;
	STDOUT->printflush("\rLoading NZWB data ... [$loaded] rows loaded");
	say "";
}

sub age_from_header {
	my $header = shift;
	$header =~ s/Less than 1 year/0/;
	$header =~ s/ years and over//;
	$header =~ s/ years//;
	$header =~ s/ year//;
	$header =~ s/ Years and Over//;
	$header =~ s/ Years//;
	$header =~ s/ Year//;
	if ($header >= 90) {
		$header = 90;
	}
	return $header;
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

sub calculate_days_difference {
    my ($date1, $date2) = @_;

    # Calculate the difference as a DateTime::Duration object
    my $duration = $date1->delta_days($date2);

    # Get the difference in days as a number
    my $days = $duration->in_units('days');

    # Return the absolute value of the difference
    return abs($days);
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
	if ($age_groups_src eq '90_94' || $age_groups_src eq '95_') {
		$age_groups_src = '90_';
	}
	$age_groups_srcs{$age_group} = $age_groups_src;
	return $age_group;
}

sub age_group_5_from_age {
	my $header = shift;
	$header =~ s/Less than 1 year/0/;
	$header =~ s/ years and over//;
	$header =~ s/ years//;
	$header =~ s/ year//;
	$header =~ s/ Years and Over//;
	$header =~ s/ Years//;
	$header =~ s/ Year//;
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

sub calc_expected_mortality_rates {
	say "Calculating official mortality rates ...";
	my %monthly_odds_of_dying = ();
	my $start_date = DateTime->new(year => 2021, month => 1, day => 01);
	my $end_date   = DateTime->new(year => 2023, month => 9, day => 30);
	my %days_by_months = ();
	while ($start_date <= $end_date) {
	    my ($y, $m, $d) = split '-', $start_date->ymd;
	    $days_by_months{$y}->{$m}++;
	    $start_date->add(days => 1);
	}
	open my $out, '>:utf8', 'monthly_odds_of_dying.csv';
	say $out "year,age_group,age_group_name,ref_pop,month,days_in_month,days_of_exposure,deaths,monthly_deaths_per_100000";
	for my $year (sort{$a <=> $b} keys %deaths_by_months) {
		# say '*' x 50;
		# say "year : $year";
		for my $age_group (sort{$a <=> $b} keys %age_groups) {
			my $age_group_name = $age_groups{$age_group} // die;
			my $ref_pop = $pop{$year}->{$age_group} // die;
			# say "age_group : $age_group";
			# say "age_group_name : $age_group_name";
			# say "ref_pop : $ref_pop";
			for my $month (sort{$a <=> $b} keys %{$deaths_by_months{$year}}) {
				# say "month : $month";
				# p$deaths_by_months{$year}->{$month};
				my $deaths = $deaths_by_months{$year}->{$month}->{$age_group} // 0;
				# say "deaths : $deaths";
				$month = "0$month" if $month < 10;
				my $days_in_month = $days_by_months{$year}->{$month} // die;
				# say "days_in_month : $days_in_month";
				my $days_of_exposure = $days_in_month * $ref_pop;
				# say "days_of_exposure : $days_of_exposure";
				my $monthly_deaths_per_100000 = $deaths * 100000 / $days_of_exposure;
				# say "monthly_deaths_per_100000 : $monthly_deaths_per_100000";
				my $daily_deaths_per_100000 = $monthly_deaths_per_100000 / $days_in_month;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'ref_pop'} = $ref_pop;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'days_in_month'} = $days_in_month;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'days_of_exposure'} = $days_of_exposure;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'deaths'} = $deaths;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'monthly_deaths_per_100000'} = $monthly_deaths_per_100000;
				$monthly_odds_of_dying{$year}->{$month}->{$age_group}->{'daily_deaths_per_100000'} = $daily_deaths_per_100000;
				say $out "$year,$age_group,$age_group_name,$ref_pop,$month,$days_in_month,$days_of_exposure,$deaths,$monthly_deaths_per_100000,$daily_deaths_per_100000";
				
				# If we are within the window covered by NZWB dataset (+/- 8 days in April, increment stats for the age group)
				if (($year eq 2021 && $month >= 4) || ($year > 2020 && $year ne 2023) || ($year eq '2023' && $month < 10)) {
					$nz_deaths_stats{$age_group}->{'subjects_died'}+= $deaths;
					$nz_deaths_stats{$age_group}->{'subjects_total'}+= $ref_pop;
					$nz_deaths_stats{$age_group}->{'days_of_exposure'} += $days_of_exposure;
					$nz_deaths_stats{$age_group}->{'age_group_name'} = $age_group_name;
				}
			}
		}
	}
	close $out;
	$start_date = DateTime->new(year => 2021, month => 1, day => 01);
	$end_date   = DateTime->new(year => 2023, month => 9, day => 30);

	# Printing daily dataframe.
	open my $out_day, '>:utf8', 'daily_odds_of_dying.csv';
	my $line = "day";
	for my $age_group (sort{$a <=> $b} keys %age_groups) {
		my $age_group_name = $age_groups{$age_group} // die;
		$line .= ",$age_group_name"
	}
	say $out_day $line;
	while ($start_date <= $end_date) {
	    my ($y, $m, $d) = split '-', $start_date->ymd;
		my $line = "$y-$m-$d";
	    for my $age_group (sort{$a <=> $b} keys %age_groups) {
	    	my $daily_deaths_per_100000 = $monthly_odds_of_dying{$y}->{$m}->{$age_group}->{'daily_deaths_per_100000'} // 0;
			$line .= ",$daily_deaths_per_100000";
	    }
	    say $out_day $line;
	    $start_date->add(days => 1);
	}
	close $out_day;
}

sub convert_compdate_to_date {
	my $cp = shift;
	my ($y, $m, $d) = $cp =~ /(....)(..)(..)/;
	return "$y-$m-$d";
}

sub calc_nzwb_dataset_stats {
	STDOUT->printflush("\rCalculating NZWB stats ...");
	my ($loaded, $cpt) = (0, 0);
	open my $out_sub, '>:utf8', 'subjects_data.csv';
	say $out_sub "subject_id,age_group,date_of_death,joined_on,subject_cutoff,days_of_exposure,died";
	my $total = keys %nzwb_data;
	for my $subject_id (sort{$a <=> $b} keys %nzwb_data) {
		my $age = $nzwb_data{$subject_id}->{'age'} // die;
		$loaded++;
		$cpt++;
		if ($cpt == 1000) {
			$cpt = 0;
			STDOUT->printflush("\rCalculating NZWB stats ... [$loaded / $total]");
		}
		if ($age <= 4) {
			$stats{'under_or_4'}++;
			next;
		}
		my ($age_group, $age_group_name) = age_group_5_from_age($age);
		my $died = $nzwb_data{$subject_id}->{'died'} // die;
		my $date_of_death = $nzwb_data{$subject_id}->{'date_of_death'};
		my $compdate_death;
		if ($date_of_death) {
			$compdate_death = $date_of_death;
			$compdate_death =~ s/\D//g;
		}
		if ($died && $compdate_death && ($compdate_death <= $cutoff_compdate)) {
			$nzwb_deaths_stats{$age_group}->{'subjects_died'}++;
			$kdeaths_stats_by_days{'totals'}->{$compdate_death}->{'subjects_died'}++;
			$kdeaths_stats_by_days{'by_age_groups'}->{$compdate_death}->{$age_group}->{'subjects_died'}++;
		}
		my $joined_on = $nzwb_data{$subject_id}->{'joined_on'} // die;
		my $subject_cutoff;
		if ($compdate_death) {
			$subject_cutoff  = $compdate_death;
		} else {
			$subject_cutoff  = $cutoff_compdate;
		}
		$nzwb_population{$joined_on}->{'total'}++;
		$nzwb_population{$joined_on}->{'by_age_groups'}->{$age_group}++;
		$joined_on = convert_compdate_to_date($joined_on);
		$recruitment_by_day{$joined_on}++;
		$subject_cutoff = convert_compdate_to_date($subject_cutoff);
		my $joined_on_dt = parse_date($joined_on);
		my $subject_cutoff_dt = parse_date($subject_cutoff);
		my $days_of_exposure = calculate_days_difference($joined_on_dt, $subject_cutoff_dt);
		say $out_sub "$subject_id,$age_group,$date_of_death,$joined_on,$subject_cutoff,$days_of_exposure,$died";
		$nzwb_deaths_stats{$age_group}->{'subjects_total'}++;
		$nzwb_deaths_stats{$age_group}->{'days_of_exposure'} += $days_of_exposure;
		$nzwb_deaths_stats{$age_group}->{'age_group_name'} = $age_group_name;
	}
	STDOUT->printflush("\rCalculating NZWB stats ... [$loaded / $total]");
	say "";
	close $out_sub;
	open my $out, '>:utf8', 'nzwb_observed_deaths.csv';
	open my $out_comp, '>:utf8', 'nzwb_vs_official_observed_deaths.csv';
	say $out "age_group,age_group_name,subjects_died,subjects_total,days_of_exposure,deaths_per_100000";
	say $out_comp "age_group,age_group_name,nzwb_subjects_died,nzwb_subjects_total,nzwb_days_of_exposure,nzwb_deaths_per_100000,nz_subjects_died,nz_subjects_total,nz_days_of_exposure,nz_deaths_per_100000";
	for my $age_group (sort{$a <=> $b} keys %nzwb_deaths_stats) {
		my $age_group_name = $nzwb_deaths_stats{$age_group}->{'age_group_name'} // die;
		my $nzwb_subjects_died = $nzwb_deaths_stats{$age_group}->{'subjects_died'} // 0;
		my $nzwb_subjects_total = $nzwb_deaths_stats{$age_group}->{'subjects_total'} // 0;
		my $nzwb_days_of_exposure = $nzwb_deaths_stats{$age_group}->{'days_of_exposure'} // 0;
		my $nzwb_deaths_per_100000 = $nzwb_subjects_died * 100000 / $nzwb_days_of_exposure;
		$nzwb_deaths_stats{$age_group}->{'deaths_per_100000'} = $nzwb_deaths_per_100000;

		my $nz_subjects_died = $nz_deaths_stats{$age_group}->{'subjects_died'} // 0;
		my $nz_subjects_total = $nz_deaths_stats{$age_group}->{'subjects_total'} // 0;
		my $nz_days_of_exposure = $nz_deaths_stats{$age_group}->{'days_of_exposure'} // 0;
		my $nz_deaths_per_100000 = $nz_subjects_died * 100000 / $nz_days_of_exposure;
		$nz_deaths_stats{$age_group}->{'deaths_per_100000'} = $nz_deaths_per_100000;
		say $out "$age_group,$age_group_name,$nzwb_subjects_died,$nzwb_subjects_total,$nzwb_days_of_exposure,$nzwb_deaths_per_100000";
		if ($age_group > 2) {
			say $out_comp "$age_group,$age_group_name,$nzwb_subjects_died,$nzwb_subjects_total,$nzwb_days_of_exposure,$nzwb_deaths_per_100000,$nz_subjects_died,$nz_subjects_total,$nz_days_of_exposure,$nz_deaths_per_100000";
		}
	}
	close $out;
	close $out_comp;

	open my $out_pop, '>:utf8', 'nzwb_population_by_day.csv';
	say $out_pop "date,total";
	for my $compdate (sort{$a <=> $b} keys %nzwb_population) {
		my $total = $nzwb_population{$compdate}->{'total'} // die;
		my $date = convert_compdate_to_date($compdate);
		say $out_pop "$date,$total";
	}
	close $out_pop;

	open my $out_d1, '>:utf8', 'nzwb_deaths_by_day.csv';
	say $out_d1 "date,deaths total,cumulated population to day,deaths per 10000000 DOE";
	my $died_to_date = 0;
	for my $compdate (sort{$a <=> $b} keys %{$kdeaths_stats_by_days{'totals'}}) {
	    my ($y, $m, $d) = $compdate =~ /(....)(..)(..)/;
	    my $date = "$y-$m-$d";
		my $subjects_died = $kdeaths_stats_by_days{'totals'}->{$compdate}->{'subjects_died'} // die;
		my $population_total = 0;
		for my $pop_compdate (sort{$b <=> $a} keys %nzwb_population) {
			next if $pop_compdate > $compdate;
			$population_total += $nzwb_population{$pop_compdate}->{'total'};
		}
		$population_total = $population_total - $died_to_date;
		my $deaths_per_10000000_doe = $subjects_died * 10000000 / $population_total;
		say $out_d1 "$date,$subjects_died,$population_total,$deaths_per_10000000_doe";

		$died_to_date += $subjects_died;
	}
	close $out_d1;

	open my $out_d2, '>:utf8', 'nzwb_deaths_by_day_age_groups.csv';
	say $out_d2 "date,age group,deaths total,cumulated population to day,deaths per 10000000 DOE";
	my %died_to_date = ();
	for my $compdate (sort{$a <=> $b} keys %{$kdeaths_stats_by_days{'by_age_groups'}}) {
	    my ($y, $m, $d) = $compdate =~ /(....)(..)(..)/;
	    my $date = "$y-$m-$d";
		for my $age_group (sort{$a <=> $b} keys %{$kdeaths_stats_by_days{'by_age_groups'}->{$compdate}}) {
			my $age_group_name = $age_groups{$age_group} // die;
			my $subjects_died  = $kdeaths_stats_by_days{'by_age_groups'}->{$compdate}->{$age_group}->{'subjects_died'} // die;
			my $population_total = 0;
			for my $pop_compdate (sort{$b <=> $a} keys %nzwb_population) {
				next if $pop_compdate > $compdate;
				next unless exists $nzwb_population{$pop_compdate}->{'by_age_groups'}->{$age_group};
				$population_total += $nzwb_population{$pop_compdate}->{'by_age_groups'}->{$age_group};
			}

			my $died_to_date  = $died_to_date{$age_group} // 0;
			$population_total = $population_total - $died_to_date;

			my $deaths_per_10000000_doe = $subjects_died * 10000000 / $population_total;


			say $out_d2 "$date,$age_group_name,$subjects_died,$population_total,$deaths_per_10000000_doe";

			$died_to_date{$age_group} += $subjects_died;
		}
	}
	close $out_d2;
}