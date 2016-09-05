#! /usr/local/bin/perl5 -w
#===========================================================================
# Program: partui.pl
#
# Purpose: Allow lookup, selection, and modification of records in a
#          database accessible via Perl DBI.
#
# Created: 10/02/1997 by Terry Nightingale <tnight@pobox.com>
#
# Changed: 99/99/9999 by xxx to ...
#
# This work is based on code written by Terry Nightingale <tnight@pobox.com>
# (c) Copyright 1997, all rights reserved.  See the file license.txt for
# licensing information.
#
# Overview:
#
# This module is intended to be an engine for maintenance (aka ACQD or
# CRUD) of database tables.  Ideally, it should be 100% template driven,
# with common features built in, such that simple applications could use it
# with no code changes.  In addition, it should be extensible, so that by
# deriving a new module from it, and overriding or adding functionality,
# more complex applications can make use of the module.
#
# Notes:
#
# o  Need more sophisticated template processing, to enable field names to
#    be duplicated between forms.  Each master and detail section has its
#    own form, and the template parser should be smart enough to know
#    which form it is processing.  One possibility is using LWP to parse
#    the templates.  Another is objectifying the form and the fields in it.
#    Each field might have a "table" attribute (among others), specifying
#    which database table needs to be updated when it is modified.
#
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
$main::DOCROOT = "$ENV{'DOCUMENT_ROOT'}";
$main::incompletepage       = "$main::DOCROOT/partui/incomplete.html";
$main::dblookuppage         = "$main::DOCROOT/partui/lookup.html";
$main::dbselectpage         = "$main::DOCROOT/partui/select.html";
$main::dbupdatepage         = "$main::DOCROOT/partui/update.html";

$main::driver               = "Informix";

$main::dbname               = "elc_test\@redhot";
### DEBUG, TEST ONLY!
### 
###$main::dbname               = "elc_prod\@mars";

$main::dbh                  = "";
$main::sth                  = "";

$main::section              = "";

# Start of main routine.

my ($key, $action) = "";

if ($ENV{'REQUEST_METHOD'} eq "POST") {

    my $form = new CGI_Lite;
    my %fields = $form->parse_form_data ();
    %main::fields = build_field_struct(%fields);

    # If no action is defined, we can't do anything, so exit the program.
    if (! defined ($main::fields{'action'})) {
        error_page("No action defined!");
    }

    if (ref $main::fields{'action'}) {
        if (keys %{$main::fields{'action'}} > 1) {
            error_page ("Too many actions defined!");
        }

        ($main::section) = keys %{$main::fields{'action'}};
        $action = $main::fields{'action'}{$main::section};
    }
    else {
        error_page ("Action must include section name.");
        ### $action = $main::fields{'action'};
    }

#DEBUG CODE: use data-dumper here.
#if (($action eq "lookup" || $action eq "select") &&
#    exists $main::fields{'item_sku'})
#{
#    print "Content-Type: text/plain\r\n\r\n";
#    use Data::Dumper;
#    my $d = Data::Dumper->new([$action, \%fields, \%main::fields], [qw(action *fields *main::fields)]);
#    print "before dump.\n";
#    print $d->Dump;
#    print "after dump.\n";
#    exit;
#}

    if ($action eq "lookup" || $action eq "select") {
        do_lookup();
    }
    elsif ($action eq "update") {
        if (validate()) {
            do_update();
            my $item_sku = $main::fields{'item_sku'}{$main::section};
            $main::section = "M0";
            $main::fields{'item_sku'}{$main::section} = $item_sku;
            $main::fields{'tablename'}{$main::section} = "elc_part";
            do_lookup(
                qq|<P ALIGN="CENTER">The previous update was 
                    successful.</P>|);
        }
        else {
            my $item_sku = $main::fields{'item_sku'}{$main::section};
            $main::section = "M0";
            $main::fields{'item_sku'}{$main::section} = $item_sku;
            $main::fields{'tablename'}{$main::section} = "elc_part";
            do_lookup();
        }
    }
    elsif ($action eq "insert") {
        if (validate()) {
            do_insert();
            my $item_sku = $main::fields{'item_sku'}{$main::section};
            $main::section = "M0";
            $main::fields{'item_sku'}{$main::section} = $item_sku;
            $main::fields{'tablename'}{$main::section} = "elc_part";
            do_lookup(
                qq|<P ALIGN="CENTER">The previous insert was
                    successful.</P>|);
        }
        else {
            my $item_sku = $main::fields{'item_sku'}{$main::section};
            $main::section = "M0";
            $main::fields{'item_sku'}{$main::section} = $item_sku;
            $main::fields{'tablename'}{$main::section} = "elc_part";

#DEBUG CODE: use data-dumper here.
#if (($action eq "lookup" || $action eq "select") &&
#    exists $main::fields{'item_sku'})
#{
#    print "Content-Type: text/plain\r\n\r\n";
#    use Data::Dumper;
#    my $d = Data::Dumper->new([$action, \%fields, \%main::fields], [qw(action *fields *main::fields)]);
#    print "before dump.\n";
#    print $d->Dump;
#    print "after dump.\n";
#    exit;
#}

            do_lookup();
        }
    }
####
#### Delete functionality is not needed by the partui application, need to
#### genericize determination of which functionality is needed (via
#### meta-data).
####
####    elsif ($action eq "delete") {
####        do_delete();
####        lookup_page (
####            "<P ALIGN=\"CENTER\">The previous deletion was
####                successful.</P>");
####    }

}
else {
    lookup_page();
}

# Debug code:
#print STDERR "Back in main routine, about to call \$main::dbh->disconnect()...\n";

# Clean up and release the database handle.
if ($main::dbh) {
    $main::dbh->disconnect or error_page($DBI::errstr);
}

# Debug code:
#print STDERR "Still in main routine, Just called \$main::dbh->disconnect()...\n";

# Debug code:
### print STDERR "Made it to the end!";
### exit;

# End of main routine.

#===========================================================================
# Routine: build_field_struct
#
# Purpose: Separate single hash with coded field names into hash of hashes,
#          representing each field present, and a value for each of the
#          page sections it is present in.
#---------------------------------------------------------------------------
sub build_field_struct
{
    my (%foo) = @_;
    my (%bar) = ();

    foreach (keys %foo) {

        # Skip blank fields.
        next if (! $foo{$_});

        if (m/^([A-Za-z]+?[0-9]+?)_(.*)$/igo) {
            $bar{$2}{$1} = $foo{$_};
        }
        else {
            $bar{$_} = $foo{$_};
        }
    }

    return %bar;
}

#===========================================================================
# Routine: validate
#
# Purpose: Validate data entry to prevent database errors.
#---------------------------------------------------------------------------
sub validate
{
####
#### Need to decide whether JavaScript in UI will handle all validation, or
#### whether some needs to be done here.  Possibly make sure that all
#### non-NULL fields are present and non-blank in the associative array.
####

    my ($scratch, $date, $is_valid) = "";
    my (@dates)                     = ();

    # Make sure the dates are valid, and store them away.
    foreach $scratch (qw(dt_begin dt_end)) {
        $date =
            Date::Manip::ParseDate($main::fields{$scratch}{$main::section});
        if (! $date) {
            $main::fields{'errormsg'} = "Invalid date!";
            $main::fields{'errorfld'} = "$scratch";
            $main::fields{'errorfrm'} = "$main::section";
            return $is_valid;
        }
        else {
            push @dates, $date;

            # Format the date/time for later insertion into the database.
            $main::fields{$scratch}{$main::section} =
                Date::Manip::UnixDate($date, "%Y-%m-%d %H:%M:%S");
        }
    }

    # Make sure the end date is greater than the begin date.
    if ($dates[1] le $dates[0]) {
        $main::fields{'errormsg'}
            = "End Date must be greater than Begin Date!";
        $main::fields{'errorfld'} = "dt_end";
        $main::fields{'errorfrm'} = "$main::section";
        return $is_valid;
    }

    #
    # Make sure that the date range does not overlap any existing date
    # ranges for the selected item SKU.
    #
    dbconnect() if not $main::dbh;

    my ($pattern, $query)   = "";
    $pattern = <<END;
select dt_begin, dt_end
    from part_override
    where item_sku = %s
    order by dt_begin
END

    $query = sprintf($pattern,
        $main::dbh->quote($main::fields{'item_sku'}{$main::section}));

#### Debug code:
#### print STDERR "Now in validate, \$query = [$query]";
#### exit;

    # Submit query to database to be executed.
    $main::sth = $main::dbh->prepare($query)
        or error_page($DBI::errstr);

    $main::sth->execute() or error_page($DBI::errstr);

    # Assume valid unless found to be invalid in loop below.
    $is_valid = 1;

    my ($count, $ref, $dt1, $dt2)   = "";
    my (%fields)                    = ();

    for ($count = 1; $ref = $main::sth->fetchrow_hashref(); $count++) {
        %fields = %$ref;

        $dt1 = &Date::Manip::ParseDate($fields{'dt_begin'});
        $dt2 = &Date::Manip::ParseDate($fields{'dt_end'});

        if (! $dt1 || ! $dt2) {
            $main::fields{'errormsg'}
                = "Invalid date in existing data!";
            $main::fields{'errorfld'} = "";
            $main::fields{'errorfrm'} = "";
            $is_valid = "";
            last;
        }

#DEBUG
#print STDERR "Now in validate(), row_num = [$main::fields{'row_num'}{$main::section}], count = [$count]\n";

        # When updating, skip overlap validation on the row that is being
        # modified.  In other words, it is OK for the updated row to
        # overlap itself, but not any other rows that may exist.
        if ($main::fields{'row_num'}{$main::section} &&
            $count == $main::fields{'row_num'}{$main::section})
        {
#DEBUG
#print STDERR "Found count match!\n";
            next;
        }

        if (($dates[0] ge $dt1 && $dates[0] lt $dt2) ||
            ($dates[1] gt $dt1 && $dates[1] le $dt2))
        {
            $main::fields{'errormsg'}
                = "Date range overlaps existing data!";
            $main::fields{'errorfld'} = "dt_begin";
            $main::fields{'errorfrm'} = "$main::section";
            $is_valid = "";
            last;
        }
    }

    $main::sth->finish();

#DEBUG
#print STDERR "Leaving validate, \$is_valid = [$is_valid]\n";

    return $is_valid;
}

#===========================================================================
# Routine: dbconnect
#
# Purpose: Connect to the database.
#---------------------------------------------------------------------------
sub dbconnect
{
    # Connect to the database.
    $main::dbh = DBI->connect("dbi:${main::driver}:${main::dbname}")
        or error_page($DBI::errstr);

    # Strip trailing blanks from fixed-width character fields.
    $main::dbh->{ChopBlanks} = 1;
}

#===========================================================================
# Routine: set_defaults
#
# Purpose: Populate fields in a database table that will not be maintained
#          by the user, but must contain values.
#---------------------------------------------------------------------------
sub set_defaults
{
    ####
    #### This is the type of custom logic that would be used by an
    #### application that is a client of the framework.  Possible
    #### strategies include the provision of hooks for processing that
    #### happens before the update, after the update, etc., most likely
    #### implemented with closures or subroutine pointers.
    ####
    $main::fields{'retail_price'}{$main::section} =
        $main::fields{'sell_price'}{$main::section};
    $main::fields{'discount_rate'}{$main::section} = 0.00;
}

#===========================================================================
# Routine: do_insert
#
# Purpose: Insert a previously validated row into a database.
#---------------------------------------------------------------------------
sub do_insert
{

####
#### Needs to be genericized, probably with meta-data.
####

    if ($main::fields{'tablename'}{$main::section} eq "part_override") {
        pre_insert_part_override();
        insert_part_override();
        #post_insert_part_override();
    }
    else {
        error_page("Invalid table name for insert.");
    }
}

#===========================================================================
# Routine: pre_insert_part_override
#
# Purpose: Processing to be performed prior to an insert of a previously
#          validated row in part_override.
#---------------------------------------------------------------------------
sub pre_insert_part_override
{
    set_defaults("part_override");
}

#===========================================================================
# Routine: insert_part_override
#
# Purpose: Insert a previously validated row in part_override.
#---------------------------------------------------------------------------
sub insert_part_override
{
    my @fields = ();
    my ($pattern,$query) = "";

    # Connect to the database.
    dbconnect() if not $main::dbh;

    # Uppercase all text fields.
    ####
    #### Need to genericize this (via meta-data).
    ####
    ####foreach $key ('Name') {
    ####    $main::fields{$key} = uc($main::fields{$key});
    ####}

    # Nullify all null fields.
    ####
    #### Need to genericize this (via meta-data), but is it necessary
    #### when using DBI?
    ####
    ####if ($main::fields{'Parent_CatlgGroupId'} eq "") {
    ####    $main::fields{'Parent_CatlgGroupId'} = "NULL";
    ####}

    $pattern = <<END;
insert into part_override (
    item_sku, dt_begin, dt_end, retail_price, sell_price, discount_rate
) values (
    %s, %s, %s, %s, %s, %s
)
END

    $query = sprintf($pattern,
        $main::dbh->quote($main::fields{'item_sku'}{$main::section}),
        $main::dbh->quote($main::fields{'dt_begin'}{$main::section}),
        $main::dbh->quote($main::fields{'dt_end'}{$main::section}),
        $main::fields{'retail_price'}{$main::section},
        $main::fields{'sell_price'}{$main::section},
        $main::fields{'discount_rate'}{$main::section});

### Debug Code:
### print STDERR "<PRE>Now in insert_part_override, \$query = [$query]</PRE>";

    $main::dbh->do($query) or error_page($DBI::errstr);
}

#===========================================================================
# Routine: do_update
#
# Purpose: Update a previously validated row in a database.
#---------------------------------------------------------------------------
sub do_update
{

####
#### Needs to be genericized, probably with meta-data.
####

    if ($main::fields{'tablename'}{$main::section} eq "part_override") {
        pre_update_part_override();
        update_part_override();
    }
    else {
        error_page("Invalid table name for update.");
    }
}

#===========================================================================
# Routine: pre_update_part_override
#
# Purpose: Processing to be performed prior to an update of a previously
#          validated row in part_override.
#---------------------------------------------------------------------------
sub pre_update_part_override
{
    set_defaults("part_override");
}

#===========================================================================
# Routine: update_part_override
#
# Purpose: Update a previously validated row in part_override.
#---------------------------------------------------------------------------
sub update_part_override
{
    my @fields = ();
    my ($pattern,$query) = "";

    # Connect to the database.
    dbconnect() if not $main::dbh;

    if (! $main::fields{'item_sku'}{$main::section}) {
        error_page("No item SKU specified for update!");
    }

    # Escape single quotes in all fields.
    ####
    #### Should not be necessary, if we use the proper DBI quoting function.
    ####
    ####my $key = "";
    ####foreach $key (keys %main::fields) {
    ####    $main::fields{$key} =~ s/\'/\\\'/g;
    ####}

    # Uppercase all text fields.
    ####
    #### Need to genericize this (via meta-data).
    ####
    ####foreach $key ('Name') {
    ####    $main::fields{$key} = uc($main::fields{$key});
    ####}

    # Nullify all null fields.
    ####
    #### Need to genericize this (via meta-data), but should not be 
    #### necessary when using DBI.
    ####
    ####if ($main::fields{'Parent_CatlgGroupId'} eq "") {
    ####    $main::fields{'Parent_CatlgGroupId'} = "NULL";
    ####}

    $pattern = <<END;
update part_override
    set dt_begin        = %s,
        dt_end          = %s,
        retail_price    = %s,
        sell_price      = %s,
        discount_rate   = %s
    where part_override.item_sku = %s
        and part_override.dt_begin = %s
END

    $query = sprintf($pattern,
        $main::dbh->quote($main::fields{'dt_begin'}{$main::section}),
        $main::dbh->quote($main::fields{'dt_end'}{$main::section}),
        $main::fields{'retail_price'}{$main::section},
        $main::fields{'sell_price'}{$main::section},
        $main::fields{'discount_rate'}{$main::section},
        $main::dbh->quote($main::fields{'item_sku'}{$main::section}),
        $main::dbh->quote($main::fields{'old_dt_begin'}{$main::section}));

    $main::dbh->do($query) or error_page($DBI::errstr);
}

####
#### Delete functionality is not needed by this application, but the code 
#### needs to be genericized, using meta-data about the table.
####

#===========================================================================
# Routine: do_delete
#
# Purpose: Delete a previously validated row in a database.
#---------------------------------------------------------------------------
sub do_delete
{
    if ($main::fields{'tablename'}{$main::section} eq "DSPL_Catlg_Group") {
        delete_group();
    }
    elsif ($main::fields{'tablename'}{$main::section} eq "DSPL_Catlg_Item") {
        delete_item();
    }
    else {
        error_page("Invalid table name for delete.");
    }
}

#===========================================================================
# Routine: delete_group
#
# Purpose: Delete a previously validated row in DSPL_Catlg_Group.
#---------------------------------------------------------------------------
sub delete_group
{
    my $query = "";

    # Connect to the database.
    dbconnect() if not $main::dbh;

    if (! $main::fields{'CatlgGroupId'}{$main::section}) {
        error_page("No CatlgGroupId specified for delete!");
    }

    if (! defined ($main::fields{'deleteconfirm'}{$main::section})
        || $main::fields{'deleteconfirm'}{$main::section} ne 'yes') {
            noconfirm_page();
    }

    $query = <<END;
delete from DSPL_Catlg_Group
    where DSPL_Catlg_Group.CatlgGroupId = 
        $main::fields{'CatlgGroupId'}{$main::section}
END

    $main::dbh->Query($query) or error_page($DBI::errstr);
}

#===========================================================================
# Routine: do_lookup
#
# Purpose: Lookup a row in a database.
#---------------------------------------------------------------------------
sub do_lookup
{
    my $msg         = $_[0];

####
#### Needs to be genericized, probably with meta-data.
####

# DEBUG
### print STDERR "Now in do_lookup, \$main::section = [$main::section]";
### exit;

    if ($main::fields{'tablename'}{$main::section} eq "elc_part") {
        lookup_part($msg);
    }
    else {
        error_page("Invalid table name for lookup.");
    }
}

#===========================================================================
# Routine: lookup_part
#
# Purpose: Lookup a row in elc_part.
#---------------------------------------------------------------------------
sub lookup_part
{
    my $msg     = $_[0];

    my ($key, $prefix, $pattern, $query)  = "";

    if ($main::section) {
        $prefix = $main::section . "_";
    }

    # Connect to the database.
    dbconnect() if not $main::dbh;

### DEBUG!
#return;
### END DEBUG

    if (exists($main::fields{'item_sku'}) && ref($main::fields{'item_sku'})
        && $main::fields{'item_sku'}{$main::section})
    {
        $pattern = <<END;
select item_sku, item_class, prefix_c, product_c, platform_c, version_c,
        channel_c, item_name, item_url, retail_price, sell_price,
        discount_rate, taxable_c, reg_prod, num_seats, hard_goods,
        electronic_goods
    from elc_part
    where item_sku = %s
END
        ####
        #### Need to genericize filtering such as the following line.
        ####
        $main::fields{'item_sku'}{$main::section} =~ s/\D//go;

        $query = sprintf($pattern, 
            $main::dbh->quote($main::fields{'item_sku'}{$main::section}));
    }
    else {
        $query = build_query($main::fields{'tablename'}{$main::section});

        if (! $query) {
            lookup_page($msg);
            return;
        }
    }

#### Debug code:
#print STDERR "\$query = [$query]";
#exit;

    # Submit query to database to be executed.
    $main::sth = $main::dbh->prepare($query)
        or error_page($DBI::errstr);

    $main::sth->execute() or error_page($DBI::errstr);

    ####
    #### New implementation for DBI, since number of rows to be fetched is 
    #### not known after cursor execute.
    ####

    my $hashref1 = $main::sth->fetchrow_hashref();
    error_page($DBI::errstr) if $DBI::errstr;

    if (not defined $hashref1) {
        lookup_page ("No record found.");
    }
    else {
        my $hashref2 = $main::sth->fetchrow_hashref();
        error_page($DBI::errstr) if $DBI::errstr;

        ####
        #### A hack, but we need to get back to the beginning of the 
        #### rowset.  Ideally, we should cache the first two rows.
        ####
        $main::sth->finish or error_page($DBI::errstr);

        # Necessary to properly release database resources (investigate?)
        $main::sth = $main::dbh->prepare($query)
            or error_page($DBI::errstr);

        $main::sth->execute or error_page($DBI::errstr);

        # Bind the column values to the pertinent keys of %main::fields.
        bind_columns_to_hash($main::sth, \%main::fields, $main::section);

        if (not defined $hashref2) {
            $main::sth->fetch;
            error_page($DBI::errstr) if $DBI::errstr;

            ####
            #### Need to genericize this kind of stuff.
            ####
            # Adjust for floating point storage.
            for (qw(retail_price sell_price discount_rate)) {
                $main::fields{$_}{$main::section} =
                    sprintf("%.2f", $main::fields{$_}{$main::section});
            }


### DEBUG!
#$main::sth->finish or error_page($DBI::errstr);
#return;
### END DEBUG


            update_page($msg);

#print STDERR "Back in lookup_part(), after update_page()...\n";

        }
        else {


### DEBUG!
#return;
### END DEBUG


            select_page ($main::dbselectpage);
        }
    }

#print STDERR "Now in lookup_part(), about to finish/undef \$main::sth...\n";

    ### $main::sth->finish or error_page($DBI::errstr);
# DEBUG!
if (defined $main::sth) {
$main::sth->finish or error_page($DBI::errstr);
}
# END DEBUG

#print STDERR "Now in lookup_part(), just finished \$main::sth...\n";
    undef $main::sth;
#print STDERR "Now in lookup_part(), just undef'd \$main::sth...\n";

#print STDERR "Leaving lookup_part()...\n";
}

#===========================================================================
# Routine: bind_columns_to_hash
#
# Purpose: Bind the column values to the pertinent keys of a hash.  If the
#          section parameter is non-blank, we are working with a hash of
#          hashes, in which case the section value will be used to reference
#          the inner hashes.
#
# NOTE:    Must be called *after* calling the statement handle's execute()
#          method.
#---------------------------------------------------------------------------
sub bind_columns_to_hash
{
    my ($sth, $hashref, $section)   = @_;
    my ($count, $field)             = "";

my ($rc, $foo) = "";

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
# Routine: build_query
#
# Purpose: Build a database query from field data submitted.
#---------------------------------------------------------------------------
sub build_query
{
    my ($key, $query, $word, $complete) = "";

    ####
    #### Need to genericize this whole function, via meta-data.  Should be
    #### easy, given the repeating patterns.
    ####
    # Uppercase all text fields.
    foreach $key ('item_name_match', 'product_c', 'platform_c') {
        if (defined($main::fields{$key}{$main::section})
            && length($main::fields{$key}{$main::section}) > 0)
        {
            $main::fields{$key}{$main::section} =
                uc($main::fields{$key}{$main::section});
        }
    }

    $query = <<EOQ;
select item_sku, item_class, prefix_c, product_c, platform_c, version_c,
        channel_c, item_name, item_url, retail_price, sell_price,
        discount_rate, taxable_c, reg_prod, num_seats, hard_goods,
        electronic_goods
    from elc_part
EOQ

    $word = "where";

    if (exists($main::fields{'item_sku'}{$main::section}) &&
        length($main::fields{'item_sku'}{$main::section}) > 0)
    {
        ####
        #### Need to genericize filtering such as the following line.
        ####
        $main::fields{'item_sku'}{$main::section} =~ s/\D//go;
        $query .= 
            " $word item_sku = $main::fields{'item_sku'}{$main::section}";
        $word = "and";
        $complete = 1;
    }

    foreach $key ('item_name_match', 'product_c', 'platform_c') {
        if (exists($main::fields{$key}{$main::section}) &&
            length($main::fields{$key}{$main::section}) > 0)
        {
            $main::fields{$key}{$main::section} =~ s/\s/%/g;
            $main::fields{$key}{$main::section}
                = "$main::fields{$key}{$main::section}\%";
            $query .= sprintf(" $word $key like '%s'",
                $main::fields{$key}{$main::section});
            $word = "and";
            $complete = 1;
        }
    }

    if (! $complete) {
        $query = "";
    }
    else {
        $query .= " order by item_name, item_sku";
    }

#### Debug code:
####print STDERR "At end of build_query(), \$query = [$query], \$complete = [$complete]";
####exit;

    return $query;
}

#===========================================================================
# Routine: lookup_page
#
# Purpose: Display the lookup page to the browser.
#---------------------------------------------------------------------------
sub lookup_page
{
    my $msg = $_[0];

    select_page($main::dblookuppage, $msg);
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

# DEBUG:
#my (@foo) = ();
#return;
# END DEBUG

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

# DEBUG EXPERIMENT:
#return;
# END DEBUG.

                if ($attributes{'query'} eq "cache") {
                    $sth = $main::sth;
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
                ####$total = $sth->numrows;

                $total = 100;
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
# DEBUG CODE:
####%fields = ();
####@foo = $sth->fetchrow_array() or last;
# END DEBUG.

#print STDERR "active subst: about to fetch...\n";

#DEBUG
#%main::fields = ();
#END DEBUG

                    $sth->fetch() or last;
#print STDERR "active subst: after fetch...\n";

#DEBUG CODE: use data-dumper here.
#use Data::Dumper;
#my $d = Data::Dumper->new([\%main::fields, \%fields], [qw(*main::fields *fields)]);
#print "</TABLE></CENTER><PRE>before dump.\n";
#print $d->Dump;
#print "after dump.</PRE><CENTER><TABLE>\n";
#exit;

                    #%fields = %$ref;
                    #@foo = @$ref;
#%fields = ();
# END DEBUG TEST
#print STDERR "active subst: after hash assignment...\n";

                    ####
                    #### Need to genericize this kind of stuff.
                    ####
                    # Adjust for floating point storage.
                    for (qw(retail_price sell_price discount_rate))
                    {
                        $fldref->{$_}{$main::section} =
                            sprintf("%.2f", $fldref->{$_}{$main::section});
                    }

                    $scratch = $qbuf;
                    foreach (keys %$fldref) {
                        $scratch =~
                            s!\Q%%${prefix}$_%%\E!$fldref->{$_}{$main::section}!g;
#print STDERR "active subst: looking for: [${prefix}$_]\n";
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
# Routine: update_page
#
# Purpose: Display the data entry page to the browser, substituting tokens
#          therein with values from a lookup.
#---------------------------------------------------------------------------
sub update_page
{
    my $msg         = $_[0];

####
#### Needs to be genericized, probably with meta-data.
####

    ####
    #### This pair of calls should not be necessary, since the algorithm 
    #### used with DBI has to attempt to fetch the first two rows, in the 
    #### absence of cursor metadata about the number of rows selected.
    ####
    # Fetch a row from the query result set.
    ####@main::dbfields = $main::sth->fetchrow_array();
    ####do_named_fields();

    if ($main::fields{'tablename'}{$main::section} eq "elc_part" ||
        $main::fields{'tablename'}{$main::section} eq "part_override")
    {
        select_page($main::dbupdatepage, $msg);
#DEBUG
#print STDERR "Now in update_page, back from select_page()\n";
#exit;
    }
    else {
        error_page("Invalid table name for update.");
    }

#print STDERR "Leaving update_page()...\n";

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

#===========================================================================
# Routine: noconfirm_page
#
# Purpose: Display the "you must confirm the delete" page to the browser.
#---------------------------------------------------------------------------
sub noconfirm_page
{
    my $msg = "You must confirm the delete.  Please go back.";

    print "Content-Type: text/html\r\n\r\n";
    print <<EOF;
<html><head><title>No Confirmation Given</title></head>
<body bgcolor="ffffff">
<h1>No Confirmation Given</h1>
EOF

    print "<P>$msg</P>" if $msg;
    print "</body></html>\n";
    exit 1;
}


