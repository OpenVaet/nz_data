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
my $target_year   = 2023;
my $target_date   = '2022-12-07';
my $from_date     = '20221207';
my $cutoff_date   = '20231231';
my %pop_by_ages   = ();
my %target_doses  = ();

load_deaths();
load_births();
load_pop();
load_immi();
load_target_doses();

my %doses_by_dates = ();
my %negative_offsets_to_smooth = ();
my %doses_by_dates_and_age_groups = ();
model_targeted_year_pop();

print_report_by_age_groups();


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

sub load_target_doses {
	my $file_2022 = 'data/2022_first_doses_no_dose_by_age_and_dates.csv';
	open my $in, '<:utf8', $file_2022;
	while (<$in>) {
		chomp $_;
		my ($date, $age, $had_first_dose, $had_no_dose) = split ',', $_;
		next unless $date eq $target_date;
		$target_doses{$age}->{'had_first_dose'} = $had_first_dose;
		$target_doses{$age}->{'had_no_dose'} = $had_no_dose;
		$target_doses{$age}->{'dose_sum'} = $had_no_dose + $had_first_dose;
	}
	close $in;
}

sub model_targeted_year_pop {
	my %yearly_pop  = ();
	# For each year following 2018, each age group ages 1. Births & Immigration are integrated, and deaths are subtracted from each age group.
	for my $age (sort{$a <=> $b} keys %{$pop_esti{2018}}) {
		$pop_by_ages{$age}->{'count'} = $pop_esti{2018}->{$age};
		$yearly_pop{2018}->{$age} = $pop_esti{2018}->{$age};
		$yearly_pop{2018}->{'Total'} += $pop_esti{2018}->{$age};
	}

	for my $year (2019 .. $target_year) {

		# if ($year eq $target_year) {
		# 	p%pop_by_ages;
		# 	p%target_doses;
		# 	die;
		# }

		# Subtract to each age count & doses every people who died in the past year.
		# if ($year != $target_year) {
			for my $age (sort{$a <=> $b} keys %pop_by_ages) {
				my $deaths = $deaths{$year}->{$age} // die;
				my $pop = $pop_by_ages{$age}->{'count'} // die;
				$pop_by_ages{$age}->{'count'} -= $deaths;
				die if $pop_by_ages{$age}->{'count'} < 0;
				if ($year eq $target_year && exists $target_doses{$age}) {

					# Also subtract to the doses an equal amount of death rates 
					# to the doses of this age, assuming equal distribution
					# with no COVID.
					# p$target_doses{$age};
					my $had_first_dose = $target_doses{$age}->{'had_first_dose'} // 0;
					my $had_no_dose = $target_doses{$age}->{'had_no_dose'} // 0;
					my $sum_of_doses = $had_first_dose + $had_no_dose;
					my $had_first_dose_percent = $had_first_dose * 100 / $sum_of_doses;
					my $had_first_dose_deaths  = nearest(1, $deaths * $had_first_dose_percent / 100);
					my $had_no_dose_deaths = $deaths - $had_first_dose_deaths;
					# say "$age - $had_first_dose_deaths vs $had_no_dose_deaths";
					$target_doses{$age}->{'had_first_dose'} -= $had_first_dose_deaths;
					$target_doses{$age}->{'had_no_dose'} -= $had_no_dose_deaths;
				}
			}
		# }

		# Adds or subtract to each age the yearly net immigration.
		# You had to be vaccinated to grab a plane in, so this impacts the
		# vaccinated population only.
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			my $immi = $r_immi{$year}->{$age} // die;
			$pop_by_ages{$age}->{'count'} += $immi;
			die if $pop_by_ages{$age}->{'count'} < 0;
			if ($year eq $target_year && exists $target_doses{$age}) {
				$target_doses{$age}->{'had_first_dose'} += $immi;
			}
			# say "$age : $immi";
		}

		# The 90+ who aren't dead are staying there.
		my %new_pop_age = ();
		$new_pop_age{90}->{'count'} = $pop_by_ages{90}->{'count'} // die;
		if ($year eq $target_year) {
			$new_pop_age{90}->{'had_first_dose'} = $target_doses{90}->{'had_first_dose'} // die;
			$new_pop_age{90}->{'had_no_dose'} = $target_doses{90}->{'had_no_dose'} // die;
		}

		# Each age ages of 1 year (aside for the 90+)
		for my $age (0 .. 89) {
			my $pop = $pop_by_ages{$age}->{'count'} // die;
			my $had_first_dose = $target_doses{$age}->{'had_first_dose'} // 0;
			my $had_no_dose = $target_doses{$age}->{'had_no_dose'} // 0;
			my $age_p_1 = $age + 1;
			$new_pop_age{$age_p_1}->{'count'} += $pop;
			if ($year eq $target_year && exists $target_doses{$age}) {
				$new_pop_age{$age_p_1}->{'had_first_dose'} += $had_first_dose;
				$new_pop_age{$age_p_1}->{'had_no_dose'} += $had_no_dose;
			} else {
				$new_pop_age{$age_p_1}->{'had_no_dose'} = $pop;
			}
		}

		# Lastly, the births are added as new zero.
		$new_pop_age{0}->{'count'} = $births{$year} // die;
		$new_pop_age{0}->{'had_no_dose'} = $births{$year} // die;

		# The old pyramide is erased, and the yearly totals are incremented to the recap.
		for my $age (sort{$a <=> $b} keys %new_pop_age) {
			my $pop = $new_pop_age{$age}->{'count'} // die;
			my $had_first_dose = $new_pop_age{$age}->{'had_first_dose'} // 0;
			my $had_no_dose = $new_pop_age{$age}->{'had_no_dose'} // 0;
			$pop_by_ages{$age}->{'count'} = $pop;
			$pop_by_ages{$age}->{'had_first_dose'} = $had_first_dose;
			$pop_by_ages{$age}->{'had_no_dose'} = $had_no_dose;
			$yearly_pop{$year}->{$age} = $pop;
			$yearly_pop{$year}->{'Total'} += $pop;
		}
	}

	# Controls against the census data (we would expect +/- 6K offset).
	my $offset_sum = 0;
	for my $age (sort{$a <=> $b} keys %pop_by_ages) {
		my $pop = $pop_by_ages{$age}->{'count'} // die;
		my $control_pop = $pop_esti{$target_year}->{$age} // die;
		my $offset = $control_pop - $pop;
		say "$age | $pop vs $control_pop ($offset)";
		$offset_sum += $offset;
	}
	say "offset_sum : $offset_sum";

	# Now for each date and age group with dose data, 
	# instead of "just calculating" vaccination percents for each age among the scope (0 - 90+),
	# adds the total of dose received by each age since the last datapoint.
	my $file   = 'data/first_doses_by_age_groups_and_dates.csv';
	open my $in, '<:utf8', $file or die $!;
	my %last_data = ();
	while (<$in>) {
		chomp $_;
		my ($date, $age_group, $first_doses) = split ',', $_;
		next if $date eq 'Date';
		my $compdate = $date;
		$compdate =~ s/\D//g;
		next if $compdate < $from_date;
		next if $compdate > $cutoff_date;
		my ($from_age, $to_age) = split '-', $age_group;
		if ($to_age) {
		} else {
			die unless $from_age =~ /\+/;
			$from_age =~ s/\+//;
			$to_age = 90;
		}
		my $age_offset = $to_age - $from_age;
		my $ages_included = $age_offset + 1;

		# Calculates the number of doses administered in each age inside of
		# the age group (assuming equal distribution in the age group allowed)
		my $doses_by_ages = nearest(1, $first_doses / $ages_included);

		# Checks for consistency.
		my $control_doses = $doses_by_ages * $ages_included;
		if ($control_doses == 0) {
			$control_doses = $first_doses;
		}
		my $offset_introduced = 0;
		if ($control_doses != $first_doses) {
			$offset_introduced = abs($first_doses - $control_doses);
			if ($control_doses > $first_doses) {
				$offset_introduced = "-$offset_introduced";
			}
		}
		for my $age ($from_age .. $to_age) {

			my $age_dose = $doses_by_ages;
			if ($offset_introduced && $age eq $to_age) {
				$age_dose = $doses_by_ages + $offset_introduced;
			}

			# If we don't have yet the former datapoint used, stores it.
			if (!exists $last_data{$age}) {
				$last_data{$age}->{'age_dose'} = $age_dose;
				$last_data{$age}->{'date'} = $date;
				$last_data{$age}->{'age_group'} = $age_group;
				$last_data{$age}->{'first_doses'} = $first_doses;
			} else {

				# Otherwise, calculates the new doses received in this age group.
				my $last_score   = $last_data{$age}->{'age_dose'} // die;
				my $new_doses    = $age_dose - $last_score;
				if ($new_doses < 0) {
					# say "$date - $age - $new_doses ($age_dose on $date via $age_group at $first_doses | $last_score on " . $last_data{$age}->{'date'} . ' via ' . $last_data{$age}->{'age_group'} . ' at ' . $last_data{$age}->{'first_doses'} . ')';
					$negative_offsets_to_smooth{$compdate}->{$age}->{'new_doses'}   = $new_doses;
					$negative_offsets_to_smooth{$compdate}->{$age}->{'doses_by_ages'} = $doses_by_ages;
					$negative_offsets_to_smooth{$compdate}->{$age}->{'age_group'}   = $age_group;
					$negative_offsets_to_smooth{$compdate}->{$age}->{'first_doses'} = $first_doses;
				}
				$last_data{$age}->{'age_dose'} = $age_dose;
				$last_data{$age}->{'date'} = $date;
				$last_data{$age}->{'age_group'} = $age_group;
				$last_data{$age}->{'first_doses'} = $first_doses;
				$doses_by_dates{$compdate}->{'date'} = $date;
				die if exists $doses_by_dates{$compdate}->{'ages'}->{$age};
				$doses_by_dates{$compdate}->{'ages'}->{$age} += $new_doses;
			}
		}
	}
	close $in;

	# At this stage we have a snapshot of the situation 
	# if our population had "just aged".
	# We have every dose administered
	# on every day of datapoint,
	# with some negative offsets to smooth.
	# We also have a snapshot of the situation as it would be if
	# new doses hadn't been administered.
	# We will want, for each day of the covered period, to have an accurate estimate
	# of the balance in each population (ever vs never vaxxed).
	# die;
	open my $out, '>:utf8', 'data/2023_first_doses_no_dose_by_age_and_dates.csv';
	say $out 'Date,Age,Ever Vaccinated,Never Vaccinated';
	for my $compdate (sort{$a <=> $b} keys %doses_by_dates) {
		my $date = $doses_by_dates{$compdate}->{'date'} // die;
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			my $new_doses = $doses_by_dates{$compdate}->{'ages'}->{$age} // 0;
			if ($new_doses >= 0) {
				$pop_by_ages{$age}->{'had_first_dose'} += $new_doses;
				$pop_by_ages{$age}->{'had_no_dose'} -= $new_doses;
				# Sadly we can't test for logic as there is none.
				# die "age : $age ($new_doses), compdate : $compdate" if $pop_by_ages{$age}->{'had_no_dose'} < -100 && $age > 17;
			} else {
				$new_doses = abs($new_doses);
				$pop_by_ages{$age}->{'had_first_dose'} -= $new_doses;
				$pop_by_ages{$age}->{'had_no_dose'} += $new_doses;
				# Sadly we can't test for logic as there is none.
				# die "age : $age ($new_doses), compdate : $compdate" if $pop_by_ages{$age}->{'had_first_dose'} < -100 && $age > 17;
			}
			my $had_no_dose = $pop_by_ages{$age}->{'had_no_dose'} // die;
			my $had_first_dose = $pop_by_ages{$age}->{'had_first_dose'} // die;
			say $out "$date,$age,$had_first_dose,$had_no_dose";
			my $oia_age_group  = oia_age_group_from_age_groups_src($age);
			$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'date'} = $date;
			$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_first_dose'} += $had_first_dose;
			$doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_no_dose'} += $had_no_dose;
		}
		say "compdate : $compdate";
		p%pop_by_ages;
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

sub generate_population_by_age_group {
	my ($age_group_name) = @_;
	my ($from_age, $to_age) = split '-', $age_group_name;
	my $population = 0;
	if ($from_age && $to_age) {
		for my $age (sort{$a <=> $b} keys %pop_by_ages) {
			next unless $from_age <= $age && $age <=$to_age;
			$population += $pop_by_ages{$age}->{'count'};
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
				$population += $pop_by_ages{$age}->{'count'};
			}
		} else {
			die "from_age : $from_age";
		}
	}
	return $population;
}

sub print_report_by_age_groups {
	open my $out, '>:utf8', 'data/2023_first_doses_no_dose_by_oia_age_groups_and_dates.csv';
	say $out 'Date,Age Group,Ever Vaccinated,Never Vaccinated';
	for my $oia_age_group (sort keys %doses_by_dates_and_age_groups) {
		for my $compdate (sort{$a <=> $b} keys %{$doses_by_dates_and_age_groups{$oia_age_group}}) {
			my $date = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'date'} // die;
			my $had_first_dose = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_first_dose'} // 0;
			my $had_no_dose = $doses_by_dates_and_age_groups{$oia_age_group}->{$compdate}->{'had_no_dose'} // 0;
			say $out "$date,$oia_age_group,$had_first_dose,$had_no_dose";
		}
	}
	close $out;
}