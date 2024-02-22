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

# Group: Population Estimates - DPE
# Table: Estimated Resident Population by Age and Sex (1991+) (Annual-Dec)
my $pop_esti_file = 'raw_data/DPE403905_20240219_032202_8.csv';

# Group: Births - VSB
# Table: Live births by age of mother (Annual-Dec)
my $births_file   = 'raw_data/VSB355804_20240221_104322_48.csv';

# Group: Deaths - VSD
# Table: Deaths by age and sex (Annual-Dec)
my $deaths_file   = 'raw_data/VSD349204_20240221_105046_61.csv';

# Group: International Travel and Migration - ITM
# Table: Estimated migration by direction, age group and sex, 12/16-month rule (Annual-Dec)
my $immi_file     = 'raw_data/ITM552114_20240221_105550_31.csv';

my %deaths        = ();
my %births        = ();
my %pop_esti      = ();
my %immi          = ();
my %y_immi        = ();
my %r_immi        = ();
my %y_pop_esti    = ();
my %y_deaths      = ();

my $target_year   = 2022;
my $from_date     = '20230101';
my $cutoff_date   = '20231231';
my %pop_by_ages   = ();

load_deaths();
load_births();
load_pop();
load_immi();

my %doses_by_dates = ();
model_targeted_year_pop();

my %doses_by_dates_and_age_groups = ();
print_report_by_age();
open my $out, '>:utf8', 'data/2023_first_doses_no_dose_by_oia_age_groups_and_dates.csv';
say $out 'Date,Age Group,First Doses,No Dose';
for my $oia_age_group (sort keys %doses_by_dates_and_age_groups) {
	for my $compdate (sort{$a <=> $b} keys %{$doses_by_dates_and_age_groups{$oia_age_group}}) {
		my $date = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'date'} // die;
		my $had_first_dose = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_first_dose'} // 0;
		my $had_no_dose = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_no_dose'} // 0;
		say $out "$date,$oia_age_group,$had_first_dose,$had_no_dose";
	}
}
close $out;

sub print_report_by_age {
	open my $out, '>:utf8', 'data/2023_first_doses_no_dose_by_age_and_dates.csv';
	say $out 'Date,Age,First Doses,No Dose';
	for my $compdate (sort{$a <=> $b} keys %doses_by_dates) {
		my $date = $doses_by_dates{$compdate}->{'date'} // die;
		my %daily_rates_by_ages = ();
		my ($year, $month) = split '-', $date;
		for my $age_group_name (sort keys %{$doses_by_dates{$compdate}->{'age_groups'}}) {
			next if $age_group_name eq 'Total' || $age_group_name eq 'Various';
			my $population  = generate_population_by_age_group($age_group_name);
			die unless $population;
			my $first_doses = $doses_by_dates{$compdate}->{'age_groups'}->{$age_group_name} // die;
			my $first_doses_by_100 = nearest(0.01, $first_doses * 100 / $population);
			$daily_rates_by_ages{$age_group_name}->{'first_doses'}        = $first_doses;
			$daily_rates_by_ages{$age_group_name}->{'first_doses_by_100'} = $first_doses_by_100;
		}

		for my $age_group_name (sort keys %daily_rates_by_ages) {
			my $first_doses         = $daily_rates_by_ages{$age_group_name}->{'first_doses'}        // die;
			my $first_doses_by_100  = $daily_rates_by_ages{$age_group_name}->{'first_doses_by_100'} // die;
			my ($from_age, $to_age) = split '-', $age_group_name;
			if ($to_age) {
			} else {
				die unless $from_age =~ /\+/;
				$from_age =~ s/\+//;
				$to_age = 90;
			}
			for my $age ($from_age .. $to_age) {
				my $population     = $pop_by_ages{$age} // die;
				my $had_first_dose = nearest(1, $population * $first_doses_by_100 / 100);
				my $had_no_dose    = $population - $had_first_dose;
				my $oia_age_group  = oia_age_group_from_age_groups_src($age);
				$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'date'} = $date;
				$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'year_month'} = "$year-$month";
				$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_first_dose'} += $had_first_dose;
				$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_no_dose'} += $had_no_dose;
				say $out "$date,$age,$had_first_dose,$had_no_dose";
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
				$header    = 90 if $header > 90;
				$deaths{$year}->{$header} += $value;
				$y_deaths{$year} += $value;
			}
		}
	}
	close $in;
	# p%deaths;die;
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

sub load_births {
	my %headers = ();
	open my $in, '<:utf8', $births_file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year, $value) = split ',', $_;
		next unless defined $year && looks_like_number $year;
		$births{$year} = $value;
	}
	close $in;
}

sub load_pop {
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
				$header    = 90 if $header > 90;
				$pop_esti{$year}->{$header} += $value;
			}
		}
	}
	close $in;
}

sub load_immi {
	my %headers = ();
	open my $in, '<:utf8', $immi_file;
	my @ages = (0 .. 89);
	push @ages, '90+';
	my @directions = ('arrivals', 'departures');
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year, @values) = split ',', $_;
		next unless defined $year && looks_like_number $year;
		my $v_num = 0;
		for my $direction (@directions) {
			for my $age (@ages) {
				$age =~ s/\+//;
				my $female = $values[$v_num] // die;
				$v_num++;
				my $male = $values[$v_num] // die;
				$v_num++;
				$immi{$year}->{$age}->{$direction}->{'female'} = $female;
				$immi{$year}->{$age}->{$direction}->{'male'} = $male;
				if ($direction eq 'arrivals') {
					$y_immi{$year} += $female;
					$y_immi{$year} += $male;
					if ($year >= 2019 && $year <= 2023) {
						$r_immi{$year}->{$age} += $female;
						$r_immi{$year}->{$age} += $male;
					}
				} else {
					unless (exists $y_immi{$year}) {
						$y_immi{$year} = 0;
					}
					$y_immi{$year} -= $female;
					$y_immi{$year} -= $male;
					if ($year >= 2019 && $year <= 2023) {
						$r_immi{$year}->{$age} -= $female;
						$r_immi{$year}->{$age} -= $male;
					}
				}
			}
		}
	}
	close $in;
}

sub model_targeted_year_pop {
	my %yearly_pop  = ();
	# For each year following 2018, each age group ages 1. Births & Immigration are integrated, and deaths are subtracted from each age group.
	for my $age (sort{$a <=> $b} keys %{$pop_esti{2018}}) {
		$pop_by_ages{$age} = $pop_esti{2018}->{$age};
		$yearly_pop{2018}->{$age} = $pop_esti{2018}->{$age};
		$yearly_pop{2018}->{'Total'} += $pop_esti{2018}->{$age};
	}
	# p%pop_by_ages;die;

	for my $year (2019 .. $target_year) {

		# Subtract to each age every people who died in the past year.
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			my $deaths = $deaths{$year}->{$age} // die;
			$pop_by_ages{$age} -= $deaths;
			die if $pop_by_ages{$age} < 0;
			# say "$age : $deaths";
		}

		# Adds or subtract to each age the yearly net immigration.
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			my $immi = $r_immi{$year}->{$age} // die;
			$pop_by_ages{$age} += $immi;
			die if $pop_by_ages{$age} < 0;
			# say "$age : $immi";
		}

		# The 90+ who aren't dead are staying there.
		my %new_pop_age = ();
		$new_pop_age{90} = $pop_by_ages{90} // die;

		# Each age ages of 1 year (aside for the 90+)
		for my $age (0 .. 89) {
			my $pop = $pop_by_ages{$age} // die;
			my $age_p_1 = $age + 1;
			$new_pop_age{$age_p_1} += $pop;
		}

		# Lastly, the births are added as new zero.
		$new_pop_age{0} = $births{$year} // die;

		# The old pyramide is erased, and the yearly totals are incremented to the recap.
		for my $age (sort{$a <=> $b} keys %new_pop_age) {
			my $pop = $new_pop_age{$age} // die;
			$pop_by_ages{$age} = $pop;
			$yearly_pop{$year}->{$age} = $pop;
			$yearly_pop{$year}->{'Total'} += $pop;
		}
	}

	# Controls against the census data (we would expect +/- 6K offset).
	my $offset_sum = 0;
	for my $age (sort{$a <=> $b} keys %pop_by_ages) {
		my $pop = $pop_by_ages{$age} // die;
		my $control_pop = $pop_esti{$target_year}->{$age} // die;
		my $offset = $control_pop - $pop;
		say "$age | $pop vs $control_pop ($offset)";
		$offset_sum += $offset;
	}
	say "offset_sum : $offset_sum";

	# Now for each date and age group with dose data, calculating vaccination percents for each age among the scope (0 - 90+).
	my $file   = 'data/first_doses_by_age_groups_and_dates.csv';
	open my $in, '<:utf8', $file or die $!;
	while (<$in>) {
		chomp $_;
		my ($date, $age_group, $first_doses) = split ',', $_;
		next if $date eq 'Date';
		my $compdate = $date;
		$compdate =~ s/\D//g;
		next if $compdate < $from_date;
		next if $compdate > $cutoff_date;
		$doses_by_dates{$compdate}->{'date'} = $date;
		$doses_by_dates{$compdate}->{'age_groups'}->{$age_group} += $first_doses;
	}
	close $in;
}

sub generate_population_by_age_group {
	my ($age_group_name) = @_;
	my ($from_age, $to_age) = split '-', $age_group_name;
	my $population = 0;
	if ($from_age && $to_age) {
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			next unless $from_age <= $age && $age <=$to_age;
			$population += $pop_by_ages{$age};
		}
	} else {
		die unless $from_age;
		if (
			$from_age eq '65+' ||
			$from_age eq '90+' ||
			$from_age eq '80+'
		) {
			$from_age =~ s/\+//;
			for my $age (sort{$a <=> $b} keys %pop_by_ages) {
				next unless $from_age <= $age;
				$population += $pop_by_ages{$age};
			}
		} else {
			die "from_age : $from_age";
		}
	}
	return $population;
}