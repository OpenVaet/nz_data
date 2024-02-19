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
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);

my %doses_by_dates     = ();

# Loading population estimates.
my %pop_by_age_groups  = ();
my %pop_by_ages        = ();
my $pop_esti_file      = 'raw_data/DPE403905_20240219_032202_8.csv';
my $archive_doses_file = 'data/nz_doses_administered_from_archive.csv';
load_pop_esti();
load_archive_doses();
load_git_doses();
my %evaluated_months   = ();
my %first_doses_by_dates_ages = ();
print_data_by_ages_and_age_groups();
print_oia_compatible_data();

sub load_pop_esti {
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
			next if $year < 2019;
			my %values = ();
			my @values = split ',', $_;
			for my $value_ref (1 .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				$header    = strip_age($header);
				$pop_by_ages{$year}->{$header} += $value;
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

sub generate_population_by_age_group {
	my ($year, $age_group_name) = @_;
	my ($from_age, $to_age) = split '-', $age_group_name;
	my $population = 0;
	if ($from_age && $to_age) {
		for my $age (sort{$a <=> $b} keys %{$pop_by_ages{$year}}) {
			next unless $from_age <= $age && $age <=$to_age;
			$population += $pop_by_ages{$year}->{$age};
		}
	} else {
		die unless $from_age;
		if (
			$from_age eq '65+' ||
			$from_age eq '90+' ||
			$from_age eq '80+'
		) {
			$from_age =~ s/\+//;
			for my $age (sort{$a <=> $b} keys %{$pop_by_ages{$year}}) {
				next unless $from_age <= $age;
				$population += $pop_by_ages{$year}->{$age};
			}
		} else {
			die "from_age : $from_age";
		}
	}
	return $population;
}

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
	open my $out_1, '>:utf8', 'data/last_date_doses_rates_by_dates_and_age_groups.csv';
	say $out_1 'Date,Age Group,First Doses,Population,% With First Doses';
	open my $out_3, '>:utf8', 'data/total_first_doses_by_dates.csv';
	say $out_3 'Date,First Doses';
	open my $out_4, '>:utf8', 'data/first_doses_no_dose_by_age_and_dates';
	say $out_4 'Date,Age,First Doses,No Dose,Population,% With First Doses From Age Group';
	my $total_dates = keys %doses_by_dates;
	my $d_num = 0;
	for my $compdate (sort{$a <=> $b} keys %doses_by_dates) {
		my $date = $doses_by_dates{$compdate}->{'date'} // die;
		$d_num++;
		my $out_2;
		if ($d_num == $total_dates) {
			open $out_2, '>:utf8', 'data/last_date_doses_rates_by_age_groups.csv';
			say $out_2 'Age Group,First Doses,Population,% With First Doses';
		}
		my $daily_doses_total = 0;
		my %daily_rates_by_ages = ();
		my ($year, $month) = split '-', $date;
		$evaluated_months{$year}->{$month} = 1;
		for my $age_group_name (sort keys %{$doses_by_dates{$compdate}->{'age_groups'}}) {
			next if $age_group_name eq 'Total' || $age_group_name eq 'Various';
			my $population  = $pop_by_age_groups{$year}->{$age_group_name}->{'population'};
			if (!$population) {
				$population = generate_population_by_age_group($year, $age_group_name);
				die unless $population;
			}
			my $first_doses = $doses_by_dates{$compdate}->{'age_groups'}->{$age_group_name} // die;
			my $first_doses_by_100 = nearest(0.01, $first_doses * 100 / $population);
			if ($d_num == $total_dates) {
				say $out_2 "$age_group_name,$first_doses,$population,$first_doses_by_100";
			}
			say $out_1 "$date,$age_group_name,$first_doses,$population,$first_doses_by_100";
			$daily_doses_total += $first_doses;
			$daily_rates_by_ages{$age_group_name}->{'first_doses'}        = $first_doses;
			$daily_rates_by_ages{$age_group_name}->{'first_doses_by_100'} = $first_doses_by_100;
		}
		say $out_3 "$date,$daily_doses_total";
		if ($d_num == $total_dates) {
			close $out_2;
		}

		for my $age_group_name (sort keys %daily_rates_by_ages) {
			my $first_doses         = $daily_rates_by_ages{$age_group_name}->{'first_doses'}        // die;
			my $first_doses_by_100  = $daily_rates_by_ages{$age_group_name}->{'first_doses_by_100'} // die;
			my ($from_age, $to_age) = split '-', $age_group_name;
			if ($to_age) {
			} else {
				die unless $from_age =~ /\+/;
				$from_age =~ s/\+//;
				$to_age = 95;
			}
			for my $age ($from_age .. $to_age) {
				my $population     = $pop_by_ages{$year}->{$age} // die;
				my $had_first_dose = nearest(1, $population * $first_doses_by_100 / 100);
				my $had_no_dose    = $population - $had_first_dose;
				$first_doses_by_dates_ages{$year}->{"$month"}->{$date}->{$age}->{'had_first_dose'} = $had_first_dose;
				$first_doses_by_dates_ages{$year}->{"$month"}->{$date}->{$age}->{'had_no_dose'} = $had_no_dose;
				$first_doses_by_dates_ages{$year}->{"$month"}->{$date}->{$age}->{'population'} = $population;
				$first_doses_by_dates_ages{$year}->{"$month"}->{$date}->{$age}->{'first_dose_percent'} = $first_doses_by_100;
				say $out_4 "$date,$age,$had_first_dose,$had_no_dose,$population,$first_doses_by_100";
			}
		}
	}
	close $out_1;
	close $out_3;
	close $out_4;
}

sub print_oia_compatible_data {
	open my $out, '>:utf8', 'data/first_doses_no_dose_by_oia_age_groups_and_months.csv';
	say $out "year_month,closest_dose_date,age_group,had_first_dose,had_no_dose";
	for my $year (sort{$a <=> $b} keys %evaluated_months) {
		for my $month (sort{$a <=> $b} keys %{$evaluated_months{$year}}) {
			die unless exists $first_doses_by_dates_ages{$year}->{$month};
			my %by_dif_to_15 = ();
			for my $date (sort keys %{$first_doses_by_dates_ages{$year}->{$month}}) {
				my (undef, undef, $day) = split '-', $date;
				my $dif_to_15 = abs(15 - $day);
				$by_dif_to_15{$dif_to_15} = $date;
			}

			my $closest_dose_date;
			for my $dif_to_15 (sort{$a <=> $b} keys %by_dif_to_15) {
				$closest_dose_date = $by_dif_to_15{$dif_to_15} // die;
				last;
			}
			die unless $closest_dose_date;

			my %oia_age_groups_on_date = ();
			for my $age (sort{$a <=> $b} keys %{$first_doses_by_dates_ages{$year}->{"$month"}->{$closest_dose_date}}) {
				my $had_first_dose = $first_doses_by_dates_ages{$year}->{"$month"}->{$closest_dose_date}->{$age}->{'had_first_dose'} // die;
				my $had_no_dose    = $first_doses_by_dates_ages{$year}->{"$month"}->{$closest_dose_date}->{$age}->{'had_no_dose'}    // die;
				my $oia_age_group  = oia_age_group_from_age_groups_src($age);
				$oia_age_groups_on_date{$oia_age_group}->{'had_first_dose'} += $had_first_dose;
				$oia_age_groups_on_date{$oia_age_group}->{'had_no_dose'}    += $had_no_dose;
			}
			for my $oia_age_group (sort keys %oia_age_groups_on_date) {
				my $had_first_dose = $oia_age_groups_on_date{$oia_age_group}->{'had_first_dose'} // die;
				my $had_no_dose = $oia_age_groups_on_date{$oia_age_group}->{'had_no_dose'} // die;
				say $out "$year-$month,$closest_dose_date,$oia_age_group,$had_first_dose,$had_no_dose";
			}
		}
	}
	close $out;
}

sub oia_age_group_from_age_groups_src {
	my $age = shift;
	my $oia_age_group;
	if ($age <= 20) {
		$oia_age_group = '0-20';
	} elsif ($age >= 21 && $age <= 40) {
		$oia_age_group = '21-40';
	} elsif ($age >= 41 && $age <= 60) {
		$oia_age_group = '41-60';
	} elsif ($age >= 61 && $age <= 80) {
		$oia_age_group = '61-80';
	} elsif ($age >= 81) {
		$oia_age_group = '81+';
	} else {
		die "age : $age";
	}
	return $oia_age_group;
}