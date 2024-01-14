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
use File::Path qw(make_path);
use Text::CSV qw( csv );
use Statistics::Descriptive;
use Statistics::LineFit;
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Group: Population Estimates - DPE
# Table: Estimated Resident Population by Age and Sex (1991+) (Annual-Dec)
my $pop_esti_file = 'raw_data/DPE403905_20240106_104639_36.csv';

# Group: Births - VSB
# Table: Live births by age of mother (Annual-Dec)
my $births_file    = 'raw_data/VSB355804_20240106_104105_54.csv';

# Group: Deaths - VSD
# Table: Deaths by age and sex (Annual-Dec)
my $deaths_file    = 'raw_data/VSD349204_20240106_103532_75.csv';

# Group: International Travel and Migration - ITM
# Table: Estimated migration by direction, age group and sex, 12/16-month rule (Annual-Dec)
my $immi_file      = 'raw_data/ITM552114_20240106_105644_18.csv';

# 
my $d_r_file = 'raw_data/DMM168901_20240110_095412_56.csv';

my %deaths     = ();
my %births     = ();
my %pop_esti   = ();
my %immi       = ();
my %y_immi     = ();
my %y_pop_esti = ();
my %y_deaths   = ();

load_deaths();
load_births();
load_pop_esti();
load_immi();

# Output files.
my $pop_census_file = 'data/2010_2022_dec_census_data.csv';
my $pop_growth_file = 'data/2010_2022_dec_natural_and_immi_vs_census_data.csv';

generate_population_totals();

generate_natural_growth();


# La différence entre la population des 70+ de l'année A (P0) et
# celle des 71+ de l'année A+1 (P1) est composée des décès des 70+ (D)
# et de leurs émigrations (E), moins leurs immigrations (I).
# P1 = P0 - D + I - E
# D - (P0 - P1) - (I - E) = 0
# Comme les populations sont prises au 1er janvier de l'année A (en fait le
# 31 décembre de l'année A-1, à une mouche près…), et les décès de même, il y
# a un problème avec les décès des 69 ans au 1er janvier qui sont morts à 70 la
# même année (c'est pas grand chose, mais bon). J'utilise les mortalités M69 et M70
# des 69 ans et 70 ans pour faire un ratio:
# D corrigé = D - D70*M69/(M69 + M70)
# J'ai donc: D - D70*M69/(M69 + M70) - (P0 - P1) - (I - E) = 0


# my %last_year = ();
# for my $year (sort{$a <=> $b} keys %deaths) {
# 	next if $year < 2009;
# 	say "year : $year";
# 	my $deaths_this_year = $deaths{$year} // die;
# 	$last_year{'deaths_this_year'} = $deaths_this_year;
# }
# p%last_year;

# p%deaths;
# p%births;
# p%immi;
# p%pop_esti;



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
				$deaths{$year}->{$header} += $value;
				$y_deaths{$year} += $value;
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
			my %values = ();
			my @values = split ',', $_;
			for my $value_ref (1 .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				$header    = strip_age($header);
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
				my $female = $values[$v_num] // die;
				$v_num++;
				my $male = $values[$v_num] // die;
				$v_num++;
				$immi{$year}->{$age}->{$direction}->{'female'} = $female;
				$immi{$year}->{$age}->{$direction}->{'male'} = $male;
				if ($direction eq 'arrivals') {
					$y_immi{$year} += $female;
					$y_immi{$year} += $male;
				} else {
					unless (exists $y_immi{$year}) {
						$y_immi{$year} = 0;
					}
					$y_immi{$year} -= $female;
					$y_immi{$year} -= $male;
				}
			}
		}
	}
	close $in;
}

sub generate_population_totals {
	say "*" x 50;
	say "Official census population :";
	open my $out, '>:utf8', $pop_census_file;
	say $out "year,population";
	for my $year (sort{$a <=> $b} keys %pop_esti) {
		next if $year < 2010;
		my $total_population = 0;
		for my $age (sort{$a <=> $b} keys %{$pop_esti{$year}}) {
			$total_population += $pop_esti{$year}->{$age};
		}
		say $out "$year,$total_population";
		say "year : [$year] - $total_population";
		$y_pop_esti{$year} = $total_population;
	}
	close $out;
}

sub generate_natural_growth {

	# Fetching 2009 population total.
	say "*" x 50;
	say "Natural growth of the population :";
	my $total_population_2009 = 0;
	for my $age (sort{$a <=> $b} keys %{$pop_esti{2009}}) {
		$total_population_2009 += $pop_esti{2009}->{$age};
	}
	say "[2009] : $total_population_2009";

	# p%y_immi;

	# For each year following 2009, adding births & immigration net growth, subtracting deaths.
	my $natural_growth_population = $total_population_2009;
	open my $out, '>:utf8', $pop_growth_file;
	say $out "year,births,deaths,immigration,census population,natural growth and immigration population,offset";
	for my $year (2010 .. 2022) {
		my $births = $births{$year}   // die;
		my $deaths = $y_deaths{$year} // die;
		my $immi   = $y_immi{$year} // die;
		$natural_growth_population += $births;
		$natural_growth_population -= $deaths;
		$natural_growth_population += $immi;
		my $census_pop = $y_pop_esti{$year} // die;
		my $offset_to_census = $census_pop - $natural_growth_population;
		say $out "$year,$births,$deaths,$immi,$census_pop,$natural_growth_population,$offset_to_census";
		say "[$year] : +$births -$deaths | $immi -> $natural_growth_population vs $census_pop | (+$offset_to_census on Census)";
	}
	close $out;
}