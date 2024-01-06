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
# Table: Estimated Resident Population by Age and Sex (1991+) (Annual-Sep)
# https://infoshare.stats.govt.nz/ViewTable.aspx?pxID=dee85724-b752-40d4-8201-1f2a3623f4cd
my $pop_esti_file = 'raw_data/DPE403904_20240106_043738_97.csv';

# Group: Births - VSB
# Table: Live births by age of mother (Annual-Sep)
# https://infoshare.stats.govt.nz/ViewTable.aspx?pxID=fcbe5dd9-d7bc-43cc-83e6-100a2ec46c24
my $births_file    = 'raw_data/VSB355803_20240106_044138_29.csv';

# Group: Deaths - VSD
# Table: Deaths by age and sex (Annual-Sep)
# https://infoshare.stats.govt.nz/ViewTable.aspx?pxID=d7f5170d-b233-406e-935e-bf0cd23dd09c
my $deaths_file    = 'raw_data/VSD349203_20240106_044840_86.csv';

# Group: International Travel and Migration - ITM
# Table: Permanent & long-term migration key series (Annual-Sep)
# https://infoshare.stats.govt.nz/ViewTable.aspx?pxID=1442953e-597e-47a7-b409-de82c8717ef4
my $immi_file      = 'raw_data/ITM552111_20240106_070445_77.csv';

my %deaths   = ();
my %births   = ();
my %pop_esti = ();
my %immi     = ();

load_deaths();
load_births();
load_pop_esti();
load_immi();

# p%deaths;
# p%births;
p%immi;

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
			}
		}
	}
	close $in;
}