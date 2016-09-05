#! /usr/local/bin/perl5 -w
#===========================================================================
# Program: report1.pl
#
# Purpose: Display a report of upcoming price changes via Perl DBI.
#
# Created: 10/23/1997 by Terry Nightingale <tnight@pobox.com>
#
# Changed: 99/99/9999 by xxx to ...
#
# This work is based on code written by Terry Nightingale <tnight@pobox.com>
# (c) Copyright 1997, all rights reserved.  See the file license.txt for
# licensing information.
#---------------------------------------------------------------------------

# For better compile-time error checking.
use strict;

# Be sure to use "no integer" if floating-point arithmetic is needed.
# The integer pragma is used here for efficiency with Date::Manip.
use integer;

use CGI_Lite;
use Date::Manip;
use DBI;

# For time/date calculations.
$ENV{'TZ'} = "PST8PDT";

# Initialize globals.
$main::DOCROOT              = "$ENV{'DOCUMENT_ROOT'}";
$main::parampage            = "$main::DOCROOT/report1/report1.html";
$main::resultspage          = "$main::DOCROOT/report1/results1.html";

$main::dbdriver             = "Informix";
$main::dbname               = "elc_test\@redhot";
$main::dbh                  = "";
$main::sth                  = "";

$main::section              = "";

# Start of main routine.

my ($key, $action) = "";

my $form = new CGI_Lite;
%main::fields = $form->parse_form_data ();

if (defined $main::fields{'action'}
    && $main::fields{'action'} eq "report")
{
    if (validate()) {
        do_report();
    }
    else {
        param_page();
    }
}
else {
    param_page();
}

# Clean up and release the database handle.
if ($main::dbh) {
    $main::dbh->disconnect or error_page($DBI::errstr);
}

# End of main routine.

#===========================================================================
# Routine: validate
#
# Purpose: Validate data entry to prevent database errors.
#---------------------------------------------------------------------------
sub validate
{
    return 1;
}

#===========================================================================
# Routine: dbconnect
#
# Purpose: Connect to the database.
#---------------------------------------------------------------------------
sub dbconnect
{
    # Connect to the database.
    $main::dbh = DBI->connect("dbi:${main::dbdriver}:${main::dbname}")
        or error_page($DBI::errstr);

    # Strip trailing blanks from fixed-width character fields.
    $main::dbh->{ChopBlanks} = 1;
}

#===========================================================================
# Routine: do_report
#
# Purpose: Create a report of upcoming price changes.
#---------------------------------------------------------------------------
sub do_report
{
    my ($key, $prefix, $pattern, $query)    = "";
    my (@queries, @rows, @result)           = ();

    # Connect to the database.
    dbconnect() if not $main::dbh;

    $query = <<END;
select p.item_sku, p.item_name, o.dt_begin, o.dt_end, o.sell_price
    from elc_part p, part_override o
    where p.item_sku = o.item_sku
    and o.dt_begin >= current
    order by o.dt_begin, p.item_name, p.item_sku;
END

    push @queries, $query;

    $query = <<END;
select p.item_sku, p.item_name, o.dt_end dt_begin, "n/a" dt_end,
       p.sell_price
    from elc_part p, part_override o
    where p.item_sku = o.item_sku
    and o.dt_begin < current
    and o.dt_end >= current
    order by o.dt_end, p.item_name, p.item_sku;
END

    push @queries, $query;

    foreach $query (@queries) {

        # Submit query to database to be executed.
        $main::sth = $main::dbh->prepare($query)
            or error_page($DBI::errstr);

        $main::sth->execute() or error_page($DBI::errstr);

        # Bind the column values to the pertinent keys of %main::fields.
        bind_columns_to_hash($main::sth, \%main::fields);

        while ($main::sth->fetch()) {
            my %row = %main::fields;
            push @rows, \%row;
        }

        $main::sth->finish();
    }

    # Sort the results from the two queries.  Arrange based on begin date
    # (or end date in disguise).
    #
    # NOTE:  There must be a better way to do this!
    #
    my @elems = sort { $::a->{'dt_begin'} cmp $::b->{'dt_begin'} } @rows;

    my $scratch = "";
    foreach $scratch (@elems) {
        push @main::rows, {%$scratch};
    }

#DEBUG CODE: use data-dumper here.
#print "Content-Type: text/plain\r\n\r\n";
#use Data::Dumper;
#my $d = Data::Dumper->new([\@rows, \@main::rows], [qw(*rows *main::rows)]);
#print "=== before dump. ===\n";
#print $d->Dump;
#print "=== after  dump. ===\n";
#exit;

    # Display the results of the query.
    select_page($main::resultspage);
}

#===========================================================================
# Routine: bind_columns_to_hash
#
# Purpose: Bind the column values to the pertinent keys of a hash.  If the
#          section parameter is non-blank, we are working with a hash of
#          hashes, in which case the section value will be used to
#          reference the inner hashes.
#
# NOTE:    Must be called *after* calling the statement handle's execute()
#          method.
#---------------------------------------------------------------------------
sub bind_columns_to_hash
{
    my ($sth, $hashref, $section)   = @_;
    my ($count, $field, $rc)        = "";

    $count = 1;
    foreach $field (@{$sth->{NAME}}) {

#print STDERR "Now in bind_columns_to_hash: \$field = [$field]\n";

        if ($section) {
            $rc = $sth->bind_col($count, \$hashref->{$field}{$section});
        }
        else {
            $rc = $sth->bind_col($count, \$hashref->{$field});
        }

        $count++;
    }
}

#===========================================================================
# Routine: param_page
#
# Purpose: Display the parameter page to the browser.
#---------------------------------------------------------------------------
sub param_page
{
    my $msg = $_[0];

    select_page($main::parampage, $msg);
}

#===========================================================================
# Routine: select_page
#
# Purpose: Display the select page to the browser.
#---------------------------------------------------------------------------
sub select_page
{
    my $filename    = $_[0];
    my $msg         = $_[1];

    my $key         = "";

    open (DBSELECT, $filename)
        or error_page("Cannot open data select or data update page.");

    print "Content-Type: text/html\r\n\r\n";
    while (<DBSELECT>) {
        if ($msg && m/<!-- Message Here -->/io) {
            print "$msg\n";
        }
        elsif (m/<!-- active: (.*) -->/io) {

            my $attrs = $1;
            my @words = ();

### print STDERR "<PRE>active attrs before main::fields subst = [$attrs]</PRE>";

            foreach $key (keys %main::fields) {
                if (defined $main::fields{$key}) {
                    if (ref $main::fields{$key}) {
                        my $section = "";
                        foreach $section (keys %{$main::fields{$key}}) {
                            $attrs =~
                                s!\Q^^${section}_${key}^^\E!$main::fields{$key}{$section}!g;
                        }
                    }
                    else {
                        $attrs =~
                            s!\Q^^$key^^\E!$main::fields{$key}!g;
                    }
                }
            }

### print STDERR "<PRE>active attrs after main::fields subst = [$attrs]</PRE>";

            push(@words, defined($1) ? $1:$3) while
                $attrs =~ m/(\w*="[^"\\]*(\\.[^"\\]*)*")|([^\s]+)/g;

            my ($scratch,$key,$value) = "";
            my %attributes = ();
            foreach $scratch (@words) {
                ($key, $value) = split(/=/, $scratch, 2);
                $value =~ s!\A\"(.*)\"\Z!$1!o;
                $value =~ s|\\\'|'|o;
                $value =~ s|\\\"|"|o;

                $attributes{$key} = $value;
            }

            # Handle the query.
            if (exists $attributes{'query'} && $attributes{'query'}) {
                my ($sth, $total, $prefix) = "";
                my ($fldref) = "";
                my (%fields) = ();

                dbconnect() if not $main::dbh;

                # Read until we find the end tag.
                my $qbuf = "";
                while (<DBSELECT>) {
                    if (m|<!--\s+?/active\s+?-->|io) {
                        last;
                    }
                    else {
                        $qbuf .= $_;
                    }
                }

                if ($attributes{'name'}) {
                    $prefix = $attributes{'name'} . "_";
                }

                if ($attributes{'query'} eq "cache") {
                    $fldref = \%main::fields;
                }
                else {
# DEBUG EXPERIMENT:
                    $main::sth->finish() or error_page($DBI::errstr);
# END DEBUG.
                    $sth = $main::dbh->prepare($attributes{'query'})
                        or error_page($DBI::errstr);
                    $sth->execute() or error_page($DBI::errstr);

                    # Bind the column values to the pertinent keys of
                    # the %fields associative array.
                    bind_columns_to_hash($sth, \%fields, $main::section);
                    $fldref = \%fields;
                }

#DEBUG
#return;
#END DEBUG

                # Limit number of displayed listings to 100.
                $total = scalar @main::rows;
# DEBUG VALUE:
#$total = 5;
# END DEBUG.
                if ($total > 100) {
                    $total = 100;
                }

                my ($i, $j, $scratch, $repeat, $ref) = "";

                if (exists ($attributes{'repeat'})) {
                    $repeat = $attributes{'repeat'};
                }

                # loop through result rows, substituting tokens.
                for ($i = 1; $i <= $total; $i++) {

                    # Fake a fetch.
                    %main::fields = %{$main::rows[$i - 1]};

                    ####
                    #### Need to genericize this kind of stuff.
                    ####
                    # Adjust for floating point storage.
                    for (qw(sell_price))
                    {
                        if (defined $fldref->{$_}) {
                            if (ref $fldref->{$_}) {
                                my $section = "";
                                foreach $section (keys %{$fldref->{$_}}) {
                                    $fldref->{$_}{$main::section} =
                                        sprintf("%.2f",
                                            $fldref->{$_}{$main::section});
                                }
                            }
                            else {
                                $fldref->{$_} =
                                    sprintf("%.2f", $fldref->{$_});
                            }
                        }
                    }

                    $scratch = $qbuf;
                    foreach (keys %$fldref) {
                        if (defined $fldref->{$_}) {
                            if (ref $fldref->{$_}) {
                                my $section = "";
                                foreach $section (keys %{$fldref->{$_}}) {
                                    $scratch =~
                                        s!\Q%%${prefix}$_%%\E!$fldref->{$_}{$main::section}!g;
                                }
                            }
                            else {
                                $scratch =~
                                    s!\Q%%${prefix}$_%%\E!$fldref->{$_}!g;
                            }
                        }
                    }

                    # Replace meta tokens, if found.
                    $scratch =~ s!\Q%%${prefix}count%%\E!$i!g;
                    $scratch =~ s!\Q%%${prefix}total%%\E!$total!g;

                    #
                    # Replace named tokens, if any.
                    #

                    ####
                    #### Need to genericize this kind of stuff.
                    ####
                    # Adjust for floating point storage.
                    for (qw(retail_price sell_price discount_rate))
                    {
                        if (exists $main::fields{$_} &&
                            ref $main::fields{$_})
                        {
                            $main::fields{$_}{$main::section} =
                                sprintf("%.2f",
                                    $main::fields{$_}{$main::section});
                        }
                    }
                    ####
                    #### if ($key eq "061confirmation and pick up time via") {
                    ####     s!\Q^^${key}:$main::fields{$key}^^\E!CHECKED!g;
                    #### }
                    $key = "";
                    foreach $key (keys %main::fields) {

                        ####
                        #### Need to genericize this kind of stuff.
                        ####
                        ####if ($key eq "Parent_CatlgGroupId"
                        ####    || $key eq "CatGroupId")
                        ####{
                        ####    $scratch =~
                        ####        s!\Q^^${key}:$main::fields{$key}^^\E!SELECTED!g;
                        ####}
                        ####else {
                        ####    $scratch =~
                        ####        s!\Q^^$key^^\E!$main::fields{$key}!g;
                        ####}

                        if (defined $main::fields{$key}) {

                            if (ref $main::fields{$key}) {
                                my $section = "";
                                foreach $section
                                    (keys %{$main::fields{$key}})
                                {
                                    $scratch =~
                                        s!\Q^^${section}_${key}^^\E!$main::fields{$key}{$section}!g;
                                }
                            }
                            else {
                                $scratch =~
                                    s!\Q^^$key^^\E!$main::fields{$key}!g;
                            }
                        }
                    }

                    # Nuke any remaining tokens.
                    $scratch =~ s!\^\^.+?\^\^!!go;

                    print $scratch;
                    last if not $repeat;

#DEBUG
####undef $ref;
#END DEBUG

                }

                # Clean up after query.
                if ($attributes{'query'} ne "cache") {
                    $sth->finish() or error_page($DBI::errstr);
                }
#DEBUG
#undef @foo;
undef %fields;
undef $ref;
undef $sth;
#END DEBUG
            }
        }
        else {
            #
            # Replace named tokens, if any.
            #
            ####
            #### The code below is for fields that are radio buttons or
            #### checkboxes, which need to be handled more generically,
            #### probably via meta-data.
            ####
            ####if ($key eq "061confirmation and pick up time via") {
            ####    s!\Q^^${key}:$main::fields{$key}^^\E!CHECKED!g;
            ####}
            foreach $key (keys %main::fields) {
                ####
                #### The code below is for fields that are select lists
                #### which need to be handled generically.
                ####
                ####if ($key eq "Parent_CatlgGroupId"
                ####    || $key eq "CatGroupId")
                ####{
                ####    s!\Q^^${key}:$main::fields{$key}^^\E!SELECTED!g;
                ####}
                ####else {
                ####    s!\Q^^$key^^\E!$main::fields{$key}!g;
                ####}

                if (defined $main::fields{$key}) {
                    if (ref $main::fields{$key}) {
                        my $section = "";
                        foreach $section (keys %{$main::fields{$key}}) {
                            s!\Q^^${section}_${key}^^\E!$main::fields{$key}{$section}!g;
                        }
                    }
                    else {
                        s!\Q^^$key^^\E!$main::fields{$key}!g;
                    }
                }
            }

            # Nuke any remaining tokens.
            s!\^\^.+?\^\^!!go;

            print;
        }
    }

#print STDERR "Now in select_page(), after all loops...\n";

    close DBSELECT;

#print STDERR "Leaving select_page() ...\n";

}

#===========================================================================
# Routine: error_page
#
# Purpose: Display an HTML page to the browser indicating an error.
#---------------------------------------------------------------------------
sub error_page
{
    my $msg = shift;

    print "Content-Type: text/html\r\n\r\n";
    print <<EOF;
<html><head><title>Script Error</title></head>
<body bgcolor="ffffff">
<h1>Script Error</h1>
<p>There was a script error.  Please contact the <a
href="mailto:macooper\@adobe.com">webmaster</a>.</p>
EOF

    print "<P>$msg</P>" if $msg;
    print "</body></html>\n";
    exit 1;
}

#===========================================================================
# Routine: incomplete_page
#
# Purpose: Display the incomplete page to the browser.
#---------------------------------------------------------------------------
sub incomplete_page
{
    open (INC, $main::incompletepage)
        or error_page("Cannot open incomplete page.");
    print "Content-Type: text/html\r\n\r\n";
    while (<INC>) {
        print;
    }
    close INC;
}


