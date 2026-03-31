#!/usr/bin/perl
# The following makes that when we read a file, we read all of it, rather than just the first line.
undef $/;
# The following allows data to be printed to the page immediately, rather than after accumulation of lots of data.
# Somehow this does not appear to work anymore.
$| =1;
# We print the following line to tell the web browser that we are "html" output.
print "Content-type: text/html\n\n";

# print HTML page with title in the wide EPTCS style.
print <<EndOfHTML;
<!DOCTYPE HTML PUBLIC>
<html><head><title>
EPTCS - Doi lookup page
</title>
<link rel="stylesheet" type="text/css" href="../wide.css">
EndOfHTML

# This subroutine reads the file whose name $filename is specified as argument,
# and stores its contents in $value{$filename}. If the file does not exists, it
# stores in $value{$filename} the empty string.
sub findvalue {
 if (-e $_[0]){
 open(FILE,$_[0]) || die("Cannot open $_[0].");
 $value{$_[0]}=<FILE>;
 close(FILE);
 } else {$value{$_[0]} = ''};
};

# If $ENV{QUERY_STRING} exists, we have started this task already, and skip the phase prior to looking up references at Crossref.
# Instead, we go to the directory $paper := $ENV{QUERY_STRING}, where the files for this task are stored.
if ($ENV{QUERY_STRING}) {
 $paper = $ENV{QUERY_STRING}; chdir $paper;
 # Also start the body of this webpage
 print "</head>\n<body>\n";
} else {
 # run latex, bibtex and latex on the file "nocite.tex", thereby creating the file "nocite.rebib"
 # of references extracted from the bibliography file "file.bib" (called from "nocite.tex").
 # The file "file.bib" is written by "bibfile.php" prior to calling the current program 'bibproc.cgi'.
 system("latex nocite > /dev/null; bibtex nocite > /dev/null; latex nocite > /dev/null");
 # after running latex we need to erase the .aux files, so that it doesn't effect the next job, with a different paper.
 unlink "nocite.aux";

 # collect the current time as a long string in $time.
 # this string will be the name $paper of the current data gathering attempt.
 ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime (time);
 $year = $year + 1900;
 $month = $mon + 1;
 $date = $mday + 0;
 $time = $sec + ($min * 100) + ($hour * 10000) + ($date * 1000000)
	      + ($month * 100000000) + ($year * 10000000000);

 $name = "../nocite"; $paper = $time; $paperdir = "."; # this is used in sub....pl, files shared with ~eptcs/scripts/.

 # Create a readable directory for the current data gathering attempt and go there.
 mkdir "$paper"; system ("chmod a+x $paper"); chdir "$paper";
 # Create reconstructed bibtex, XML and HTML versions of the given bibliography out of "nocite.rebib".
 # The first two of these subroutines use the name "../nocite" as filename $name.
 do "../subxmlbib.pl"; do "../subrebib.pl"; do "../subcrossxml.pl";

 # Start the body of this webpage, in such a way that it revisits the page with a QUERY_STRING when finished or stuck.
 print <<EndOfHTML;
<script>
 function revisit() {
  location.replace("bibproc.cgi?$paper")
 }
</script>
</head>
<body onLoad = "revisit()">
EndOfHTML
};

# Make a list of missing DOI, using output from subcrossxml.pl, and count their number.
&findvalue('missingDOIs');
@missing = split(/\n/,$value{missingDOIs});
$missingcount = $#missing+1;

# Write links to the reconstructed bibtex, XML and HTML versions of the given bibliography.
print "References, in
<a href='../references.cgi?bibliography:$paper.bib' target='_blank'>reconstructed bibtex</a>,
<a href='../references.cgi?bibliography:$paper.xml' target='_blank'>XML</a> and
<a href='../references.cgi?bibliography:$paper.html' target='_blank'>HTML</a> format.
<br>

There are $missingcount missing DOIs; we are now looking those up.\n";
# Create a table with the missing DOIs; some of them perhaps now found by CrossRef.
print "<table rules=cols bgcolor='white'>\n";
# Write headers of the two columns: first the references with missing DOIs; then the DOI if found.
print "<tr><td bgcolor='pink'>Reference</td><td bgcolor='pink'>DOI</td></tr>";
# First print all CrossRef output we have gathered already.
&findvalue("crossrefoutput");
print $value{crossrefoutput};

# The actual work needs to be done only the first time we visit this page.
unless ($ENV{QUERY_STRING}) {# This signals a revisit.
 # Call cr.pl to look up a DOI for each missing reference.
 for ($i = 0; $i < @missing; $i++) {
  ($nextkey,$nexttype) = split(/\t/,$missing[$i],2);
  # Store our progress in the file "pending".
  open(PENDING,">pending") || die("Cannot open pending");
  print PENDING $i;
  close(PENDING);
  do "../cr.pl";
 };
 # Store our progress in the file "pending".
 open(PENDING,">pending") || die("Cannot open pending");
 print PENDING "done";
 close(PENDING);
};
# After filling in all relevant references, end the table.
print "</table>\n";

# If we are not ready yet, invite the reader to do a refresh.
&findvalue("pending");
unless ($value{pending} eq "done") {
 print "We so far have looked up $value{pending} references out of $missingcount with a missing DOI.
 <br>Work is going on in the background; refresh this page to check our progress.";
};

# End the page by printing the EPTCS footer.
&findvalue("../../footer.html");
print <<EndOfHTML;
$value{"../../footer.html"}
</body></html>
EndOfHTML
