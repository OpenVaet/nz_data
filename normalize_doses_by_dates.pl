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

open my $out_1, '>:utf8', 'data/last_date_doses_rates_by_dates_and_age_groups.csv';
say $out_1 'Date,Age Group,First Doses,Population,% With First Doses';
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
	my $year = $doses_by_dates{$compdate}->{'year'} // die;
	for my $age_group_name (sort keys %{$doses_by_dates{$compdate}->{'age_groups'}}) {
		next if $age_group_name eq 'Total' || $age_group_name eq 'Various';
		my $population  = $pop_by_age_groups{$year}->{$age_group_name}->{'population'};
		if (!$population) {
			$population = generate_population_by_age_group($year, $age_group_name);
			die unless $population;
		}
		my $first_doses = $doses_by_dates{$compdate}->{'age_groups'}->{$age_group_name} // die;
		my $first_doses_by_100 = nearest(0.01, $first_doses * 100 / $population);
		say "$age_group_name | $first_doses / $population | $first_doses_by_100";
		if ($d_num == $total_dates) {
			say $out_2 "$age_group_name,$first_doses,$population,$first_doses_by_100";
		}
		say $out_1 "$date,$age_group_name,$first_doses,$population,$first_doses_by_100";
	}
	if ($d_num == $total_dates) {
		close $out_2;
	}
}
close $out_1;

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
		say "from_age : $from_age";
		say "to_age   : $to_age";
		for my $age (sort{$a <=> $b} keys %{$pop_by_ages{$year}}) {
			next unless $from_age <= $age && $age <=$to_age;
			$population += $pop_by_ages{$year}->{$age};
			say "age : $age";
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
				say "age : $age";
			}
		} else {
			die "from_age : $from_age";
		}
		say "from_age : $from_age";
		say "to_age   : $to_age";
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
		# say "$archive_url, $archive_date, $age_group, $first_doses, $second_doses";
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
		my $dhb_file = "$date_folder/dhb_residence_uptake.csv";
		die unless -f $dhb_file;
		open my $in, '<:', $dhb_file or die $!;
		say $dhb_file;
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