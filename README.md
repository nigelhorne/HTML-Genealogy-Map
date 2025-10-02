# NAME

HTML::Genealogy::Map - Extract and map genealogical events from GEDCOM file

# VERSION

Version 0.01

# DESCRIPTION

This module parses GEDCOM genealogy files and creates an interactive map showing
the locations of births, marriages, and deaths. Events at the same location are
grouped together in a single marker with a scrollable popup.

The program uses a multi-tier geocoding strategy:
1\. Local geocoding cache (Geo::Coder::Free::Local)
2\. Free geocoding database (Geo::Coder::Free)
3\. OpenStreetMap Nominatim service (Geo::Coder::OSM)

All geocoding results are cached to improve performance and reduce API calls.

# SUBROUTINES/METHODS

## onload\_render

Render the map.
It takes one mandatory and one optional parameter.
It returns an arrayref of two elements, the items for the `head` and `body`.

- **gedcom\_file**

    Path to the GEDCOM file to process.

- **debug**

    Enable print statements of what's going on

# ENVIRONMENT VARIABLES

- **GMAP\_WEBSITE\_KEY**

    Google Maps API key. If set, the program will use Google Maps for rendering.
    Otherwise, it will use OpenStreetMap via HTML::OSM.

- **CACHE\_DIR**

    Custom directory for geocoding cache. If not set, defaults to 
    ~/.cache/\_\_PACKAGE\_\_

# FEATURES

- Extracts births, marriages, and deaths with location data
- Geocodes locations using multiple fallback providers
- Groups events at the same location (within ~0.1m precision)
- Color-coded event indicators (green=birth, blue=marriage, red=death)
- Sorts events chronologically within each category
- Scrollable popups for locations with more than 5 events
- Persistent caching of geocoding results
- For OpenStreetMap: centers on location with most events

# AUTHOR

Nigel Horne, `<njh at nigelhorne.com>`

# BUGS

# REPOSITORY

[https://github.com/nigelhorne/HTML-Genealogy-Map](https://github.com/nigelhorne/HTML-Genealogy-Map)

# SUPPORT

This module is provided as-is without any warranty.

Please report any bugs or feature requests to `bug-html-genealogy-map at rt.cpan.org`,
or through the web interface at
[http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTML-Genealogy-Map](http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTML-Genealogy-Map).
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

You can find documentation for this module with the perldoc command.

    perldoc HTML::Genalogy::Map

You can also look for information at:

- MetaCPAN

    [https://metacpan.org/dist/HTML-Genealogy-Map](https://metacpan.org/dist/HTML-Genealogy-Map)

- RT: CPAN's request tracker

    [https://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Genealogy-Map](https://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Genealogy-Map)

- CPAN Testers' Matrix

    [http://matrix.cpantesters.org/?dist=HTML-Genealogy-Map](http://matrix.cpantesters.org/?dist=HTML-Genealogy-Map)

- CPAN Testers Dependencies

    [http://deps.cpantesters.org/?module=HTML::Genalogy::Map](http://deps.cpantesters.org/?module=HTML::Genalogy::Map)

# LICENCE AND COPYRIGHT

Copyright 2010-2025 Nigel Horne.

Usage is subject to licence terms.

The licence terms of this software are as follows:

- Personal single user, single computer use: GPL2
- All other users (including Commercial, Charity, Educational, Government)
  must apply in writing for a licence for use from Nigel Horne at the
  above e-mail.
