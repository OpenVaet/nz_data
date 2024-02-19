#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';

# Cpan dependencies.
no autovivification;
use Data::Printer;
use Data::Dumper;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::Path qw(make_path);
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);

my %years     = ();
my %dates     = ();

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);

my $target_url = 'https://health.govt.nz/our-work/diseases-and-conditions/covid-19-novel-coronavirus/covid-19-data-and-statistics/covid-19-vaccine-data';
my $target_url_formatted = $target_url;
$target_url_formatted =~ s/:/\%3A/g;
$target_url_formatted =~ s/\//\%2F/g;

# Fetching years with available data on archive.org
fetch_years();

# Fetching the dates by years on which we have archives.
fetch_yearly_dates();

# Fetching the hours every 7 days at least.
fetch_dates_hours();

# Recreating the archive.
print_archive();

sub fetch_years {

    # Setting headers & URL.
    my $path    = "/__wb/sparkline?output=json&url=$target_url_formatted&collection=web";
    my @headers = set_headers($path, $target_url);
    my $url     = "https://web.archive.org$path";
    say "Getting years";

    # Getting data.
    my $res     = $ua->get($url, @headers);
    unless ($res->is_success)
    {
        p$res;
        die "failed to get [$url]";
    }
    my $content = $res->decoded_content;
    my $content_json;
    eval {
        $content_json = decode_json($content);
    };
    if ($@) {
        die "Failed to get a proper response from [$url].";
    }

    # Listing years.
    if (%$content_json{'years'}) {
        for my $year (sort keys %{%$content_json{'years'}}) {
            $years{$year} = 1;
        }
    }
}

sub set_headers {
    my ($path, $target_url) = @_;
    my @headers = (
        'Accept'          => '*/*',
        'Accept-Encoding' => 'gzip, deflate, br',
        'Connection'      => 'keep-alive',
        ':Authority'      => 'web.archive.org',
        ':Method'         => 'GET',
        ':Path'           => $path,
        ':Scheme'         => 'https',
        'Referer'         => "https://web.archive.org/web/20220000000000*/$target_url",
        'sec-fetch-mode'  => 'cors',
        'sec-fetch-site'  => 'same-origin'
    );
    return @headers;
}

sub fetch_yearly_dates {
    for my $year (sort{$a <=> $b} keys %years) {
        say "Getting dates - [$year]";
        my $path    = "/__wb/calendarcaptures/2?url=$target_url_formatted&date=$year&groupby=day";
        my @headers = set_headers($path, $target_url);
        my $url     = "https://web.archive.org$path";

        # Getting data.
        my $res     = $ua->get($url, @headers);
        unless ($res->is_success)
        {
            p$res;
            die "failed to get [$url]";
        }
        my $content = $res->decoded_content;
        my $content_json;
        eval {
            $content_json = decode_json($content);
        };
        if ($@) {
            die "Failed to get a proper response from [$url].";
        }
        if (%$content_json{'items'}) {
            for my $item (@{%$content_json{'items'}}) {
                my $month_day = @$item[0] // die;
                my $hits     = @$item[2] // die;
                my ($month,
                    $day) = $month_day =~ /(.*)(..)$/;
                die unless $month && $day;
                $month = "0$month" if ($month < 10);
                $dates{$year}->{$month}->{$day} = $hits;
            }
        }
    }
}

sub fetch_dates_hours {
    make_path("archive_org_data/json")
        unless (-d "archive_org_data/json");
    make_path("archive_org_data/hours")
        unless (-d "archive_org_data/hours");
    make_path("archive_org_data/html")
        unless (-d "archive_org_data/html");
    my ($current, $total) = (0, 0);
    for my $year (sort{$a <=> $b} keys %dates) {
        for my $month (sort{$a <=> $b} keys %{$dates{$year}}) {
            for my $day (sort{$a <=> $b} keys %{$dates{$year}->{$month}}) {
                $total++;
            }
        }
    }
    for my $year (sort{$a <=> $b} keys %dates) {
        for my $month (sort{$a <=> $b} keys %{$dates{$year}}) {
            for my $day (sort{$a <=> $b} keys %{$dates{$year}->{$month}}) {
                my $compdate = "$year$month$day";
                next if $compdate > 20210831;
                $current++;
                STDOUT->printflush("\rGetting archives - [$current / $total] - [$year-$month-$day]");

                # Getting last hour of the day.
                my $hour;
                while (!$hour) {
                    $hour = get_hour($year, $month, $day);
                    if (!$hour) {
                        say "Failed retrieving hours on [$year-$month-$day], sleeping 3 seconds before to try again...";
                        sleep 3;
                    }
                }
                my ($h, $m, $s) = $hour =~ /(.*)(..)(..)$/;
                if (!$h) {
                    ($h, $m, $s) = $hour =~ /(.)(.)(..)$/;
                    unless (defined $h) {
                        ($m, $s) = $hour =~ /(.*)(..)$/;
                        next unless defined $m;
                        $h = 0;
                    }
                    die "$year-$month-$day - hour : $hour" unless defined $h;
                }
                $h = "0$h" if $h < 10;

                # Getting archived page if we haven't stored it already.
                my $date_hour = "$year$month$day$h$m$s";
                my $h_file    = "archive_org_data/json/$date_hour.json";
                unless (-f $h_file) {
                    my $content;
                    my $file = "archive_org_data/html/$date_hour.html";
                    unless (-f $file) {
                        my $path    = "/web/$date_hour/$target_url";
                        my @headers = set_headers($path, $target_url);
                        my $url     = "https://web.archive.org$path";
                        my $res     = $ua->get($url, @headers);
                        unless ($res->is_success)
                        {
                            next
                        }
                        $content    = $res->decoded_content;
                        open my $out, '>:utf8', $file;
                        print $out $content;
                        close $out;
                    } else {
                        open my $in, '<:utf8', $file;
                        while (<$in>) {
                            $content .= $_;
                        }
                        close $in;
                    }
                    my $tree    = HTML::Tree->new();
                    $tree->parse($content);
                    if ($tree->look_down(id=>"by_age")) {

                        # Locating the adequate table by age.
                        my $age_table_num;
                        my $t_num = 0;
                        my @tables = $tree->look_down(class=>"table-style-two");
                        for my $table (@tables) {
                            my @ths = $table->find('th');
                            my $head1 = $ths[0]->as_trimmed_text // die;
                            if ($head1 eq 'Age') {
                                $age_table_num = $t_num;
                                last;
                            }
                            $t_num++;
                        }
                        if (!$age_table_num) {
                            open my $out, '>:utf8', 'archive.html';
                            say $out $tree->as_HTML('<>&', "\t");
                            close $out;
                            die;
                        }
                        my $doses_by_ages = $tables[$age_table_num] // die;
                        my @headers = $doses_by_ages->find('tr')->find('th');
                        my $total_headers = scalar @headers;
                        if ($total_headers == 3) {
                            my %headers = ();
                            my $h_num   = 0;
                            for my $header (@headers) {
                                $h_num++;
                                $header = $header->as_trimmed_text;
                                $headers{$h_num} = $header;
                            }
                            unless (
                                $headers{1} eq 'Age' &&
                                $headers{2} eq 'First dose administered' &&
                                $headers{3} eq 'Second dose administered'
                            ) {
                                open my $out, '>:utf8', 'archive.html';
                                say $out $tree->as_HTML('<>&', "\t");
                                close $out;
                                die;
                            }
                            my @rows = $doses_by_ages->find('tr');
                            my %by_age_groups = ();
                            for my $row (@rows) {
                                next unless $row->find('td');
                                # say $row->as_HTML('<>&', "\t");
                                my $c_num = 0;
                                my @tds = $row->find('td');
                                my $total_rows = scalar @tds;
                                my $age = $tds[0]->as_trimmed_text // die;
                                for my $td (@tds) {
                                    $c_num++;
                                    $td = $td->as_trimmed_text;
                                    next if $td eq 'Age';
                                    my $header = $headers{$c_num} // die;
                                    $by_age_groups{$age}->{$header} = $td;
                                }
                            }
                            # p%by_age_groups;
                            open my $out, '>:utf8', $h_file;
                            print $out encode_json\%by_age_groups;
                            close $out;
                            # p%rows;
                            # die;
                        } elsif ($total_headers == 5) {
                            my %headers = ();
                            my $h_num   = 0;
                            for my $header (@headers) {
                                $h_num++;
                                $header = $header->as_trimmed_text;
                                $headers{$h_num} = $header;
                            }
                            # p%headers;
                            unless (
                                $headers{1} eq 'Age' &&
                                $headers{2} eq 'First dose administered' &&
                                ($headers{3} eq 'First doses per 1000 people' ||
                                 $headers{3} eq 'First doses per 1,000 people') &&
                                $headers{4} eq 'Fully vaccinated' &&
                                ($headers{5} eq 'Fully vaccinated per 1000 people' ||
                                 $headers{5} eq 'Fully vaccinated per 1,000 people')
                            ) {
                                open my $out, '>:utf8', 'archive.html';
                                say $out $tree->as_HTML('<>&', "\t");
                                close $out;
                                die;
                            }
                            my @rows = $doses_by_ages->find('tr');
                            my %by_age_groups = ();
                            for my $row (@rows) {
                                next unless $row->find('td');
                                say $row->as_HTML('<>&', "\t");
                                my $c_num = 0;
                                my @tds = $row->find('td');
                                my $total_rows = scalar @tds;
                                my $age;
                                if ($total_rows == $total_headers) {
                                    $age = $tds[0]->as_trimmed_text // die;
                                } elsif (($total_rows + 1) == $total_headers) {
                                    $age = $row->find('th')->as_trimmed_text;
                                } else {
                                    die;
                                }
                                for my $td (@tds) {
                                    $c_num++;
                                    $td = $td->as_trimmed_text;
                                    next if $td eq 'Age';
                                    my $header = $headers{$c_num} // die;
                                    $by_age_groups{$age}->{$header} = $td;
                                }
                            }
                            # p%by_age_groups;
                            open my $out, '>:utf8', $h_file;
                            print $out encode_json\%by_age_groups;
                            close $out;
                            # p%rows;
                            # die;
                        } else {
                            open my $out, '>:utf8', 'archive.html';
                            say $out $doses_by_ages->as_HTML('<>&', "\t");
                            close $out;
                            say "\nscalars : $total_headers";
                            die;
                        }
                    } else {
                        open my $out, '>:utf8', 'archive.html';
                        say $out $tree->as_HTML('<>&', "\t");
                        close $out;
                        die;
                    }
                }
            }
        }
    }
    say "";
}

sub get_hour {
    my ($year, $month, $day) = @_;
    my $file     = "archive_org_data/hours/$year$month$day.json";
    my $content;
    unless (-f $file) {
        my $path    = "/__wb/calendarcaptures/2?url=$target_url_formatted&date=$year$month$day";
        my @headers = set_headers($path, $target_url);
        my $url     = "https://web.archive.org$path";
        my $res     = $ua->get($url, @headers);
        unless ($res->is_success)
        {
            return;
        }
        $content    = $res->decoded_content;
        open my $out, '>:utf8', $file;
        print $out $content;
        close $out;
    } else {
        open my $in, '<:utf8', $file;
        while (<$in>) {
            $content .= $_;
        }
        close $in;
    }
    my $content_json;
    eval {
        $content_json = decode_json($content);
    };
    if ($@) {
        die "Failed to parse json on [$file].";
    }
    die unless %$content_json{'items'};
    my $last_hour;
    for my $item (@{%$content_json{'items'}}) {
        my $hour  = @$item[0] // die;
        $last_hour = $hour;
    }
    die unless $last_hour;
}

sub json_from_file {
    my $file = shift;
    if (-f $file) {
        my $json;
        eval {
            open my $in, '<:utf8', $file;
            while (<$in>) {
                $json .= $_;
            }
            close $in;
            $json = decode_json($json) or die $!;
        };
        if ($@) {
            {
                local $/;
                open (my $fh, $file) or die $!;
                $json = <$fh>;
                close $fh;
            }
            eval {
                $json = decode_json($json);
            };
            if ($@) {
                die "failed parsing json : " . @!;
            }
        }
        return $json;
    } else {
        return {};
    }
}

sub print_archive {
    my $former_total = 0;
    open my $out, '>:utf8', 'data/nz_doses_administered_from_archive.csv';
    say $out "archive_url,archive_date,age_group,first_doses,second_doses";
    for my $file (glob "archive_org_data/json/*") {
        my ($compdatetime) = $file =~ /json\/(.*)\.json$/;
        my ($year, $month, $day) = $compdatetime =~ /^(....)(..)(..).*/;
        die unless $compdatetime;
        die "file : $file" unless length $compdatetime == 14 || length $compdatetime == 13;
        my $archive_url = "https://web.archive.org/web/$compdatetime/$target_url";
        my $json = json_from_file($file);
        my $current_total = %$json{'Total'}->{'First dose administered'} // die;
        $current_total =~ s/,//g;
        if (!$former_total || ($former_total != $current_total)) {
            $former_total = $current_total;
            for my $age_group (sort keys %$json) {
                my $first_doses = %$json{$age_group}->{'First dose administered'} // die;
                my $second_doses = %$json{$age_group}->{'Second dose administered'} // %$json{$age_group}->{'Fully vaccinated'} // die;
                $first_doses =~ s/,//g;
                $second_doses =~ s/,//g;
                say $out "$archive_url,$year-$month-$day,$age_group,$first_doses,$second_doses";
            }
        }
        # p$json;
        # die;
    }
    close $out;
}