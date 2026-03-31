#!/usr/bin/perl -w
use CGI;

$cgi = CGI->new;
print $cgi->header;
undef $/;

sub findvalue {
 if (-e $_[0]){
 open(FILE,$_[0]) || die("Cannot open $_[0].");
 $value{$_[0]}=<FILE>;
 close(FILE);
 } else {$value{$_[0]} = ''};
};

&findvalue("../footer.html");

print <<EndOfHTML;
<!DOCTYPE HTML PUBLIC>
<html><head><title>
EPTCS - Doi lookup page
</title>
<link rel="stylesheet" type="text/css" href="../style.css">
</head>
<body>
EndOfHTML

unless ($ENV{QUERY_STRING}) {print "Please add query_string. $value{'../footer.html'}"; exit;};
($workshop,$paper) = split(/:/,$ENV{QUERY_STRING},2); 
unless (defined($paper) && $paper ne "") {print "2nd argument should be nonempty. $value{'../footer.html'}"; exit};
if ($workshop eq "") {# $workshop is empty if this comes from a supplied bib-file; nonempty if from an EPTCS paper
  $published = '.';
} elsif (-d "../Accepted/".$workshop."/Papers/".$paper) {
  $published = "../Accepted/".$workshop;
} elsif (-d "../Published/".$workshop."/Papers/".$paper) {
  $published = "../Published/".$workshop;
} else {
  print "$workshop paper $paper does not exist. $value{'../footer.html'}"; exit;
};
if ($workshop) {
 chdir $published;
 &findvalue("acronym");
 chdir "Papers/".$paper;
 &findvalue("status");
 &findvalue("title");
 &findvalue("references.xml");
 &findvalue("references.bib");
 print "<b><font size=-1>$value{acronym} $value{status} $paper:</font><br> $value{title} </b><p>\n";
 unless ($value{'references.xml'}) {print "No references have been harvested from this $value{status}.
   $value{'../footer.html'}"; exit};
 print "References";
 unless ($value{'references.bib'} =~ /@/) {print " (DOIs only)"};
 print ", in
 <a href='$published/Papers/$paper/references.bib'>reconstructed bibtex</a> and
 <a href='$published/Papers/$paper/references.xml'>XML</a> format.
 <hr>\n";
 @input = split(/\n/,$value{'references.xml'});
} else {
 chdir $paper;
 $value{status} = "bibtex file";
 &findvalue("references.xml");
 &findvalue("references.bib");
 print "References, in
 <a href='../references.cgi?bibliography:$paper.bib'>reconstructed bibtex</a>,
 <a href='../references.cgi?bibliography:$paper.xml'>XML</a> and
 <a href='../references.cgi?bibliography:$paper.html'>HTML</a> format.
 <hr>\n";
 @input = split(/\n/,$value{"references.xml"});
};
$count = 0; $reportcount =0; $thesiscount = 0; $doicount = 0;
foreach $line (@input) {
 if ($line =~ /^ <citation type="(.*)" key="(.*)">$/o) {
  $type="$1"; $key="$2";
  if ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished")
   {$reportcount = $reportcount+1} else {$count = $count+1};
  if ($type eq "phdthesis" || $type eq "mastersthesis" || $type eq "manual") {$thesiscount=$thesiscount+1};
 } elsif ($line =~ s/^  <doi>//) {
  $doicount = $doicount+1;
 } elsif ($line =~ m#^  <url>http://dx.doi.org/(.*)</url>$#) {
  $doicount = $doicount+1;
 }
};
if (defined($type) && $type eq "unknown") {print "
 This $value{status} has been bibtexed with the previous version of eptcs.bst.
 We would prefer it if you reuploaded this $value{status}, bibtexed with the current
 <a href='eptcs.bst'>eptcs.bst</a>.<p>\n"};

if ($value{'references.bib'} =~ /@/) {
 print "This $value{status} features $count references";
 if ($reportcount != 0) {print ", not counting $reportcount
  of type <b>TechReport</b>, <b>Booklet</b>, <b>Misc</b> or <b>Unpublished</b>"};
 print ".\n  Of those, $doicount explicitly list a DOI. ";
 if ($workshop) {
  if ($doicount == 1) {print "Thank you for looking up this DOI."}
  elsif ($doicount > 1) {print "Thank you for looking up these DOIs."}
  if ($doicount + $doicount + $thesiscount < $count) {print " We would ";
   unless ($doicount > 1) {print "strongly "};
   print "prefer it if you added the missing DOIs to your bibtex file,
   provided you can find them, ";
   unless ($doicount > 1) {print "using the bibtex field 'doi', "};
   print "and reuploaded this $value{status}, bibtexed with the enriched bibtex file.\n";
 }};
 print "<p>
 Below is an interface to check your references with the database of CrossRef.\n";
 print "You can use it to find DOIs of references (provided the publisher is a CrossRef member) and also\n";
} else {
 print "Below is an interface to check your $count DOI references with the database of CrossRef.
 You can use it ";
};
$save=20;
$threshold = ($save, $count)[$save > $count]; # minimum of $save and $count
print <<EndOfHTML;
to check your references against the data that CrossRef has obtained directly from the publisher.
<p>
<FORM enctype="application/x-www-form-urlencoded" method="POST"
 action="doilookup.cgi">
<INPUT TYPE="hidden" NAME="workshop" VALUE="$workshop">
<INPUT TYPE="hidden" NAME="paper" VALUE="$paper">
 Select result format:&nbsp;&nbsp;&nbsp;
 abbreviated<input type='radio' name='restype' value='abbrev' checked>&nbsp;&nbsp;&nbsp;
 medium<input type='radio' name='restype' value='medium'>&nbsp;&nbsp;&nbsp;
 or full<input type='radio' name='restype' value='full'><br>
EndOfHTML
if ($count > 2) {print "<font size=-1>
 CrossRef can handle only about 10-30 references at a time, depending on traffic. Sometimes none at all.
 Thus, after incorporating the data of the first $save references,
 please use your browser's back button twice to return to this page for the next batch.
 </font><br>\n"};
print <<EndOfHTML;
 Check references <INPUT type="text" name="first" size="2" value="1">
 to <INPUT type="text" name="last" size="2" value="$threshold">.
<input type='submit' name='submit' value='Submit'>
</FORM>
$value{'../footer.html'}
</body></html>
EndOfHTML
