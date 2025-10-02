package HTML::Genealogy::Map;

use strict;
use warnings;

use utf8;

use open qw(:std :encoding(UTF-8));

use autodie;
use Date::Cmp;
use HTML::GoogleMaps::V3;
use HTML::OSM;
use Params::Get;
use Params::Validate::Strict;

=head1 NAME

HTML::Genealogy::Map - Extract and map genealogical events from GEDCOM file

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 DESCRIPTION

This module parses GEDCOM genealogy files and creates an interactive map showing
the locations of births, marriages, and deaths. Events at the same location are
grouped together in a single marker with a scrollable popup.

The program uses a multi-tier geocoding strategy:
1. Local geocoding cache (Geo::Coder::Free::Local)
2. Free geocoding database (Geo::Coder::Free)
3. OpenStreetMap Nominatim service (Geo::Coder::OSM)

All geocoding results are cached to improve performance and reduce API calls.

=head1 SUBROUTINES/METHODS

=head2 onload_render

Render the map.
It takes two mandatory and one optional parameter.
It returns an array of two elements, the items for the C<head> and C<body>.

=over 4

=item B<gedcom>

L<GEDCOM> object to process.

=item B<geocoder>

Geocoder to use.

=item B<google_key>

Key to Google's map API.

=item B<debug>

Enable print statements of what's going on

=back

=head1 FEATURES

=over 4

=item * Extracts births, marriages, and deaths with location data

=item * Geocodes locations using multiple fallback providers

=item * Groups events at the same location (within ~0.1m precision)

=item * Color-coded event indicators (green=birth, blue=marriage, red=death)

=item * Sorts events chronologically within each category

=item * Scrollable popups for locations with more than 5 events

=item * Persistent caching of geocoding results

=item * For OpenStreetMap: centers on location with most events

=back

=head3	API SPECIFICATION

=head4	INPUT

  {
    'gedcom' => { 'type' => 'object', 'can' => 'individuals' },
    'geocoder' => { 'type' => 'object', 'can' => 'geocode' },
    'debug' => { 'type' => 'boolean', optional => 1 },
    'google_key' => { 'type' => 'string', optional => 1, min => 39, max => 39, matches => qr/^AIza[0-9A-Za-z_-]{35}$/ }
  }

=head4	OUTPUT

Argument error: croak
No matches found: undef

Returns an array of two strings:

  {
    'type' => 'array',
    'min' => 2,
    'max' => 2,
    'schema' => { 'type' => 'string', min => 10 },
  }

=cut

sub onload_render
{
	my $class = shift;

	# Configuration
	my $params = Params::Validate::Strict::validate_strict({
		args => Params::Get::get_params('gedcom', @_),
		schema => {
			'gedcom' => { 'type' => 'object', 'can' => 'individuals' },
			'geocoder' => { 'type' => 'object', 'can' => 'geocode' },
			'debug' => { 'type' => 'boolean', optional => 1 },
			'google_key' => { 'type' => 'string', optional => 1, min => 39, max => 39, matches => qr/^AIza[0-9A-Za-z_-]{35}$/ }
		}
	});

	my $ged = $params->{'gedcom'};
	my $debug = $params->{'debug'};
	my $google_key = $params->{'google_key'};
	my $geocoder = $params->{'geocoder'};

	# Storage for events
	my @events;

	print "Parsing GEDCOM file...\n" if($debug);

	# Process all individuals
	foreach my $indi ($ged->individuals) {
		my $name = $indi->name || 'Unknown';
		$name =~ s/\///g;	# Remove GEDCOM name delimiters

		# Birth events
		if (my $birth = $indi->birth) {
			if (ref($birth) && (my $place = $birth->place)) {
				push @events, {
					type => 'birth',
					name => $name,
					place => $place,
					date => $birth->date || 'Unknown date',
				};
			}
		}

		# Death events
		if (my $death = $indi->death) {
			if (ref($death) && (my $place = $death->place)) {
				push @events, {
					type => 'death',
					name => $name,
					place => $place,
					date => $death->date || 'Unknown date',
				};
			}
		}
	}

	# Process all families (marriages)
	foreach my $fam ($ged->families) {
		my $husband = $fam->husband ? ($fam->husband->name || 'Unknown') : 'Unknown';
		my $wife = $fam->wife ? ($fam->wife->name || 'Unknown') : 'Unknown';
		$husband =~ s/\///g;
		$wife =~ s/\///g;

		if (my $marriage = $fam->marriage) {
			if (ref($marriage) && (my $place = $marriage->place)) {
				push @events, {
					type => 'marriage',
					name => "$husband & $wife",
					place => $place,
					date => $marriage->date || 'Unknown date',
				};
			}
		}
	}

	print 'Found ', scalar(@events), " events with location data.\n" if($debug);
	print "Geocoding locations...\n" if($debug);

	# Geocode all events
	my @geocoded_events;
	my %cache;

	foreach my $event (@events) {
		my $place = $event->{place};

		# Check cache
		unless (exists $cache{$place}) {
			my $location = $geocoder->geocode(location => $place);
			if ($location && $location->{lat} && $location->{lon}) {
				$cache{$place} = {
					lat => $location->{lat},
					lon => $location->{lon},
				};
				print "\tGeocoded: $place\n" if($debug);
				sleep 1 if($location->{'geocoder'} !~ /^Geo::Coder::Free/);	# Be nice to geocoding service

			} else {
				print "\tFailed to geocode: $place\n" if($debug);
				$cache{$place} = undef;
				sleep 1;	# Be nice to geocoding service
			}
		}

		if ($cache{$place}) {
			push @geocoded_events, {
				%$event,
				lat => $cache{$place}{lat},
				lon => $cache{$place}{lon},
			};
		}
	}

	print 'Successfully geocoded ', scalar(@geocoded_events), " events.\n" if($debug);

	return('', '') if(scalar(@geocoded_events) == 0);	# Empty

	print "Generating map...\n" if($debug);

	# Group events by location
	my %location_groups;
	foreach my $event (@geocoded_events) {
		my $key = sprintf('%.6f,%.6f', $event->{lat}, $event->{lon});
		push @{$location_groups{$key}}, $event;
	}

	print "Generating map\n" if($debug);

	# Generate map based on available API key
	my $map;
	if ($google_key) {
		$map = generate_google_map(\%location_groups, $google_key);
	} else {
		$map = generate_osm_map(\%location_groups);
	}

	return $map->onload_render();
}

# Generate HTML for grouped events
sub generate_popup_html {
	my ($events) = @_;

	my $place = $events->[0]{place};
	my $event_count = scalar(@$events);

	# Add scrollable container if more than 5 events
	my $container_start = '';
	my $container_end = '';
	if ($event_count > 5) {
		$container_start = '<div style="max-height: 300px; overflow-y: auto;">';
		$container_end = '</div>';
	}

	my $html = "<b>$place</b><br><br>$container_start";

	# Group by type
	my %by_type;
	foreach my $event (@$events) {
		push @{$by_type{$event->{type}}}, $event;
	}

	# Sort function for dates
	my $sort_by_date = sub {
		return 0 if(($a->{'date'} =~ /^Unknown/i) || ($b->{'date'} =~ /^Unknown/));
		return Date::Cmp::datecmp($a->{'date'}, $b->{'date'});
	};

	# Add births
	if ($by_type{birth}) {
		$html .= '<b>Births:</b><br>';
		foreach my $event (sort $sort_by_date @{$by_type{birth}}) {
			$html .= sprintf(
				'<span style="color: green; font-size: 20px;">●</span> %s (%s)<br>',
				$event->{name},
				$event->{date}
			);
		}
		$html .= '<br>';
	}

	# Add marriages
	if ($by_type{marriage}) {
		$html .= '<b>Marriages:</b><br>';
		foreach my $event (sort $sort_by_date @{$by_type{marriage}}) {
			$html .= sprintf(
				'<span style="color: blue; font-size: 20px;">●</span> %s (%s)<br>',
				$event->{name},
				$event->{date}
			);
		}
		$html .= '<br>';
	}

	# Add deaths
	if ($by_type{death}) {
		$html .= '<b>Deaths:</b><br>';
		foreach my $event (sort $sort_by_date @{$by_type{death}}) {
			$html .= sprintf(
				'<span style="color: red; font-size: 20px;">●</span> %s (%s)<br>',
				$event->{name},
				$event->{date}
			);
		}
	}

	$html .= $container_end;

	return $html;
}

# Generate Google Maps
sub generate_google_map {
	my ($location_groups, $file, $key) = @_;

	my $map = HTML::GoogleMaps::V3->new(
		key => $key,
		height => '600px',
		width => '100%',
	);

	# Add markers for each location
	my $first = 1;
	foreach my $loc_key (keys %$location_groups) {
		my $events = $location_groups->{$loc_key};
		my ($lat, $lon) = split /,/, $loc_key;

		my $html = generate_popup_html($events);

		$map->add_marker(
			point => [$lat, $lon],
			html => $html,
		);

		# Center on first location
		if ($first) {
			$map->center([$lat, $lon]);
			$map->zoom(4);
			$first = 0;
		}
	}

	return $map;
}

# Generate OpenStreetMap using HTML::OSM
sub generate_osm_map {
	my ($location_groups, $file) = @_;

	# Create HTML::OSM object
	my $osm = HTML::OSM->new(zoom => 12);

	# Add markers for each location
	foreach my $loc_key (keys %$location_groups) {
		my $events = $location_groups->{$loc_key};
		my ($lat, $lon) = split /,/, $loc_key;

		my $html = generate_popup_html($events);

		$osm->add_marker(
			point => [$lat, $lon],
			html => $html,
		);
	}

	# Find location with most events
	my ($center_lat, $center_lon) = (0, 0);
	my $max_events = 0;
	foreach my $loc_key (keys %$location_groups) {
		my $event_count = scalar(@{$location_groups->{$loc_key}});
		if ($event_count > $max_events) {
			$max_events = $event_count;
			($center_lat, $center_lon) = split /,/, $loc_key;
		}
	}

	$osm->center([$center_lat, $center_lon]);

	return $osm;
}

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=head1 BUGS

=head1 SEE ALSO

=over 4

=item * Test coverage report: L<https://nigelhorne.github.io/HTML-Genealogy-Map/coverage/>

=back

=head1 REPOSITORY

L<https://github.com/nigelhorne/HTML-Genealogy-Map>

=head1 SUPPORT

This module is provided as-is without any warranty.

Please report any bugs or feature requests to C<bug-html-genealogy-map at rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTML-Genealogy-Map>.
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

You can find documentation for this module with the perldoc command.

    perldoc HTML::Genalogy::Map

You can also look for information at:

=over 4

=item * MetaCPAN

L<https://metacpan.org/dist/HTML-Genealogy-Map>

=item * RT: CPAN's request tracker

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Genealogy-Map>

=item * CPAN Testers' Matrix

L<http://matrix.cpantesters.org/?dist=HTML-Genealogy-Map>

=item * CPAN Testers Dependencies

L<http://deps.cpantesters.org/?module=HTML::Genalogy::Map>

=back

=head1 LICENCE AND COPYRIGHT

Copyright 2010-2025 Nigel Horne.

Usage is subject to licence terms.

The licence terms of this software are as follows:

=over 4

=item * Personal single user, single computer use: GPL2

=item * All other users (including Commercial, Charity, Educational, Government)
  must apply in writing for a licence for use from Nigel Horne at the
  above e-mail.

=back

=cut

1;
